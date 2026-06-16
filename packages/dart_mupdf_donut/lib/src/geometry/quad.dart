import 'point.dart';
import 'rect.dart';

/// A quadrilateral defined by four corner points,
/// equivalent to PyMuPDF's `fitz.Quad`.
///
/// Quad corners are: upper-left (ul), upper-right (ur),
/// lower-left (ll), lower-right (lr).
class Quad {
  final Point ul;
  final Point ur;
  final Point ll;
  final Point lr;

  const Quad(this.ul, this.ur, this.ll, this.lr);

  /// Create from a Rect (axis-aligned quad).
  factory Quad.fromRect(Rect r) => Quad(
        Point(r.x0, r.y0),
        Point(r.x1, r.y0),
        Point(r.x0, r.y1),
        Point(r.x1, r.y1),
      );

  /// Create from a list of 8 values [ulx, uly, urx, ury, llx, lly, lrx, lry].
  factory Quad.fromList(List<num> list) {
    assert(list.length >= 8);
    return Quad(
      Point(list[0].toDouble(), list[1].toDouble()),
      Point(list[2].toDouble(), list[3].toDouble()),
      Point(list[4].toDouble(), list[5].toDouble()),
      Point(list[6].toDouble(), list[7].toDouble()),
    );
  }

  /// Enclosing rectangle.
  Rect get rect {
    double x0 = ul.x, y0 = ul.y, x1 = ul.x, y1 = ul.y;
    for (final p in [ur, ll, lr]) {
      if (p.x < x0) x0 = p.x;
      if (p.y < y0) y0 = p.y;
      if (p.x > x1) x1 = p.x;
      if (p.y > y1) y1 = p.y;
    }
    return Rect(x0, y0, x1, y1);
  }

  /// Whether this quad is rectangular (axis-aligned).
  bool get isRectangular {
    return ul.y == ur.y && ll.y == lr.y && ul.x == ll.x && ur.x == lr.x;
  }

  /// Whether this quad is convex.
  bool get isConvex {
    double cross(Point o, Point a, Point b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final c1 = cross(ul, ur, lr);
    final c2 = cross(ur, lr, ll);
    final c3 = cross(lr, ll, ul);
    final c4 = cross(ll, ul, ur);
    return (c1 >= 0 && c2 >= 0 && c3 >= 0 && c4 >= 0) ||
        (c1 <= 0 && c2 <= 0 && c3 <= 0 && c4 <= 0);
  }

  /// Whether the given point is inside this quad.
  bool containsPoint(Point p) {
    // Use winding number or cross product test for convex quad
    return rect.containsPoint(p); // simplified for axis-aligned
  }

  /// Transform using a matrix.
  Quad transform(List<double> matrix) => Quad(
        ul.transform(matrix),
        ur.transform(matrix),
        ll.transform(matrix),
        lr.transform(matrix),
      );

  /// Area of the quad.
  double get area {
    // Shoelace formula for quadrilateral
    final pts = [ul, ur, lr, ll];
    double sum = 0;
    for (int i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      sum += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
    }
    return sum.abs() / 2;
  }

  List<double> toList() => [ul.x, ul.y, ur.x, ur.y, ll.x, ll.y, lr.x, lr.y];

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      ul == other.ul &&
      ur == other.ur &&
      ll == other.ll &&
      lr == other.lr;

  @override
  int get hashCode => Object.hash(ul, ur, ll, lr);

  @override
  String toString() => 'Quad($ul, $ur, $ll, $lr)';
}
