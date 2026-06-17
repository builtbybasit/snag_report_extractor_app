import 'dart:isolate';
import 'dart:typed_data';

/// Typed message protocol streamed from [extractPdfWorker] (the extraction
/// isolate) back to the controller on the main isolate.
///
/// Instances are sent across the isolate `SendPort`, so every field is a
/// sendable type (int / String / Uint8List / SendPort).
sealed class PdfWorkerMessage {
  const PdfWorkerMessage();
}

/// First message the worker sends. Carries the back-channel [ackPort] the main
/// isolate replies on to grant the worker permission to send more images.
///
/// This is the handshake for image backpressure: the worker streams images
/// faster than the main isolate can render/encode/write them, so without a
/// credit window the in-flight image bytes pile up in the receive port. The
/// main isolate sends one ack per consumed [ImageExtracted]; the worker only
/// blocks once a small window of unacked images is outstanding.
class WorkerReady extends PdfWorkerMessage {
  final SendPort ackPort;

  const WorkerReady(this.ackPort);
}

/// Control signals the main isolate sends back to the worker over the ack
/// port (the same [SendPort] handed out by [WorkerReady]).
///
/// The port carries two kinds of value:
///   * `null`            — one image-credit ack (see [WorkerReady]).
///   * [WorkerCancel]    — a graceful cancellation request.
///
/// Cancellation flows over this existing channel rather than relying on
/// `Isolate.kill`, so the worker can break out of its page loop and run its
/// `finally` block — closing the native MuPDF document + file handle instead
/// of leaking them on every pause/cancel.
class WorkerCancel {
  const WorkerCancel();
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
