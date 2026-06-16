/// Donut — OCR-free Document Understanding Transformer.
///
/// A pure Dart implementation of the Donut model (ECCV 2022) for
/// end-to-end document understanding without OCR.
///
/// ## Components
///
/// - [DonutModel] — Main model combining encoder + decoder + inference pipeline
/// - [DonutConfig] — Configuration for model architecture
/// - [SwinEncoder] — Swin Transformer visual encoder
/// - [BartDecoder] — mBART-based text decoder
/// - [DonutTokenizer] — SentencePiece BPE tokenizer
/// - [DonutImageUtils] — Image preprocessing utilities
/// - [DonutWeightLoader] — Weight loading from safetensors/JSON
/// - [Tensor] — N-dimensional tensor for all computations
///
/// ## Quick Start
///
/// ```dart
/// import 'package:dart_mupdf_donut/donut.dart';
///
/// // Create model
/// final config = DonutConfig.base();
/// final model = DonutModel(config);
///
/// // Load weights and tokenizer
/// await model.loadWeights('path/to/model');
/// await model.loadTokenizer('path/to/tokenizer.json');
///
/// // Run inference
/// final result = model.inferenceFromBytes(
///   imageBytes: imageFileBytes,
///   prompt: '<s_cord-v2>',
/// );
/// print(result.json);
/// ```
///
/// ## Supported Tasks
///
/// - **Document Parsing**: Extract structured information from receipts,
///   invoices, forms, etc.
/// - **Document Classification**: Classify document types (RVL-CDIP)
/// - **Visual Question Answering**: Answer questions about document content
/// - **Text Reading**: OCR-free text extraction
///
/// ## Reference
///
/// Kim et al., "OCR-free Document Understanding Transformer", ECCV 2022.
/// https://github.com/clovaai/donut
library;

// Core model
export 'donut_config.dart';
export 'donut_model.dart';

// Encoder
export 'encoder/swin_encoder.dart';

// Decoder
export 'decoder/bart_decoder.dart';

// Tokenizer
export 'tokenizer/tokenizer.dart';

// Tensor
export 'tensor/tensor.dart';

// Neural network layers
export 'nn/layers.dart';

// Utilities
export 'utils/image_utils.dart';
export 'utils/weight_loader.dart';
