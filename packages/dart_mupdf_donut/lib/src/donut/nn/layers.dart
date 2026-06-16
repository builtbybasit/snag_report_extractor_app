/// Neural network layer implementations for Donut inference.
///
/// Provides pure Dart implementations of common neural network layers
/// including Linear, LayerNorm, Embedding, Conv2d, and activations.
/// These are inference-only (no gradient tracking).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../tensor/tensor.dart';

// ─── Linear Layer ──────────────────────────────────────────────────────

/// Fully connected (linear) layer: y = x @ W^T + b
///
/// Transforms input of shape (..., inFeatures) to (..., outFeatures).
class Linear {
  final int inFeatures;
  final int outFeatures;

  /// Weight matrix of shape (outFeatures, inFeatures).
  late Tensor weight;

  /// Optional bias vector of shape (outFeatures,).
  Tensor? bias;

  Linear(this.inFeatures, this.outFeatures, {bool useBias = true}) {
    weight = Tensor.zeros([outFeatures, inFeatures]);
    if (useBias) {
      bias = Tensor.zeros([outFeatures]);
    }
  }

  /// Forward pass: x @ weight^T + bias
  Tensor forward(Tensor input) {
    // input shape: (..., inFeatures)
    // weight shape: (outFeatures, inFeatures) → need W^T = (inFeatures, outFeatures)
    final wt = weight.transpose(0, 1); // (inFeatures, outFeatures)
    var output = input.matmul(wt); // (..., outFeatures)

    if (bias != null) {
      // Broadcast bias across batch dimensions
      output = output +
          bias!.reshape([
            for (int i = 0; i < output.ndim - 1; i++) 1,
            outFeatures
          ]).expand(output.shape);
    }
    return output;
  }
}

// ─── Layer Normalization ───────────────────────────────────────────────

/// Layer normalization over the last dimension.
///
/// Normalizes the input to zero mean and unit variance, then applies
/// learnable affine transform: y = (x - mean) / sqrt(var + eps) * gamma + beta
class LayerNorm {
  final int normalizedShape;
  final double eps;

  /// Scale parameter (gamma).
  late Tensor weight;

  /// Shift parameter (beta).
  late Tensor bias;

  LayerNorm(this.normalizedShape, {this.eps = 1e-5}) {
    weight = Tensor.ones([normalizedShape]);
    bias = Tensor.zeros([normalizedShape]);
  }

  /// Forward pass.
  Tensor forward(Tensor input) {
    // Normalize over the last dimension
    final batchSize = input.size ~/ normalizedShape;
    final result = Float32List(input.size);

    for (int b = 0; b < batchSize; b++) {
      final offset = b * normalizedShape;

      // Compute mean
      double mean = 0.0;
      for (int i = 0; i < normalizedShape; i++) {
        mean += input.data[offset + i];
      }
      mean /= normalizedShape;

      // Compute variance
      double variance = 0.0;
      for (int i = 0; i < normalizedShape; i++) {
        final diff = input.data[offset + i] - mean;
        variance += diff * diff;
      }
      variance /= normalizedShape;

      // Normalize and apply affine
      final invStd = 1.0 / math.sqrt(variance + eps);
      for (int i = 0; i < normalizedShape; i++) {
        result[offset + i] =
            ((input.data[offset + i] - mean) * invStd) * weight.data[i] +
                bias.data[i];
      }
    }

    return Tensor(result, List<int>.from(input.shape));
  }
}

// ─── Embedding Layer ───────────────────────────────────────────────────

/// Lookup table embedding layer.
///
/// Maps integer token IDs to dense vectors.
class Embedding {
  final int numEmbeddings;
  final int embeddingDim;
  int? paddingIdx;

  /// Embedding weight matrix (numEmbeddings, embeddingDim).
  late Tensor weight;

  Embedding(this.numEmbeddings, this.embeddingDim, {this.paddingIdx}) {
    weight = Tensor.zeros([numEmbeddings, embeddingDim]);
  }

  /// Forward pass: lookup embeddings for given token IDs.
  ///
  /// [indices] is a list of integer token IDs.
  /// Returns tensor of shape (indices.length, embeddingDim).
  Tensor forward(List<int> indices) {
    final n = indices.length;
    final result = Float32List(n * embeddingDim);
    for (int i = 0; i < n; i++) {
      final idx = indices[i];
      if (idx < 0 || idx >= numEmbeddings) {
        throw RangeError(
            'Embedding index $idx out of range [0, $numEmbeddings)');
      }
      final srcOffset = idx * embeddingDim;
      final dstOffset = i * embeddingDim;
      for (int j = 0; j < embeddingDim; j++) {
        result[dstOffset + j] = weight.data[srcOffset + j];
      }
    }
    return Tensor(result, [n, embeddingDim]);
  }

  /// Batch forward: indices is shape (batch, seqLen), returns (batch, seqLen, embeddingDim).
  Tensor forwardBatch(Tensor indices) {
    // indices contains integer values as floats
    final batch = indices.shape[0];
    final seqLen = indices.shape[1];
    final result = Float32List(batch * seqLen * embeddingDim);

    for (int b = 0; b < batch; b++) {
      for (int s = 0; s < seqLen; s++) {
        final idx = indices.data[b * seqLen + s].toInt();
        if (idx < 0 || idx >= numEmbeddings) continue;
        final srcOffset = idx * embeddingDim;
        final dstOffset = (b * seqLen + s) * embeddingDim;
        for (int j = 0; j < embeddingDim; j++) {
          result[dstOffset + j] = weight.data[srcOffset + j];
        }
      }
    }
    return Tensor(result, [batch, seqLen, embeddingDim]);
  }
}

// ─── Conv2d Layer ──────────────────────────────────────────────────────

/// 2D Convolution layer.
///
/// Applies a 2D convolution over an input image tensor.
/// Input shape: (batch, inChannels, height, width)
/// Output shape: (batch, outChannels, outH, outW)
class Conv2d {
  final int inChannels;
  final int outChannels;
  final int kernelSize;
  final int stride;
  final int padding;

  /// Weight tensor (outChannels, inChannels, kernelSize, kernelSize).
  late Tensor weight;

  /// Bias tensor (outChannels,).
  Tensor? bias;

  Conv2d(
    this.inChannels,
    this.outChannels,
    this.kernelSize, {
    this.stride = 1,
    this.padding = 0,
    bool useBias = true,
  }) {
    weight = Tensor.zeros([outChannels, inChannels, kernelSize, kernelSize]);
    if (useBias) {
      bias = Tensor.zeros([outChannels]);
    }
  }

  /// Forward pass.
  Tensor forward(Tensor input) {
    final batch = input.shape[0];
    final inH = input.shape[2];
    final inW = input.shape[3];
    final outH = (inH + 2 * padding - kernelSize) ~/ stride + 1;
    final outW = (inW + 2 * padding - kernelSize) ~/ stride + 1;

    final output = Float32List(batch * outChannels * outH * outW);

    for (int b = 0; b < batch; b++) {
      for (int oc = 0; oc < outChannels; oc++) {
        for (int oh = 0; oh < outH; oh++) {
          for (int ow = 0; ow < outW; ow++) {
            double sum = 0.0;
            for (int ic = 0; ic < inChannels; ic++) {
              for (int kh = 0; kh < kernelSize; kh++) {
                for (int kw = 0; kw < kernelSize; kw++) {
                  final ih = oh * stride - padding + kh;
                  final iw = ow * stride - padding + kw;
                  if (ih >= 0 && ih < inH && iw >= 0 && iw < inW) {
                    final inputIdx =
                        ((b * inChannels + ic) * inH + ih) * inW + iw;
                    final weightIdx =
                        ((oc * inChannels + ic) * kernelSize + kh) *
                                kernelSize +
                            kw;
                    sum += input.data[inputIdx] * weight.data[weightIdx];
                  }
                }
              }
            }
            if (bias != null) {
              sum += bias!.data[oc];
            }
            output[((b * outChannels + oc) * outH + oh) * outW + ow] = sum;
          }
        }
      }
    }

    return Tensor(output, [batch, outChannels, outH, outW]);
  }
}

// ─── Dropout ───────────────────────────────────────────────────────────

/// Dropout layer — identity in inference mode.
class Dropout {
  final double p;
  Dropout([this.p = 0.0]);

  /// In inference mode, dropout is a no-op.
  Tensor forward(Tensor input) => input;
}

// ─── Activation Functions ──────────────────────────────────────────────

/// GELU activation function (Gaussian Error Linear Unit).
class GELU {
  Tensor forward(Tensor input) => input.gelu();
}

/// ReLU activation function.
class ReLU {
  Tensor forward(Tensor input) => input.relu();
}

/// Softmax activation along a dimension.
class Softmax {
  final int dim;
  Softmax(this.dim);

  Tensor forward(Tensor input) => input.softmax(dim);
}

// ─── Multi-Head Attention ──────────────────────────────────────────────

/// Scaled dot-product multi-head attention.
///
/// Supports both self-attention and cross-attention.
class MultiHeadAttention {
  final int embedDim;
  final int numHeads;
  final int headDim;

  late Linear qProj;
  late Linear kProj;
  late Linear vProj;
  late Linear outProj;

  MultiHeadAttention(this.embedDim, this.numHeads)
      : headDim = embedDim ~/ numHeads {
    qProj = Linear(embedDim, embedDim);
    kProj = Linear(embedDim, embedDim);
    vProj = Linear(embedDim, embedDim);
    outProj = Linear(embedDim, embedDim);
  }

  /// Forward pass.
  ///
  /// [query]: (batch, seqLen, embedDim)
  /// [key]: (batch, kvLen, embedDim) — if null, uses query (self-attention)
  /// [value]: (batch, kvLen, embedDim) — if null, uses query
  /// [mask]: optional attention mask (seqLen, kvLen) or (batch, seqLen, kvLen)
  Tensor forward(
    Tensor query, {
    Tensor? key,
    Tensor? value,
    Tensor? mask,
  }) {
    key ??= query;
    value ??= query;

    final batch = query.shape[0];
    final seqLen = query.shape[1];
    final kvLen = key.shape[1];
    final scale = 1.0 / math.sqrt(headDim.toDouble());

    // Project Q, K, V
    var q = qProj.forward(query); // (batch, seqLen, embedDim)
    var k = kProj.forward(key); // (batch, kvLen, embedDim)
    var v = vProj.forward(value); // (batch, kvLen, embedDim)

    // Reshape to (batch, numHeads, seqLen/kvLen, headDim)
    q = q.reshape([batch, seqLen, numHeads, headDim]).permute(
        [0, 2, 1, 3]); // (batch, numHeads, seqLen, headDim)
    k = k.reshape([batch, kvLen, numHeads, headDim]).permute(
        [0, 2, 1, 3]); // (batch, numHeads, kvLen, headDim)
    v = v.reshape([batch, kvLen, numHeads, headDim]).permute(
        [0, 2, 1, 3]); // (batch, numHeads, kvLen, headDim)

    // Attention scores: Q @ K^T / sqrt(d)
    final kT = k.transpose(2, 3); // (batch, numHeads, headDim, kvLen)
    var attnWeights =
        q.matmul(kT).mulScalar(scale); // (batch, numHeads, seqLen, kvLen)

    // Apply mask
    if (mask != null) {
      if (mask.ndim == 2) {
        // Expand to (1, 1, seqLen, kvLen)
        final expandedMask =
            mask.unsqueeze(0).unsqueeze(0).expand(attnWeights.shape);
        attnWeights = attnWeights + expandedMask;
      } else if (mask.ndim == 3) {
        final expandedMask = mask.unsqueeze(1).expand(attnWeights.shape);
        attnWeights = attnWeights + expandedMask;
      } else {
        attnWeights = attnWeights + mask;
      }
    }

    // Softmax
    attnWeights = attnWeights.softmax(-1);

    // Weighted sum of values
    var attnOutput =
        attnWeights.matmul(v); // (batch, numHeads, seqLen, headDim)

    // Reshape back to (batch, seqLen, embedDim)
    attnOutput =
        attnOutput.permute([0, 2, 1, 3]).reshape([batch, seqLen, embedDim]);

    // Output projection
    return outProj.forward(attnOutput);
  }
}

// ─── Feed-Forward Network ──────────────────────────────────────────────

/// Position-wise feed-forward network: Linear → GELU → Linear
class FeedForward {
  late Linear fc1;
  late Linear fc2;
  final GELU activation = GELU();

  FeedForward(int embedDim, int ffnDim) {
    fc1 = Linear(embedDim, ffnDim);
    fc2 = Linear(ffnDim, embedDim);
  }

  Tensor forward(Tensor input) {
    var x = fc1.forward(input);
    x = activation.forward(x);
    return fc2.forward(x);
  }
}
