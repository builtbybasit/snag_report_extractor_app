// ignore_for_file: avoid_print
/// dart_mupdf_donut — Example Usage
///
/// Demonstrates both the PDF module and the Donut OCR-free document
/// understanding module.
///
/// Run with:
///   dart run example/example.dart
import 'dart:typed_data';

import 'package:dart_mupdf_donut/dart_mupdf.dart';
import 'package:dart_mupdf_donut/donut.dart';

void main() {
  _pdfExamples();
  _donutExamples();
}

// ═══════════════════════════════════════════════════════════════════════
// PDF MODULE
// ═══════════════════════════════════════════════════════════════════════

void _pdfExamples() {
  print('╔══════════════════════════════════════════╗');
  print('║  dart_mupdf — PDF Module Examples        ║');
  print('╚══════════════════════════════════════════╝\n');

  // ── Create a new PDF from scratch ──────────────────────────────────
  print('▸ Creating a new PDF...');
  final doc = DartMuPDF.createPdf();
  doc.newPage(width: 595.28, height: 841.89); // A4
  print('  Created PDF with ${doc.pageCount} page(s)');

  // ── Access page properties ─────────────────────────────────────────
  final page = doc.getPage(0);
  print('  Page size: ${page.width} × ${page.height}');
  print('  Page rect: ${page.rect}');
  print('  Rotation:  ${page.rotation}°');

  // ── Geometry types ─────────────────────────────────────────────────
  print('\n▸ Geometry types');
  final p1 = Point(100, 200);
  final p2 = Point(300, 400);
  print(
      '  Point: $p1,  distance to $p2: ${p1.distanceTo(p2).toStringAsFixed(1)}');

  final rect = Rect(50, 50, 500, 700);
  print('  Rect: $rect  (${rect.width} × ${rect.height})');
  print('  Contains $p1: ${rect.contains(p1)}');

  final matrix = Matrix.rotation(45);
  print('  Rotation matrix (45°): $matrix');

  final quad = Quad.fromRect(rect);
  print('  Quad area: ${quad.area}');

  // ── Drawing with Shape ─────────────────────────────────────────────
  print('\n▸ Drawing shapes');
  final shape = Shape(pageWidth: 595.28, pageHeight: 841.89);

  shape.drawLine(Point(50, 50), Point(200, 50));
  shape.finish(color: [0, 0, 0], width: 2);

  shape.drawRect(Rect(100, 100, 300, 200));
  shape.finish(color: [1, 0, 0], fill: [0.9, 0.9, 1.0], width: 1);

  shape.drawCircle(Point(200, 400), 50);
  shape.finish(color: [0, 0, 1], width: 1.5);

  final stream = shape.commit();
  print('  Content stream: ${stream.length} bytes');

  // ── Pixmap ─────────────────────────────────────────────────────────
  print('\n▸ Pixmap operations');
  final pixmap = Pixmap(
    colorspace: Colorspace.csRgb,
    width: 100,
    height: 100,
    hasAlpha: false,
  );
  pixmap.clearWith(255);
  for (int x = 10; x < 90; x++) {
    for (int y = 10; y < 90; y++) {
      pixmap.setPixel(x, y, [255, 0, 0]);
    }
  }
  final grayPix = pixmap.toColorspace(Colorspace.csGray);
  print('  RGB pixmap:  $pixmap');
  print('  Gray pixmap: $grayPix');

  final pngBytes = pixmap.toPng();
  print('  PNG size: ${pngBytes.length} bytes');

  // ── PDF detection utility ──────────────────────────────────────────
  print('\n▸ Utility');
  final header = Uint8List.fromList('%PDF-1.7'.codeUnits);
  print('  Is PDF: ${DartMuPDF.isPdf(header)}');
  print('  Library version: ${DartMuPDF.version}');

  doc.close();

  // ── Opening an existing PDF (uncomment with a real file) ──────────
  // final existing = DartMuPDF.openFile('invoice.pdf');
  // print('Pages: ${existing.pageCount}');
  // print('Title: ${existing.metadata.title}');
  //
  // for (int i = 0; i < existing.pageCount; i++) {
  //   final p = existing.getPage(i);
  //   print('Page ${i + 1}: ${p.getText().length} chars');
  //   print('  Images: ${p.getImages().length}');
  //   print('  Links:  ${p.getLinks().length}');
  // }
  //
  // final toc = existing.getToc();
  // for (final entry in toc) {
  //   print('${"  " * (entry.level - 1)}${entry.title} → p.${entry.pageNumber}');
  // }
  // existing.close();

  print('\n');
}

// ═══════════════════════════════════════════════════════════════════════
// DONUT MODULE
// ═══════════════════════════════════════════════════════════════════════

void _donutExamples() {
  print('╔══════════════════════════════════════════╗');
  print('║  donut — Document Understanding Examples ║');
  print('╚══════════════════════════════════════════╝\n');

  // ── 1. Tensor basics ───────────────────────────────────────────────
  print('▸ Tensor operations');
  final a = Tensor.zeros([2, 3]);
  final b = Tensor.ones([2, 3]);
  final c = a + b;
  print('  zeros + ones = $c');
  print('  Shape: ${c.shape}, size: ${c.size}');

  final x = Tensor.ones([2, 4]);
  final w = Tensor.ones([4, 3]);
  final y = x.matmul(w);
  print('  matmul [2,4] × [4,3] → ${y.shape}');

  final softmaxed = Tensor.fromList([1.0, 2.0, 3.0]).softmax(0);
  print('  softmax([1,2,3]) = ${softmaxed.data}');

  // ── 2. Neural network layers ───────────────────────────────────────
  print('\n▸ Neural network layers');
  final linear = Linear(8, 4);
  final input = Tensor.ones([1, 8]);
  final output = linear.forward(input);
  print('  Linear(8→4): input ${input.shape} → output ${output.shape}');

  final norm = LayerNorm(4);
  final normalized = norm.forward(output);
  print('  LayerNorm(4): ${normalized.shape}');

  final embed = Embedding(100, 16);
  final embedded = embed.forward([5, 10, 15]);
  print('  Embedding(100, 16) [5,10,15] → ${embedded.shape}');

  // ── 3. Tokenizer ──────────────────────────────────────────────────
  print('\n▸ Tokenizer');
  final vocab = <String, int>{
    '<s>': 0,
    '<pad>': 1,
    '</s>': 2,
    '<unk>': 3,
    '▁': 4,
    'H': 5,
    'e': 6,
    'l': 7,
    'o': 8,
    '▁world': 9,
    '▁Hello': 10,
    '<s_cord-v2>': 11,
    '</s_cord-v2>': 12,
    '<s_menu>': 13,
    '</s_menu>': 14,
    '<s_nm>': 15,
    '</s_nm>': 16,
    '<s_price>': 17,
    '</s_price>': 18,
    '<s_total>': 19,
    '</s_total>': 20,
    '<s_total_price>': 21,
    '</s_total_price>': 22,
    '<sep/>': 23,
  };
  final tokenizer = DonutTokenizer(
    vocab: vocab,
    merges: [],
    specialTokens: {
      '<s_cord-v2>',
      '</s_cord-v2>',
      '<s_menu>',
      '</s_menu>',
      '<s_nm>',
      '</s_nm>',
      '<s_price>',
      '</s_price>',
      '<s_total>',
      '</s_total>',
      '<s_total_price>',
      '</s_total_price>',
      '<sep/>',
    },
  );
  print('  Vocab size: ${tokenizer.vocabSize}');
  print('  BOS=${tokenizer.bosTokenId}, EOS=${tokenizer.eosTokenId}');

  final tokens = tokenizer.encode('▁Hello▁world');
  print('  encode("Hello world") → $tokens');
  print('  decode → "${tokenizer.decode(tokens)}"');

  // ── 4. JSON ↔ token conversion ────────────────────────────────────
  print('\n▸ JSON ↔ Donut token conversion');
  final receiptJson = {
    'menu': [
      {'nm': 'Latte', 'price': '5.00'},
      {'nm': 'Muffin', 'price': '3.50'},
    ],
    'total': {'total_price': '8.50'},
  };

  final tokenStr = DonutModel.json2token(receiptJson);
  print('  JSON → tokens: ${tokenStr.substring(0, 80)}...');

  final parsed = DonutModel.token2json(tokenStr);
  print('  tokens → JSON: $parsed');

  // ── 5. Full model pipeline (tiny config, random weights) ──────────
  print('\n▸ Full Donut model pipeline (random weights)');
  final config = DonutConfig(
    inputSize: [128, 96],
    alignLongAxis: true,
    windowSize: 4,
    encoderLayer: [2, 2],
    decoderLayer: 1,
    maxPositionEmbeddings: 256,
    maxLength: 40,
    encoderEmbedDim: 32,
    encoderNumHeads: [2, 4],
    patchSize: 4,
    decoderEmbedDim: 64,
    decoderFfnDim: 128,
    decoderNumHeads: 4,
    vocabSize: tokenizer.vocabSize,
  );

  final model = DonutModel(config);
  model.randomInit(seed: 42);
  model.setTokenizer(tokenizer);
  print('  Config: input=${config.inputSize}, '
      'encoder=[${config.encoderLayer.join(",")}], '
      'decoder=${config.decoderLayer}');

  // Create a synthetic 96×128 test image (gradient)
  final imgTensor = Tensor.zeros([1, 3, 128, 96]);
  for (int c = 0; c < 3; c++) {
    for (int h = 0; h < 128; h++) {
      for (int w = 0; w < 96; w++) {
        imgTensor.data[c * 128 * 96 + h * 96 + w] =
            (h + w + c * 50) / 300.0 - 0.5;
      }
    }
  }
  print('  Synthetic image tensor: ${imgTensor.shape}');

  // Encode
  final encoderOut = model.encode(imgTensor);
  print('  Encoder output: ${encoderOut.shape}');

  // Full inference
  final result = model.inference(
    imageTensor: imgTensor,
    prompt: '<s_cord-v2>',
    maxLength: 20,
  );
  print('  Generated ${result.tokens.length} tokens');
  print(
      '  Text: "${result.text.substring(0, result.text.length.clamp(0, 60))}"');
  print('  JSON: ${result.json}');

  // ── 6. Image preprocessing pipeline ───────────────────────────────
  print('\n▸ Image preprocessing');
  print(DonutImageUtils.describePipeline(config));

  // ── With real images (uncomment) ──────────────────────────────────
  // import 'dart:io';
  // final imgBytes = File('receipt.jpg').readAsBytesSync();
  // final tensor = DonutImageUtils.preprocessBytes(imgBytes, config);
  // print('  Preprocessed: ${tensor.shape}');
  //
  // final realResult = model.inferenceFromBytes(
  //   imageBytes: imgBytes,
  //   prompt: '<s_cord-v2>',
  // );
  // print('  ${realResult.json}');

  print('\n▸ Done! For real document understanding, load pretrained weights.');
  print('  See README.md for weight export instructions.\n');
}
