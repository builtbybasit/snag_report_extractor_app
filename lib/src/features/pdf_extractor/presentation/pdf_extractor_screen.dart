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
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_state.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_file_card.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/queue_count_badge.dart';
import 'package:snag_report_extractor_app/src/routing/app_routing.dart';
import 'package:snag_report_extractor_app/src/theme_mode_provider.dart';

class PdfExtractorScreen extends ConsumerWidget {
  const PdfExtractorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      pdfExtractorScreenControllerProvider.notifier,
    );
    final state = ref.watch(pdfExtractorScreenControllerProvider);
    final directoryManager = ref.watch(directoryManagerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                _outputDirectorySection(context, ref, directoryManager),
                gapH24,
                _dropZone(context, controller, state, isDark),
                gapH24,
                if (state.files.isNotEmpty) ...[
                  _queueHeader(context, ref, state),
                  gapH12,
                  _queueList(context, controller, state),
                  gapH16,
                ],
                _bottomBar(context, ref, controller, state, directoryManager),
                gapH8,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Queue list (reorderable)
  // ---------------------------------------------------------------------------

  /// The queue rendered as a reorderable list. Each row carries a grip handle on
  /// its left edge (grab-to-drag); dragging a file changes its processing order,
  /// and dragging the file that's currently extracting below another pending
  /// file pauses it (it resumes when it returns to the top).
  Widget _queueList(
    BuildContext context,
    PdfExtractorScreenController controller,
    PdfExtractorState state,
  ) {
    final items = state.items.values.toList();

    return ReorderableListView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      // The default proxy wraps the dragged item in an opaque (white) Material;
      // use a transparent one so the card keeps its own rounded background while
      // being dragged.
      proxyDecorator: (child, index, animation) =>
          Material(type: MaterialType.transparency, child: child),
      // ignore: deprecated_member_use
      onReorder: controller.reorderQueue,
      itemBuilder: (context, i) {
        final item = items[i];
        // The grab handle lives on the card's left border (see PdfFileCard);
        // reorderIndex wires it to this list's drag listener.
        return PdfFileCard(
          key: ValueKey(item.file.path),
          reorderIndex: i,
          file: item.file,
          progress: item.progress,
          imageCount: item.imageCount,
          pageCount: item.pageCount,
          addedAt: item.addedAt,
          sizeBytes: item.sizeBytes,
          onDelete: () => controller.removeFromQueue(item.file),
        );
      },
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

  // ---------------------------------------------------------------------------
  // Output directory
  // ---------------------------------------------------------------------------

  Widget _outputDirectorySection(
    BuildContext context,
    WidgetRef ref,
    String? directory,
  ) {
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

  // ---------------------------------------------------------------------------
  // Drop zone
  // ---------------------------------------------------------------------------

  Widget _dropZone(
    BuildContext context,
    PdfExtractorScreenController controller,
    PdfExtractorState state,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final borderColor = state.isDragging ? accent : theme.dividerColor;

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
          strokeWidth: state.isDragging ? 2 : 1.5,
          radius: 16,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: state.isDragging
                  ? accent.withValues(alpha: 0.05)
                  : Colors.transparent,
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

  // ---------------------------------------------------------------------------
  // Queue header
  // ---------------------------------------------------------------------------

  Widget _queueHeader(
      BuildContext context, WidgetRef ref, PdfExtractorState state) {
    final theme = Theme.of(context);
    final hasCompleted = state.completedCount > 0;

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
              QueueCountBadge(count: state.files.length),
            ],
          ),
        ),
        gapW8,
        OutlinedButton.icon(
          onPressed: (state.isProcessing || !hasCompleted)
              ? null
              : () =>
                  ref.read(pdfExtractorScreenControllerProvider.notifier)
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
          onPressed: state.isProcessing
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

  // ---------------------------------------------------------------------------
  // Bottom status + Extract bar
  // ---------------------------------------------------------------------------

  Widget _bottomBar(
    BuildContext context,
    WidgetRef ref,
    PdfExtractorScreenController controller,
    PdfExtractorState state,
    String? directory,
  ) {
    // One full-width white panel holding the status on the left and the
    // Extract button on the right.
    return _panel(
      context,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _statusContent(context, state)),
          gapW16,
          _extractButton(context, ref, controller, state, directory),
        ],
      ),
    );
  }

  Widget _statusContent(BuildContext context, PdfExtractorState state) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    IconData icon;
    String title;
    String subtitle;
    Color color = accent;

    if (state.isProcessing) {
      icon = Icons.autorenew_rounded;
      title = "Extracting…";
      subtitle = "${state.processedFiles} of ${state.files.length} processed";
    } else if (state.errors.isNotEmpty) {
      icon = Icons.error_outline_rounded;
      title = "Completed with errors";
      subtitle = "${state.errors.length} file(s) failed";
      color = Colors.red.shade400;
    } else if (state.completedCount > 0) {
      icon = Icons.task_alt_rounded;
      title = "Extraction complete!";
      subtitle =
          "${state.completedCount} file(s) processed successfully";
      color = Colors.green;
    } else if (state.files.isNotEmpty) {
      icon = Icons.playlist_add_check_rounded;
      title = "Ready to extract";
      subtitle = "${state.files.length} file(s) in queue";
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

  Widget _extractButton(
    BuildContext context,
    WidgetRef ref,
    PdfExtractorScreenController controller,
    PdfExtractorState state,
    String? directory,
  ) {
    final disabled = state.isProcessing || state.files.isEmpty;

    return SizedBox(
      width: 230,
      // Fixed height so the button doesn't shrink when the subtitle is hidden
      // during extraction.
      height: 52,
      child: ElevatedButton(
        onPressed: disabled
            ? null
            : () => _runExtraction(context, ref, controller, directory),
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
                    if (state.isProcessing)
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
                      state.isProcessing ? "Extracting…" : "Extract",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                // Subtitle only when idle — no file count while extracting.
                if (!state.isProcessing) ...[
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

  // ---------------------------------------------------------------------------
  // Actions / helpers
  // ---------------------------------------------------------------------------

  Future<void> _runExtraction(
    BuildContext context,
    WidgetRef ref,
    PdfExtractorScreenController controller,
    String? directory,
  ) async {
    if (directory == null || directory.isEmpty) {
      AlertInfo.show(
        context: context,
        typeInfo: TypeInfo.error,
        position: MessagePosition.bottom,
        text: "Please select an output directory.",
      );
      return;
    }

    await controller.processPdfFiles();
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
}
