import 'dart:typed_data';

/// Typed message protocol streamed from [extractPdfWorker] (the extraction
/// isolate) back to the controller on the main isolate.
///
/// Instances are sent across the isolate `SendPort`, so every field is a
/// sendable type (int / String / Uint8List).
sealed class PdfWorkerMessage {
  const PdfWorkerMessage();
}

/// Progress for a single page: `page` of `pageCount` has been parsed.
class PageProgress extends PdfWorkerMessage {
  final int page;
  final int pageCount;

  const PageProgress(this.page, this.pageCount);
}

/// One extracted, captioned photo. `imgCount` is this image's 1-based index;
/// `totalImages` is the full count pre-computed before streaming.
class ImageExtracted extends PdfWorkerMessage {
  final Uint8List bytes;
  final String caption;
  final int imgCount;
  final int totalImages;

  const ImageExtracted(
    this.bytes,
    this.caption,
    this.imgCount,
    this.totalImages,
  );
}

/// Extraction finished cleanly; images were written under `outputDir`.
class ExtractionDone extends PdfWorkerMessage {
  final String outputDir;

  const ExtractionDone(this.outputDir);
}

/// Extraction failed; `error` is the stringified exception.
class ExtractionFailed extends PdfWorkerMessage {
  final String error;

  const ExtractionFailed(this.error);
}
