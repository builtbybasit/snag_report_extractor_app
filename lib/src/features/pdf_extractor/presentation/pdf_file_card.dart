import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_state.dart';

class PdfFileCard extends StatelessWidget {
  final DropItem file;
  final PdfFileProgress? progress;
  final VoidCallback? onDelete;

  /// Pre-scan image count shown while the file is queued:
  /// `null` = still counting, `-1` = count failed, `>= 0` = image count.
  final int? imageCount;

  /// Pre-scan page count (same value semantics as [imageCount]).
  final int? pageCount;

  /// When the file was added; drives the "Added … ago" subtitle.
  final DateTime? addedAt;

  /// File size in bytes, appended to the subtitle when available.
  final int? sizeBytes;

  /// Index of this card in the reorderable queue. When non-null, a grab handle
  /// is rendered flush on the card's left border for drag-to-reorder. Null
  /// renders no handle (e.g. when the card is used outside a reorderable list).
  final int? reorderIndex;

  const PdfFileCard({
    super.key,
    required this.file,
    this.progress,
    this.imageCount,
    this.pageCount,
    this.addedAt,
    this.sizeBytes,
    this.onDelete,
    this.reorderIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final p = progress;

    final done = p?.done == true && p?.error == null;
    final failed = p?.error != null;
    final paused = p?.paused == true && p?.done != true && p?.error == null;
    final processing = p != null && !p.done && p.error == null && !paused;

    final progressRatio = (p != null && p.error == null && p.totalPages > 0)
        ? (p.currentPage / p.totalPages).clamp(0.0, 1.0)
        : (done ? 1.0 : 0.0);
    final percent = (progressRatio * 100).round();

    // Pages/images strings — fall back to the pre-scan counts before processing.
    final totalPages = (p != null && p.totalPages > 0)
        ? p.totalPages
        : (pageCount != null && pageCount! >= 0 ? pageCount! : null);
    final totalImages = (p != null && p.totalImages > 0)
        ? p.totalImages
        : (imageCount != null && imageCount! >= 0 ? imageCount! : null);
    final pagesValue = totalPages != null
        ? "${p?.currentPage ?? 0} / $totalPages"
        : (pageCount == null ? "Counting…" : "—");
    final imagesValue = totalImages != null
        ? "${p?.currentImage ?? 0} / $totalImages"
        : (imageCount == null ? "Counting…" : "—");

    const handleWidth = 28.0;
    final hasHandle = reorderIndex != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      // Stack rather than a stretched Row: the non-positioned body defines the
      // card's height and the handle is stretched to it via top/bottom: 0, which
      // always yields bounded constraints — a stretched Row root can hit
      // unbounded-height constraints inside the reorder drag overlay and hang.
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hasHandle ? handleWidth + 12 : 16, 16,
                16, 16),
            child: _cardBody(context, done, failed, processing, paused,
                progressRatio, percent, pagesValue, imagesValue),
          ),
          if (hasHandle)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: handleWidth,
              child: _dragHandle(context, isDark),
            ),
        ],
      ),
    );
  }

  /// A full-height grab strip on the card's left border: a dotted grip painted
  /// down the edge, wrapped in a [ReorderableDragStartListener] so dragging it
  /// reorders the queue.
  Widget _dragHandle(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return ReorderableDragStartListener(
      index: reorderIndex!,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : const Color(0xFFF9FAFB),
            // Round the outer-left corners to match the card so the strip color
            // fills the card's left border radius instead of leaving a notch.
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              bottomLeft: Radius.circular(14),
            ),
            border: Border(
              right: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: CustomPaint(
            painter: DottedGripPainter(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Widget _cardBody(
    BuildContext context,
    bool done,
    bool failed,
    bool processing,
    bool paused,
    double progressRatio,
    int percent,
    String pagesValue,
    String imagesValue,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final p = progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Header: thumbnail + name + timestamp + delete
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Colors.red.shade400,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                onPressed: onDelete,
                tooltip: "Remove file",
                style: IconButton.styleFrom(
                  side: BorderSide(color: theme.dividerColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Stat boxes
          Row(
            children: [
              Expanded(
                child: _statusBox(context, done, failed, processing, paused),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBox(
                  context,
                  Colors.blue,
                  Icons.description_outlined,
                  "Pages",
                  pagesValue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBox(
                  context,
                  Colors.purple,
                  Icons.image_outlined,
                  "Images",
                  imagesValue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar + percent
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: processing && (p?.totalPages ?? 0) == 0
                        ? null
                        : progressRatio,
                    minHeight: 8,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey.shade200,
                    color: failed
                        ? Colors.red.shade400
                        : (done ? Colors.green : theme.colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "$percent%",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      );
  }

  String _subtitle() {
    final added = _addedAgo();
    final size = sizeBytes == null ? null : _formatSize(sizeBytes!);
    if (added == null) return size ?? "Ready to extract";
    return size == null ? added : "$added • $size";
  }

  String? _addedAgo() {
    if (addedAt == null) return null;
    final diff = DateTime.now().difference(addedAt!);
    if (diff.inSeconds < 60) return "Added a few seconds ago";
    if (diff.inMinutes < 60) return "Added ${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "Added ${diff.inHours}h ago";
    return "Added ${diff.inDays}d ago";
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    if (bytes >= 1024) return "${(bytes / 1024).round()} KB";
    return "$bytes B";
  }

  /// First box reflects overall status (queue / processing / paused / complete /
  /// failed).
  Widget _statusBox(
    BuildContext context,
    bool done,
    bool failed,
    bool processing,
    bool paused,
  ) {
    if (failed) {
      return _statBox(context, Colors.red, Icons.error_outline, "Failed", null);
    }
    if (done) {
      return _statBox(
        context,
        Colors.green,
        Icons.check_circle_outline,
        "Complete",
        null,
      );
    }
    if (paused) {
      return _statBox(
        context,
        Colors.orange,
        Icons.pause_circle_outline,
        "Paused",
        null,
      );
    }
    if (processing) {
      return _statBox(
        context,
        Colors.blue,
        Icons.autorenew,
        "Processing",
        null,
      );
    }
    return _statBox(
      context,
      Colors.grey,
      Icons.schedule,
      "In Queue",
      null,
    );
  }

  Widget _statBox(
    BuildContext context,
    MaterialColor base,
    IconData icon,
    String title,
    String? value,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? base.withValues(alpha: 0.13) : base.shade50;
    final border = isDark ? base.withValues(alpha: 0.30) : base.shade100;
    final fg = isDark ? base.shade200 : base.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the two-column dotted "grip" used on each card's reorder handle.
/// The dot column is centred vertically within the available height.
class DottedGripPainter extends CustomPainter {
  final Color color;

  const DottedGripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // A 2-column × 6-row grip, centred in the strip — the universal "grab to
    // drag" affordance, rather than a full-height run of dots.
    const dotRadius = 1.8;
    const colGap = 7.0;
    const rowGap = 7.0;
    const rows = 5;

    final cx = size.width / 2;
    final col1X = cx - colGap / 2;
    final col2X = cx + colGap / 2;
    final startY = (size.height - (rows - 1) * rowGap) / 2;

    for (var r = 0; r < rows; r++) {
      final y = startY + r * rowGap;
      canvas.drawCircle(Offset(col1X, y), dotRadius, paint);
      canvas.drawCircle(Offset(col2X, y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DottedGripPainter oldDelegate) =>
      oldDelegate.color != color;
}
