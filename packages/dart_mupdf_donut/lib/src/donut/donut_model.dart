/// Donut model — OCR-free Document Understanding Transformer.
///
/// Pure Dart implementation of the full Donut pipeline:
///   Image → SwinEncoder → BartDecoder → Structured JSON
///
/// Supports document classification, information extraction, and visual QA
/// without any external OCR engine.
///
/// Reference: "OCR-free Document Understanding Transformer" (Kim et al., ECCV 2022)
library;

import 'dart:math' as math;

import 'donut_config.dart';
import 'nn/layers.dart';
import 'tensor/tensor.dart';
import 'encoder/swin_encoder.dart';
import 'decoder/bart_decoder.dart';
import 'tokenizer/tokenizer.dart';
import 'utils/image_utils.dart';
import 'utils/weight_loader.dart';

/// Result of a Donut inference pass.
class DonutResult {
  /// The raw generated token sequence.
  final List<int> tokens;

  /// The decoded text string.
  final String text;

  /// The parsed JSON output (may be null if parsing fails).
  final dynamic json;

  const DonutResult({
    required this.tokens,
    required this.text,
    this.json,
  });

  @override
  String toString() => 'DonutResult(text: $text, json: $json)';
}

/// The complete Donut model combining Swin Transformer encoder and BART decoder.
///
/// Usage:
/// ```dart
/// final config = DonutConfig.base();
/// final model = DonutModel(config);
/// await model.loadWeights('path/to/weights');
///
/// final image = DonutImageUtils.loadAndPreprocess(imageBytes, config);
/// final result = model.inference(
///   imageTensor: image,
///   prompt: '<s_cord-v2>',
/// );
/// print(result.json);
/// ```
class DonutModel {
  /// Model configuration.
  final DonutConfig config;

  /// Visual encoder (Swin Transformer).
  late SwinEncoder encoder;

  /// Text decoder (BART).
  late BartDecoder decoder;

  /// Tokenizer for encoding/decoding text.
  DonutTokenizer? tokenizer;

  /// Whether weights have been loaded.
  bool _isLoaded = false;

  /// Creates a new Donut model with the given configuration.
  ///
  /// The model is created with random weights. Call [loadWeights] or
  /// [fromPretrained] to load pretrained weights before inference.
  DonutModel(this.config) {
    encoder = SwinEncoder(
      inputSize: config.inputSize,
      patchSize: config.patchSize,
      embedDim: config.encoderEmbedDim,
      encoderLayer: config.encoderLayer,
      numHeads: config.encoderNumHeads,
      windowSize: config.windowSize,
    );

    decoder = BartDecoder(
      decoderLayers: config.decoderLayer,
      maxPositionEmbeddings: config.maxPositionEmbeddings,
      vocabSize: config.vocabSize,
      embedDim: config.decoderEmbedDim,
      ffnDim: config.decoderFfnDim,
      numHeads: config.decoderNumHeads,
    );
  }

  /// Whether the model has loaded weights and is ready for inference.
  bool get isReady => _isLoaded;

  /// Initialize all model weights with small random values.
  ///
  /// Uses Xavier/Glorot uniform initialization scaled by [scale].
  /// Useful for testing to ensure non-degenerate outputs.
  void randomInit({double scale = 0.02, int? seed}) {
    final rng = seed != null ? math.Random(seed) : math.Random();
    _randomInitTensors(encoder, rng, scale);
    _randomInitTensors(decoder, rng, scale);
    _isLoaded = true;
  }

  /// Recursively initialize all weight tensors in an object.
  static void _randomInitTensors(dynamic obj, math.Random rng, double scale) {
    if (obj is SwinEncoder) {
      _randomInitTensors(obj.patchEmbed, rng, scale);
      for (final layer in obj.layers) {
        _randomInitTensors(layer, rng, scale);
      }
    } else if (obj is SwinLayer) {
      for (final block in obj.blocks) {
        _randomInitTensors(block, rng, scale);
      }
      if (obj.patchMerging != null) {
        _randomInitTensors(obj.patchMerging!, rng, scale);
      }
    } else if (obj is SwinTransformerBlock) {
      _randomInitTensors(obj.norm1, rng, scale);
      _randomInitTensors(obj.attn, rng, scale);
      _randomInitTensors(obj.norm2, rng, scale);
      _randomInitTensors(obj.mlpFc1, rng, scale);
      _randomInitTensors(obj.mlpFc2, rng, scale);
    } else if (obj is WindowAttention) {
      _randomInitTensors(obj.qkv, rng, scale);
      _randomInitTensors(obj.proj, rng, scale);
      _fillRandom(obj.relativePositionBiasTable, rng, scale);
    } else if (obj is PatchEmbed) {
      _randomInitTensors(obj.proj, rng, scale);
      _randomInitTensors(obj.norm, rng, scale);
    } else if (obj is PatchMerging) {
      _randomInitTensors(obj.reduction, rng, scale);
      _randomInitTensors(obj.norm, rng, scale);
    } else if (obj is BartDecoder) {
      _randomInitTensors(obj.embedTokens, rng, scale);
      _randomInitTensors(obj.embedPositions, rng, scale);
      _randomInitTensors(obj.layerNorm, rng, scale);
      _randomInitTensors(obj.lmHead, rng, scale);
      for (final layer in obj.layers) {
        _randomInitTensors(layer, rng, scale);
      }
    } else if (obj is BartDecoderLayer) {
      _randomInitTensors(obj.selfAttn, rng, scale);
      _randomInitTensors(obj.selfAttnLayerNorm, rng, scale);
      _randomInitTensors(obj.encoderAttn, rng, scale);
      _randomInitTensors(obj.encoderAttnLayerNorm, rng, scale);
      _randomInitTensors(obj.fc1, rng, scale);
      _randomInitTensors(obj.fc2, rng, scale);
      _randomInitTensors(obj.finalLayerNorm, rng, scale);
    } else if (obj is BartAttention) {
      _randomInitTensors(obj.qProj, rng, scale);
      _randomInitTensors(obj.kProj, rng, scale);
      _randomInitTensors(obj.vProj, rng, scale);
      _randomInitTensors(obj.outProj, rng, scale);
    } else if (obj is Linear) {
      _fillRandom(obj.weight, rng, scale);
      if (obj.bias != null) _fillRandom(obj.bias!, rng, scale * 0.1);
    } else if (obj is LayerNorm) {
      // LayerNorm weight should be ~1.0, bias ~0.0
      _fillRandom(obj.weight, rng, 0.01, mean: 1.0);
      _fillRandom(obj.bias, rng, 0.01);
    } else if (obj is Conv2d) {
      _fillRandom(obj.weight, rng, scale);
      if (obj.bias != null) _fillRandom(obj.bias!, rng, scale * 0.1);
    } else if (obj is Embedding) {
      _fillRandom(obj.weight, rng, scale);
    } else if (obj is MultiHeadAttention) {
      _randomInitTensors(obj.qProj, rng, scale);
      _randomInitTensors(obj.kProj, rng, scale);
      _randomInitTensors(obj.vProj, rng, scale);
      _randomInitTensors(obj.outProj, rng, scale);
    } else if (obj is FeedForward) {
      _randomInitTensors(obj.fc1, rng, scale);
      _randomInitTensors(obj.fc2, rng, scale);
    }
  }

  static void _fillRandom(Tensor t, math.Random rng, double scale,
      {double mean = 0.0}) {
    for (int i = 0; i < t.size; i++) {
      // Box-Muller for normal distribution
      final u1 = rng.nextDouble();
      final u2 = rng.nextDouble();
      final z = math.sqrt(-2.0 * math.log(u1 == 0 ? 1e-10 : u1)) *
          math.cos(2.0 * math.pi * u2);
      t.data[i] = (z * scale + mean).toDouble();
    }
  }

  /// Set the tokenizer.
  void setTokenizer(DonutTokenizer tok) {
    tokenizer = tok;
    decoder.tokenizer = tok;
  }

  /// Load a tokenizer from a HuggingFace tokenizer.json file.
  void loadTokenizerFromFile(String path) {
    tokenizer = DonutTokenizer.fromFile(path);
    decoder.tokenizer = tokenizer;
  }

  /// Load model weights from a directory containing safetensors or
  /// weight files.
  ///
  /// Expects the directory to contain:
  /// - `model.safetensors` or `pytorch_model.bin`
  /// - `config.json` (optional, overrides current config)
  /// - `tokenizer.json` (optional, loads tokenizer)
  Future<void> loadWeights(String directory) async {
    final loader = DonutWeightLoader(
      encoder: encoder,
      decoder: decoder,
    );
    await loader.loadFromDirectory(directory);
    _isLoaded = true;
  }

  /// Load weights from a map of tensor name → Tensor.
  void loadWeightsFromMap(Map<String, Tensor> weights) {
    final loader = DonutWeightLoader(
      encoder: encoder,
      decoder: decoder,
    );
    loader.loadFromMap(weights);
    _isLoaded = true;
  }

  /// Run the encoder on an image tensor.
  ///
  /// [imageTensor]: (batch, 3, height, width) — preprocessed image
  /// Returns: (batch, numPatches, encoderOutputDim)
  Tensor encode(Tensor imageTensor) {
    return encoder.forward(imageTensor);
  }

  /// Run the decoder to generate tokens given encoder output.
  ///
  /// [encoderOutput]: (1, numPatches, encoderOutputDim)
  /// [promptTokens]: initial tokens (e.g., task-specific start tokens)
  /// [maxLength]: maximum generation length
  /// [eosTokenId]: end-of-sequence token ID
  ///
  /// Returns generated token list.
  List<int> decode({
    required Tensor encoderOutput,
    required List<int> promptTokens,
    int? maxLength,
    int? eosTokenId,
  }) {
    return decoder.generate(
      encoderOutput: encoderOutput,
      promptTokens: promptTokens,
      maxLength: maxLength ?? config.maxLength,
      eosTokenId: eosTokenId ?? tokenizer?.eosTokenId,
    );
  }

  /// Run full inference: image → structured JSON output.
  ///
  /// [imageTensor]: preprocessed image tensor (1, 3, H, W)
  /// [prompt]: task prompt string (e.g., `<s_cord-v2>`, `<s_docvqa>`)
  /// [maxLength]: maximum generation length (default from config)
  ///
  /// Returns a [DonutResult] with raw tokens, decoded text, and parsed JSON.
  ///
  /// Example:
  /// ```dart
  /// // Document parsing (CORD receipt dataset)
  /// final result = model.inference(
  ///   imageTensor: preprocessedImage,
  ///   prompt: '<s_cord-v2>',
  /// );
  /// print(result.json);
  /// // {'menu': [{'nm': 'Lemon Tea', 'price': '3.50'}], ...}
  ///
  /// // Visual Question Answering
  /// final vqaResult = model.inference(
  ///   imageTensor: preprocessedImage,
  ///   prompt: '<s_docvqa><s_question>What is the total?</s_question><s_answer>',
  /// );
  /// print(vqaResult.text);
  /// ```
  DonutResult inference({
    required Tensor imageTensor,
    required String prompt,
    int? maxLength,
  }) {
    if (tokenizer == null) {
      throw StateError('Tokenizer not loaded. Call setTokenizer() or '
          'loadTokenizer() before inference.');
    }

    // 1. Encode image
    final encoderOutput = encode(imageTensor);

    // 2. Encode prompt to tokens
    final promptTokens = tokenizer!.encode(prompt);

    // 3. Generate tokens auto-regressively
    final generatedTokens = decode(
      encoderOutput: encoderOutput,
      promptTokens: promptTokens,
      maxLength: maxLength,
      eosTokenId: tokenizer!.eosTokenId,
    );

    // 4. Decode tokens to text
    final outputText = tokenizer!.decode(generatedTokens);

    // 5. Parse tokens to JSON
    final parsedJson = token2json(outputText);

    return DonutResult(
      tokens: generatedTokens,
      text: outputText,
      json: parsedJson,
    );
  }

  /// Run inference on raw image bytes.
  ///
  /// Handles preprocessing (resize, normalize) automatically.
  ///
  /// [imageBytes]: raw image file bytes (PNG, JPEG, etc.)
  /// [prompt]: task prompt string
  /// [maxLength]: maximum generation length
  DonutResult inferenceFromBytes({
    required List<int> imageBytes,
    required String prompt,
    int? maxLength,
  }) {
    final imageTensor = DonutImageUtils.preprocessBytes(imageBytes, config);
    return inference(
      imageTensor: imageTensor,
      prompt: prompt,
      maxLength: maxLength,
    );
  }

  // ─── JSON ↔ Token Conversion ──────────────────────────────────────────

  /// Convert a JSON object to a Donut token sequence.
  ///
  /// This converts structured JSON into the special token format used by
  /// Donut for sequence-to-sequence training/inference.
  ///
  /// Rules:
  ///   - dict → `<s_{key}>{value}</s_{key}>` for each key-value pair
  ///   - list → elements joined by `<sep/>`
  ///   - string/number → literal text
  ///
  /// Example:
  /// ```dart
  /// json2token({'menu': {'nm': 'Latte', 'price': '5.0'}})
  /// // → '<s_menu><s_nm>Latte</s_nm><s_price>5.0</s_price></s_menu>'
  /// ```
  static String json2token(dynamic obj,
      {bool updateSpecialTokens = true, DonutTokenizer? tokenizer}) {
    if (obj is Map<String, dynamic>) {
      final buf = StringBuffer();
      for (final entry in obj.entries) {
        buf.write('<s_${entry.key}>');
        buf.write(json2token(
          entry.value,
          updateSpecialTokens: updateSpecialTokens,
          tokenizer: tokenizer,
        ));
        buf.write('</s_${entry.key}>');

        if (updateSpecialTokens && tokenizer != null) {
          tokenizer.addSpecialTokens([
            '<s_${entry.key}>',
            '</s_${entry.key}>',
          ]);
        }
      }
      return buf.toString();
    } else if (obj is List) {
      final parts = obj.map((e) => json2token(
            e,
            updateSpecialTokens: updateSpecialTokens,
            tokenizer: tokenizer,
          ));
      if (updateSpecialTokens && tokenizer != null) {
        tokenizer.addSpecialTokens(['<sep/>']);
      }
      return parts.join('<sep/>');
    } else {
      return obj.toString();
    }
  }

  /// Convert a Donut token sequence back to a JSON object.
  ///
  /// Parses the special token format back into structured data.
  ///
  /// Example:
  /// ```dart
  /// token2json('<s_menu><s_nm>Latte</s_nm></s_menu>')
  /// // → {'menu': {'nm': 'Latte'}}
  /// ```
  static dynamic token2json(String tokenStr) {
    // Remove BOS/EOS tokens
    tokenStr = tokenStr
        .replaceAll(RegExp(r'</?s>'), '')
        .replaceAll(RegExp(r'<s_[^>]+>$'), '') // trailing open tags
        .trim();

    return _parseTokensToJson(tokenStr);
  }

  static dynamic _parseTokensToJson(String text) {
    // Find start tags <s_key>
    final startTagPattern = RegExp(r'<s_([^/>]+?)>');
    final firstMatch = startTagPattern.firstMatch(text);

    if (firstMatch == null) {
      // No tags found — this is a leaf value
      // Check for <sep/> (list separator)
      if (text.contains('<sep/>')) {
        return text.split('<sep/>').map((s) => s.trim()).toList();
      }
      return text.trim();
    }

    // Parse all key-value pairs at this level
    final result = <String, dynamic>{};
    var remaining = text;

    while (true) {
      final startMatch = startTagPattern.firstMatch(remaining);
      if (startMatch == null) break;

      final key = startMatch.group(1)!;
      final endTag = '</s_$key>';
      final endIdx = remaining.indexOf(endTag);

      if (endIdx == -1) {
        // Unclosed tag — take rest as value
        final value = remaining.substring(startMatch.end);
        result[key] = _parseTokensToJson(value.trim());
        break;
      }

      // Extract content between start and end tags
      final content = remaining.substring(startMatch.end, endIdx);

      // Check if content contains <sep/> at top level (list)
      if (_containsTopLevelSep(content)) {
        final items = _splitTopLevelSep(content);
        result[key] = items.map((s) => _parseTokensToJson(s.trim())).toList();
      } else {
        final parsed = _parseTokensToJson(content);
        // If key already exists, convert to list
        if (result.containsKey(key)) {
          if (result[key] is List) {
            (result[key] as List).add(parsed);
          } else {
            result[key] = [result[key], parsed];
          }
        } else {
          result[key] = parsed;
        }
      }

      remaining = remaining.substring(endIdx + endTag.length);
    }

    return result.isEmpty ? text.trim() : result;
  }

  /// Check if <sep/> appears at the top level (not nested inside tags).
  static bool _containsTopLevelSep(String text) {
    int depth = 0;
    int i = 0;
    while (i < text.length) {
      if (text.startsWith('<s_', i)) {
        depth++;
        i = text.indexOf('>', i) + 1;
        if (i == 0) break;
      } else if (text.startsWith('</s_', i)) {
        depth--;
        i = text.indexOf('>', i) + 1;
        if (i == 0) break;
      } else if (depth == 0 && text.startsWith('<sep/>', i)) {
        return true;
      } else {
        i++;
      }
    }
    return false;
  }

  /// Split text at top-level <sep/> markers.
  static List<String> _splitTopLevelSep(String text) {
    final parts = <String>[];
    int depth = 0;
    int lastSplit = 0;
    int i = 0;

    while (i < text.length) {
      if (text.startsWith('<s_', i)) {
        depth++;
        i = text.indexOf('>', i) + 1;
        if (i == 0) break;
      } else if (text.startsWith('</s_', i)) {
        depth--;
        i = text.indexOf('>', i) + 1;
        if (i == 0) break;
      } else if (depth == 0 && text.startsWith('<sep/>', i)) {
        parts.add(text.substring(lastSplit, i));
        i += '<sep/>'.length;
        lastSplit = i;
      } else {
        i++;
      }
    }

    if (lastSplit < text.length) {
      parts.add(text.substring(lastSplit));
    }

    return parts;
  }

  /// Prepare task-specific prompt tokens with special tokens added.
  ///
  /// Adds the required special tokens for a given task to the tokenizer
  /// and returns the encoded prompt.
  ///
  /// [task]: one of 'cord-v2', 'rvlcdip', 'docvqa', or a custom task name
  /// [question]: optional question text (for VQA tasks)
  String preparePrompt(String task, {String? question}) {
    final startToken = '<s_$task>';

    // Ensure special token exists
    tokenizer?.addSpecialTokens([startToken, '</s_$task>']);

    if (question != null) {
      tokenizer?.addSpecialTokens([
        '<s_question>',
        '</s_question>',
        '<s_answer>',
        '</s_answer>',
      ]);
      return '$startToken<s_question>$question</s_question><s_answer>';
    }

    return startToken;
  }

  /// Add task-specific special tokens for a dataset.
  ///
  /// This should be called before inference to ensure all task-specific
  /// tokens are in the vocabulary.
  ///
  /// [labels]: list of JSON objects representing ground truth labels.
  /// Each JSON object's keys define the special tokens needed.
  void addTaskTokens(List<Map<String, dynamic>> labels) {
    if (tokenizer == null) return;

    final tokens = <String>{};
    for (final label in labels) {
      _extractSpecialTokensFromJson(label, tokens);
    }

    tokenizer!.addSpecialTokens(tokens.toList());
  }

  void _extractSpecialTokensFromJson(dynamic obj, Set<String> tokens) {
    if (obj is Map<String, dynamic>) {
      for (final key in obj.keys) {
        tokens.add('<s_$key>');
        tokens.add('</s_$key>');
        _extractSpecialTokensFromJson(obj[key], tokens);
      }
    } else if (obj is List) {
      tokens.add('<sep/>');
      for (final item in obj) {
        _extractSpecialTokensFromJson(item, tokens);
      }
    }
  }

  /// Create a pre-configured model for CORD receipt parsing.
  ///
  /// Returns a model configured for the CORD-v2 dataset.
  /// Still requires loading weights via [loadWeights].
  factory DonutModel.cordV2() {
    final config = DonutConfig.base();
    final model = DonutModel(config);
    return model;
  }

  /// Create a pre-configured model for document classification (RVL-CDIP).
  factory DonutModel.rvlcdip() {
    final config = DonutConfig.base();
    return DonutModel(config);
  }

  /// Create a pre-configured model for document VQA.
  factory DonutModel.docvqa() {
    final config = DonutConfig.base();
    return DonutModel(config);
  }

  @override
  String toString() =>
      'DonutModel(encoder: SwinEncoder(${config.encoderLayer}), '
      'decoder: BartDecoder(${config.decoderLayer} layers), '
      'ready: $_isLoaded)';
}
