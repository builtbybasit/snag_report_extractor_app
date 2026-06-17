import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/directory_manager.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/app_panel.dart';

/// The "Output Directory" panel: shows the selected output folder and a button
/// to change it.
class OutputDirectorySection extends ConsumerWidget {
  const OutputDirectorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(directoryManagerProvider);
    final theme = Theme.of(context);
    final hasDir = directory != null && directory.isNotEmpty;
    void pick() =>
        ref.read(directoryManagerProvider.notifier).selectDirectory();

    return appPanel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_rounded,
                  size: 18, color: theme.colorScheme.primary),
              gapW8,
              Text(
                "Output Directory",
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          gapH12,
          // The whole field is one rounded box; the "Change" button is a
          // rounded suffix inside it.
          InkWell(
            onTap: pick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasDir ? directory : "No directory selected",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasDir
                            ? theme.colorScheme.onSurface
                            : theme.hintColor,
                      ),
                    ),
                  ),
                  gapW8,
                  FilledButton.icon(
                    onPressed: pick,
                    label: const Text("Choose"),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          gapH8,
          Text(
            "All extracted files will be saved to this location",
            style: TextStyle(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
