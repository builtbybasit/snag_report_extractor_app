import 'dart:typed_data';

import 'document.dart';
import 'geometry/rect.dart';

/// Main entry point for the dart_mupdf library.
///
/// Equivalent to PyMuPDF's `fitz` module. Provides static factory
/// methods for opening and creating PDF documents.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:dart_mupdf_donut/dart_mupdf.dart';
///
/// // Open from file
/// final doc = DartMuPDF.openFile('document.pdf');
///
/// // Open from bytes
/// final bytes = File('document.pdf').readAsBytesSync();
/// final doc2 = DartMuPDF.openBytes(bytes);
///
/// // Create new PDF
/// final doc3 = DartMuPDF.createPdf();
///
/// // Get text from first page
/// final page = doc.getPage(0);
/// print(page.getText());
/// ```
class DartMuPDF {
  /// Library version string.
  static const String version = '1.0.0';

  /// PDF version supported.
  static const String pdfVersion = '1.7';

  /// Equivalent to `fitz.version`.
  static List<String> get versionInfo => [version, pdfVersion, '1'];

  // ---------- Document Creation ----------

  /// Open a PDF document from a file path.
  ///
  /// Equivalent to PyMuPDF's `fitz.open(filename)`.
  static Document openFile(String filePath) {
    return Document.openFile(filePath);
  }

  /// Open a PDF document from bytes.
  ///
  /// Equivalent to PyMuPDF's `fitz.open(stream=data, filetype="pdf")`.
  static Document openBytes(Uint8List data) {
    return Document.openBytes(data);
  }

  /// Create a new empty PDF document.
  ///
  /// Equivalent to PyMuPDF's `fitz.open()` (with no arguments).
  static Document createPdf() {
    return Document.create();
  }

  // ---------- Utilities ----------

  /// Get PDF information from bytes without fully parsing.
  static Map<String, dynamic> getPdfInfo(Uint8List data) {
    final info = <String, dynamic>{};

    // Check header
    if (data.length < 8) {
      info['valid'] = false;
      return info;
    }

    final header = String.fromCharCodes(data.sublist(0, 8));
    if (!header.startsWith('%PDF-')) {
      info['valid'] = false;
      return info;
    }

    info['valid'] = true;
    info['version'] = header.substring(5, 8);

    // Check if encrypted (look for /Encrypt in trailer)
    final content = String.fromCharCodes(data);
    info['encrypted'] = content.contains('/Encrypt');

    // Estimate page count (crude: count /Type /Page)
    final pagePattern = RegExp(r'/Type\s*/Page\b');
    info['estimatedPages'] = pagePattern.allMatches(content).length;

    return info;
  }

  /// Create a blank PDF with a single page.
  ///
  /// A convenience wrapper around [createPdf] and `Document.newPage`.
  static Document createBlank({
    double width = 612,
    double height = 792,
  }) {
    final doc = createPdf();
    doc.newPage(width: width, height: height);
    return doc;
  }

  /// Check if data looks like a valid PDF.
  static bool isPdf(Uint8List data) {
    if (data.length < 5) return false;
    return data[0] == 0x25 && // %
        data[1] == 0x50 && // P
        data[2] == 0x44 && // D
        data[3] == 0x46 && // F
        data[4] == 0x2D; // -
  }

  // ---------- Constants ----------

  /// Text extraction flags, matching PyMuPDF's constants.
  static const int textPreserveLigatures = 1;
  static const int textPreserveWhitespace = 2;
  static const int textPreserveImages = 4;
  static const int textInhibitSpaces = 8;
  static const int textDehyphenate = 16;
  static const int textMediaboxClip = 32;

  /// Link destination kinds.
  static const int linkNone = 0;
  static const int linkGoto = 1;
  static const int linkUri = 2;
  static const int linkLaunch = 3;
  static const int linkNamed = 4;
  static const int linkGotoR = 5;

  /// Annotation types.
  static const int annotText = 0;
  static const int annotLink = 1;
  static const int annotFreeText = 2;
  static const int annotLine = 3;
  static const int annotSquare = 4;
  static const int annotCircle = 5;
  static const int annotPolygon = 6;
  static const int annotPolyLine = 7;
  static const int annotHighlight = 8;
  static const int annotUnderline = 9;
  static const int annotSquiggly = 10;
  static const int annotStrikeOut = 11;
  static const int annotStamp = 13;
  static const int annotCaret = 14;
  static const int annotInk = 15;
  static const int annotPopup = 16;
  static const int annotFileAttachment = 17;
  static const int annotSound = 18;
  static const int annotMovie = 19;
  static const int annotWidget = 20;

  /// Standard page sizes.
  static const Rect pageSizeA3 = Rect(0, 0, 841.89, 1190.55);
  static const Rect pageSizeA4 = Rect(0, 0, 595.28, 841.89);
  static const Rect pageSizeA5 = Rect(0, 0, 420.94, 595.28);
  static const Rect pageSizeA6 = Rect(0, 0, 297.64, 420.94);
  static const Rect pageSizeLetter = Rect(0, 0, 612, 792);
  static const Rect pageSizeLegal = Rect(0, 0, 612, 1008);
  static const Rect pageSizeLedger = Rect(0, 0, 792, 1224);
  static const Rect pageSizeB5 = Rect(0, 0, 498.90, 708.66);

  /// Encryption methods.
  static const int pdfEncryptNone = 0;
  static const int pdfEncryptKeepExisting = 1;
  static const int pdfEncryptRc4_40 = 2;
  static const int pdfEncryptRc4_128 = 3;
  static const int pdfEncryptAes_128 = 4;
  static const int pdfEncryptAes_256 = 5;

  /// Permission flags.
  static const int pdfPermPrint = 4;
  static const int pdfPermModify = 8;
  static const int pdfPermCopy = 16;
  static const int pdfPermAnnotate = 32;
  static const int pdfPermFormFill = 256;
  static const int pdfPermAccessibility = 512;
  static const int pdfPermAssemble = 1024;
  static const int pdfPermPrintHq = 2048;

  /// Private constructor — this is a static-only utility class.
  DartMuPDF._();
}
