
import 'dart:isolate';

import 'package:desktop_drop/desktop_drop.dart';

class PdfFileProgress {
  final String fileName;
  final int currentPage;
  final int totalPages;
  final int currentImage;
  final int totalImages;
  final String? outputDir;
  final bool done;
  final String? error;
  /// Timestamp when this file started processing
  final Isolate? isolate;

  // --- ETA tracking ---
  final List<int> pageDurations; // stores ms/page
  final DateTime? lastPageTime;

  PdfFileProgress({
    required this.fileName,
    this.currentPage = 0,
    this.totalPages = 0,
    this.currentImage = 0,
    this.totalImages = 0,
    this.outputDir,
    this.done = false,
    this.error,
    this.isolate,
    List<int>? pageDurations,
    this.lastPageTime,
  }) : pageDurations = pageDurations ?? [];

  PdfFileProgress copyWith({
    String? fileName,
    DateTime? startTime,
    int? currentPage,
    int? totalPages,
    int? currentImage,
    int? totalImages,
    bool? done,
    String? outputDir,
    String? error,
    Isolate? isolate,
    List<int>? pageDurations,
    DateTime? lastPageTime,
  }) {
    return PdfFileProgress(
      fileName: fileName ?? this.fileName,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      currentImage: currentImage ?? this.currentImage,
      totalImages: totalImages ?? this.totalImages,
      done: done ?? this.done,
      outputDir: outputDir ?? this.outputDir,
      error: error ?? this.error,
      isolate: isolate ?? this.isolate,
      pageDurations: pageDurations ?? List.from(this.pageDurations),
      lastPageTime: lastPageTime ?? this.lastPageTime,
    );
  }

  /// Call this when a page finishes processing
  PdfFileProgress markPageDone() {
    final now = DateTime.now();
    final newDurations = List<int>.from(pageDurations);

    if (lastPageTime != null) {
      final duration = now.difference(lastPageTime!).inMilliseconds;
      newDurations.add(duration);

      // keep only last 10 page durations for stable avg
      if (newDurations.length > 10) {
        newDurations.removeAt(0);
      }
    }

    return copyWith(pageDurations: newDurations, lastPageTime: now);
  }

  /// Estimated time remaining
  Duration? get remainingTime {
    if (currentPage == 0 || totalPages == 0 || pageDurations.isEmpty) {
      return null;
    }

    final avgMs =
        pageDurations.reduce((a, b) => a + b) / pageDurations.length;
    final remainingPages = totalPages - currentPage;
    return Duration(milliseconds: (remainingPages * avgMs).round());
  }

}

/// A single PDF in the queue, bundling its [DropItem] with all per-file state
/// (pre-scan counts, extraction progress, and when it was added). Replaces the
/// former parallel maps keyed by file path.
class QueuedPdf {
  final DropItem file;

  /// When the file was added to the queue. Drives the "Added … ago" subtitle.
  final DateTime addedAt;

  /// File size in bytes, or `null` if it couldn't be determined.
  final int? sizeBytes;

  /// Pre-scan total page count: `null` = still counting, `-1` = count failed,
  /// `>= 0` = number of pages.
  final int? pageCount;

  /// Pre-scan image count (same value semantics as [pageCount]).
  final int? imageCount;

  /// Extraction progress; `null` until extraction starts for this file.
  final PdfFileProgress? progress;

  QueuedPdf({
    required this.file,
    required this.addedAt,
    this.sizeBytes,
    this.pageCount,
    this.imageCount,
    this.progress,
  });

  QueuedPdf copyWith({
    int? pageCount,
    int? imageCount,
    PdfFileProgress? progress,
  }) {
    return QueuedPdf(
      file: file,
      addedAt: addedAt,
      sizeBytes: sizeBytes,
      pageCount: pageCount ?? this.pageCount,
      imageCount: imageCount ?? this.imageCount,
      progress: progress ?? this.progress,
    );
  }
}

class PdfExtractorState {
  final bool isDragging;
  final bool isProcessing;
  final DropItem? currentFile;
  final int processedFiles;
  final List<String> errors;

  /// Insertion-ordered queue keyed by file path. Dart maps preserve insertion
  /// order, so this keeps the queue order while collapsing what used to be five
  /// parallel structures into one.
  final Map<String, QueuedPdf> items;

  PdfExtractorState({
    this.isDragging = false,
    this.isProcessing = false,
    this.currentFile,
    this.processedFiles = 0,
    this.errors = const [],
    this.items = const {},
  });

  /// The queued files in order.
  List<DropItem> get files => items.values.map((i) => i.file).toList();

  PdfExtractorState copyWith({
    bool? isDragging,
    bool? isProcessing,
    DropItem? currentFile,
    int? processedFiles,
    List<String>? errors,
    List<String>? outputPaths,
    Map<String, QueuedPdf>? items,
  }) {
    return PdfExtractorState(
      isDragging: isDragging ?? this.isDragging,
      isProcessing: isProcessing ?? this.isProcessing,
      currentFile: currentFile ?? this.currentFile,
      processedFiles: processedFiles ?? this.processedFiles,
      errors: errors ?? this.errors,
      items: items ?? this.items,
    );
  }

  /// Files whose extraction finished successfully.
  int get completedCount => items.values
      .where((i) => i.progress?.done == true && i.progress?.error == null)
      .length;
}
