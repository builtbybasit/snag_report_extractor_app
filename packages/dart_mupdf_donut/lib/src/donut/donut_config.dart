/// Donut model configuration.
///
/// Stores all hyperparameters needed to construct a DonutModel.
/// Matches the configuration format used by the original Donut implementation.
library;

/// Configuration class for the Donut model.
///
/// This stores the architecture hyperparameters for both the
/// Swin Transformer encoder and BART decoder.
///
/// Default values match the `donut-base` pretrained model:
/// - Input size: 2560x1920 (height x width)
/// - Encoder: Swin-B with layers [2, 2, 14, 2]
/// - Decoder: 4-layer BART with 1024-dim embeddings
class DonutConfig {
  /// Input image size as [height, width].
  final List<int> inputSize;

  /// Whether to rotate image if height > width.
  final bool alignLongAxis;

  /// Window size for Swin Transformer.
  final int windowSize;

  /// Depth of each Swin Transformer stage.
  final List<int> encoderLayer;

  /// Number of BART decoder layers.
  final int decoderLayer;

  /// Maximum position embeddings for decoder.
  final int maxPositionEmbeddings;

  /// Maximum sequence length for generation.
  final int maxLength;

  /// Embedding dimension for the encoder.
  final int encoderEmbedDim;

  /// Number of attention heads per encoder stage.
  final List<int> encoderNumHeads;

  /// Patch size for the visual encoder.
  final int patchSize;

  /// Embedding dimension for the decoder.
  final int decoderEmbedDim;

  /// FFN dimension for the decoder.
  final int decoderFfnDim;

  /// Number of attention heads for the decoder.
  final int decoderNumHeads;

  /// Vocabulary size.
  final int vocabSize;

  /// Path or name of pretrained model.
  final String nameOrPath;

  /// ImageNet normalization mean.
  static const List<double> imagenetMean = [0.485, 0.456, 0.406];

  /// ImageNet normalization std.
  static const List<double> imagenetStd = [0.229, 0.224, 0.225];

  const DonutConfig({
    this.inputSize = const [2560, 1920],
    this.alignLongAxis = false,
    this.windowSize = 10,
    this.encoderLayer = const [2, 2, 14, 2],
    this.decoderLayer = 4,
    this.maxPositionEmbeddings = 1536,
    this.maxLength = 1536,
    this.encoderEmbedDim = 128,
    this.encoderNumHeads = const [4, 8, 16, 32],
    this.patchSize = 4,
    this.decoderEmbedDim = 1024,
    this.decoderFfnDim = 4096,
    this.decoderNumHeads = 16,
    this.vocabSize = 57522,
    this.nameOrPath = '',
  });

  /// Configuration for the donut-base pretrained model.
  factory DonutConfig.base() => const DonutConfig();

  /// Configuration for the donut-proto (smaller) model.
  factory DonutConfig.proto() => const DonutConfig(
        inputSize: [2048, 1536],
        windowSize: 8,
        encoderLayer: [2, 2, 18, 2],
      );

  /// Configuration for a small model (for testing/development).
  factory DonutConfig.small() => const DonutConfig(
        inputSize: [640, 480],
        windowSize: 5,
        encoderLayer: [2, 2, 6, 2],
        decoderLayer: 2,
        maxLength: 256,
        encoderEmbedDim: 64,
        encoderNumHeads: [2, 4, 8, 16],
        decoderEmbedDim: 256,
        decoderFfnDim: 1024,
        decoderNumHeads: 8,
        vocabSize: 10000,
      );

  /// Compute the encoder's output dimension.
  int get encoderOutputDim {
    int d = encoderEmbedDim;
    for (int i = 0; i < encoderLayer.length - 1; i++) {
      d *= 2;
    }
    return d;
  }

  /// Create from JSON map (for loading from config.json).
  factory DonutConfig.fromJson(Map<String, dynamic> json) {
    return DonutConfig(
      inputSize: (json['input_size'] as List?)?.cast<int>() ?? [2560, 1920],
      alignLongAxis: json['align_long_axis'] as bool? ?? false,
      windowSize: json['window_size'] as int? ?? 10,
      encoderLayer:
          (json['encoder_layer'] as List?)?.cast<int>() ?? [2, 2, 14, 2],
      decoderLayer: json['decoder_layer'] as int? ?? 4,
      maxPositionEmbeddings: json['max_position_embeddings'] as int? ?? 1536,
      maxLength: json['max_length'] as int? ?? 1536,
      encoderEmbedDim: json['encoder_embed_dim'] as int? ?? 128,
      encoderNumHeads:
          (json['encoder_num_heads'] as List?)?.cast<int>() ?? [4, 8, 16, 32],
      patchSize: json['patch_size'] as int? ?? 4,
      decoderEmbedDim: json['decoder_embed_dim'] as int? ?? 1024,
      decoderFfnDim: json['decoder_ffn_dim'] as int? ?? 4096,
      decoderNumHeads: json['decoder_num_heads'] as int? ?? 16,
      vocabSize: json['vocab_size'] as int? ?? 57522,
      nameOrPath: json['name_or_path'] as String? ?? '',
    );
  }

  /// Convert to JSON map for serialization.
  Map<String, dynamic> toJson() => {
        'input_size': inputSize,
        'align_long_axis': alignLongAxis,
        'window_size': windowSize,
        'encoder_layer': encoderLayer,
        'decoder_layer': decoderLayer,
        'max_position_embeddings': maxPositionEmbeddings,
        'max_length': maxLength,
        'encoder_embed_dim': encoderEmbedDim,
        'encoder_num_heads': encoderNumHeads,
        'patch_size': patchSize,
        'decoder_embed_dim': decoderEmbedDim,
        'decoder_ffn_dim': decoderFfnDim,
        'decoder_num_heads': decoderNumHeads,
        'vocab_size': vocabSize,
        'name_or_path': nameOrPath,
      };

  @override
  String toString() =>
      'DonutConfig(inputSize: $inputSize, encoderLayer: $encoderLayer, '
      'decoderLayer: $decoderLayer, maxLength: $maxLength)';
}
