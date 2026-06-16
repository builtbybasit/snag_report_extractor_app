/// An outline (bookmark) item, equivalent to PyMuPDF's `Outline` class.
class OutlineItem {
  /// Title of the bookmark.
  final String title;

  /// Target page number (0-based).
  final int page;

  /// URI destination (if external link).
  final String? uri;

  /// Nesting level.
  final int level;

  /// Whether this item is open (expanded).
  final bool isOpen;

  /// Child items.
  final List<OutlineItem> children;

  /// Destination y coordinate.
  final double? destY;

  const OutlineItem({
    required this.title,
    required this.page,
    this.uri,
    this.level = 0,
    this.isOpen = true,
    this.children = const [],
    this.destY,
  });

  /// Down (first child).
  OutlineItem? get down => children.isNotEmpty ? children.first : null;

  /// Next sibling — accessed from parent's children list.

  @override
  String toString() => 'OutlineItem("$title" -> page $page)';
}
