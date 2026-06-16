/// A table of contents entry, equivalent to PyMuPDF's TOC list items.
///
/// Each entry is [level, title, pageNumber, destination].
class TocEntry {
  /// Indentation level (1 = top level).
  final int level;

  /// Bookmark title.
  final String title;

  /// Target page number (1-based).
  final int pageNumber;

  /// Optional destination details (y coordinate, zoom, etc.).
  final Map<String, dynamic>? destination;

  const TocEntry({
    required this.level,
    required this.title,
    required this.pageNumber,
    this.destination,
  });

  /// Convert to list format [level, title, page] as in PyMuPDF.
  List<dynamic> toList() => [level, title, pageNumber];

  @override
  String toString() =>
      'TocEntry(level: $level, title: "$title", page: $pageNumber)';
}
