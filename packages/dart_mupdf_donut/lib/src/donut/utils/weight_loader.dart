/// Weight loader for Donut model — safetensors and JSON format.
///
/// Loads pretrained model weights from HuggingFace-format weight files
/// and maps them to the Dart model's parameters.
///
/// Supported formats:
/// - **Safetensors**: Efficient binary format used by HuggingFace (`model.safetensors`)
/// - **JSON weights**: Portable JSON format with base64-encoded tensors
///
/// The loader maps Python-style weight names (e.g., `encoder.layers.0.blocks.0.attn.qkv.weight`)
/// to the corresponding Dart model parameters.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../tensor/tensor.dart';
import '../encoder/swin_encoder.dart';
import '../decoder/bart_decoder.dart';

/// Loads pretrained weights into a Donut model.
///
/// Supports loading from a directory with safetensors files or from an
/// in-memory weight map.
///
/// Weight name mapping follows the HuggingFace Donut naming convention:
///
/// **Encoder weights:**
/// - `encoder.model.patch_embed.proj.weight` → PatchEmbed.proj
/// - `encoder.model.layers.{i}.blocks.{j}.attn.*` → WindowAttention
/// - `encoder.model.layers.{i}.downsample.*` → PatchMerging
///
/// **Decoder weights:**
/// - `decoder.model.decoder.embed_tokens.weight` → token embeddings
/// - `decoder.model.decoder.embed_positions.weight` → position embeddings
/// - `decoder.model.decoder.layers.{i}.*` → decoder layers
/// - `decoder.model.lm_head.weight` → output projection
class DonutWeightLoader {
  final SwinEncoder encoder;
  final BartDecoder decoder;

  DonutWeightLoader({
    required this.encoder,
    required this.decoder,
  });

  /// Load weights from a directory.
  ///
  /// Searches in order:
  /// 1. `model.safetensors`
  /// 2. `weights.json`
  Future<void> loadFromDirectory(String directory) async {
    final safetensorsFile = File('$directory/model.safetensors');
    if (await safetensorsFile.exists()) {
      final weights = await _loadSafetensors(safetensorsFile);
      loadFromMap(weights);
      return;
    }

    final jsonFile = File('$directory/weights.json');
    if (await jsonFile.exists()) {
      final weights = await _loadJsonWeights(jsonFile);
      loadFromMap(weights);
      return;
    }

    throw FileSystemException(
      'No weight file found in directory. '
      'Expected model.safetensors or weights.json',
      directory,
    );
  }

  /// Load weights from an in-memory map.
  ///
  /// [weights]: map of parameter name → Tensor
  void loadFromMap(Map<String, Tensor> weights) {
    for (final entry in weights.entries) {
      try {
        _loadSingleWeight(entry.key, entry.value);
      } catch (_) {
        // Silently skip weights that don't match
      }
    }
  }

  /// Load a single weight by name.
  /// Returns true if the weight was loaded, false if skipped.
  bool _loadSingleWeight(String name, Tensor tensor) {
    // ─── Encoder weights ───────────────────────────────────────

    // Patch embedding
    if (name == 'encoder.model.patch_embed.proj.weight' ||
        name == 'encoder.patch_embed.proj.weight') {
      encoder.patchEmbed.proj.weight = tensor;
      return true;
    }
    if (name == 'encoder.model.patch_embed.proj.bias' ||
        name == 'encoder.patch_embed.proj.bias') {
      encoder.patchEmbed.proj.bias = tensor;
      return true;
    }
    if (name == 'encoder.model.patch_embed.norm.weight' ||
        name == 'encoder.patch_embed.norm.weight') {
      encoder.patchEmbed.norm.weight = tensor;
      return true;
    }
    if (name == 'encoder.model.patch_embed.norm.bias' ||
        name == 'encoder.patch_embed.norm.bias') {
      encoder.patchEmbed.norm.bias = tensor;
      return true;
    }

    // Swin layers
    final swinLayerMatch = RegExp(
      r'encoder\.(?:model\.)?layers\.(\d+)\.(.+)',
    ).firstMatch(name);
    if (swinLayerMatch != null) {
      final layerIdx = int.parse(swinLayerMatch.group(1)!);
      final rest = swinLayerMatch.group(2)!;
      if (layerIdx < encoder.layers.length) {
        return _loadSwinLayerWeight(encoder.layers[layerIdx], rest, tensor);
      }
      return false;
    }

    // Encoder norm — Swin encoder doesn't have a top-level norm
    // (norm is per-layer), so skip these

    // ─── Decoder weights ───────────────────────────────────────

    // Token embeddings
    if (name == 'decoder.model.decoder.embed_tokens.weight' ||
        name == 'decoder.embed_tokens.weight') {
      decoder.embedTokens.weight = tensor;
      return true;
    }

    // Position embeddings
    if (name == 'decoder.model.decoder.embed_positions.weight' ||
        name == 'decoder.embed_positions.weight') {
      decoder.embedPositions.weight = tensor;
      return true;
    }

    // Decoder layers
    final decoderLayerMatch = RegExp(
      r'decoder\.(?:model\.decoder\.)?layers\.(\d+)\.(.+)',
    ).firstMatch(name);
    if (decoderLayerMatch != null) {
      final layerIdx = int.parse(decoderLayerMatch.group(1)!);
      final rest = decoderLayerMatch.group(2)!;
      if (layerIdx < decoder.layers.length) {
        return _loadBartLayerWeight(decoder.layers[layerIdx], rest, tensor);
      }
      return false;
    }

    // Decoder layer norm
    if (name == 'decoder.model.decoder.layer_norm.weight' ||
        name == 'decoder.layer_norm.weight') {
      decoder.layerNorm.weight = tensor;
      return true;
    }
    if (name == 'decoder.model.decoder.layer_norm.bias' ||
        name == 'decoder.layer_norm.bias') {
      decoder.layerNorm.bias = tensor;
      return true;
    }

    // LM head
    if (name == 'decoder.model.lm_head.weight' ||
        name == 'decoder.lm_head.weight') {
      decoder.lmHead.weight = tensor;
      return true;
    }
    if (name == 'decoder.model.lm_head.bias' ||
        name == 'decoder.lm_head.bias') {
      decoder.lmHead.bias = tensor;
      return true;
    }

    return false;
  }

  // ─── Swin Layer Weight Loading ─────────────────────────────────────

  bool _loadSwinLayerWeight(SwinLayer layer, String name, Tensor tensor) {
    // Block weights: blocks.{j}.xxx
    final blockMatch = RegExp(r'blocks\.(\d+)\.(.+)').firstMatch(name);
    if (blockMatch != null) {
      final blockIdx = int.parse(blockMatch.group(1)!);
      final rest = blockMatch.group(2)!;
      if (blockIdx < layer.blocks.length) {
        return _loadSwinBlockWeight(layer.blocks[blockIdx], rest, tensor);
      }
      return false;
    }

    // Downsample (PatchMerging) weights
    if (name.startsWith('downsample.')) {
      if (layer.patchMerging == null) return false;
      final pmName = name.substring('downsample.'.length);
      return _loadPatchMergingWeight(layer.patchMerging!, pmName, tensor);
    }

    return false;
  }

  bool _loadSwinBlockWeight(
      SwinTransformerBlock block, String name, Tensor tensor) {
    // Attention
    if (name == 'attn.qkv.weight') {
      block.attn.qkv.weight = tensor;
      return true;
    }
    if (name == 'attn.qkv.bias') {
      block.attn.qkv.bias = tensor;
      return true;
    }
    if (name == 'attn.proj.weight') {
      block.attn.proj.weight = tensor;
      return true;
    }
    if (name == 'attn.proj.bias') {
      block.attn.proj.bias = tensor;
      return true;
    }
    if (name == 'attn.relative_position_bias_table') {
      block.attn.relativePositionBiasTable = tensor;
      return true;
    }

    // Layer norms
    if (name == 'norm1.weight') {
      block.norm1.weight = tensor;
      return true;
    }
    if (name == 'norm1.bias') {
      block.norm1.bias = tensor;
      return true;
    }
    if (name == 'norm2.weight') {
      block.norm2.weight = tensor;
      return true;
    }
    if (name == 'norm2.bias') {
      block.norm2.bias = tensor;
      return true;
    }

    // MLP
    if (name == 'mlp.fc1.weight') {
      block.mlpFc1.weight = tensor;
      return true;
    }
    if (name == 'mlp.fc1.bias') {
      block.mlpFc1.bias = tensor;
      return true;
    }
    if (name == 'mlp.fc2.weight') {
      block.mlpFc2.weight = tensor;
      return true;
    }
    if (name == 'mlp.fc2.bias') {
      block.mlpFc2.bias = tensor;
      return true;
    }

    return false;
  }

  bool _loadPatchMergingWeight(PatchMerging pm, String name, Tensor tensor) {
    if (name == 'reduction.weight') {
      pm.reduction.weight = tensor;
      return true;
    }
    if (name == 'reduction.bias') {
      pm.reduction.bias = tensor;
      return true;
    }
    if (name == 'norm.weight') {
      pm.norm.weight = tensor;
      return true;
    }
    if (name == 'norm.bias') {
      pm.norm.bias = tensor;
      return true;
    }
    return false;
  }

  // ─── BART Layer Weight Loading ─────────────────────────────────────

  bool _loadBartLayerWeight(
      BartDecoderLayer layer, String name, Tensor tensor) {
    // Self attention
    if (name.startsWith('self_attn.')) {
      return _loadBartAttentionWeight(
          layer.selfAttn, name.substring('self_attn.'.length), tensor);
    }

    // Cross attention (encoder_attn)
    if (name.startsWith('encoder_attn.')) {
      return _loadBartAttentionWeight(
          layer.encoderAttn, name.substring('encoder_attn.'.length), tensor);
    }

    // Layer norms
    if (name == 'self_attn_layer_norm.weight') {
      layer.selfAttnLayerNorm.weight = tensor;
      return true;
    }
    if (name == 'self_attn_layer_norm.bias') {
      layer.selfAttnLayerNorm.bias = tensor;
      return true;
    }
    if (name == 'encoder_attn_layer_norm.weight') {
      layer.encoderAttnLayerNorm.weight = tensor;
      return true;
    }
    if (name == 'encoder_attn_layer_norm.bias') {
      layer.encoderAttnLayerNorm.bias = tensor;
      return true;
    }
    if (name == 'final_layer_norm.weight') {
      layer.finalLayerNorm.weight = tensor;
      return true;
    }
    if (name == 'final_layer_norm.bias') {
      layer.finalLayerNorm.bias = tensor;
      return true;
    }

    // FFN
    if (name == 'fc1.weight') {
      layer.fc1.weight = tensor;
      return true;
    }
    if (name == 'fc1.bias') {
      layer.fc1.bias = tensor;
      return true;
    }
    if (name == 'fc2.weight') {
      layer.fc2.weight = tensor;
      return true;
    }
    if (name == 'fc2.bias') {
      layer.fc2.bias = tensor;
      return true;
    }

    return false;
  }

  bool _loadBartAttentionWeight(
      BartAttention attn, String name, Tensor tensor) {
    if (name == 'k_proj.weight') {
      attn.kProj.weight = tensor;
      return true;
    }
    if (name == 'k_proj.bias') {
      attn.kProj.bias = tensor;
      return true;
    }
    if (name == 'v_proj.weight') {
      attn.vProj.weight = tensor;
      return true;
    }
    if (name == 'v_proj.bias') {
      attn.vProj.bias = tensor;
      return true;
    }
    if (name == 'q_proj.weight') {
      attn.qProj.weight = tensor;
      return true;
    }
    if (name == 'q_proj.bias') {
      attn.qProj.bias = tensor;
      return true;
    }
    if (name == 'out_proj.weight') {
      attn.outProj.weight = tensor;
      return true;
    }
    if (name == 'out_proj.bias') {
      attn.outProj.bias = tensor;
      return true;
    }

    return false;
  }

  // ─── File Format Parsers ───────────────────────────────────────────

  /// Load weights from safetensors format.
  ///
  /// Safetensors format:
  ///   - 8 bytes: little-endian uint64 = metadata JSON length (N)
  ///   - N bytes: JSON metadata (tensor names, dtypes, shapes, offsets)
  ///   - Remaining: raw tensor data
  Future<Map<String, Tensor>> _loadSafetensors(File file) async {
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes);

    // Read metadata length (first 8 bytes, little-endian uint64)
    final metadataLength = data.getUint64(0, Endian.little);
    if (metadataLength > bytes.length - 8) {
      throw FormatException(
          'Invalid safetensors: metadata length exceeds file size');
    }

    // Parse metadata JSON
    final metadataStr = utf8.decode(bytes.sublist(8, 8 + metadataLength));
    final metadata = jsonDecode(metadataStr) as Map<String, dynamic>;

    final dataOffset = 8 + metadataLength;
    final weights = <String, Tensor>{};

    for (final entry in metadata.entries) {
      final name = entry.key;
      if (name == '__metadata__') continue;

      final info = entry.value as Map<String, dynamic>;
      final dtype = info['dtype'] as String;
      final shape = (info['shape'] as List).cast<int>();
      final offsets = (info['data_offsets'] as List).cast<int>();

      final start = dataOffset + offsets[0];
      final end = dataOffset + offsets[1];

      final tensorData = _readTensorData(bytes, start, end, dtype);
      weights[name] = Tensor(tensorData, shape);
    }

    return weights;
  }

  /// Read raw tensor data and convert to Float32List.
  Float32List _readTensorData(
      Uint8List bytes, int start, int end, String dtype) {
    final slice = bytes.sublist(start, end);
    final byteData = ByteData.sublistView(slice);

    switch (dtype) {
      case 'F32':
        final count = (end - start) ~/ 4;
        return Float32List.sublistView(slice, 0, count);

      case 'F16':
        // Convert float16 to float32
        final count = (end - start) ~/ 2;
        final result = Float32List(count);
        for (int i = 0; i < count; i++) {
          result[i] =
              _float16ToFloat32(byteData.getUint16(i * 2, Endian.little));
        }
        return result;

      case 'BF16':
        // Convert bfloat16 to float32
        final count = (end - start) ~/ 2;
        final result = Float32List(count);
        for (int i = 0; i < count; i++) {
          final bf16 = byteData.getUint16(i * 2, Endian.little);
          // bfloat16 is just the upper 16 bits of float32
          final asFloat = ByteData(4)..setUint32(0, bf16 << 16, Endian.little);
          result[i] = asFloat.getFloat32(0, Endian.little);
        }
        return result;

      case 'I32':
        final count = (end - start) ~/ 4;
        final result = Float32List(count);
        for (int i = 0; i < count; i++) {
          result[i] = byteData.getInt32(i * 4, Endian.little).toDouble();
        }
        return result;

      case 'I64':
        final count = (end - start) ~/ 8;
        final result = Float32List(count);
        for (int i = 0; i < count; i++) {
          result[i] = byteData.getInt64(i * 8, Endian.little).toDouble();
        }
        return result;

      default:
        throw FormatException('Unsupported tensor dtype: $dtype');
    }
  }

  /// Convert IEEE 754 half-precision (float16) to float32.
  double _float16ToFloat32(int half) {
    final sign = (half >> 15) & 0x1;
    final exponent = (half >> 10) & 0x1F;
    final mantissa = half & 0x3FF;

    if (exponent == 0) {
      if (mantissa == 0) {
        return sign == 0 ? 0.0 : -0.0;
      }
      // Subnormal
      final val = mantissa / 1024.0 * (1.0 / 16384.0);
      return sign == 0 ? val : -val;
    } else if (exponent == 31) {
      if (mantissa == 0) {
        return sign == 0 ? double.infinity : double.negativeInfinity;
      }
      return double.nan;
    }

    final float32Exp = exponent - 15 + 127;
    final float32Mantissa = mantissa << 13;
    final bits = (sign << 31) | (float32Exp << 23) | float32Mantissa;
    final bd = ByteData(4)..setUint32(0, bits, Endian.big);
    return bd.getFloat32(0, Endian.big);
  }

  /// Load weights from JSON format.
  ///
  /// Expected JSON structure:
  /// ```json
  /// {
  ///   "tensor_name": {
  ///     "shape": [dim1, dim2, ...],
  ///     "dtype": "float32",
  ///     "data": "base64-encoded-data"
  ///   }
  /// }
  /// ```
  Future<Map<String, Tensor>> _loadJsonWeights(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final weights = <String, Tensor>{};

    for (final entry in json.entries) {
      final info = entry.value as Map<String, dynamic>;
      final shape = (info['shape'] as List).cast<int>();
      final dataBase64 = info['data'] as String;

      final bytes = base64Decode(dataBase64);
      final data = Float32List.sublistView(Uint8List.fromList(bytes));

      weights[entry.key] = Tensor(data, shape);
    }

    return weights;
  }
}

/// Utility for converting PyTorch/HuggingFace model weights to
/// a format suitable for the Dart Donut model.
///
/// Use this with a Python script to export weights:
/// ```python
/// import torch, json, base64
/// from safetensors.torch import load_file
///
/// weights = load_file("model.safetensors")
/// out = {}
/// for name, tensor in weights.items():
///     t = tensor.cpu().float().numpy()
///     out[name] = {
///         "shape": list(t.shape),
///         "dtype": "float32",
///         "data": base64.b64encode(t.tobytes()).decode()
///     }
/// with open("weights.json", "w") as f:
///     json.dump(out, f)
/// ```
class WeightExportGuide {
  /// Python script to convert HuggingFace model to JSON weights.
  static const String exportScript = '''
import torch
import json
import base64
from transformers import DonutProcessor, VisionEncoderDecoderModel

# Load pretrained model
model = VisionEncoderDecoderModel.from_pretrained("naver-clova-ix/donut-base-finetuned-cord-v2")

# Export weights as JSON
weights = {}
for name, param in model.named_parameters():
    t = param.detach().cpu().float().numpy()
    weights[name] = {
        "shape": list(t.shape),
        "dtype": "float32",
        "data": base64.b64encode(t.tobytes()).decode("ascii")
    }

with open("weights.json", "w") as f:
    json.dump(weights, f)

print(f"Exported {len(weights)} weight tensors")
''';

  /// Python script to export tokenizer in HuggingFace format.
  static const String tokenizerExportScript = '''
from transformers import DonutProcessor

processor = DonutProcessor.from_pretrained("naver-clova-ix/donut-base-finetuned-cord-v2")
processor.tokenizer.save_pretrained("./tokenizer_output/")
# This creates tokenizer.json which can be loaded by DonutTokenizer.fromFile()
''';
}
