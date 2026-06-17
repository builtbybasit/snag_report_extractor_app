import 'dart:io';
import 'package:alert_info/alert_info.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snag_report_extractor_app/src/common_widgets/dashed_rect.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_controller.dart';

/// Drag-and-drop / click-to-pick area for adding PDFs to the queue.
class PdfDropZone extends ConsumerWidget {
  const PdfDropZone({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.read(pdfExtractorScreenControllerProvider.notifier);
    // Only the dashed border / fill depend on the drag state, so isolate it.
    final isDragging = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.isDragging),
    );
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final borderColor = isDragging ? accent : theme.dividerColor;

    return DropTarget(
      onDragEntered: (_) => controller.startDragging(),
      onDragExited: (_) => controller.stopDragging(),
      onDragDone: (detail) {
        controller.stopDragging();
        final files = detail.files;
        if (files.isNotEmpty) {
          final added = controller.addToQueue(files);
          _reportAddResult(context, requested: files.length, added: added);
        }
      },
      child: GestureDetector(
        onTap: () => _pickFiles(context, controller),
        child: DashedRect(
          color: borderColor,
          strokeWidth: isDragging ? 2 : 1.5,
          radius: 16,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              // Subtle always-on fill so the drop area reads as a distinct
              // panel against the page, deepening while a file is dragged over.
              color: isDragging
                  ? accent.withValues(alpha: isDark ? 0.12 : 0.07)
                  : accent.withValues(alpha: isDark ? 0.05 : 0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.15 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.upload_file_rounded,
                        size: 30, color: accent),
                  ),
                  gapH16,
                  Text(
                    "Drag & Drop PDF files here",
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  gapH4,
                  Text(
                    "or click to select files",
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  gapH8,
                  Text(
                    "Supports PDF files up to 500MB",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pickFiles(
  BuildContext context,
  PdfExtractorScreenController controller,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: true,
  );
  if (result == null || result.files.isEmpty) return;

  final added = result.files.map((file) {
    final bytes = File(file.path!).readAsBytesSync();
    return DropItemFile.fromData(
      bytes,
      name: file.name,
      length: file.size,
      mimeType: 'application/pdf',
      path: file.path,
    );
  }).toList();

  final count = controller.addToQueue(added);
  if (context.mounted) {
    _reportAddResult(context, requested: added.length, added: count);
  }
}

/// Toasts the outcome of an add: how many were queued, and how many were
/// skipped because they were already in the queue.
void _reportAddResult(
  BuildContext context, {
  required int requested,
  required int added,
}) {
  final skipped = requested - added;

  if (added == 0) {
    AlertInfo.show(
      context: context,
      typeInfo: TypeInfo.warning,
      position: MessagePosition.bottom,
      text: skipped == 1
          ? "That file is already in the queue."
          : "Those files are already in the queue.",
    );
    return;
  }

  final addedText = "$added ${added == 1 ? 'file' : 'files'} added to queue";
  AlertInfo.show(
    context: context,
    typeInfo: TypeInfo.success,
    position: MessagePosition.bottom,
    text: skipped > 0
        ? "$addedText ($skipped duplicate skipped)."
        : "$addedText.",
  );
}
