import 'dart:math' as math;

import 'geometry/point.dart';
import 'geometry/rect.dart';
import 'geometry/quad.dart';

/// Drawing helper class, equivalent to PyMuPDF's `Shape`.
///
/// Provides methods to draw lines, rectangles, circles, curves,
/// and other shapes on a PDF page, then commit them to the
/// content stream.
///
/// Usage:
/// ```dart
/// final shape = Shape(page);
/// shape.drawLine(Point(50, 50), Point(200, 50));
/// shape.drawRect(Rect(100, 100, 300, 200));
/// shape.finish(color: [0, 0, 0], width: 1);
/// shape.commit();
/// ```
class Shape {
  /// The content buffer.
  final StringBuffer _content = StringBuffer();

  /// Current path buffer (before finish()).
  final StringBuffer _path = StringBuffer();

  /// Width of the page.
  final double pageWidth;

  /// Height of the page.
  final double pageHeight;

  /// Whether there are uncommitted drawings.
  bool get hasDrawings => _content.isNotEmpty;

  /// Whether the current path has elements.
  bool get hasPath => _path.isNotEmpty;

  /// Number of drawing operations in the current path.
  int _pathOps = 0;

  /// Last point in the current path.
  Point? _lastPoint;

  /// Sum of all drawing commands.
  int totalContents = 0;

  /// Create a new Shape for a page.
  Shape({required this.pageWidth, required this.pageHeight});

  // ---------- Path Drawing Methods ----------

  /// Draw a line from [p1] to [p2].
  ///
  /// Equivalent to PyMuPDF's `shape.draw_line()`.
  Point drawLine(Point p1, Point p2) {
    _path.write('${_f(p1.x)} ${_f(p1.y)} m ');
    _path.write('${_f(p2.x)} ${_f(p2.y)} l ');
    _pathOps++;
    _lastPoint = p2;
    return p2;
  }

  /// Draw a sequence of connected lines.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_polyline()`.
  Point drawPolyline(List<Point> points) {
    if (points.length < 2) {
      throw ArgumentError('Need at least 2 points for polyline');
    }
    _path.write('${_f(points.first.x)} ${_f(points.first.y)} m ');
    for (int i = 1; i < points.length; i++) {
      _path.write('${_f(points[i].x)} ${_f(points[i].y)} l ');
    }
    _pathOps++;
    _lastPoint = points.last;
    return points.last;
  }

  /// Draw a rectangle.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_rect()`.
  Point drawRect(Rect rect) {
    _path.write(
      '${_f(rect.x0)} ${_f(rect.y0)} '
      '${_f(rect.width)} ${_f(rect.height)} re ',
    );
    _pathOps++;
    _lastPoint = Point(rect.x0, rect.y0);
    return _lastPoint!;
  }

  /// Draw a circle with given center and radius.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_circle()`.
  Point drawCircle(Point center, double radius) {
    return drawOval(
      Rect(
        center.x - radius,
        center.y - radius,
        center.x + radius,
        center.y + radius,
      ),
    );
  }

  /// Draw an oval inscribed in a rectangle.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_oval()`.
  Point drawOval(Rect rect) {
    // Approximate ellipse with 4 cubic Bezier curves
    final cx = (rect.x0 + rect.x1) / 2;
    final cy = (rect.y0 + rect.y1) / 2;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    // kappa for circle approximation
    const k = 0.5522847498;
    final kx = rx * k;
    final ky = ry * k;

    // Start at right-middle
    _path.write('${_f(cx + rx)} ${_f(cy)} m ');
    // Top-right quarter
    _path.write(
      '${_f(cx + rx)} ${_f(cy - ky)} '
      '${_f(cx + kx)} ${_f(cy - ry)} '
      '${_f(cx)} ${_f(cy - ry)} c ',
    );
    // Top-left quarter
    _path.write(
      '${_f(cx - kx)} ${_f(cy - ry)} '
      '${_f(cx - rx)} ${_f(cy - ky)} '
      '${_f(cx - rx)} ${_f(cy)} c ',
    );
    // Bottom-left quarter
    _path.write(
      '${_f(cx - rx)} ${_f(cy + ky)} '
      '${_f(cx - kx)} ${_f(cy + ry)} '
      '${_f(cx)} ${_f(cy + ry)} c ',
    );
    // Bottom-right quarter (close)
    _path.write(
      '${_f(cx + kx)} ${_f(cy + ry)} '
      '${_f(cx + rx)} ${_f(cy + ky)} '
      '${_f(cx + rx)} ${_f(cy)} c ',
    );

    _pathOps++;
    _lastPoint = Point(cx + rx, cy);
    return _lastPoint!;
  }

  /// Draw a Bezier curve.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_bezier()`.
  Point drawBezier(Point p1, Point p2, Point p3, Point p4) {
    _path.write('${_f(p1.x)} ${_f(p1.y)} m ');
    _path.write('${_f(p2.x)} ${_f(p2.y)} ');
    _path.write('${_f(p3.x)} ${_f(p3.y)} ');
    _path.write('${_f(p4.x)} ${_f(p4.y)} c ');
    _pathOps++;
    _lastPoint = p4;
    return p4;
  }

  /// Draw a quadratic Bezier curve.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_quad()`.
  Point drawQuad(Quad quad) {
    _path.write('${_f(quad.ul.x)} ${_f(quad.ul.y)} m ');
    _path.write('${_f(quad.ur.x)} ${_f(quad.ur.y)} l ');
    _path.write('${_f(quad.lr.x)} ${_f(quad.lr.y)} l ');
    _path.write('${_f(quad.ll.x)} ${_f(quad.ll.y)} l ');
    _path.write('h '); // close subpath
    _pathOps++;
    _lastPoint = quad.ul;
    return quad.ul;
  }

  /// Draw a sector (pie slice).
  ///
  /// Equivalent to PyMuPDF's `shape.draw_sector()`.
  Point drawSector(
    Point center,
    Point point,
    double angle, {
    bool fullSector = true,
  }) {
    final radius = center.distanceTo(point);
    final startAngle = math.atan2(point.y - center.y, point.x - center.x);
    final endAngle = startAngle + angle * math.pi / 180;

    if (fullSector) {
      _path.write('${_f(center.x)} ${_f(center.y)} m ');
      _path.write('${_f(point.x)} ${_f(point.y)} l ');
    } else {
      _path.write('${_f(point.x)} ${_f(point.y)} m ');
    }

    // Approximate arc with Bezier curves
    _drawArc(center, radius, startAngle, endAngle);

    if (fullSector) {
      _path.write('h '); // close path back to center
    }

    _pathOps++;
    final endPoint = Point(
      center.x + radius * math.cos(endAngle),
      center.y + radius * math.sin(endAngle),
    );
    _lastPoint = endPoint;
    return endPoint;
  }

  void _drawArc(Point center, double radius, double start, double end) {
    // Split arc into segments of max 90 degrees
    final segments = ((end - start).abs() / (math.pi / 2)).ceil().clamp(1, 16);
    final segAngle = (end - start) / segments;

    for (int i = 0; i < segments; i++) {
      final a1 = start + i * segAngle;
      final a2 = a1 + segAngle;
      _drawArcSegment(center, radius, a1, a2);
    }
  }

  void _drawArcSegment(Point center, double radius, double a1, double a2) {
    final alpha = (a2 - a1) / 2;
    final cosAlpha = math.cos(alpha);
    final f = 4.0 / 3.0 * (1.0 - cosAlpha) / math.sin(alpha);

    final x1 = math.cos(a1);
    final y1 = math.sin(a1);
    final x2 = math.cos(a2);
    final y2 = math.sin(a2);

    final cp1x = center.x + radius * (x1 - f * y1);
    final cp1y = center.y + radius * (y1 + f * x1);
    final cp2x = center.x + radius * (x2 + f * y2);
    final cp2y = center.y + radius * (y2 - f * x2);
    final ex = center.x + radius * x2;
    final ey = center.y + radius * y2;

    _path.write(
      '${_f(cp1x)} ${_f(cp1y)} '
      '${_f(cp2x)} ${_f(cp2y)} '
      '${_f(ex)} ${_f(ey)} c ',
    );
  }

  /// Draw a squiggly (wavy) line.
  ///
  /// Equivalent to PyMuPDF's `shape.draw_squiggle()`.
  Point drawSquiggle(Point p1, Point p2, {double breadth = 2}) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return p1;

    final unitX = dx / length;
    final unitY = dy / length;
    final perpX = -unitY;
    final perpY = unitX;

    final wavelength = breadth * 4;
    final segments = (length / wavelength).ceil();
    final segLen = length / segments;

    _path.write('${_f(p1.x)} ${_f(p1.y)} m ');

    for (int i = 0; i < segments; i++) {
      final base = i * segLen;
      final cp1x = p1.x + unitX * (base + segLen * 0.25) + perpX * breadth;
      final cp1y = p1.y + unitY * (base + segLen * 0.25) + perpY * breadth;
      final cp2x = p1.x + unitX * (base + segLen * 0.75) - perpX * breadth;
      final cp2y = p1.y + unitY * (base + segLen * 0.75) - perpY * breadth;
      final ex = p1.x + unitX * (base + segLen);
      final ey = p1.y + unitY * (base + segLen);

      _path.write(
        '${_f(cp1x)} ${_f(cp1y)} '
        '${_f(cp2x)} ${_f(cp2y)} '
        '${_f(ex)} ${_f(ey)} c ',
      );
    }

    _pathOps++;
    _lastPoint = p2;
    return p2;
  }

  /// Draw a zigzag line.
  Point drawZigzag(Point p1, Point p2, {double breadth = 2}) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return p1;

    final unitX = dx / length;
    final unitY = dy / length;
    final perpX = -unitY;
    final perpY = unitX;

    final segments = (length / (breadth * 2)).ceil();
    final segLen = length / segments;

    _path.write('${_f(p1.x)} ${_f(p1.y)} m ');

    for (int i = 0; i < segments; i++) {
      final mid = i * segLen + segLen / 2;
      final end = (i + 1) * segLen;
      final sign = (i % 2 == 0) ? 1.0 : -1.0;

      _path.write(
        '${_f(p1.x + unitX * mid + perpX * breadth * sign)} '
        '${_f(p1.y + unitY * mid + perpY * breadth * sign)} l ',
      );
      _path.write(
        '${_f(p1.x + unitX * end)} '
        '${_f(p1.y + unitY * end)} l ',
      );
    }

    _pathOps++;
    _lastPoint = p2;
    return p2;
  }

  // ---------- Finishing ----------

  /// Finish the current path with stroke/fill properties.
  ///
  /// Equivalent to PyMuPDF's `shape.finish()`.
  void finish({
    List<double>? color,
    List<double>? fill,
    double width = 1,
    List<double>? dashes,
    int lineCap = 0,
    int lineJoin = 0,
    bool closePath = false,
    bool even_odd = false,
    double opacity = 1,
    double fillOpacity = 1,
    String? morph,
  }) {
    if (_pathOps == 0) return;

    final cmd = StringBuffer();
    cmd.writeln('q');

    // Line cap
    if (lineCap != 0) cmd.writeln('$lineCap J');

    // Line join
    if (lineJoin != 0) cmd.writeln('$lineJoin j');

    // Dash pattern
    if (dashes != null && dashes.isNotEmpty) {
      cmd.write('[');
      for (int i = 0; i < dashes.length; i++) {
        if (i > 0) cmd.write(' ');
        cmd.write(_f(dashes[i]));
      }
      cmd.writeln('] 0 d');
    }

    // Line width
    cmd.writeln('${_f(width)} w');

    // Stroke color
    if (color != null) {
      if (color.length == 1) {
        cmd.writeln('${_f(color[0])} G');
      } else if (color.length == 3) {
        cmd.writeln('${_f(color[0])} ${_f(color[1])} ${_f(color[2])} RG');
      } else if (color.length == 4) {
        cmd.writeln(
          '${_f(color[0])} ${_f(color[1])} ${_f(color[2])} ${_f(color[3])} K',
        );
      }
    }

    // Fill color
    if (fill != null) {
      if (fill.length == 1) {
        cmd.writeln('${_f(fill[0])} g');
      } else if (fill.length == 3) {
        cmd.writeln('${_f(fill[0])} ${_f(fill[1])} ${_f(fill[2])} rg');
      } else if (fill.length == 4) {
        cmd.writeln(
          '${_f(fill[0])} ${_f(fill[1])} ${_f(fill[2])} ${_f(fill[3])} k',
        );
      }
    }

    // Path
    cmd.write(_path.toString());
    if (closePath) cmd.write('h ');

    // Painting operator
    if (fill != null && color != null) {
      cmd.writeln(even_odd ? 'B*' : 'B'); // fill and stroke
    } else if (fill != null) {
      cmd.writeln(even_odd ? 'f*' : 'f'); // fill only
    } else if (color != null) {
      cmd.writeln('S'); // stroke only
    } else {
      cmd.writeln('n'); // no-op (path only)
    }

    cmd.writeln('Q');

    _content.write(cmd.toString());
    _path.clear();
    _pathOps = 0;
    totalContents++;
  }

  /// Commit all drawing commands to the page content stream.
  ///
  /// Equivalent to PyMuPDF's `shape.commit()`.
  /// Returns the generated content stream string.
  String commit({bool overlay = true}) {
    final result = _content.toString();
    _content.clear();
    totalContents = 0;
    return result;
  }

  // ---------- Text Insertion ----------

  /// Insert text at a point.
  ///
  /// Equivalent to PyMuPDF's `shape.insert_text()`.
  int insertText(
    Point point,
    String text, {
    double fontSize = 11,
    String fontName = 'Helvetica',
    List<double>? color,
    double rotate = 0,
  }) {
    final c = color ?? [0, 0, 0];
    final colorStr =
        c.length == 3 ? '${_f(c[0])} ${_f(c[1])} ${_f(c[2])} rg' : '0 0 0 rg';

    final lines = text.split('\n');
    final leading = fontSize * 1.2;

    _content.writeln('q');
    _content.writeln('BT');
    _content.writeln('/$fontName ${_f(fontSize)} Tf');
    _content.writeln(colorStr);
    _content.writeln('${_f(leading)} TL');
    _content.writeln('${_f(point.x)} ${_f(point.y)} Td');

    for (int i = 0; i < lines.length; i++) {
      final escaped = lines[i]
          .replaceAll(r'\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
      if (i == 0) {
        _content.writeln('($escaped) Tj');
      } else {
        _content.writeln("T* ($escaped) '");
      }
    }

    _content.writeln('ET');
    _content.writeln('Q');
    totalContents++;

    return lines.length;
  }

  /// Insert text into a rectangle.
  ///
  /// Equivalent to PyMuPDF's `shape.insert_textbox()`.
  double insertTextbox(
    Rect rect,
    String text, {
    double fontSize = 11,
    String fontName = 'Helvetica',
    List<double>? color,
    int align = 0,
  }) {
    return insertText(
      Point(rect.x0, rect.y1 - fontSize),
      text,
      fontSize: fontSize,
      fontName: fontName,
      color: color,
    ).toDouble();
  }

  // ---------- Utility ----------

  String _f(double v) {
    // Format number with reasonable precision
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '');
  }

  @override
  String toString() => 'Shape(ops: $totalContents, pathOps: $_pathOps)';
}
