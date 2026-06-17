// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart' as ui;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/directory_manager.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/pdf_worker.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/pdf_worker_message.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_state.dart';
import 'package:snag_report_extractor_app/src/logging/talker.dart';

/// Bundles every per-file control handle for one in-flight extraction. These
/// are identity-bearing resources (an [Isolate], a [ReceivePort], a cancel
/// [Completer]) plus a transient pause flag — deliberately kept OUT of the
/// equality-compared state model so they never cause spurious rebuilds. One
/// [ExtractionTask] per active file lives in [PdfExtractorScreenController._tasks],
/// replacing the three formerly-parallel maps so there is a single source of
/// truth that can't desync on reorder/remove.
class ExtractionTask {
  /// The spawned worker isolate for this file.
  Isolate? isolate;

  /// The port the worker streams [PdfWorkerMessage]s back on.
  final ReceivePort receivePort;

  /// Completing this token deterministically unblocks the processing loop for
  /// this file — unlike relying on a killed isolate to close its port, which is
  /// what made cancellation flaky before.
  final Completer<void> cancelToken;

  /// True when the cancel token was completed for a *pause* (reordered below
  /// another pending file) rather than a removal. The processing loop reads
  /// this to keep the partial output and resume checkpoint instead of deleting.
  bool pauseRequested;

  ExtractionTask({
    required this.receivePort,
    required this.cancelToken,
    this.isolate,
    this.pauseRequested = false,
  });
}

class PdfExtractorScreenController extends Notifier<PdfExtractorState> {
  late final DirectoryManager directoryManager;

  /// Single source of truth for per-file extraction control handles, keyed by
  /// file path. Replaces the former parallel `_activePorts` / `_cancelTokens` /
  /// `_pauseRequested` maps so reorder/remove can't leave them desynced and
  /// cleanup removes exactly one entry.
  final Map<String, ExtractionTask> _tasks = {};

  @override
  PdfExtractorState build() {
    directoryManager = ref.read(directoryManagerProvider.notifier);
    return PdfExtractorState();
  }

  void startDragging() {
    talker.debug("Dragging started");
    state = state.copyWith(isDragging: true);
  }

  void stopDragging() {
    talker.debug("Dragging stopped");
    state = state.copyWith(isDragging: false);
  }

  /// Adds [files] to the queue, skipping any whose path is already queued.
  /// Returns the number of files actually added (after de-duplication).
  int addToQueue(List<DropItem> files) {
    final existingPaths = state.items.keys.toSet();
    final newFiles = <DropItem>[];
    for (final f in files) {
      if (existingPaths.add(f.path)) newFiles.add(f);
    }

    final skipped = files.length - newFiles.length;
    if (skipped > 0) {
      talker.warning("Skipped $skipped duplicate file(s) already in queue");
    }
    if (newFiles.isEmpty) return 0;

    talker.info("Adding ${newFiles.length} file(s) to queue");
    final now = DateTime.now();
    state = state.copyWith(
      items: {
        ...state.items,
        for (final f in newFiles)
          f.path: QueuedPdf(
            file: f,
            addedAt: now,
            sizeBytes: _fileSize(f.path),
          ),
      },
    );

    // Kick off a background pre-scan for each newly added file so the queue
    // can show its page and image counts before Extract runs.
    for (final file in newFiles) {
      _scanFile(file);
    }

    return newFiles.length;
  }

  /// Reorders the queue by moving the item at [oldIndex] to [newIndex] (indices
  /// into the visible, insertion-ordered list). Wired to `onReorder`, which
  /// reports [newIndex] as if the moved item were still present, so a downward
  /// move overshoots by one. If extraction is running and the file currently
  /// being extracted is no longer the top pending item after the move, it is
  /// paused so the loop switches to the new top; the paused file resumes from
  /// its checkpoint once it returns to the top.
  void reorderQueue(int oldIndex, int newIndex) {
    final entries = state.items.entries.toList();
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= entries.length) newIndex = entries.length - 1;
    if (newIndex == oldIndex) return;

    final moved = entries.removeAt(oldIndex);
    entries.insert(newIndex, moved);
    state = state.copyWith(items: {for (final e in entries) e.key: e.value});

    _maybePauseReorderedActive();
  }

  /// Path of the file currently being extracted, or `null`. Extraction is
  /// sequential, so there is at most one active task.
  String? get _activePath => _tasks.keys.isEmpty ? null : _tasks.keys.first;

  /// The first item that still needs extracting (not done, not failed), in
  /// queue order — this is the file the drain loop will pick next.
  String? get _topPendingPath {
    for (final entry in state.items.entries) {
      final p = entry.value.progress;
      if (p?.done == true || p?.error != null) continue;
      return entry.key;
    }
    return null;
  }

  /// If the file being extracted has been reordered below another pending file,
  /// pause it so the loop can start the new top item.
  void _maybePauseReorderedActive() {
    if (!state.isProcessing) return;
    final active = _activePath;
    if (active == null) return;
    final top = _topPendingPath;
    if (top != null && top != active) _pauseActive(active);
  }

  /// Stops the running isolate for [filePath] and marks it paused, preserving
  /// its partial output and resume checkpoint. Completing the cancel token
  /// unblocks the processing loop's wait so it can move to the next file.
  void _pauseActive(String filePath) {
    final item = state.items[filePath];
    final progress = item?.progress;
    if (item == null || progress == null) return;
    talker.info("Pausing ${progress.fileName} (reordered below another file)");

    final task = _tasks[filePath];
    task?.pauseRequested = true;
    state = state.copyWith(items: {
      ...state.items,
      filePath: item.copyWith(progress: progress.copyWith(paused: true)),
    });

    task?.isolate?.kill(priority: Isolate.immediate);
    final token = task?.cancelToken;
    if (token != null && !token.isCompleted) token.complete();
  }

  /// File size in bytes via a cheap stat, or `null` if it can't be read.
  int? _fileSize(String path) {
    try {
      return File(path).statSync().size;
    } catch (_) {
      return null;
    }
  }

  /// Pre-scans a file off the UI isolate and writes its page/image counts onto
  /// the queue item: `null` while scanning, `-1` on failure, otherwise the
  /// count.
  Future<void> _scanFile(DropItem file) async {
    final path = file.path;

    // Mark as "counting" immediately so the card shows a spinner. The item was
    // created with null counts in addToQueue, so nothing to set here.

    try {
      final result = await Isolate.run(() => scanPdf(path));
      // The file may have been removed from the queue while we were scanning.
      if (!state.items.containsKey(path)) return;
      talker.debug(
        "Pre-scan: ${result.pages} page(s), ${result.images} image(s) in ${file.name}",
      );
      state = state.copyWith(
        items: {
          ...state.items,
          path: state.items[path]!.copyWith(
            imageCount: result.images,
            pageCount: result.pages,
          ),
        },
      );
    } catch (e, st) {
      talker.error("Failed to pre-scan ${file.name}", e, st);
      if (!state.items.containsKey(path)) return;
      state = state.copyWith(
        items: {
          ...state.items,
          path: state.items[path]!.copyWith(imageCount: -1, pageCount: -1),
        },
      );
    }
  }

  Future<void> removeFromQueue(DropItem file) async {
    final progress = state.items[file.path]?.progress;
    talker.info("Removing file from queue: ${file.name}");

    // "In flight" means the drain loop is actively extracting this file right
    // now (it owns an active task). A paused file holds a dead isolate ref but
    // is NOT in flight, so its partial folder must be deleted here rather than
    // left for the loop.
    final task = _tasks[file.path];
    final inFlight = task != null;
    if (inFlight) {
      talker.warning("Killing isolate for file: ${file.name}");
      task.isolate?.kill(priority: Isolate.immediate);
    }

    // Completing the cancel token instantly unblocks the processing loop for
    // this file (it races every wait against the token). Closing the port is
    // just belt-and-suspenders cleanup.
    final token = task?.cancelToken;
    if (token != null && !token.isCompleted) token.complete();
    task?.receivePort.close();

    // Drop the file from state first so the processing loop stops touching it.
    state = state.copyWith(
      items: {...state.items}..remove(file.path),
    );

    // Delete the partial output folder unless extraction finished cleanly.
    // For an in-flight file we DON'T delete here — the processing loop deletes
    // it after it has stopped, so a still-pending image write can't race the
    // deletion and resurrect the folder. For any other case (queued, failed,
    // already finished) no write is pending, so it's safe to delete now.
    final dir = progress?.outputDir;
    final cleanlyDone = progress?.done == true && progress?.error == null;
    if (!inFlight && dir != null && !cleanlyDone) {
      await _deletePartialOutput(dir, file.name);
    }
  }

  /// Recursively deletes a partial/failed output folder. Safe to call on a
  /// folder that no longer exists.
  Future<void> _deletePartialOutput(String dir, String label) async {
    try {
      final directory = Directory(dir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        talker.info("Deleted partial output folder for $label: $dir");
      }
    } catch (e, st) {
      talker.error("Failed to delete partial output folder: $dir", e, st);
    }
  }

  /// Removes every file from the queue and resets per-file state. Any
  /// still-running isolates are killed first. Intended for use when not
  /// processing (the UI disables the action while extraction is in flight).
  void clearQueue() {
    talker.info("Clearing queue (${state.items.length} file(s))");

    for (final task in _tasks.values) {
      task.isolate?.kill(priority: Isolate.immediate);
      if (!task.cancelToken.isCompleted) task.cancelToken.complete();
      task.receivePort.close();
    }
    _tasks.clear();

    state = state.copyWith(
      items: {},
      errors: [],
      processedFiles: 0,
    );
  }

  /// Removes only the files that finished successfully, leaving queued and
  /// failed files in place. No isolates are running for completed files.
  void clearCompleted() {
    final completedPaths = state.items.entries
        .where((e) =>
            e.value.progress?.done == true && e.value.progress?.error == null)
        .map((e) => e.key)
        .toSet();

    if (completedPaths.isEmpty) return;
    talker.info("Clearing ${completedPaths.length} completed file(s)");

    state = state.copyWith(
      items: {...state.items}
        ..removeWhere((k, v) => completedPaths.contains(k)),
    );
  }

  Future<void> processPdfFiles() async {
    // Guard against re-entrancy (e.g. double-clicking Extract). The UI also
    // disables the button while processing, but this is the safety net that
    // prevents duplicate isolates/output directories if it's ever called again.
    if (state.isProcessing) {
      talker.warning("processPdfFiles() called while already processing — ignoring");
      return;
    }

    try {
      final outputRoot = directoryManager.getDirectory();
      talker.info("Starting PDF processing. Output root: $outputRoot");

      state = state.copyWith(isProcessing: true, errors: []);

      // Drain the live queue rather than a one-time snapshot: re-read it each
      // iteration so files added mid-run are picked up automatically, files
      // removed mid-run simply stop being selected, and already-done/failed
      // files are skipped by the selector below.
      while (true) {
        QueuedPdf? next;
        for (final item in state.items.values) {
          final progress = item.progress;
          if (progress?.done == true || progress?.error != null) continue;
          next = item;
          break;
        }
        if (next == null) break; // queue fully drained

        final file = next.file;
        final fileName = file.name;
        final filePath = file.path;

        // A paused file resumes into its existing folder (already holds the
        // images written before the pause); a fresh file gets a new folder.
        final resuming = next.progress?.paused == true &&
            next.progress?.outputDir != null;
        final outputDir = resuming
            ? next.progress!.outputDir!
            : await _resolveOutputDir(outputRoot, filePath);
        talker.info(
          "${resuming ? 'Resuming' : 'Processing'} file: $fileName -> $outputDir",
        );

        final cancelled = await _extractFile(filePath, fileName, outputDir);

        // If the file was removed mid-extraction, the loop has now fully
        // stopped writing for it, so it's safe to delete its partial folder
        // (no write can race the deletion).
        if (cancelled || !state.items.containsKey(filePath)) {
          await _deletePartialOutput(outputDir, fileName);
        }
      }
    } catch (e, st) {
      talker.error("Unexpected error in processPdfFiles", e, st);
      rethrow;
    } finally {
      talker.info("Processing finished");
      _tasks.clear();
      state = state.copyWith(isProcessing: false, currentFile: null);
    }
  }

  /// Resolves the output folder for [filePath] under [outputRoot]: uses the
  /// file's basename, and if that folder already exists appends " (2)", " (3)",
  /// … until a free name is found. Creates the folder before returning.
  Future<String> _resolveOutputDir(String outputRoot, String filePath) async {
    final folderName = p.basenameWithoutExtension(filePath);
    var outputDir = p.join(outputRoot, folderName);

    if (await Directory(outputDir).exists()) {
      for (var i = 2; Directory(outputDir).existsSync(); i++) {
        outputDir = p.join(outputRoot, "$folderName ($i)");
      }
    }
    await Directory(outputDir).create(recursive: true);
    return outputDir;
  }

  /// Replaces the queued item at [path] via [update], unless it was removed
  /// (e.g. during an `await`) — in which case this is a no-op. This is what
  /// prevents null-check crashes when a file is deleted mid-extraction.
  void _patchItem(String path, QueuedPdf Function(QueuedPdf item) update) {
    final item = state.items[path];
    if (item == null) return;
    state = state.copyWith(items: {...state.items, path: update(item)});
  }

  /// Spawns the extraction isolate for one file and consumes its message
  /// stream until completion, failure, or cancellation. Returns `true` if the
  /// file was cancelled mid-run (so the caller can delete its partial folder).
  ///
  /// Every wait is raced against the file's cancel token so a removal unblocks
  /// us instantly — the killed isolate will never send another message or
  /// reliably close its port.
  Future<bool> _extractFile(
    String filePath,
    String fileName,
    String outputDir,
  ) async {
    final receivePort = ReceivePort();
    final cancelToken = Completer<void>();
    final task = ExtractionTask(
      receivePort: receivePort,
      cancelToken: cancelToken,
    );
    _tasks[filePath] = task;

    // Resume support: a paused file already has images written up to
    // currentImage, so tell the worker to skip re-sending those and keep the
    // counters in the UI rather than resetting to a fresh run.
    final resumed = state.items[filePath]?.progress;
    final isResume = resumed != null && resumed.paused;
    final resumeFromImage = isResume ? resumed.currentImage : 0;

    final isolate = await Isolate.spawn(extractPdfWorker, {
      "sendPort": receivePort.sendPort,
      "path": filePath,
      "outputDir": outputDir,
      "resumeFromImage": resumeFromImage,
    });
    // Attach the isolate to its task (the single source of truth for control
    // handles) rather than the equality-compared progress model.
    task.isolate = isolate;

    // The file may have been removed while the isolate was spawning.
    _patchItem(
      filePath,
      (item) {
        final base = item.progress;
        // Resuming: keep the existing counters and clear the paused flag.
        // Fresh start: a brand-new progress record.
        if (isResume && base != null) {
          return item.copyWith(progress: base.copyWith(paused: false));
        }
        return item.copyWith(
          progress: PdfFileProgress(
            fileName: fileName,
            outputDir: outputDir,
          ),
        );
      },
    );

    final iterator = StreamIterator<PdfWorkerMessage>(
      receivePort.cast<PdfWorkerMessage>(),
    );
    var cancelled = false;
    var paused = false;
    // Set from the worker's WorkerReady handshake; used to grant the worker
    // permission to send the next image once we've consumed the current one.
    SendPort? ackPort;
    try {
      while (true) {
        final hasNext = await Future.any<bool>([
          iterator.moveNext(),
          cancelToken.future.then((_) => false),
        ]);
        if (cancelToken.isCompleted) {
          cancelled = true;
          paused = task.pauseRequested;
          break;
        }
        if (!hasNext) break; // worker finished and closed its port

        final msg = iterator.current;
        final currentProgress = state.items[filePath]?.progress;
        if (currentProgress == null) {
          cancelled = true;
          break;
        }

        switch (msg) {
          case WorkerReady(ackPort: final port):
            ackPort = port;

          case ExtractionFailed(:final error):
            talker.error("Error processing $fileName", error);
            final item = state.items[filePath];
            if (item != null) {
              state = state.copyWith(
                items: {
                  ...state.items,
                  filePath: item.copyWith(
                    progress: currentProgress.copyWith(
                      error: error,
                      done: true,
                    ),
                  ),
                },
                errors: [...state.errors, error],
                processedFiles: state.processedFiles + 1,
              );
            }
            return cancelled;

          case PageProgress(:final page, :final pageCount):
            // On resume the worker re-walks pages from the start; don't let the
            // progress bar rewind past where it already was.
            if (page < currentProgress.currentPage) break;
            talker.debug("[$fileName] Processed page $page/$pageCount");
            _patchItem(
              filePath,
              (item) => item.copyWith(
                progress: currentProgress
                    .copyWith(currentPage: page, totalPages: pageCount)
                    .markPageDone(),
              ),
            );

          case ImageExtracted(
              :final bytes,
              :final caption,
              :final imgCount,
              :final totalImages,
            ):
            ui.Image? rendered;
            try {
              // Render the caption strip onto the photo, then encode to JPEG.
              rendered = await _renderImageWithCaption(bytes, caption);
              final outputBytes = await _imageToBytes(rendered);

              // Cancelled/paused/removed while rendering — don't write into a
              // folder that may be getting deleted, and preserve the checkpoint
              // if this was a pause.
              if (cancelToken.isCompleted ||
                  state.items[filePath]?.progress == null) {
                cancelled = true;
                paused = task.pauseRequested;
                return paused ? false : cancelled;
              }

              final imageFile = File(p.join(outputDir, "image_$imgCount.jpg"));
              await imageFile.writeAsBytes(outputBytes);

              talker.debug(
                "[$fileName] Extracted image $totalImages/$imgCount",
              );
              // Re-checked inside _patchItem: the file may have been removed
              // during the write above, so don't assume it still exists.
              _patchItem(
                filePath,
                (item) => item.copyWith(
                  progress: currentProgress.copyWith(
                    currentImage: imgCount,
                    totalImages: totalImages,
                  ),
                ),
              );
            } catch (e, st) {
              // A single corrupt/undecodable image must not abort the whole
              // file: log it and move on to the next photo.
              talker.error(
                "[$fileName] Skipped image $imgCount (render/write failed)",
                e,
                st,
              );
            } finally {
              // Free the composed image's native memory before the next one.
              rendered?.dispose();
              // Grant the worker a credit so it can send the next image,
              // regardless of whether this one succeeded or was skipped.
              ackPort?.send(null);
            }

          case ExtractionDone(:final outputDir):
            talker.log("Finished processing $fileName");
            final item = state.items[filePath];
            if (item != null) {
              state = state.copyWith(
                items: {
                  ...state.items,
                  filePath: item.copyWith(
                    progress: currentProgress.copyWith(
                      done: true,
                      outputDir: outputDir,
                    ),
                  ),
                },
                processedFiles: state.processedFiles + 1,
              );
            }
            return cancelled;
        }
      }
    } finally {
      await iterator.cancel();
      receivePort.close();
      _tasks.remove(filePath);
    }

    // A pause keeps its partial output and checkpoint, so report it as "not
    // cancelled" to the loop, which then leaves the folder in place.
    return paused ? false : cancelled;
  }

  /// Encode the composed ui.Image as JPEG.
  ///
  /// The content is a photo plus a solid white caption strip (no transparency),
  /// so JPEG is far smaller than PNG with no meaningful quality loss. dart:ui
  /// can't emit JPEG, so we pull raw RGBA and encode via the `image` package.
  Future<Uint8List> _imageToBytes(ui.Image image) async {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: byteData!.buffer,
      numChannels: 4,
    );
    return img.encodeJpg(rgba, quality: 90);
  }

  String wrapCaption(String text, {int maxChars = 30}) {
    final words = text.split(' ');
    final lines = <String>[];
    var currentLine = '';

    for (final word in words) {
      if ((currentLine + word).length <= maxChars) {
        currentLine = currentLine.isEmpty ? word : '$currentLine $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);

    return lines.join('\n');
  }

  /// Render caption with TextPainter
  Future<ui.Image> _renderImageWithCaption(
    Uint8List imageBytes,
    String caption, {
    double fontSize = 20,
    double padding = 10,
  }) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final ui.Image original;
    try {
      final frame = await codec.getNextFrame();
      original = frame.image;
    } finally {
      // The codec holds native decode buffers; release them once we have the
      // single frame. Without this they accumulate across every photo.
      codec.dispose();
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();

    // Wrap caption (30 chars max per line, no word break)
    final wrappedCaption = wrapCaption(caption, maxChars: 30);
    // Prepare text painter
    final textPainter = ui.TextPainter(
      text: ui.TextSpan(
        text: wrappedCaption,
        style: ui.TextStyle(
          color: const ui.Color(0xFF000000),
          fontSize: fontSize,
          fontFamily: 'Roboto',
        ),
      ),
      textAlign: ui.TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout(maxWidth: original.width.toDouble() - (2 * padding));

    final captionHeight = textPainter.height + (2 * padding);

    // Draw background
    canvas.drawRect(
      ui.Rect.fromLTWH(
        0,
        0,
        original.width.toDouble(),
        original.height + captionHeight,
      ),
      paint..color = const ui.Color(0xFFFFFFFF),
    );

    // Draw original image
    canvas.drawImage(original, ui.Offset.zero, paint);

    // Draw caption (centered, auto height, wraps text)
    final dx = (original.width - textPainter.width) / 2;
    final dy = original.height + padding;
    textPainter.paint(canvas, ui.Offset(dx, dy));

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        original.width,
        (original.height + captionHeight).toInt(),
      );
    } finally {
      // Rasterisation is done; release the recorded picture and the decoded
      // source image so they don't leak per photo. The returned image is the
      // caller's to dispose.
      picture.dispose();
      original.dispose();
    }
  }

  void clearErrors() {
    talker.info("Clearing all errors");

    state = state.copyWith(errors: []);
  }
}

final pdfExtractorScreenControllerProvider =
    NotifierProvider<PdfExtractorScreenController, PdfExtractorState>(
  PdfExtractorScreenController.new,
);
