import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_controller.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_file_card.dart';

/// NUL separator for the queue-keys fingerprint: it can't appear in a
/// filesystem path on any OS, so joining/splitting the ordered keys with it is
/// lossless even for paths containing spaces.
final String _queueKeySeparator = String.fromCharCode(0);

/// The queue rendered as a reorderable list. Each row carries a grip handle on
/// its left edge (grab-to-drag); dragging a file changes its processing order,
/// and dragging the file that's currently extracting below another pending
/// file pauses it (it resumes when it returns to the top).
class QueueList extends ConsumerWidget {
  const QueueList({super.key});

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
    final pathsKey = ref.watch(
      pdfExtractorScreenControllerProvider
          .select((s) => s.items.keys.join(_queueKeySeparator)),
    );
    final paths = pathsKey.isEmpty
        ? const <String>[]
        : pathsKey.split(_queueKeySeparator);

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
