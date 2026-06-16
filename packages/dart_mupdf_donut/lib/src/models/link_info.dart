import '../geometry/rect.dart';

/// Link information from a PDF page.
///
/// Equivalent to items returned by PyMuPDF's `page.get_links()`.
class LinkInfo {
  /// Link kind constants.
  static const int kindNone = 0;
  static const int kindGoto = 1;
  static const int kindUri = 2;
  static const int kindNamed = 3;
  static const int kindGotoR = 4;
  static const int kindLaunch = 5;

  /// Link type.
  final int kind;

  /// Bounding rectangle on the page.
  final Rect from;

  /// Target page number (for kindGoto).
  final int? page;

  /// Target URI (for kindUri).
  final String? uri;

  /// Target point on the destination page.
  final double? toX;
  final double? toY;

  /// File specification (for kindGotoR, kindLaunch).
  final String? fileSpec;

  /// Named action.
  final String? named;

  /// Zoom factor.
  final double? zoom;

  const LinkInfo({
    required this.kind,
    required this.from,
    this.page,
    this.uri,
    this.toX,
    this.toY,
    this.fileSpec,
    this.named,
    this.zoom,
  });

  /// Whether this is a URI link.
  bool get isUri => kind == kindUri;

  /// Whether this is an internal goto link.
  bool get isGoto => kind == kindGoto;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'kind': kind, 'from': from.toList()};
    if (page != null) map['page'] = page;
    if (uri != null) map['uri'] = uri;
    if (toX != null) map['to'] = [toX, toY];
    if (fileSpec != null) map['file'] = fileSpec;
    if (named != null) map['named'] = named;
    if (zoom != null) map['zoom'] = zoom;
    return map;
  }

  @override
  String toString() {
    if (isUri) return 'LinkInfo(uri: $uri, at: $from)';
    if (isGoto) return 'LinkInfo(goto page $page, at: $from)';
    return 'LinkInfo(kind: $kind, at: $from)';
  }
}
