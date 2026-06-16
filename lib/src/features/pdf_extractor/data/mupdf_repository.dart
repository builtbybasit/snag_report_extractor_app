import 'package:dart_mupdf_donut/dart_mupdf.dart';

/// Thin wrapper over the vendored pure-Dart `dart_mupdf_donut` engine.
///
/// Replaces the previous `mutool` Process-based implementation: there is no
/// external binary and no hardcoded dev path. It relies only on `dart:io`
/// under the hood, so it works inside the extraction isolate.
///
/// The caller owns the instance and must call [close] when done.
class MuPdfRepository {
  final Document _doc;

  MuPdfRepository._(this._doc);

  /// Open a PDF from disk.
  static MuPdfRepository openFile(String pdfPath) =>
      MuPdfRepository._(DartMuPDF.openFile(pdfPath));

  /// Total number of pages.
  int get pageCount => _doc.pageCount;

  /// Text/image layout dictionary for a zero-based [pageIndex].
  ///
  /// Image blocks (`type == 1`) carry `imageXref`/`bbox`; text blocks
  /// (`type == 0`) carry `lines` -> `spans` with per-span `size`/`bbox`/`text`.
  TextDict getTextDict(int pageIndex) => _doc.getPage(pageIndex).getTextDict();

  /// Extract the embedded image stream identified by [xref].
  ///
  /// Returns `null` when the xref is not an image stream. DCT images come back
  /// as JPEG bytes; other filters return raw decompressed samples (see
  /// [ExtractedImage.ext]).
  ExtractedImage? extractImage(int xref) => _doc.extractImage(xref);

  void close() => _doc.close();
}
