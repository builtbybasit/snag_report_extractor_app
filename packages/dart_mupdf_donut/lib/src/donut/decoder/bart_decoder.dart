/// BART (Bidirectional Auto-Regressive Transformer) decoder for Donut.
///
/// Pure Dart implementation of the mBART-based decoder used in the Donut model.
/// Generates token sequences auto-regressively conditioned on encoder outputs.
///
/// Architecture:
///   Token Embedding + Position Embedding →
///   [BartDecoderLayer × numLayers] →
///   LayerNorm → LM Head
///
/// Each BartDecoderLayer:
///   Self-Attention (causal) → Cross-Attention (to encoder) → FFN
///
/// Reference: "BART: Denoising Sequence-to-Sequence Pre-training" (Lewis et al., 2020)
library;

import 'dart:math' as math;

import '../tensor/tensor.dart';
import '../nn/layers.dart';
import '../tokenizer/tokenizer.dart';

// ─── BART Attention ────────────────────────────────────────────────────

/// Scaled dot-product attention used in BART decoder.
///
/// Supports both causal self-attention and cross-attention.
class BartAttention {
  final int embedDim;
  final int numHeads;
  final int headDim;
  final bool isCrossAttention;

  late Linear kProj;
  late Linear vProj;
  late Linear qProj;
  late Linear outProj;

  BartAttention({
    required this.embedDim,
    required this.numHeads,
    this.isCrossAttention = false,
  }) : headDim = embedDim ~/ numHeads {
    kProj = Linear(embedDim, embedDim);
    vProj = Linear(embedDim, embedDim);
    qProj = Linear(embedDim, embedDim);
    outProj = Linear(embedDim, embedDim);
  }

  /// Forward pass.
  ///
  /// [hiddenStates]: (batch, seqLen, embedDim)
  /// [keyValueStates]: for cross-attention, the encoder output (batch, srcLen, embedDim)
  /// [pastKeyValue]: cached K,V from previous steps for auto-regressive decoding
  /// [attentionMask]: causal or padding mask
  ///
  /// Returns (output, (cachedKey, cachedValue))
  (Tensor, (Tensor, Tensor)) forward(
    Tensor hiddenStates, {
    Tensor? keyValueStates,
    (Tensor, Tensor)? pastKeyValue,
    Tensor? attentionMask,
  }) {
    final batch = hiddenStates.shape[0];
    final tgtLen = hiddenStates.shape[1];
    final scale = 1.0 / math.sqrt(headDim.toDouble());

    // Project query
    var q = qProj.forward(hiddenStates); // (batch, tgtLen, embedDim)
    q = q.reshape([batch, tgtLen, numHeads, headDim]).permute(
        [0, 2, 1, 3]); // (batch, numHeads, tgtLen, headDim)

    // Project key/value (from encoder output for cross-attn, or self for self-attn)
    Tensor k, v;
    if (isCrossAttention && keyValueStates != null) {
      if (pastKeyValue != null) {
        // Reuse cached encoder key/value
        k = pastKeyValue.$1;
        v = pastKeyValue.$2;
      } else {
        final srcLen = keyValueStates.shape[1];
        k = kProj.forward(keyValueStates);
        k = k.reshape([batch, srcLen, numHeads, headDim]).permute([0, 2, 1, 3]);
        v = vProj.forward(keyValueStates);
        v = v.reshape([batch, srcLen, numHeads, headDim]).permute([0, 2, 1, 3]);
      }
    } else {
      // Self-attention
      k = kProj.forward(hiddenStates);
      k = k.reshape([batch, tgtLen, numHeads, headDim]).permute([0, 2, 1, 3]);
      v = vProj.forward(hiddenStates);
      v = v.reshape([batch, tgtLen, numHeads, headDim]).permute([0, 2, 1, 3]);

      // Concatenate with past key/value
      if (pastKeyValue != null) {
        k = Tensor.cat([pastKeyValue.$1, k], 2);
        v = Tensor.cat([pastKeyValue.$2, v], 2);
      }
    }

    // Attention scores: Q @ K^T / sqrt(d)
    final kT = k.transpose(2, 3);
    var attnWeights =
        q.matmul(kT).mulScalar(scale); // (batch, numHeads, tgtLen, srcLen)

    // Apply causal mask for self-attention
    if (!isCrossAttention && attentionMask != null) {
      if (attentionMask.ndim == 2) {
        final expanded =
            attentionMask.unsqueeze(0).unsqueeze(0).expand(attnWeights.shape);
        attnWeights = attnWeights + expanded;
      } else {
        attnWeights = attnWeights + attentionMask;
      }
    }

    // Softmax
    attnWeights = attnWeights.softmax(-1);

    // Weighted sum of values
    var attnOutput =
        attnWeights.matmul(v); // (batch, numHeads, tgtLen, headDim)

    // Reshape: (batch, tgtLen, embedDim)
    attnOutput =
        attnOutput.permute([0, 2, 1, 3]).reshape([batch, tgtLen, embedDim]);

    // Output projection
    attnOutput = outProj.forward(attnOutput);

    return (attnOutput, (k, v));
  }
}

// ─── BART Decoder Layer ────────────────────────────────────────────────

/// A single BART decoder layer.
///
/// Consists of:
/// 1. Self-attention with causal mask
/// 2. Cross-attention to encoder outputs
/// 3. Feed-forward network
///
/// Each sub-layer has a residual connection and layer normalization.
class BartDecoderLayer {
  final int embedDim;
  final int ffnDim;
  final int numHeads;

  late BartAttention selfAttn;
  late LayerNorm selfAttnLayerNorm;
  late BartAttention encoderAttn;
  late LayerNorm encoderAttnLayerNorm;
  late Linear fc1;
  late Linear fc2;
  late LayerNorm finalLayerNorm;

  BartDecoderLayer({
    required this.embedDim,
    required this.ffnDim,
    required this.numHeads,
  }) {
    selfAttn = BartAttention(
      embedDim: embedDim,
      numHeads: numHeads,
      isCrossAttention: false,
    );
    selfAttnLayerNorm = LayerNorm(embedDim);

    encoderAttn = BartAttention(
      embedDim: embedDim,
      numHeads: numHeads,
      isCrossAttention: true,
    );
    encoderAttnLayerNorm = LayerNorm(embedDim);

    fc1 = Linear(embedDim, ffnDim);
    fc2 = Linear(ffnDim, embedDim);
    finalLayerNorm = LayerNorm(embedDim);
  }

  /// Forward pass.
  ///
  /// [hiddenStates]: (batch, seqLen, embedDim)
  /// [encoderHiddenStates]: (batch, srcLen, embedDim) — encoder output
  /// [selfAttnPast]: cached self-attention K,V
  /// [crossAttnPast]: cached cross-attention K,V
  /// [causalMask]: causal attention mask
  ///
  /// Returns (output, selfAttnCache, crossAttnCache)
  (Tensor, (Tensor, Tensor), (Tensor, Tensor)) forward(
    Tensor hiddenStates, {
    required Tensor encoderHiddenStates,
    (Tensor, Tensor)? selfAttnPast,
    (Tensor, Tensor)? crossAttnPast,
    Tensor? causalMask,
  }) {
    var residual = hiddenStates;

    // 1. Self-attention
    hiddenStates = selfAttnLayerNorm.forward(hiddenStates);
    final (selfAttnOut, selfAttnCache) = selfAttn.forward(
      hiddenStates,
      pastKeyValue: selfAttnPast,
      attentionMask: causalMask,
    );
    hiddenStates = residual + selfAttnOut;

    // 2. Cross-attention
    residual = hiddenStates;
    hiddenStates = encoderAttnLayerNorm.forward(hiddenStates);
    final (crossAttnOut, crossAttnCache) = encoderAttn.forward(
      hiddenStates,
      keyValueStates: encoderHiddenStates,
      pastKeyValue: crossAttnPast,
    );
    hiddenStates = residual + crossAttnOut;

    // 3. FFN
    residual = hiddenStates;
    hiddenStates = finalLayerNorm.forward(hiddenStates);
    hiddenStates = fc1.forward(hiddenStates);
    hiddenStates = hiddenStates.gelu();
    hiddenStates = fc2.forward(hiddenStates);
    hiddenStates = residual + hiddenStates;

    return (hiddenStates, selfAttnCache, crossAttnCache);
  }
}

// ─── BART Decoder (Full) ──────────────────────────────────────────────

/// Key-value cache for auto-regressive decoding.
///
/// Stores previously computed key/value tensors for each layer
/// to avoid recomputation during token-by-token generation.
class KVCache {
  final List<(Tensor, Tensor)?> selfAttnCache;
  final List<(Tensor, Tensor)?> crossAttnCache;

  KVCache(int numLayers)
      : selfAttnCache = List.filled(numLayers, null),
        crossAttnCache = List.filled(numLayers, null);
}

/// Complete BART decoder for Donut.
///
/// Generates token sequences auto-regressively given encoder outputs.
/// Uses cross-attention to attend to the encoder's visual features.
///
/// The decoder operates in two modes:
/// 1. **Full sequence mode**: Process entire input sequence (for prefilling)
/// 2. **Single token mode**: Process one token at a time with KV cache
///    (for auto-regressive generation)
class BartDecoder {
  final int decoderLayers;
  final int maxPositionEmbeddings;
  final int vocabSize;
  final int embedDim;
  final int ffnDim;
  final int numHeads;

  late Embedding embedTokens;
  late Embedding embedPositions;
  late LayerNorm layerNorm;
  late Linear lmHead;
  late List<BartDecoderLayer> layers;

  /// The tokenizer for encoding/decoding text.
  DonutTokenizer? tokenizer;

  /// Scaling factor for embeddings (sqrt(embedDim)).
  late double embedScale;

  BartDecoder({
    this.decoderLayers = 4,
    this.maxPositionEmbeddings = 1536,
    this.vocabSize = 57522,
    this.embedDim = 1024,
    this.ffnDim = 4096,
    this.numHeads = 16,
  }) {
    embedTokens = Embedding(vocabSize, embedDim);
    // +2 for BART's position embedding offset
    embedPositions = Embedding(maxPositionEmbeddings + 2, embedDim);
    layerNorm = LayerNorm(embedDim);
    lmHead = Linear(embedDim, vocabSize, useBias: false);
    embedScale = math.sqrt(embedDim.toDouble());

    layers = List.generate(
      decoderLayers,
      (i) => BartDecoderLayer(
        embedDim: embedDim,
        ffnDim: ffnDim,
        numHeads: numHeads,
      ),
    );
  }

  /// Forward pass through the decoder.
  ///
  /// [inputIds]: list of token IDs (single sequence)
  /// [encoderHiddenStates]: (1, srcLen, encoderDim) — encoder output
  /// [cache]: optional KV cache for auto-regressive decoding
  /// [pastLength]: number of previously generated tokens (for position offset)
  ///
  /// Returns (logits, updatedCache)
  (Tensor, KVCache) forward(
    List<int> inputIds, {
    required Tensor encoderHiddenStates,
    KVCache? cache,
    int pastLength = 0,
  }) {
    cache ??= KVCache(decoderLayers);
    final seqLen = inputIds.length;

    // Token embeddings (scaled)
    var hidden = embedTokens.forward(inputIds).mulScalar(embedScale);

    // Position embeddings (+2 offset as in mBART)
    final posIds = List.generate(seqLen, (i) => pastLength + i + 2);
    final posEmbeds = embedPositions.forward(posIds);
    hidden = hidden + posEmbeds;

    // Reshape to (1, seqLen, embedDim) for batch processing
    hidden = hidden.unsqueeze(0);

    // Causal mask for self-attention
    Tensor? causalMask;
    if (seqLen > 1) {
      causalMask = Tensor.causalMask(seqLen);
    }

    // Apply decoder layers
    for (int i = 0; i < layers.length; i++) {
      final (output, selfCache, crossCache) = layers[i].forward(
        hidden,
        encoderHiddenStates: encoderHiddenStates,
        selfAttnPast: cache.selfAttnCache[i],
        crossAttnPast: cache.crossAttnCache[i],
        causalMask: causalMask,
      );
      hidden = output;
      cache.selfAttnCache[i] = selfCache;
      cache.crossAttnCache[i] = crossCache;
    }

    // Final layer norm
    hidden = layerNorm.forward(hidden);

    // LM head: project to vocabulary
    final logits = lmHead.forward(hidden); // (1, seqLen, vocabSize)

    return (logits, cache);
  }

  /// Add special tokens to the tokenizer vocabulary.
  void addSpecialTokens(List<String> tokens) {
    tokenizer?.addSpecialTokens(tokens);
  }

  /// Generate a token sequence auto-regressively.
  ///
  /// [encoderOutput]: (1, srcLen, encoderDim)
  /// [promptTokens]: initial token IDs to seed the generation
  /// [maxLength]: maximum number of tokens to generate
  /// [eosTokenId]: token ID that signals end of generation
  ///
  /// Returns generated token ID sequence.
  List<int> generate({
    required Tensor encoderOutput,
    required List<int> promptTokens,
    int maxLength = 1536,
    int? eosTokenId,
    int? padTokenId,
    bool greedy = true,
  }) {
    final generated = List<int>.from(promptTokens);
    KVCache? cache;
    int pastLength = 0;

    // Process prompt (prefill)
    if (promptTokens.length > 1) {
      final (_, prefillCache) = forward(
        promptTokens.sublist(0, promptTokens.length - 1),
        encoderHiddenStates: encoderOutput,
        cache: cache,
        pastLength: 0,
      );
      cache = prefillCache;
      pastLength = promptTokens.length - 1;
    }

    // Auto-regressive generation
    var currentToken = [promptTokens.last];

    for (int step = 0; step < maxLength - promptTokens.length; step++) {
      final (logits, newCache) = forward(
        currentToken,
        encoderHiddenStates: encoderOutput,
        cache: cache,
        pastLength: pastLength,
      );
      cache = newCache;
      pastLength += 1;

      // Get logits for last token: (1, 1, vocabSize) → pick last
      final lastLogits = logits[0][logits.shape[1] - 1]; // (vocabSize,)

      int nextToken;
      if (greedy) {
        nextToken = lastLogits.argmax();
      } else {
        // Sample from softmax distribution
        final probs = lastLogits.softmax(0);
        nextToken = _sampleFromDistribution(probs);
      }

      generated.add(nextToken);
      currentToken = [nextToken];

      // Stop on EOS
      if (eosTokenId != null && nextToken == eosTokenId) {
        break;
      }

      // Stop on PAD
      if (padTokenId != null && nextToken == padTokenId) {
        break;
      }
    }

    return generated;
  }

  int _sampleFromDistribution(Tensor probs) {
    final r = math.Random().nextDouble();
    double cumSum = 0.0;
    for (int i = 0; i < probs.size; i++) {
      cumSum += probs.data[i];
      if (cumSum >= r) return i;
    }
    return probs.size - 1;
  }
}
