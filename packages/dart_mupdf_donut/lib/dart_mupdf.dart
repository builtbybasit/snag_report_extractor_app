/// dart_mupdf — A comprehensive pure Dart PDF library inspired by PyMuPDF.
///
/// Provides PDF parsing, text extraction, image extraction, annotations,
/// metadata, table of contents, page manipulation, and PDF creation.
/// Works on all platforms — no native dependencies.
///
/// ## Quick Start
/// ```dart
/// import 'package:dart_mupdf_donut/dart_mupdf.dart';
///
/// final doc = DartMuPDF.openBytes(pdfBytes);
/// print('Pages: ${doc.pageCount}');
/// final text = doc.getPage(0).getText();
/// print(text);
/// doc.close();
/// ```
library dart_mupdf;

// Core types
export 'src/geometry/point.dart';
export 'src/geometry/rect.dart';
export 'src/geometry/irect.dart';
export 'src/geometry/matrix.dart';
export 'src/geometry/quad.dart';

// PDF models
export 'src/models/metadata.dart';
export 'src/models/toc_entry.dart';
export 'src/models/text_block.dart';
export 'src/models/text_word.dart';
export 'src/models/text_dict.dart';
export 'src/models/image_info.dart';
export 'src/models/link_info.dart';
export 'src/models/annotation.dart';
export 'src/models/widget_info.dart';
export 'src/models/embedded_file.dart';
export 'src/models/page_label.dart';
export 'src/models/colorspace.dart';
export 'src/models/outline_item.dart';

// Core PDF engine
export 'src/core/pdf_objects.dart';
export 'src/core/pdf_parser.dart';
export 'src/core/pdf_cross_ref.dart';
export 'src/core/pdf_stream.dart';
export 'src/core/pdf_encryption.dart';
export 'src/core/pdf_writer.dart';

// Document & Page (main API)
export 'src/document.dart';
export 'src/page.dart';
export 'src/text_page.dart';
export 'src/pixmap.dart';
export 'src/shape.dart';

// Entry point
export 'src/dart_mupdf_base.dart';

// Donut — OCR-free Document Understanding Transformer
// For focused import, use: import 'package:dart_mupdf_donut/donut.dart';
export 'src/donut/donut.dart';
