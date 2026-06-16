import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_mupdf_donut/dart_mupdf.dart';
import 'package:image/image.dart' as img;
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/mupdf_repository.dart';

const String _defaultCaption =
    'As Indicated by the Highlights in the picture';

/// Isolate entry point: extracts captioned snag photos from [data]["path"]
/// using the vendored pure-Dart engine and streams them to the main isolate.
///
/// Message protocol (must stay identical to the controller's expectations):
///   {"page": int, "pageCount": int}                              progress
///   {"imageBytes": Uint8List, "caption": String,
///    "imgCount": int, "totalImages": int}                        one photo
///   {"done": true, "outputDir": String}                          finished
///   {"error": String}                                            failed
Future<void> extractPdfWorker(Map<String, dynamic> data) async {
  final SendPort sendPort = data["sendPort"];
  final String path = data["path"];
  final String outputDir = data["outputDir"];

  MuPdfRepository? repo;
  try {
    repo = MuPdfRepository.openFile(path);

    final totalPages = repo.pageCount;
    sendPort.send({"page": 0, "pageCount": totalPages});

    // First pass: parse every page's layout up front so we can report the
    // total image count before streaming the first photo (mirrors the old
    // mutool `extractAll` pre-pass).
    final dicts = <TextDict>[
      for (int i = 0; i < totalPages; i++) repo.getTextDict(i),
    ];

    final totalImages = dicts.fold<int>(
      0,
      (sum, dict) => sum + dict.blocks.where((b) => b.type == 1).length,
    );

    // Second pass: per page, emit progress then each captioned image.
    int imageCounter = 1;
    for (int pageNo = 1; pageNo <= totalPages; pageNo++) {
      final dict = dicts[pageNo - 1];
      sendPort.send({"page": pageNo, "pageCount": totalPages});

      final imageBlocks = dict.blocks.where((b) => b.type == 1).toList();
      final textBlocks = dict.blocks.where((b) => b.type == 0).toList();

      for (final imgBlock in imageBlocks) {
        final caption = _captionFor(imgBlock.bbox, textBlocks);

        final xref = imgBlock.imageXref;
        if (xref == null) continue;
        final extracted = repo.extractImage(xref);
        if (extracted == null || extracted.image.isEmpty) continue;

        final bytes = _encodedImageBytes(extracted);
        if (bytes == null) continue;

        sendPort.send({
          "imageBytes": bytes,
          "caption": caption,
          "imgCount": imageCounter++,
          "totalImages": totalImages,
        });
      }
    }

    sendPort.send({"done": true, "outputDir": outputDir});
  } catch (e) {
    sendPort.send({"error": e.toString()});
  } finally {
    repo?.close();
  }
}

/// Pairs an image with the size-10 caption text positioned just below it.
///
/// The caption window is the image's bbox bottom edge extended down 55pt and
/// 10pt out on each side — the same geometry the mutool path used (origin is
/// top-left, y-down, matching this engine's coordinate space).
///
/// Matching is done per *span*, not per line: `getTextDict` groups two
/// side-by-side captions (e.g. for a row of two images) into one wide line, so
/// a line-level bbox test would hand both captions to both images. A span is
/// taken only when its size is 10, it sits in the caption band vertically, and
/// its horizontal centre falls within this image's (padded) x-range — which
/// assigns each caption to the image directly above it.
String _captionFor(Rect imageBbox, List<TextDictBlock> textBlocks) {
  final left = imageBbox.x0 - 10;
  final right = imageBbox.x1 + 10;
  final bandTop = imageBbox.y1;
  final bandBottom = imageBbox.y1 + 55;

  final parts = <String>[];
  for (final textBlock in textBlocks) {
    for (final line in textBlock.lines ?? const <TextDictLine>[]) {
      for (final span in line.spans) {
        if (span.size != 10) continue;
        final b = span.bbox;
        final inBand = b.y0 < bandBottom && b.y1 > bandTop;
        final centerX = (b.x0 + b.x1) / 2;
        if (inBand && centerX >= left && centerX <= right) {
          parts.add(span.text);
        }
      }
    }
  }

  final caption = _sanitizeCaption(parts.join(' '));
  return caption.isEmpty ? _defaultCaption : caption;
}

/// Cleans extracted caption text: drops C0 control characters (the vendored
/// engine interleaves NUL bytes when decoding some Type0/Identity-H fonts —
/// the high byte of each 2-byte glyph code) and collapses whitespace.
String _sanitizeCaption(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x20 || rune == 0x09) buffer.writeCharCode(rune);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Returns bytes the Flutter image codec can decode.
///
/// JPEG streams pass through. Other filters return raw decompressed samples
/// that the engine tags as `'png'` but which are NOT a real PNG file, so those
/// are wrapped into an actual PNG via the `image` package. SMask alpha is not
/// composited and CMYK/16-bit samples are unsupported (returns null to skip).
Uint8List? _encodedImageBytes(ExtractedImage ex) {
  switch (ex.ext) {
    case 'jpeg':
    case 'jpg':
      return ex.image;
    case 'png':
      if (_hasPngSignature(ex.image)) return ex.image;
      return _rawSamplesToPng(ex);
    default:
      // jp2 / tiff / jbig2 — hand to the codec and let it try.
      return ex.image;
  }
}

bool _hasPngSignature(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 && // P
    bytes[2] == 0x4E && // N
    bytes[3] == 0x47; // G

Uint8List? _rawSamplesToPng(ExtractedImage ex) {
  final channels = ex.colorspace; // component count: 1, 3 or 4
  if (ex.bpc != 8 || ex.width <= 0 || ex.height <= 0) return null;
  if (channels != 1 && channels != 3) return null; // CMYK unsupported
  if (ex.image.length < ex.width * ex.height * channels) return null;

  final image = img.Image.fromBytes(
    width: ex.width,
    height: ex.height,
    bytes: ex.image.buffer,
    numChannels: channels,
  );
  return img.encodePng(image);
}
