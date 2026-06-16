import 'dart:math' as math;
import 'point.dart';
import 'irect.dart';

/// A rectangle defined by two corner points, equivalent to PyMuPDF's `fitz.Rect`.
///
/// Coordinates are (x0, y0) for top-left and (x1, y1) for bottom-right.
class Rect {
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  const Rect(this.x0, this.y0, this.x1, this.y1);

  /// Create from two Points.
  factory Rect.fromPoints(Point topLeft, Point bottomRight) =>
      Rect(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y);

  /// Create from a list [x0, y0, x1, y1].
  factory Rect.fromList(List<num> list) {
    assert(list.length >= 4);
    return Rect(
      list[0].toDouble(),
      list[1].toDouble(),
      list[2].toDouble(),
      list[3].toDouble(),
    );
  }

  /// An empty rectangle.
  static const Rect empty = Rect(0, 0, 0, 0);

  /// An infinite rectangle.
  static const Rect infinite = Rect(-1e30, -1e30, 1e30, 1e30);

  /// Width of the rectangle.
  double get width => (x1 - x0).abs();

  /// Height of the rectangle.
  double get height => (y1 - y0).abs();

  /// Area of the rectangle.
  double get area => width * height;

  /// Whether this rectangle is empty.
  bool get isEmpty => width <= 0 || height <= 0;

  /// Whether this rectangle is infinite.
  bool get isInfinite => x0 <= -1e29 && y0 <= -1e29 && x1 >= 1e29 && y1 >= 1e29;

  /// Top-left corner.
  Point get topLeft => Point(x0, y0);

  /// Top-right corner.
  Point get topRight => Point(x1, y0);

  /// Bottom-left corner.
  Point get bottomLeft => Point(x0, y1);

  /// Bottom-right corner.
  Point get bottomRight => Point(x1, y1);

  /// Center point.
  Point get center => Point((x0 + x1) / 2, (y0 + y1) / 2);

  /// Normalize: ensure x0 <= x1 and y0 <= y1.
  Rect get normalized => Rect(
        math.min(x0, x1),
        math.min(y0, y1),
        math.max(x0, x1),
        math.max(y0, y1),
      );

  /// Convert to integer rect.
  IRect get irect => IRect(x0.floor(), y0.floor(), x1.ceil(), y1.ceil());

  /// Check if a point is inside this rectangle.
  bool containsPoint(Point p) =>
      p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;

  /// Alias for containsPoint.
  bool contains(Point p) => containsPoint(p);

  /// Check if another rectangle is fully inside this rectangle.
  bool containsRect(Rect other) =>
      other.x0 >= x0 && other.y0 >= y0 && other.x1 <= x1 && other.y1 <= y1;

  /// Check if this rectangle overlaps with another.
  bool overlaps(Rect other) {
    if (isEmpty || other.isEmpty) return false;
    return x0 < other.x1 && x1 > other.x0 && y0 < other.y1 && y1 > other.y0;
  }

  /// Union of two rectangles (smallest rect containing both).
  Rect union(Rect other) {
    if (isEmpty) return other;
    if (other.isEmpty) return this;
    return Rect(
      math.min(x0, other.x0),
      math.min(y0, other.y0),
      math.max(x1, other.x1),
      math.max(y1, other.y1),
    );
  }

  /// Intersection of two rectangles.
  Rect intersect(Rect other) {
    final ix0 = math.max(x0, other.x0);
    final iy0 = math.max(y0, other.y0);
    final ix1 = math.min(x1, other.x1);
    final iy1 = math.min(y1, other.y1);
    if (ix0 >= ix1 || iy0 >= iy1) return Rect.empty;
    return Rect(ix0, iy0, ix1, iy1);
  }

  /// Include a point in the rectangle (expand to contain it).
  Rect includePoint(Point p) => Rect(
        math.min(x0, p.x),
        math.min(y0, p.y),
        math.max(x1, p.x),
        math.max(y1, p.y),
      );

  /// Transform this rectangle using a matrix [a, b, c, d, e, f].
  Rect transform(List<double> matrix) {
    final corners = [topLeft, topRight, bottomLeft, bottomRight];
    final transformed = corners.map((p) => p.transform(matrix)).toList();
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in transformed) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect(minX, minY, maxX, maxY);
  }

  /// Morph: apply a matrix about a given fixpoint.
  Rect morph(Point fixpoint, List<double> matrix) {
    final p = Point(x0 - fixpoint.x, y0 - fixpoint.y).transform(matrix);
    final q = Point(x1 - fixpoint.x, y1 - fixpoint.y).transform(matrix);
    return Rect(
      p.x + fixpoint.x,
      p.y + fixpoint.y,
      q.x + fixpoint.x,
      q.y + fixpoint.y,
    ).normalized;
  }

  Rect operator +(Rect other) => union(other);
  Rect operator &(Rect other) => intersect(other);
  Rect operator *(double factor) =>
      Rect(x0 * factor, y0 * factor, x1 * factor, y1 * factor);

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      x0 == other.x0 &&
      y0 == other.y0 &&
      x1 == other.x1 &&
      y1 == other.y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);

  List<double> toList() => [x0, y0, x1, y1];

  @override
  String toString() => 'Rect($x0, $y0, $x1, $y1)';
}
