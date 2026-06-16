import '../geometry/rect.dart';

/// Full text page dictionary, equivalent to PyMuPDF's `page.get_text("dict")`.
class TextDict {
  final double width;
  final double height;
  final List<TextDictBlock> blocks;

  const TextDict({
    required this.width,
    required this.height,
    required this.blocks,
  });

  Map<String, dynamic> toMap() => {
        'width': width,
        'height': height,
        'blocks': blocks.map((b) => b.toMap()).toList(),
      };
}

/// A block within a TextDict.
class TextDictBlock {
  final int number;
  final int type; // 0=text, 1=image
  final Rect bbox;
  final List<TextDictLine>? lines; // for text blocks
  // For image blocks:
  final int? imageWidth;
  final int? imageHeight;
  final String? imageColorspace;
  final int? imageBpc;
  final int? imageXref;
  final int? imageSize;

  const TextDictBlock({
    required this.number,
    required this.type,
    required this.bbox,
    this.lines,
    this.imageWidth,
    this.imageHeight,
    this.imageColorspace,
    this.imageBpc,
    this.imageXref,
    this.imageSize,
  });

  bool get isImage => type == 1;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'number': number,
      'type': type,
      'bbox': bbox.toList(),
    };
    if (type == 0 && lines != null) {
      map['lines'] = lines!.map((l) => l.toMap()).toList();
    }
    if (type == 1) {
      map['width'] = imageWidth;
      map['height'] = imageHeight;
      map['colorspace'] = imageColorspace;
      map['bpc'] = imageBpc;
      map['xref'] = imageXref;
      map['size'] = imageSize;
    }
    return map;
  }
}

/// A line within a TextDictBlock.
class TextDictLine {
  final Rect bbox;
  final Point2D wmode; // 0=horizontal, 1=vertical
  final Point2D dir;
  final List<TextDictSpan> spans;

  const TextDictLine({
    required this.bbox,
    required this.wmode,
    required this.dir,
    required this.spans,
  });

  Map<String, dynamic> toMap() => {
        'bbox': bbox.toList(),
        'wmode': wmode.toList(),
        'dir': dir.toList(),
        'spans': spans.map((s) => s.toMap()).toList(),
      };
}

/// Writing mode / direction helper.
class Point2D {
  final double x, y;
  const Point2D(this.x, this.y);
  List<double> toList() => [x, y];
}

/// A span within a TextDictLine.
class TextDictSpan {
  final Rect bbox;
  final double size;
  final int flags; // bold=1, italic=2, serifed=4, monospaced=8, etc.
  final String font;
  final int color;
  final double ascender;
  final double descender;
  final String text;
  final List<TextDictChar>? chars;
  final Rect? origin;

  const TextDictSpan({
    required this.bbox,
    required this.size,
    required this.flags,
    required this.font,
    required this.color,
    this.ascender = 0,
    this.descender = 0,
    required this.text,
    this.chars,
    this.origin,
  });

  bool get isBold => (flags & 1) != 0;
  bool get isItalic => (flags & 2) != 0;
  bool get isSerifed => (flags & 4) != 0;
  bool get isMonospaced => (flags & 8) != 0;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'bbox': bbox.toList(),
      'size': size,
      'flags': flags,
      'font': font,
      'color': color,
      'ascender': ascender,
      'descender': descender,
      'text': text,
    };
    if (chars != null) {
      map['chars'] = chars!.map((c) => c.toMap()).toList();
    }
    if (origin != null) {
      map['origin'] = origin!.toList();
    }
    return map;
  }
}

/// A character within a TextDictSpan (for rawdict mode).
class TextDictChar {
  final Rect bbox;
  final int c; // unicode code point
  final Rect origin;

  const TextDictChar({
    required this.bbox,
    required this.c,
    required this.origin,
  });

  String get char => String.fromCharCode(c);

  Map<String, dynamic> toMap() => {
        'bbox': bbox.toList(),
        'c': c,
        'origin': origin.toList(),
      };
}
