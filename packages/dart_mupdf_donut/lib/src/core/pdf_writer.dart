import 'dart:typed_data';
import 'dart:io';
import 'pdf_objects.dart';

/// PDF writer — serializes PDF objects back to bytes.
///
/// Supports:
/// - Writing new PDFs from scratch
/// - Serializing modified objects
/// - Incremental saves
/// - Garbage collection
/// - Deflate compression
class PdfWriter {
  final List<PdfIndirectObject> _objects = [];
  int _nextObjNum = 1;
  PdfDict _trailer = PdfDict();

  /// Add an indirect object and return its reference.
  PdfRef addObject(PdfObject obj) {
    final objNum = _nextObjNum++;
    _objects.add(PdfIndirectObject(objNum, 0, obj));
    return PdfRef(objNum);
  }

  /// Add an object preserving its original object number.
  /// Used when rebuilding a PDF to keep cross-references intact.
  void addObjectWithNum(int objectNumber, int generation, PdfObject obj) {
    _objects.add(PdfIndirectObject(objectNumber, generation, obj));
    if (objectNumber >= _nextObjNum) {
      _nextObjNum = objectNumber + 1;
    }
  }

  /// Set the trailer dictionary.
  void setTrailer(PdfDict trailer) {
    _trailer = trailer;
  }

  /// Write the complete PDF to bytes.
  Uint8List write({int garbage = 0, bool deflate = true, bool clean = false}) {
    final buffer = BytesBuilder();

    // Header
    buffer.add('%PDF-1.7\n'.codeUnits);
    // Binary comment (marks as binary)
    buffer.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    // Write objects and record offsets
    final offsets = <int, int>{};
    for (final obj in _objects) {
      offsets[obj.objectNumber] = buffer.length;
      _writeIndirectObject(buffer, obj, deflate: deflate);
    }

    // Write xref table
    final xrefOffset = buffer.length;
    _writeXRef(buffer, offsets);

    // Write trailer
    // Compute max object number for Size
    int maxObjNum = _nextObjNum;
    for (final obj in _objects) {
      if (obj.objectNumber >= maxObjNum) {
        maxObjNum = obj.objectNumber + 1;
      }
    }
    _trailer['Size'] = PdfInt(maxObjNum);
    buffer.add('trailer\n'.codeUnits);
    buffer.add(_trailer.toPdfString().codeUnits);
    buffer.add('\n'.codeUnits);

    // Write startxref
    buffer.add('startxref\n'.codeUnits);
    buffer.add('$xrefOffset\n'.codeUnits);
    buffer.add('%%EOF\n'.codeUnits);

    return buffer.toBytes();
  }

  void _writeIndirectObject(BytesBuilder buffer, PdfIndirectObject obj,
      {bool deflate = true}) {
    buffer.add('${obj.objectNumber} ${obj.generation} obj\n'.codeUnits);

    if (obj.object is PdfStream) {
      final stream = obj.object as PdfStream;
      var streamData = stream.data;

      // Optionally compress
      if (deflate && stream.filters.isEmpty && streamData.length > 50) {
        streamData = Uint8List.fromList(zlib.encode(streamData));
        stream.dict['Filter'] = PdfName('/FlateDecode');
      }

      stream.dict['Length'] = PdfInt(streamData.length);
      buffer.add(stream.dict.toPdfString().codeUnits);
      buffer.add('\nstream\n'.codeUnits);
      buffer.add(streamData);
      buffer.add('\nendstream\n'.codeUnits);
    } else {
      buffer.add(obj.object.toPdfString().codeUnits);
      buffer.add('\n'.codeUnits);
    }

    buffer.add('endobj\n'.codeUnits);
  }

  void _writeXRef(BytesBuilder buffer, Map<int, int> offsets) {
    // Find the maximum object number
    int maxObjNum = _nextObjNum;
    for (final obj in _objects) {
      if (obj.objectNumber >= maxObjNum) {
        maxObjNum = obj.objectNumber + 1;
      }
    }

    buffer.add('xref\n'.codeUnits);
    buffer.add('0 $maxObjNum\n'.codeUnits);

    // Entry 0: free head
    buffer.add('0000000000 65535 f \n'.codeUnits);

    for (int i = 1; i < maxObjNum; i++) {
      final offset = offsets[i];
      if (offset != null) {
        final offsetStr = offset.toString().padLeft(10, '0');
        buffer.add('$offsetStr 00000 n \n'.codeUnits);
      } else {
        // Free entry for gaps
        buffer.add('0000000000 00000 f \n'.codeUnits);
      }
    }
  }

  /// Create a minimal valid PDF with no pages.
  static Uint8List createEmptyPdf() {
    final writer = PdfWriter();

    // Pages (empty)
    final pagesDict = PdfDict({
      'Type': PdfName('/Pages'),
      'Kids': PdfArray([]),
      'Count': PdfInt(0),
    });
    final pagesRef = writer.addObject(pagesDict);

    // Catalog
    final catalogDict = PdfDict({
      'Type': PdfName('/Catalog'),
      'Pages': pagesRef,
    });
    final catalogRef = writer.addObject(catalogDict);

    // Trailer
    writer.setTrailer(PdfDict({
      'Root': catalogRef,
    }));

    return writer.write(deflate: false);
  }

  /// Create a minimal valid PDF with one blank page.
  static Uint8List createBlankPdf({
    double width = 595,
    double height = 842,
  }) {
    final writer = PdfWriter();

    // Page content (empty)
    final contentStream = PdfStream(PdfDict(), Uint8List(0));
    final contentRef = writer.addObject(contentStream);

    // Page
    final pageDict = PdfDict({
      'Type': PdfName('/Page'),
      'MediaBox': PdfArray([
        PdfInt(0),
        PdfInt(0),
        PdfReal(width),
        PdfReal(height),
      ]),
      'Contents': contentRef,
      'Resources': PdfDict(),
    });
    final pageRef = writer.addObject(pageDict);

    // Pages
    final pagesDict = PdfDict({
      'Type': PdfName('/Pages'),
      'Kids': PdfArray([pageRef]),
      'Count': PdfInt(1),
    });
    final pagesRef = writer.addObject(pagesDict);

    // Set parent
    pageDict['Parent'] = pagesRef;

    // Catalog
    final catalogDict = PdfDict({
      'Type': PdfName('/Catalog'),
      'Pages': pagesRef,
    });
    final catalogRef = writer.addObject(catalogDict);

    // Trailer
    writer.setTrailer(PdfDict({
      'Root': catalogRef,
    }));

    return writer.write(deflate: false);
  }
}
