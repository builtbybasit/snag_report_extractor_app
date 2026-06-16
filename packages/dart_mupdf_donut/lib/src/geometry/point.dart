import 'dart:math' as math;

/// A 2D point, equivalent to PyMuPDF's `fitz.Point`.
class Point {
  final double x;
  final double y;

  const Point(this.x, this.y);

  /// Create a Point from a list [x, y].
  factory Point.fromList(List<num> list) {
    assert(list.length >= 2);
    return Point(list[0].toDouble(), list[1].toDouble());
  }

  /// The zero point (origin).
  static const Point zero = Point(0, 0);

  /// Distance from origin.
  double get abs => math.sqrt(x * x + y * y);

  /// Unit vector.
  Point get unit {
    final d = abs;
    if (d == 0) return Point.zero;
    return Point(x / d, y / d);
  }

  /// Euclidean distance to another point.
  double distanceTo(Point other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Transform this point using a Matrix.
  Point transform(dynamic matrix) {
    // Matrix is [a, b, c, d, e, f]
    // x' = a*x + c*y + e
    // y' = b*x + d*y + f
    if (matrix is List<double> && matrix.length == 6) {
      return Point(
        matrix[0] * x + matrix[2] * y + matrix[4],
        matrix[1] * x + matrix[3] * y + matrix[5],
      );
    }
    return this;
  }

  Point operator +(Point other) => Point(x + other.x, y + other.y);
  Point operator -(Point other) => Point(x - other.x, y - other.y);
  Point operator *(double factor) => Point(x * factor, y * factor);
  Point operator /(double factor) => Point(x / factor, y / factor);
  Point operator -() => Point(-x, -y);

  @override
  bool operator ==(Object other) =>
      other is Point && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  /// Convert to a list.
  List<double> toList() => [x, y];

  @override
  String toString() => 'Point($x, $y)';
}
