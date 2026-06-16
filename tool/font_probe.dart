// ignore_for_file: avoid_print
//
// Diagnose why custom-font text comes out garbled: dump each font's encoding,
// ToUnicode presence, and a snippet of the relevant dictionaries.
//
//   dart run tool/font_probe.dart [path/to.pdf]

import 'dart:convert';
import 'dart:io';
import 'package:dart_mupdf_donut/dart_mupdf.dart';

void main(List<String> args) {
  final pdfPath = args.isNotEmpty ? args.first : 'assets/sample_compressed.pdf';
  final doc = DartMuPDF.openFile(pdfPath);
  final parser = doc.getPage(0).parser;

  for (var pageNo = 0; pageNo < 2 && pageNo < doc.pageCount; pageNo++) {
    final page = doc.getPage(pageNo);
    print('\n══════════ PAGE $pageNo ══════════');

    // Resolve Resources -> Font (handle indirect ref)
    var resources = page.pageDict.getDict('Resources');
    if (resources == null) {
      final r = page.pageDict.getRef('Resources');
      if (r != null) resources = parser.getObject(r.objectNumber)?.dict;
    }
    if (resources == null) {
      print('  no Resources');
      continue;
    }
    var fontDict = resources.getDict('Font');
    if (fontDict == null) {
      final r = resources.getRef('Font');
      if (r != null) fontDict = parser.getObject(r.objectNumber)?.dict;
    }
    if (fontDict == null) {
      print('  no Font dict');
      continue;
    }

    for (final key in fontDict.keys) {
      final ref = fontDict.getRef(key);
      final fdict = ref == null
          ? fontDict.getDict(key)
          : parser.getObject(ref.objectNumber)?.dict;
      if (fdict == null) continue;

      final subtype = fdict.getName('Subtype');
      final base = fdict.getString('BaseFont') ?? fdict.getName('BaseFont');
      final enc = fdict['Encoding'];
      String encDesc;
      PdfDict? encDict;
      if (enc is PdfName) {
        encDesc = '/${enc.value}';
      } else if (enc is PdfRef) {
        encDict = parser.getObject(enc.objectNumber)?.dict;
        encDesc = 'dict(ref) base=${encDict?.getName('BaseEncoding')}';
      } else if (enc is PdfDict) {
        encDict = enc;
        encDesc = 'dict base=${enc.getName('BaseEncoding')}';
      } else {
        encDesc = 'none';
      }
      final hasDiff = encDict?.getArray('Differences') != null;
      final tuRef = fdict.getRef('ToUnicode');

      print('  /$key  subtype=$subtype  base=$base');
      print('       Encoding=$encDesc  Differences=$hasDiff  '
          'ToUnicode=${tuRef != null}');

      if (tuRef != null) {
        final data = parser.getStreamData(tuRef.objectNumber);
        if (data != null) {
          final s = latin1.decode(data);
          final i = s.indexOf('beginbfchar');
          final j = s.indexOf('beginbfrange');
          final at = [i, j].where((x) => x >= 0).fold<int>(s.length,
              (a, b) => b < a ? b : a);
          final snippet = s.substring(at, (at + 220).clamp(0, s.length));
          print('       ToUnicode snippet:\n${_indent(snippet)}');
        }
      } else if (hasDiff) {
        final diffs = encDict!.getArray('Differences')!;
        final preview = diffs.items.take(12).map((e) => e.toString()).join(' ');
        print('       Differences preview: $preview …');
      }
    }
  }
  doc.close();
}

String _indent(String s) =>
    s.split('\n').map((l) => '         | $l').take(8).join('\n');
