import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_mupdf_donut/dart_mupdf.dart';

void main() {
  group('Geometry Types', () {
    test('Point creation and arithmetic', () {
      final p1 = Point(1, 2);
      final p2 = Point(3, 4);

      expect(p1.x, 1);
      expect(p1.y, 2);
      expect((p1 + p2).x, 4);
      expect((p1 + p2).y, 6);
      expect((p2 - p1).x, 2);
      expect((p2 - p1).y, 2);
      expect((p1 * 3).x, 3);
      expect((p1 * 3).y, 6);
    });

    test('Point distance', () {
      final p1 = Point(0, 0);
      final p2 = Point(3, 4);
      expect(p1.distanceTo(p2), 5.0);
    });

    test('Rect creation and properties', () {
      final rect = Rect(10, 20, 110, 220);
      expect(rect.width, 100);
      expect(rect.height, 200);
      expect(rect.isEmpty, false);
      expect(Rect.empty.isEmpty, true);
    });

    test('Rect contains point', () {
      final rect = Rect(0, 0, 100, 100);
      expect(rect.contains(Point(50, 50)), true);
      expect(rect.contains(Point(150, 50)), false);
    });

    test('Rect union and intersection', () {
      final r1 = Rect(0, 0, 50, 50);
      final r2 = Rect(25, 25, 75, 75);
      final u = r1.union(r2);
      expect(u.x0, 0);
      expect(u.y0, 0);
      expect(u.x1, 75);
      expect(u.y1, 75);

      final i = r1.intersect(r2);
      expect(i.x0, 25);
      expect(i.y0, 25);
      expect(i.x1, 50);
      expect(i.y1, 50);
    });

    test('IRect creation', () {
      final ir = IRect(10, 20, 110, 220);
      expect(ir.width, 100);
      expect(ir.height, 200);
    });

    test('Matrix identity', () {
      final m = Matrix.identity;
      expect(m.a, 1);
      expect(m.d, 1);
      expect(m.e, 0);
      expect(m.f, 0);
    });

    test('Matrix rotation', () {
      final m = Matrix.rotation(90);
      expect(m.a.abs(), lessThan(0.0001));
      expect(m.b, closeTo(1.0, 0.0001));
    });

    test('Matrix concat', () {
      final m1 = Matrix.scale(2, 3);
      final m2 = Matrix.translation(10, 20);
      final m3 = m1.concat(m2);
      expect(m3.e, 10);
      expect(m3.f, 20);
    });

    test('Quad from rect', () {
      final rect = Rect(0, 0, 100, 50);
      final quad = Quad.fromRect(rect);
      expect(quad.ul, Point(0, 0));
      expect(quad.ur, Point(100, 0));
      expect(quad.lr, Point(100, 50));
      expect(quad.ll, Point(0, 50));
      expect(quad.rect, rect);
    });
  });

  group('PDF Models', () {
    test('PdfMetadata creation', () {
      final meta = PdfMetadata(title: 'Test', author: 'Author');
      expect(meta.title, 'Test');
      expect(meta.author, 'Author');
      expect(meta.subject, isNull);
    });

    test('TocEntry', () {
      final entry = TocEntry(level: 1, title: 'Chapter 1', pageNumber: 1);
      expect(entry.level, 1);
      expect(entry.title, 'Chapter 1');
      expect(entry.pageNumber, 1);
    });

    test('TextBlock', () {
      final block = TextBlock(
        x0: 0,
        y0: 0,
        x1: 100,
        y1: 20,
        text: 'Hello World',
        blockNumber: 0,
        blockType: 0,
      );
      expect(block.text, 'Hello World');
      expect(block.blockNumber, 0);
    });

    test('LinkInfo constants', () {
      expect(LinkInfo.kindNone, 0);
      expect(LinkInfo.kindGoto, 1);
      expect(LinkInfo.kindUri, 2);
    });

    test('AnnotationType from name', () {
      expect(annotationTypeFromName('/Text'), AnnotationType.text);
      expect(annotationTypeFromName('/Highlight'), AnnotationType.highlight);
      expect(annotationTypeFromName('/Unknown'), AnnotationType.unknown);
    });

    test('Colorspace constants', () {
      expect(Colorspace.csRgb.n, 3);
      expect(Colorspace.csGray.n, 1);
      expect(Colorspace.csCmyk.n, 4);
    });
  });

  group('PDF Objects', () {
    test('PdfNull', () {
      expect(PdfNull().serialize(), 'null');
    });

    test('PdfBool', () {
      expect(PdfBool(true).serialize(), 'true');
      expect(PdfBool(false).serialize(), 'false');
    });

    test('PdfInt', () {
      expect(PdfInt(42).value, 42);
      expect(PdfInt(42).serialize(), '42');
    });

    test('PdfReal', () {
      expect(PdfReal(3.14).serialize(), '3.14');
    });

    test('PdfString', () {
      expect(PdfString('Hello').serialize(), '(Hello)');
    });

    test('PdfName', () {
      expect(PdfName('/Type').serialize(), '/Type');
    });

    test('PdfArray', () {
      final arr = PdfArray([PdfInt(1), PdfInt(2), PdfInt(3)]);
      expect(arr.length, 3);
      expect(arr.serialize(), '[1 2 3]');
    });

    test('PdfDict', () {
      final dict = PdfDict({
        'Type': PdfName('/Page'),
        'Count': PdfInt(5),
      });
      expect(dict.getName('Type'), 'Page');
      expect(dict.getInt('Count'), 5);
    });
  });

  group('Pixmap', () {
    test('Create RGB pixmap', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 10,
        height: 10,
      );
      expect(pix.width, 10);
      expect(pix.height, 10);
      expect(pix.n, 3);
      expect(pix.stride, 30);
    });

    test('Set and get pixel', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 10,
        height: 10,
      );
      pix.setPixel(5, 5, [255, 128, 0]);
      expect(pix.getPixel(5, 5), [255, 128, 0]);
    });

    test('Clear with value', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 2,
        height: 2,
      );
      pix.clearWith(128);
      expect(pix.getPixel(0, 0), [128, 128, 128]);
    });

    test('Convert RGB to Grayscale', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 1,
        height: 1,
      );
      pix.setPixel(0, 0, [255, 255, 255]);
      final gray = pix.toColorspace(Colorspace.csGray);
      expect(gray.colorspace, Colorspace.csGray);
      expect(gray.n, 1);
      expect(gray.getPixel(0, 0)[0], closeTo(255, 1));
    });

    test('Invert pixmap', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 1,
        height: 1,
      );
      pix.setPixel(0, 0, [200, 100, 50]);
      pix.invertIRect();
      expect(pix.getPixel(0, 0), [55, 155, 205]);
    });

    test('Shrink pixmap', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 10,
        height: 10,
      );
      pix.clearWith(128);
      final small = pix.shrink(2);
      expect(small.width, 5);
      expect(small.height, 5);
    });

    test('To PNG bytes', () {
      final pix = Pixmap(
        colorspace: Colorspace.csRgb,
        width: 2,
        height: 2,
      );
      pix.clearWith(255);
      final png = pix.toPng();
      // PNG starts with magic bytes
      expect(png[0], 0x89);
      expect(png[1], 0x50); // P
      expect(png[2], 0x4E); // N
      expect(png[3], 0x47); // G
    });
  });

  group('Shape', () {
    test('Draw line and finish', () {
      final shape = Shape(pageWidth: 612, pageHeight: 792);
      shape.drawLine(Point(0, 0), Point(100, 100));
      shape.finish(color: [0, 0, 0], width: 1);
      final content = shape.commit();
      expect(content, contains('m'));
      expect(content, contains('l'));
      expect(content, contains('S'));
    });

    test('Draw rectangle', () {
      final shape = Shape(pageWidth: 612, pageHeight: 792);
      shape.drawRect(Rect(10, 10, 100, 100));
      shape.finish(color: [1, 0, 0], fill: [0, 0, 1]);
      final content = shape.commit();
      expect(content, contains('re'));
      expect(content, contains('B')); // fill and stroke
    });

    test('Draw circle', () {
      final shape = Shape(pageWidth: 612, pageHeight: 792);
      shape.drawCircle(Point(100, 100), 50);
      shape.finish(color: [0, 0, 0]);
      final content = shape.commit();
      expect(content, contains('c')); // cubic bezier
    });

    test('Insert text', () {
      final shape = Shape(pageWidth: 612, pageHeight: 792);
      final lines = shape.insertText(
        Point(72, 720),
        'Hello World',
        fontSize: 14,
      );
      expect(lines, 1);
      final content = shape.commit();
      expect(content, contains('BT'));
      expect(content, contains('Hello World'));
      expect(content, contains('ET'));
    });
  });

  group('DartMuPDF', () {
    test('Version info', () {
      expect(DartMuPDF.version, '1.0.0');
      expect(DartMuPDF.versionInfo.length, 3);
    });

    test('isPdf check', () {
      expect(DartMuPDF.isPdf(Uint8List.fromList('%PDF-1.7'.codeUnits)), true);
      expect(DartMuPDF.isPdf(Uint8List.fromList('NOT PDF'.codeUnits)), false);
      expect(DartMuPDF.isPdf(Uint8List(3)), false);
    });

    test('Standard page sizes', () {
      expect(DartMuPDF.pageSizeA4.width, closeTo(595.28, 0.01));
      expect(DartMuPDF.pageSizeA4.height, closeTo(841.89, 0.01));
      expect(DartMuPDF.pageSizeLetter.width, 612);
      expect(DartMuPDF.pageSizeLetter.height, 792);
    });

    test('Create new PDF', () {
      final doc = DartMuPDF.createPdf();
      expect(doc.pageCount, 0);
      expect(doc.isPDF, true);
      expect(doc.isClosed, false);
      doc.close();
      expect(doc.isClosed, true);
    });

    test('Create blank PDF', () {
      final doc = DartMuPDF.createBlank(width: 200, height: 300);
      expect(doc.pageCount, 1);
      doc.close();
    });

    test('PDF info from bytes', () {
      final header = '%PDF-1.5\n1 0 obj\n<< /Type /Catalog >>\nendobj';
      final info = DartMuPDF.getPdfInfo(Uint8List.fromList(header.codeUnits));
      expect(info['valid'], true);
      expect(info['version'], '1.5');
    });
  });

  group('Document', () {
    test('Create empty document', () {
      final doc = Document.create();
      expect(doc.pageCount, 0);
      expect(doc.isPDF, true);
      expect(doc.isClosed, false);
    });

    test('Add new page', () {
      final doc = Document.create();
      doc.newPage(width: 612, height: 792);
      expect(doc.pageCount, 1);

      final page = doc.getPage(0);
      expect(page.pageNumber, 0);
      doc.close();
    });

    test('Add multiple pages', () {
      final doc = Document.create();
      doc.newPage();
      doc.newPage();
      doc.newPage();
      expect(doc.pageCount, 3);
      doc.close();
    });

    test('Delete page', () {
      final doc = Document.create();
      doc.newPage();
      doc.newPage();
      expect(doc.pageCount, 2);
      doc.deletePage(0);
      expect(doc.pageCount, 1);
      doc.close();
    });

    test('Metadata', () {
      final doc = Document.create();
      final meta = doc.metadata;
      expect(meta, isNotNull);
      doc.close();
    });

    test('Close document', () {
      final doc = Document.create();
      expect(doc.isClosed, false);
      doc.close();
      expect(doc.isClosed, true);
    });
  });
}
