import 'package:alert_info/alert_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/directory_manager.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_controller.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/app_panel.dart';

/// The bottom bar: a full-width panel holding the run status on the left and
/// the Extract button on the right.
class ExtractBar extends StatelessWidget {
  const ExtractBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Status and button each watch their own narrow slices of state so a
    // progress tick only rebuilds what it touches.
    return appPanel(
      context,
      padding: const EdgeInsets.all(16),
      child: const Row(
        children: [
          Expanded(child: _StatusContent()),
          gapW16,
          _ExtractButton(),
        ],
      ),
    );
  }
}

class _StatusContent extends ConsumerWidget {
  const _StatusContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    // Select each primitive used to render the status independently.
    final isProcessing = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.isProcessing),
    );
    final processedFiles = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.processedFiles),
    );
    final fileCount = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.items.length),
    );
    final errorCount = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.errors.length),
    );
    final completedCount = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.completedCount),
    );

    IconData icon;
    String title;
    String subtitle;
    Color color = accent;

    if (isProcessing) {
      icon = Icons.autorenew_rounded;
      title = "Extracting…";
      subtitle = "$processedFiles of $fileCount processed";
    } else if (errorCount > 0) {
      icon = Icons.error_outline_rounded;
      title = "Completed with errors";
      subtitle = "$errorCount file(s) failed";
      color = Colors.red.shade400;
    } else if (completedCount > 0) {
      icon = Icons.task_alt_rounded;
      title = "Extraction complete!";
      subtitle = "$completedCount file(s) processed successfully";
      color = Colors.green;
    } else if (fileCount > 0) {
      icon = Icons.playlist_add_check_rounded;
      title = "Ready to extract";
      subtitle = "$fileCount file(s) in queue";
    } else {
      icon = Icons.description_outlined;
      title = "No files yet";
      subtitle = "Add PDF files to begin";
    }

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        gapW12,
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExtractButton extends ConsumerWidget {
  const _ExtractButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only isProcessing and emptiness gate the button's enabled state and
    // label, so select just those.
    final isProcessing = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.isProcessing),
    );
    final isEmpty = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.items.isEmpty),
    );
    final disabled = isProcessing || isEmpty;

    return SizedBox(
      width: 230,
      // Fixed height so the button doesn't shrink when the subtitle is hidden
      // during extraction.
      height: 52,
      child: ElevatedButton(
        onPressed: disabled ? null : () => _runExtraction(context, ref),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        // Builder so the spinner can use the button's *resolved* foreground
        // (IconTheme), keeping it the same color as the label in every state.
        child: Builder(
          builder: (context) {
            final fg = IconTheme.of(context).color;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isProcessing)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      )
                    else
                      const Icon(Icons.play_arrow_rounded, size: 22),
                    gapW8,
                    Text(
                      isProcessing ? "Extracting…" : "Extract",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                // Subtitle only when idle — no file count while extracting.
                if (!isProcessing) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Start processing files",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: fg?.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _runExtraction(BuildContext context, WidgetRef ref) async {
  final directory = ref.read(directoryManagerProvider);
  if (directory == null || directory.isEmpty) {
    AlertInfo.show(
      context: context,
      typeInfo: TypeInfo.error,
      position: MessagePosition.bottom,
      text: "Please select an output directory.",
    );
    return;
  }

  await ref
      .read(pdfExtractorScreenControllerProvider.notifier)
      .processPdfFiles();
  if (!context.mounted) return;

  final updated = ref.read(pdfExtractorScreenControllerProvider);
  if (updated.errors.isEmpty) {
    AlertInfo.show(
      context: context,
      typeInfo: TypeInfo.success,
      position: MessagePosition.bottom,
      text: "All files processed successfully.",
    );
    return;
  }

  AlertInfo.show(
    context: context,
    typeInfo: TypeInfo.error,
    position: MessagePosition.bottom,
    text: "${updated.errors.length} files failed to process.",
  );
}
