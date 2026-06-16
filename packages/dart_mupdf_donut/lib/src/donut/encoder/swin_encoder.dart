/// Swin Transformer encoder for Donut — pure Dart implementation.
///
/// Implements the full Swin Transformer architecture used as the visual
/// encoder in the Donut model. Converts document images into sequence
/// of embeddings without requiring OCR.
///
/// Architecture:
///   PatchEmbed → [SwinTransformerBlock × depth + PatchMerging] × numLayers
///
/// Reference: "Swin Transformer: Hierarchical Vision Transformer using
/// Shifted Windows" (Liu et al., 2021)
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../tensor/tensor.dart';
import '../nn/layers.dart';

// ─── Patch Embedding ───────────────────────────────────────────────────

/// Splits the input image into non-overlapping patches and projects them
/// to an embedding space using a convolution.
///
/// Input: (batch, 3, height, width) → Output: (batch, numPatches, embedDim)
class PatchEmbed {
  final int patchSize;
  final int inChannels;
  final int embedDim;
  late Conv2d proj;
  late LayerNorm norm;
  late int numPatchesH;
  late int numPatchesW;

  PatchEmbed({
    required List<int> imgSize,
    this.patchSize = 4,
    this.inChannels = 3,
    this.embedDim = 128,
  }) {
    proj = Conv2d(inChannels, embedDim, patchSize, stride: patchSize);
    norm = LayerNorm(embedDim);
    numPatchesH = imgSize[0] ~/ patchSize;
    numPatchesW = imgSize[1] ~/ patchSize;
  }

  /// Number of patches.
  int get numPatches => numPatchesH * numPatchesW;

  /// Forward pass.
  ///
  /// Input: (batch, channels, height, width)
  /// Output: (batch, numPatches, embedDim)
  Tensor forward(Tensor x) {
    final batch = x.shape[0];
    // Conv2d: (batch, 3, H, W) → (batch, embedDim, H/patch, W/patch)
    var out = proj.forward(x);
    final h = out.shape[2];
    final w = out.shape[3];
    // Reshape and permute: (batch, embedDim, h, w) → (batch, h*w, embedDim)
    out = out.reshape([batch, embedDim, h * w]).permute([0, 2, 1]);
    // LayerNorm
    out = norm.forward(out);
    return out;
  }
}

// ─── Window Attention ──────────────────────────────────────────────────

/// Window-based multi-head self attention (W-MSA / SW-MSA).
///
/// Attention is computed within local windows of size windowSize × windowSize.
/// Relative position bias is added to attention scores.
class WindowAttention {
  final int dim;
  final int windowSize;
  final int numHeads;
  final int headDim;

  late Linear qkv;
  late Linear proj;

  /// Relative position bias table: (2*windowSize-1)*(2*windowSize-1), numHeads
  late Tensor relativePositionBiasTable;

  /// Relative position index: (windowSize*windowSize, windowSize*windowSize)
  late Tensor relativePositionIndex;

  WindowAttention({
    required this.dim,
    required this.windowSize,
    required this.numHeads,
  }) : headDim = dim ~/ numHeads {
    qkv = Linear(dim, dim * 3);
    proj = Linear(dim, dim);

    final biasTableSize = (2 * windowSize - 1) * (2 * windowSize - 1);
    relativePositionBiasTable = Tensor.zeros([biasTableSize, numHeads]);

    // Compute relative position index
    _computeRelativePositionIndex();
  }

  void _computeRelativePositionIndex() {
    final ws = windowSize;

    // coords: 2D grid
    final relCoords = <int>[];
    for (int h1 = 0; h1 < ws; h1++) {
      for (int w1 = 0; w1 < ws; w1++) {
        for (int h2 = 0; h2 < ws; h2++) {
          for (int w2 = 0; w2 < ws; w2++) {
            final relH = h1 - h2 + ws - 1;
            final relW = w1 - w2 + ws - 1;
            relCoords.add(relH * (2 * ws - 1) + relW);
          }
        }
      }
    }

    final n = ws * ws;
    relativePositionIndex = Tensor(
      Float32List.fromList(relCoords.map((e) => e.toDouble()).toList()),
      [n, n],
    );
  }

  /// Forward pass.
  ///
  /// [x]: (numWindows*batch, windowSize*windowSize, dim)
  /// [mask]: optional attention mask (numWindows, windowSize*windowSize, windowSize*windowSize)
  Tensor forward(Tensor x, {Tensor? mask}) {
    final bw = x.shape[0]; // numWindows * batch
    final n = x.shape[1]; // windowSize * windowSize
    final scale = 1.0 / math.sqrt(headDim.toDouble());

    // QKV projection
    var qkvOut = qkv.forward(x); // (bw, n, 3*dim)
    qkvOut = qkvOut.reshape([bw, n, 3, numHeads, headDim]);
    qkvOut = qkvOut.permute([2, 0, 3, 1, 4]); // (3, bw, numHeads, n, headDim)

    final q = qkvOut[0]; // (bw, numHeads, n, headDim)
    final k = qkvOut[1];
    final v = qkvOut[2];

    // Attention scores
    final kT = k.transpose(2, 3); // (bw, numHeads, headDim, n)
    var attn = q.matmul(kT).mulScalar(scale); // (bw, numHeads, n, n)

    // Add relative position bias
    final bias = _getRelativePositionBias();
    attn = attn + bias.unsqueeze(0).expand(attn.shape);

    // Apply window mask if provided
    if (mask != null) {
      final numWindows = mask.shape[0];
      final batch = bw ~/ numWindows;
      attn = attn.reshape([batch, numWindows, numHeads, n, n]);
      final expandedMask = mask.unsqueeze(1).unsqueeze(0).expand(attn.shape);
      attn = attn + expandedMask;
      attn = attn.reshape([bw, numHeads, n, n]);
    }

    // Softmax
    attn = attn.softmax(-1);

    // Apply attention to values
    var output = attn.matmul(v); // (bw, numHeads, n, headDim)
    output = output.permute([0, 2, 1, 3]).reshape([bw, n, dim]);

    // Output projection
    return proj.forward(output);
  }

  Tensor _getRelativePositionBias() {
    final n = windowSize * windowSize;
    final result = Float32List(numHeads * n * n);

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        final tableIdx = relativePositionIndex.data[i * n + j].toInt();
        for (int h = 0; h < numHeads; h++) {
          result[h * n * n + i * n + j] =
              relativePositionBiasTable.data[tableIdx * numHeads + h];
        }
      }
    }

    return Tensor(result, [numHeads, n, n]);
  }
}

// ─── Swin Transformer Block ───────────────────────────────────────────

/// A single Swin Transformer block with window attention.
///
/// Alternates between regular windows (shiftSize=0) and shifted windows
/// (shiftSize=windowSize/2) to enable cross-window connections.
class SwinTransformerBlock {
  final int dim;
  final int numHeads;
  final int windowSize;
  final int shiftSize;
  final double mlpRatio;

  late LayerNorm norm1;
  late WindowAttention attn;
  late LayerNorm norm2;
  late Linear mlpFc1;
  late Linear mlpFc2;

  SwinTransformerBlock({
    required this.dim,
    required this.numHeads,
    required this.windowSize,
    this.shiftSize = 0,
    this.mlpRatio = 4.0,
  }) {
    norm1 = LayerNorm(dim);
    attn = WindowAttention(
      dim: dim,
      windowSize: windowSize,
      numHeads: numHeads,
    );
    norm2 = LayerNorm(dim);
    final mlpHiddenDim = (dim * mlpRatio).toInt();
    mlpFc1 = Linear(dim, mlpHiddenDim);
    mlpFc2 = Linear(mlpHiddenDim, dim);
  }

  /// Forward pass.
  ///
  /// [x]: (batch, height*width, dim)
  /// [h], [w]: spatial dimensions
  Tensor forward(Tensor x, int h, int w) {
    final batch = x.shape[0];
    final n = h * w;

    // ─── Window Attention ───────────────────────────────
    var shortcut = x;
    x = norm1.forward(x);

    // Reshape to 2D: (batch, h, w, dim)
    x = x.reshape([batch, h, w, dim]);

    // Cyclic shift
    Tensor? attnMask;
    if (shiftSize > 0) {
      x = _cyclicShift(x, -shiftSize, h, w);
      attnMask = _computeAttnMask(h, w);
    }

    // Partition into windows: (numWindows*batch, windowSize, windowSize, dim)
    final windows = _windowPartition(x, windowSize);

    // Reshape windows to (numWindows*batch, windowSize*windowSize, dim)
    final nw = windows.shape[0];
    final windowedX = windows.reshape([nw, windowSize * windowSize, dim]);

    // Window attention
    var attnOutput = attn.forward(windowedX, mask: attnMask);

    // Merge windows back: (batch, h, w, dim)
    attnOutput = attnOutput.reshape([nw, windowSize, windowSize, dim]);
    x = _windowReverse(attnOutput, windowSize, h, w, batch);

    // Reverse cyclic shift
    if (shiftSize > 0) {
      x = _cyclicShift(x, shiftSize, h, w);
    }

    // Reshape back to (batch, h*w, dim)
    x = x.reshape([batch, n, dim]);

    // Residual connection
    x = shortcut + x;

    // ─── MLP ────────────────────────────────────────────
    shortcut = x;
    x = norm2.forward(x);
    x = mlpFc1.forward(x);
    x = x.gelu();
    x = mlpFc2.forward(x);
    x = shortcut + x;

    return x;
  }

  /// Compute attention mask for shifted window attention.
  Tensor? _computeAttnMask(int h, int w) {
    if (shiftSize == 0) return null;

    // Create region map
    final imgMask = List.filled(h * w, 0);
    int cnt = 0;
    final hSlices = [
      [0, h - windowSize],
      [h - windowSize, h - shiftSize],
      [h - shiftSize, h]
    ];
    final wSlices = [
      [0, w - windowSize],
      [w - windowSize, w - shiftSize],
      [w - shiftSize, w]
    ];

    for (final hs in hSlices) {
      for (final ws in wSlices) {
        for (int hh = hs[0]; hh < hs[1]; hh++) {
          for (int ww = ws[0]; ww < ws[1]; ww++) {
            imgMask[hh * w + ww] = cnt;
          }
        }
        cnt++;
      }
    }

    // Partition into windows
    final numWinH = h ~/ windowSize;
    final numWinW = w ~/ windowSize;
    final numWindows = numWinH * numWinW;
    final ws2 = windowSize * windowSize;
    final maskWindows = Float32List(numWindows * ws2);

    for (int wh = 0; wh < numWinH; wh++) {
      for (int ww = 0; ww < numWinW; ww++) {
        final winIdx = wh * numWinW + ww;
        for (int i = 0; i < windowSize; i++) {
          for (int j = 0; j < windowSize; j++) {
            maskWindows[winIdx * ws2 + i * windowSize + j] =
                imgMask[(wh * windowSize + i) * w + ww * windowSize + j]
                    .toDouble();
          }
        }
      }
    }

    // Compute mask: (numWindows, ws2, ws2)
    final attnMask = Float32List(numWindows * ws2 * ws2);
    for (int win = 0; win < numWindows; win++) {
      for (int i = 0; i < ws2; i++) {
        for (int j = 0; j < ws2; j++) {
          final val = maskWindows[win * ws2 + i] - maskWindows[win * ws2 + j];
          attnMask[win * ws2 * ws2 + i * ws2 + j] = val != 0 ? -100.0 : 0.0;
        }
      }
    }

    return Tensor(attnMask, [numWindows, ws2, ws2]);
  }
}

// ─── Patch Merging ─────────────────────────────────────────────────────

/// Downsamples the spatial resolution by 2x and doubles the channel dimension.
///
/// Takes patches in 2x2 regions, concatenates them, then projects to 2*dim.
class PatchMerging {
  final int dim;
  late LayerNorm norm;
  late Linear reduction;

  PatchMerging(this.dim) {
    norm = LayerNorm(4 * dim);
    reduction = Linear(4 * dim, 2 * dim, useBias: false);
  }

  /// Forward pass.
  ///
  /// Input: (batch, h*w, dim) with h, w as spatial dims
  /// Output: (batch, h/2*w/2, 2*dim)
  Tensor forward(Tensor x, int h, int w) {
    final batch = x.shape[0];

    // Reshape to spatial: (batch, h, w, dim)
    x = x.reshape([batch, h, w, dim]);

    final newH = h ~/ 2;
    final newW = w ~/ 2;

    // Extract 4 sub-grids
    final outData = Float32List(batch * newH * newW * 4 * dim);

    for (int b = 0; b < batch; b++) {
      for (int i = 0; i < newH; i++) {
        for (int j = 0; j < newW; j++) {
          final dstBase = ((b * newH + i) * newW + j) * 4 * dim;
          // Top-left
          _copyPatch(x, b, 2 * i, 2 * j, w, dim, outData, dstBase);
          // Top-right
          _copyPatch(x, b, 2 * i, 2 * j + 1, w, dim, outData, dstBase + dim);
          // Bottom-left
          _copyPatch(
              x, b, 2 * i + 1, 2 * j, w, dim, outData, dstBase + 2 * dim);
          // Bottom-right
          _copyPatch(
              x, b, 2 * i + 1, 2 * j + 1, w, dim, outData, dstBase + 3 * dim);
        }
      }
    }

    var merged = Tensor(outData, [batch, newH * newW, 4 * dim]);

    // Layer norm then linear projection
    merged = norm.forward(merged);
    merged = reduction.forward(merged);

    return merged;
  }

  void _copyPatch(Tensor x, int b, int h, int w, int W, int dim,
      Float32List dst, int dstOffset) {
    final srcOffset = ((b * x.shape[1] + h) * W + w) * dim;
    for (int d = 0; d < dim; d++) {
      dst[dstOffset + d] = x.data[srcOffset + d];
    }
  }
}

// ─── Swin Layer ────────────────────────────────────────────────────────

/// A single Swin Transformer stage consisting of multiple blocks
/// and an optional patch merging downsample layer.
class SwinLayer {
  final int dim;
  final int depth;
  final int numHeads;
  final int windowSize;
  final bool downsample;

  late List<SwinTransformerBlock> blocks;
  PatchMerging? patchMerging;

  SwinLayer({
    required this.dim,
    required this.depth,
    required this.numHeads,
    required this.windowSize,
    this.downsample = true,
  }) {
    blocks = List.generate(
      depth,
      (i) => SwinTransformerBlock(
        dim: dim,
        numHeads: numHeads,
        windowSize: windowSize,
        shiftSize: i % 2 == 0 ? 0 : windowSize ~/ 2,
      ),
    );

    if (downsample) {
      patchMerging = PatchMerging(dim);
    }
  }

  /// Forward pass.
  ///
  /// Input: (batch, h*w, dim)
  /// Output: (batch, h'*w', dim') where h',w' may be halved
  Tensor forward(Tensor x, int h, int w) {
    for (final block in blocks) {
      x = block.forward(x, h, w);
    }

    if (patchMerging != null) {
      x = patchMerging!.forward(x, h, w);
    }

    return x;
  }
}

// ─── Swin Encoder (Full) ──────────────────────────────────────────────

/// Complete Swin Transformer encoder as used in Donut.
///
/// Converts an input document image into a sequence of embeddings
/// that can be used as input to the BART decoder.
///
/// Architecture:
/// 1. PatchEmbed: Split image into patches, project to embedDim
/// 2. Multiple SwinLayers: Hierarchical feature extraction with
///    window attention and patch merging
///
/// Default config (donut-base):
///   - embedDim: 128
///   - depths: [2, 2, 14, 2]
///   - numHeads: [4, 8, 16, 32]
///   - windowSize: 10
///   - patchSize: 4
class SwinEncoder {
  final List<int> inputSize;
  final bool alignLongAxis;
  final int windowSize;
  final List<int> encoderLayer;
  final int embedDim;
  final List<int> numHeads;
  final int patchSize;

  late PatchEmbed patchEmbed;
  late List<SwinLayer> layers;
  late Dropout posDropout;

  // Spatial dimensions at each stage
  late int patchH;
  late int patchW;

  SwinEncoder({
    required this.inputSize,
    this.alignLongAxis = false,
    this.windowSize = 10,
    this.encoderLayer = const [2, 2, 14, 2],
    this.embedDim = 128,
    this.numHeads = const [4, 8, 16, 32],
    this.patchSize = 4,
  }) {
    patchEmbed = PatchEmbed(
      imgSize: inputSize,
      patchSize: patchSize,
      embedDim: embedDim,
    );

    patchH = inputSize[0] ~/ patchSize;
    patchW = inputSize[1] ~/ patchSize;

    posDropout = Dropout();

    layers = [];
    int currentDim = embedDim;
    for (int i = 0; i < encoderLayer.length; i++) {
      final isLast = i == encoderLayer.length - 1;
      layers.add(SwinLayer(
        dim: currentDim,
        depth: encoderLayer[i],
        numHeads: numHeads[i],
        windowSize: windowSize,
        downsample: !isLast,
      ));
      if (!isLast) {
        currentDim *= 2;
      }
    }
  }

  /// Get the output dimension of the encoder.
  int get outputDim {
    int d = embedDim;
    for (int i = 0; i < encoderLayer.length - 1; i++) {
      d *= 2;
    }
    return d;
  }

  /// Forward pass.
  ///
  /// Input: (batch, 3, height, width) — preprocessed document image
  /// Output: (batch, numTokens, outputDim) — sequence of embeddings
  Tensor forward(Tensor x) {
    // Patch embedding: (batch, 3, H, W) → (batch, numPatches, embedDim)
    x = patchEmbed.forward(x);
    x = posDropout.forward(x);

    int h = patchH;
    int w = patchW;

    // Apply Swin layers
    for (int i = 0; i < layers.length; i++) {
      x = layers[i].forward(x, h, w);
      if (layers[i].patchMerging != null) {
        h = h ~/ 2;
        w = w ~/ 2;
      }
    }

    return x;
  }
}

// ─── Helper Functions ──────────────────────────────────────────────────

/// Partition feature map into windows.
///
/// Input: (batch, h, w, dim)
/// Output: (numWindows*batch, windowSize, windowSize, dim)
Tensor _windowPartition(Tensor x, int windowSize) {
  final batch = x.shape[0];
  final h = x.shape[1];
  final w = x.shape[2];
  final dim = x.shape[3];

  final numWinH = h ~/ windowSize;
  final numWinW = w ~/ windowSize;
  final numWindows = numWinH * numWinW;

  final result =
      Float32List(batch * numWindows * windowSize * windowSize * dim);
  final ws = windowSize;

  for (int b = 0; b < batch; b++) {
    for (int wh = 0; wh < numWinH; wh++) {
      for (int ww = 0; ww < numWinW; ww++) {
        final winIdx = b * numWindows + wh * numWinW + ww;
        for (int i = 0; i < ws; i++) {
          for (int j = 0; j < ws; j++) {
            final srcH = wh * ws + i;
            final srcW = ww * ws + j;
            final srcOffset = ((b * h + srcH) * w + srcW) * dim;
            final dstOffset = ((winIdx * ws + i) * ws + j) * dim;
            for (int d = 0; d < dim; d++) {
              result[dstOffset + d] = x.data[srcOffset + d];
            }
          }
        }
      }
    }
  }

  return Tensor(result, [batch * numWindows, ws, ws, dim]);
}

/// Reverse window partition back to feature map.
///
/// Input: (numWindows*batch, windowSize, windowSize, dim)
/// Output: (batch, h, w, dim)
Tensor _windowReverse(Tensor windows, int windowSize, int h, int w, int batch) {
  final dim = windows.shape[3];
  final numWinH = h ~/ windowSize;
  final numWinW = w ~/ windowSize;
  final numWindows = numWinH * numWinW;
  final ws = windowSize;

  final result = Float32List(batch * h * w * dim);

  for (int b = 0; b < batch; b++) {
    for (int wh = 0; wh < numWinH; wh++) {
      for (int ww = 0; ww < numWinW; ww++) {
        final winIdx = b * numWindows + wh * numWinW + ww;
        for (int i = 0; i < ws; i++) {
          for (int j = 0; j < ws; j++) {
            final srcOffset = ((winIdx * ws + i) * ws + j) * dim;
            final dstH = wh * ws + i;
            final dstW = ww * ws + j;
            final dstOffset = ((b * h + dstH) * w + dstW) * dim;
            for (int d = 0; d < dim; d++) {
              result[dstOffset + d] = windows.data[srcOffset + d];
            }
          }
        }
      }
    }
  }

  return Tensor(result, [batch, h, w, dim]);
}

/// Cyclic shift of a 4D tensor along height and width.
///
/// Input: (batch, h, w, dim)
Tensor _cyclicShift(Tensor x, int shift, int h, int w) {
  final batch = x.shape[0];
  final dim = x.shape[3];
  final result = Float32List(x.size);

  for (int b = 0; b < batch; b++) {
    for (int i = 0; i < h; i++) {
      for (int j = 0; j < w; j++) {
        final srcI = ((i - shift) % h + h) % h;
        final srcJ = ((j - shift) % w + w) % w;
        final srcOffset = ((b * h + srcI) * w + srcJ) * dim;
        final dstOffset = ((b * h + i) * w + j) * dim;
        for (int d = 0; d < dim; d++) {
          result[dstOffset + d] = x.data[srcOffset + d];
        }
      }
    }
  }

  return Tensor(result, List<int>.from(x.shape));
}
