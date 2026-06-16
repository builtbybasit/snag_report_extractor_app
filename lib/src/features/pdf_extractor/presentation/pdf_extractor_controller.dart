// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';
import 'dart:isolate';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart' as ui;
import 'dart:typed_data';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/directory_manager.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/pdf_worker.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_state.dart';
import 'package:snag_report_extractor_app/src/logging/talker.dart';
class PdfExtractorScreenController extends Notifier<PdfExtractorState> {
  late final DirectoryManager directoryManager;

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

  void addToQueue(List<DropItem> files) {
    talker.info("Adding ${files.length} file(s) to queue");
    state = state.copyWith(files: [...state.files, ...files]);
  }

  void removeFromQueue(DropItem file) {
    final progress = state.progress[file.path];
    talker.info("Removing file from queue: ${file.name}");

    if (progress?.isolate != null && progress?.done == false) {
      talker.warning("Killing isolate for file: ${file.name}");
      progress?.isolate!.kill(priority: Isolate.immediate);
    }

    state = state.copyWith(
      files: state.files.where((item) => item != file).toList(),
      progress: {...state.progress}..remove(file.path),
    );
  }

  Future<void> processPdfFiles() async {
    try {
      String outputRoot = directoryManager.getDirectory();
      talker.info("Starting PDF processing. Output root: $outputRoot");
      talker.info("Output root: $outputRoot");

      state = state.copyWith(isProcessing: true, errors: []);

      for (final file in state.files) {
        final fileName = file.name;
        final filePath = file.path;

        if (state.progress[filePath]?.done == true) {
          talker.debug("Skipping $fileName (already processed)");
          // already processing this file
          continue;
        }

        final folderName = p.basenameWithoutExtension(filePath);
        String outputDir = "$outputRoot/$folderName";

        if (await Directory(outputDir).exists()) {
          for (var i = 2; Directory(outputDir).existsSync(); i++) {
            outputDir = "$outputRoot/$folderName ($i)";
          }
        }
        await Directory(outputDir).create(recursive: true);

        talker.info("Processing file: $fileName -> $outputDir");

        state = state.copyWith(
          progress: {
            ...state.progress,
            filePath: PdfFileProgress(fileName: fileName),
          },
        );

        final receivePort = ReceivePort();

        final isolate = await Isolate.spawn(extractPdfWorker, {
          "sendPort": receivePort.sendPort,
          "path": filePath,
          "outputDir": outputDir,
        });

        state = state.copyWith(
          progress: {
            ...state.progress,
            filePath: PdfFileProgress(fileName: fileName, isolate: isolate),
          },
        );

        await for (final msg in receivePort) {
          final progress = msg as Map<String, dynamic>;
          final currentProgress = state.progress[filePath]!;

          if (progress["error"] != null) {
            talker.error("Error processing $fileName", progress["error"]);

            state = state.copyWith(
              progress: {
                ...state.progress,
                filePath: currentProgress.copyWith(
                  error: progress["error"],
                  done: true,
                ),
              },
              errors: [...state.errors, progress["error"]],
              processedFiles: state.processedFiles + 1,
            );
            receivePort.close();
            break;
          }

          if (progress["page"] != null && progress["pageCount"] != null) {
            talker.debug(
              "[$fileName] Processed page ${progress["page"]}/${progress["pageCount"]}",
            );

            state = state.copyWith(
              progress: {
                ...state.progress,
                filePath: currentProgress
                    .copyWith(
                      currentPage: progress["page"],
                      totalPages: progress["pageCount"],
                    )
                    .markPageDone(),
              },
            );
          }


          if (msg["imageBytes"] != null) {
            final bytes = msg["imageBytes"] as Uint8List;
            final caption = msg["caption"] as String;
            final count = msg["imgCount"] as int;
            final totalImages = msg["totalImages"] as int;

            // 🔹 Render with TextPainter
            final rendered = await _renderImageWithCaption(bytes, caption);
            final outputBytes = await _imageToBytes(rendered);

            final file = File("$outputDir/image_$count.png");
            await file.writeAsBytes(outputBytes);

            talker.debug(
              "[$fileName] Extracted image $totalImages/$count",
            );
            state = state.copyWith(
              progress: {
                ...state.progress,
                filePath: currentProgress.copyWith(
                  currentImage: count,
                  totalImages: totalImages,
                ),
              },
            );
          }

          if (progress["done"] == true) {
            talker.log("Finished processing $fileName");
            state = state.copyWith(
              progress: {
                ...state.progress,
                filePath: currentProgress.copyWith(
                  done: true,
                  outputDir: progress["outputDir"],
                ),
              },
              processedFiles: state.processedFiles + 1,
            );
            receivePort.close();
            break;
          }
        }
      }
    } catch (e, st) {
      talker.error("Unexpected error in processPdfFiles", e, st);
      rethrow;
    } finally {
      talker.info("Processing finished");
      state = state.copyWith(isProcessing: false, currentFile: null);
    }
  }

  /// Convert ui.Image to PNG bytes
  Future<Uint8List> _imageToBytes(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
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
    final frame = await codec.getNextFrame();
    final original = frame.image;

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
    return await picture.toImage(
      original.width,
      (original.height + captionHeight).toInt(),
    );
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
