// pdf_extractor_screen.dart
import 'dart:io';
import 'package:alert_info/alert_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:snag_report_extractor_app/src/app.dart';
import 'package:snag_report_extractor_app/src/common_widgets/dashed_rect.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/data/directory_manager.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_controller.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_file_card.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/queue_count_badge.dart';
import 'package:snag_report_extractor_app/src/routing/app_routing.dart';
import 'package:snag_report_extractor_app/src/theme_mode_provider.dart';

class PdfExtractorScreen extends ConsumerWidget {
  const PdfExtractorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Whether the queue is non-empty: this only flips when files are added to
    // or removed from an empty/non-empty queue, so the surrounding column does
    // not rebuild on every progress tick.
    final hasFiles = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.items.isNotEmpty),
    );

    return Scaffold(
      appBar: _buildAppBar(context, ref, isDark),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _OutputDirectorySection(),
                gapH24,
                _DropZone(isDark: isDark),
                gapH24,
                if (hasFiles) ...[
                  const _QueueHeader(),
                  gapH12,
                  const _QueueList(),
                  gapH16,
                ],
                const _BottomBar(),
                gapH8,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 16,
      backgroundColor: isDark ? AppColors.surface : null,
      flexibleSpace: isDark
          ? null
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3B7BF6), AppColors.blueDark],
                ),
              ),
            ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              'assets/images/icon-1024x1024.png',
              fit: BoxFit.contain,
            ),
          ),
          gapW12,
          const Text(
            'Snag Report Extractor',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      actions: [
        _appBarAction(
          context,
          isDark,
          icon: Icons.insights_rounded,
          tooltip: "Logs",
          onTap: () => context.goNamed(AppRoute.logs.name),
        ),
        gapW8,
        _appBarAction(
          context,
          isDark,
          icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          tooltip: "Toggle theme",
          onTap: () => ref.read(themeModeProvider.notifier).toggleTheme(),
        ),
        gapW16,
      ],
    );
  }

  Widget _appBarAction(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: Colors.white,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Output directory
// -----------------------------------------------------------------------------

class _OutputDirectorySection extends ConsumerWidget {
  const _OutputDirectorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(directoryManagerProvider);
    final theme = Theme.of(context);
    final hasDir = directory != null && directory.isNotEmpty;
    void pick() =>
        ref.read(directoryManagerProvider.notifier).selectDirectory();

    return _panel(
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

// -----------------------------------------------------------------------------
// Drop zone
// -----------------------------------------------------------------------------

class _DropZone extends ConsumerWidget {
  const _DropZone({required this.isDark});

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

// -----------------------------------------------------------------------------
// Queue header
// -----------------------------------------------------------------------------

class _QueueHeader extends ConsumerWidget {
  const _QueueHeader();

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

// -----------------------------------------------------------------------------
// Queue list (reorderable)
// -----------------------------------------------------------------------------

/// The queue rendered as a reorderable list. Each row carries a grip handle on
/// its left edge (grab-to-drag); dragging a file changes its processing order,
/// and dragging the file that's currently extracting below another pending
/// file pauses it (it resumes when it returns to the top).
class _QueueList extends ConsumerWidget {
  const _QueueList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.read(pdfExtractorScreenControllerProvider.notifier);
    // Select a stable String fingerprint of the ordered keys. `select` rebuilds
    // on `!=`, and Strings have value equality, so this rebuilds the list only
    // when files are added/removed/reordered — a per-file progress tick (which
    // leaves the key order unchanged) does not. Each row then watches its own
    // item via [_QueueListItem]. (A `toList()` would be a fresh List instance
    // each tick and never compare equal, so it can't be selected directly.)
    // Joined with NUL, which can't appear in a filesystem path on any OS, so
    // the round-trip through split is lossless even for paths with spaces.
    final pathsKey = ref.watch(
      pdfExtractorScreenControllerProvider
          .select((s) => s.items.keys.join('\u0000')),
    );
    final paths =
        pathsKey.isEmpty ? const <String>[] : pathsKey.split('\u0000');

    return ReorderableListView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: paths.length,
      // The default proxy wraps the dragged item in an opaque (white) Material;
      // use a transparent one so the card keeps its own rounded background while
      // being dragged.
      proxyDecorator: (child, index, animation) =>
          Material(type: MaterialType.transparency, child: child),
      // ignore: deprecated_member_use
      onReorder: controller.reorderQueue,
      itemBuilder: (context, i) {
        final path = paths[i];
        return _QueueListItem(
          key: ValueKey(path),
          path: path,
          reorderIndex: i,
        );
      },
    );
  }
}

/// One row of the queue. Watches only its own item (keyed by [path]) so a
/// progress update on a single file rebuilds just this card, not the whole
/// list or screen.
class _QueueListItem extends ConsumerWidget {
  const _QueueListItem({
    super.key,
    required this.path,
    required this.reorderIndex,
  });

  final String path;
  final int reorderIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.items[path]),
    );
    // Defensive: if the item was just removed, render nothing this frame.
    if (item == null) return const SizedBox.shrink();

    final controller =
        ref.read(pdfExtractorScreenControllerProvider.notifier);

    // The grab handle lives on the card's left border (see PdfFileCard);
    // reorderIndex wires it to the list's drag listener.
    return PdfFileCard(
      reorderIndex: reorderIndex,
      file: item.file,
      progress: item.progress,
      imageCount: item.imageCount,
      pageCount: item.pageCount,
      addedAt: item.addedAt,
      sizeBytes: item.sizeBytes,
      onDelete: () => controller.removeFromQueue(item.file),
    );
  }
}

// -----------------------------------------------------------------------------
// Bottom status + Extract bar
// -----------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    // One full-width white panel holding the status on the left and the
    // Extract button on the right. Status and button each watch their own
    // narrow slices of state so a progress tick only rebuilds what it touches.
    return _panel(
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
        onPressed: disabled
            ? null
            : () => _runExtraction(context, ref),
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

// -----------------------------------------------------------------------------
// Actions / helpers
// -----------------------------------------------------------------------------

Future<void> _runExtraction(
  BuildContext context,
  WidgetRef ref,
) async {
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

/// A white/surface rounded panel with a subtle border (and light shadow in
/// light mode), used for the major content sections.
Widget _panel(
  BuildContext context, {
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(20),
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
    ),
    child: child,
  );
}
