import '../geometry/rect.dart';
import '../geometry/point.dart';

/// Annotation types matching PyMuPDF constants.
enum AnnotationType {
  text,
  link,
  freeText,
  line,
  square,
  circle,
  polygon,
  polyLine,
  highlight,
  underline,
  squiggly,
  strikeOut,
  stamp,
  caret,
  ink,
  popup,
  fileAttachment,
  sound,
  movie,
  widget,
  screen,
  printerMark,
  trapNet,
  watermark,
  threeD,
  redact,
  unknown,
}

/// A PDF annotation, equivalent to PyMuPDF's `Annot` class.
class PdfAnnotation {
  /// Annotation type.
  final AnnotationType type;

  /// Bounding rectangle.
  final Rect rect;

  /// Cross-reference number.
  final int xref;

  /// Annotation content / text.
  final String? content;

  /// Title (author) of the annotation.
  final String? title;

  /// Subject.
  final String? subject;

  /// Creation date.
  final String? creationDate;

  /// Modification date.
  final String? modDate;

  /// Color (as [r, g, b] floats 0..1).
  final List<double>? color;

  /// Fill color for markup annotations.
  final List<double>? fillColor;

  /// Border width.
  final double? borderWidth;

  /// Opacity (0..1).
  final double? opacity;

  /// Annotation flags.
  final int flags;

  /// Icon name (for text, file attachment annotations).
  final String? icon;

  /// Line ending styles.
  final String? lineEnding;

  /// Vertices / points (for ink, polygon, polyline).
  final List<Point>? vertices;

  /// Quadrilateral points (for highlight, underline, etc.).
  final List<List<double>>? quadPoints;

  /// Popup annotation xref.
  final int? popupXref;

  const PdfAnnotation({
    required this.type,
    required this.rect,
    required this.xref,
    this.content,
    this.title,
    this.subject,
    this.creationDate,
    this.modDate,
    this.color,
    this.fillColor,
    this.borderWidth,
    this.opacity,
    this.flags = 0,
    this.icon,
    this.lineEnding,
    this.vertices,
    this.quadPoints,
    this.popupXref,
  });

  /// Type name string.
  String get typeName => type.name;

  /// Whether annotation is visible.
  bool get isVisible => (flags & 0x02) == 0; // hidden flag

  /// Whether annotation is printable.
  bool get isPrintable => (flags & 0x04) != 0;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': typeName,
      'rect': rect.toList(),
      'xref': xref,
    };
    if (content != null) map['content'] = content;
    if (title != null) map['title'] = title;
    if (color != null) map['color'] = color;
    if (opacity != null) map['opacity'] = opacity;
    return map;
  }

  @override
  String toString() => 'PdfAnnotation($typeName at $rect)';
}

/// Map from PDF annotation subtype names to our enum.
AnnotationType annotationTypeFromName(String name) {
  switch (name) {
    case '/Text':
      return AnnotationType.text;
    case '/Link':
      return AnnotationType.link;
    case '/FreeText':
      return AnnotationType.freeText;
    case '/Line':
      return AnnotationType.line;
    case '/Square':
      return AnnotationType.square;
    case '/Circle':
      return AnnotationType.circle;
    case '/Polygon':
      return AnnotationType.polygon;
    case '/PolyLine':
      return AnnotationType.polyLine;
    case '/Highlight':
      return AnnotationType.highlight;
    case '/Underline':
      return AnnotationType.underline;
    case '/Squiggly':
      return AnnotationType.squiggly;
    case '/StrikeOut':
      return AnnotationType.strikeOut;
    case '/Stamp':
      return AnnotationType.stamp;
    case '/Caret':
      return AnnotationType.caret;
    case '/Ink':
      return AnnotationType.ink;
    case '/Popup':
      return AnnotationType.popup;
    case '/FileAttachment':
      return AnnotationType.fileAttachment;
    case '/Sound':
      return AnnotationType.sound;
    case '/Movie':
      return AnnotationType.movie;
    case '/Widget':
      return AnnotationType.widget;
    case '/Screen':
      return AnnotationType.screen;
    case '/PrinterMark':
      return AnnotationType.printerMark;
    case '/TrapNet':
      return AnnotationType.trapNet;
    case '/Watermark':
      return AnnotationType.watermark;
    case '/3D':
      return AnnotationType.threeD;
    case '/Redact':
      return AnnotationType.redact;
    default:
      return AnnotationType.unknown;
  }
}
