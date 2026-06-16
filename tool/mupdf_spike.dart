// ignore_for_file: avoid_print
//
// Standalone spike to evaluate `dart_mupdf_donut` as a MuPDF replacement.
//
// Run from the project root:
//   dart run tool/mupdf_spike.dart [path/to.pdf]
//
// Defaults to assets/sample_compressed.pdf. It does NOT touch the Flutter app —
// it just exercises the three pillars we care about:
//   1. extractImage()  -> do embedded photos come out as openable files?
//   2. getTextDict()   -> do we get text blocks with bbox + font size?
//   3. image blocks     -> does the text-dict expose image bbox + xref
//                          (the thing getImageBbox() stubs out)?
//
// Extracted images are written to tool/spike_out/ so you can open them.

import 'dart:io';
import 'package:dart_mupdf_donut/dart_mupdf.dart';

const int maxPagesToDump = 3; // keep console output readable
const int maxBlocksPerPage = 12;

void main(List<String> args) {
  final pdfPath = args.isNotEmpty ? args.first : 'assets/sample_compressed.pdf';
  final file = File(pdfPath);
  if (!file.existsSync()) {
    stderr.writeln('PDF not found: $pdfPath');
    exit(1);
  }

  final outDir = Directory('tool/spike_out');
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  outDir.createSync(recursive: true);

  print('=== dart_mupdf_donut spike ===');
  print('PDF: $pdfPath (${file.lengthSync()} bytes)\n');

  final doc = DartMuPDF.openFile(pdfPath);
  print('pageCount: ${doc.pageCount}');
  try {
    print('title:     ${doc.metadata.title}');
  } catch (_) {/* metadata may be absent */}
  print('');

  var totalImages = 0;
  var imagesWithBbox = 0;
  var extractedOk = 0;
  var extractFailed = 0;

  final pagesToDump = doc.pageCount < maxPagesToDump
      ? doc.pageCount
      : maxPagesToDump;

  for (var i = 0; i < doc.pageCount; i++) {
    final page = doc.getPage(i);
    final verbose = i < pagesToDump;

    // --- Pillar 1+2: text dict (blocks with bbox + spans w/ font size) ---
    final dict = page.getTextDict();
    final imageBlocks = dict.blocks.where((b) => b.type == 1).toList();
    final textBlocks = dict.blocks.where((b) => b.type == 0).toList();

    if (verbose) {
      print('────────────────────────────────────────');
      print('PAGE $i  size=${page.width.toStringAsFixed(0)}x'
          '${page.height.toStringAsFixed(0)}  '
          'textBlocks=${textBlocks.length}  imageBlocks=${imageBlocks.length}');

      var shown = 0;
      for (final b in dict.blocks) {
        if (shown++ >= maxBlocksPerPage) {
          print('  … (${dict.blocks.length - maxBlocksPerPage} more blocks)');
          break;
        }
        final bb = b.bbox;
        final rect = '[${bb.x0.toStringAsFixed(0)},${bb.y0.toStringAsFixed(0)} '
            '${bb.x1.toStringAsFixed(0)},${bb.y1.toStringAsFixed(0)}]';
        if (b.type == 1) {
          print('  IMG  $rect  xref=${b.imageXref}  '
              '${b.imageWidth}x${b.imageHeight}');
        } else {
          // gather first span's font size + a text preview
          final spans = (b.lines ?? []).expand((l) => l.spans).toList();
          final size = spans.isEmpty ? null : spans.first.size;
          final preview =
              spans.map((s) => s.text).join(' ').replaceAll('\n', ' ').trim();
          final clipped =
              preview.length > 50 ? '${preview.substring(0, 50)}…' : preview;
          print('  TXT  $rect  size=${size?.toStringAsFixed(1)}  "$clipped"');
        }
      }
    }

    // --- Pillar 3: do image blocks carry a usable bbox? ---
    for (final b in imageBlocks) {
      final hasBbox = b.bbox.x1 > b.bbox.x0 && b.bbox.y1 > b.bbox.y0;
      if (hasBbox) imagesWithBbox++;
    }

    // --- Pillar 1: actually extract every embedded image to disk ---
    final imgs = page.getImages();
    for (final img in imgs) {
      totalImages++;
      final ex = doc.extractImage(img.xref);
      if (ex == null || ex.image.isEmpty) {
        extractFailed++;
        if (verbose) print('  ✗ extractImage(${img.xref}) -> null/empty');
        continue;
      }
      extractedOk++;
      final outPath =
          'tool/spike_out/p${i}_img${img.xref}.${ex.ext}';
      File(outPath).writeAsBytesSync(ex.image);
      if (verbose) {
        print('  ✓ extractImage(${img.xref}) -> ${ex.ext} '
            '${ex.width}x${ex.height} ${ex.image.length}B  $outPath');
      }
    }
  }

  final pageCount = doc.pageCount;
  doc.close();

  print('\n=== SUMMARY ===');
  print('pages:                 $pageCount');
  print('embedded images found: $totalImages');
  print('  extracted OK:        $extractedOk');
  print('  extract failed:      $extractFailed');
  print('image blocks w/ bbox:  $imagesWithBbox  '
      '(0 => positional caption matching needs content-stream parsing)');
  print('output images:         tool/spike_out/');
}
