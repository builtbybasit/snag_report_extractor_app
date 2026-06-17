import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_controller.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/queue_count_badge.dart';

/// Queue section header: the "Queue" title with a count badge, plus the
/// "Clear Completed" and "Clear All" actions.
class QueueHeader extends ConsumerWidget {
  const QueueHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Select only the primitives this row renders / enables on, so a progress
    // tick that doesn't change any of them won't rebuild the header.
    final fileCount = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.items.length),
    );
    final isProcessing = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.isProcessing),
    );
    final hasCompleted = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.completedCount > 0),
    );

    // The title group is Expanded so it yields width to the right-aligned
    // action buttons instead of overflowing on narrow windows.
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(Icons.layers_rounded,
                  size: 20, color: theme.colorScheme.primary),
              gapW8,
              Flexible(
                child: Text(
                  "Queue",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              gapW8,
              QueueCountBadge(count: fileCount),
            ],
          ),
        ),
        gapW8,
        OutlinedButton.icon(
          onPressed: (isProcessing || !hasCompleted)
              ? null
              : () => ref
                  .read(pdfExtractorScreenControllerProvider.notifier)
                  .clearCompleted(),
          icon: const Icon(Icons.cleaning_services_rounded, size: 18),
          label: const Text("Clear Completed"),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(color: theme.dividerColor),
          ),
        ),
        gapW8,
        OutlinedButton.icon(
          onPressed: isProcessing
              ? null
              : () => _confirmClearQueue(context, ref),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text("Clear All"),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade400,
            side: BorderSide(color: Colors.red.shade200),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmClearQueue(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Clear queue?"),
      content: const Text(
        "This removes all files from the queue. Files already extracted to "
        "disk are not affected.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text("Clear all"),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    ref.read(pdfExtractorScreenControllerProvider.notifier).clearQueue();
  }
}
