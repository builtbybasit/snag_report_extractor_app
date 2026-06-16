import 'dart:math' as math;
import 'rect.dart';

/// An integer rectangle, equivalent to PyMuPDF's `fitz.IRect`.
class IRect {
  final int x0;
  final int y0;
  final int x1;
  final int y1;

  const IRect(this.x0, this.y0, this.x1, this.y1);

  factory IRect.fromList(List<num> list) {
    assert(list.length >= 4);
    return IRect(
      list[0].toInt(),
      list[1].toInt(),
      list[2].toInt(),
      list[3].toInt(),
    );
  }

  static const IRect empty = IRect(0, 0, 0, 0);

  int get width => (x1 - x0).abs();
  int get height => (y1 - y0).abs();
  int get area => width * height;
  bool get isEmpty => width <= 0 || height <= 0;

  Rect get rect =>
      Rect(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());

  IRect get normalized => IRect(
        math.min(x0, x1),
        math.min(y0, y1),
        math.max(x0, x1),
        math.max(y0, y1),
      );

  bool containsPoint(int px, int py) =>
      px >= x0 && px <= x1 && py >= y0 && py <= y1;

  bool overlaps(IRect other) =>
      x0 < other.x1 && x1 > other.x0 && y0 < other.y1 && y1 > other.y0;

  IRect union(IRect other) {
    if (isEmpty) return other;
    if (other.isEmpty) return this;
    return IRect(
      math.min(x0, other.x0),
      math.min(y0, other.y0),
      math.max(x1, other.x1),
      math.max(y1, other.y1),
    );
  }

  IRect intersect(IRect other) {
    final ix0 = math.max(x0, other.x0);
    final iy0 = math.max(y0, other.y0);
    final ix1 = math.min(x1, other.x1);
    final iy1 = math.min(y1, other.y1);
    if (ix0 >= ix1 || iy0 >= iy1) return IRect.empty;
    return IRect(ix0, iy0, ix1, iy1);
  }

  @override
  bool operator ==(Object other) =>
      other is IRect &&
      x0 == other.x0 &&
      y0 == other.y0 &&
      x1 == other.x1 &&
      y1 == other.y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);

  List<int> toList() => [x0, y0, x1, y1];

  @override
  String toString() => 'IRect($x0, $y0, $x1, $y1)';
}
