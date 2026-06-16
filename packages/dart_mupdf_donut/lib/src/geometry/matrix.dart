import 'dart:math' as math;

/// A 3x3 transformation matrix (stored as [a, b, c, d, e, f]),
/// equivalent to PyMuPDF's `fitz.Matrix`.
///
/// The full matrix is:
/// ```
///   | a  b  0 |
///   | c  d  0 |
///   | e  f  1 |
/// ```
class Matrix {
  final double a, b, c, d, e, f;

  const Matrix(this.a, this.b, this.c, this.d, this.e, this.f);

  /// Identity matrix.
  static const Matrix identity = Matrix(1, 0, 0, 1, 0, 0);

  /// Create a rotation matrix (degrees).
  factory Matrix.rotation(double degrees) {
    final rad = degrees * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return Matrix(cosA, sinA, -sinA, cosA, 0, 0);
  }

  /// Create a scaling matrix.
  factory Matrix.scale(double sx, double sy) => Matrix(sx, 0, 0, sy, 0, 0);

  /// Create a translation matrix.
  factory Matrix.translation(double tx, double ty) =>
      Matrix(1, 0, 0, 1, tx, ty);

  /// Create a shearing matrix.
  factory Matrix.shear(double sx, double sy) => Matrix(1, sy, sx, 1, 0, 0);

  /// Create from a list of 6 values.
  factory Matrix.fromList(List<num> list) {
    assert(list.length >= 6);
    return Matrix(
      list[0].toDouble(),
      list[1].toDouble(),
      list[2].toDouble(),
      list[3].toDouble(),
      list[4].toDouble(),
      list[5].toDouble(),
    );
  }

  /// Determinant.
  double get determinant => a * d - b * c;

  /// Whether this matrix is invertible.
  bool get isInvertible => determinant != 0;

  /// Whether this is a rectilinear matrix (only scaling/translation/90° rotations).
  bool get isRectilinear => (a == 0 && d == 0) || (b == 0 && c == 0);

  /// Inverse matrix.
  Matrix get inverse {
    final det = determinant;
    if (det == 0) throw StateError('Matrix is not invertible');
    final id = 1.0 / det;
    return Matrix(
      d * id,
      -b * id,
      -c * id,
      a * id,
      (c * f - d * e) * id,
      (b * e - a * f) * id,
    );
  }

  /// Concatenate (multiply) two matrices.
  Matrix concat(Matrix other) => Matrix(
        a * other.a + b * other.c,
        a * other.b + b * other.d,
        c * other.a + d * other.c,
        c * other.b + d * other.d,
        e * other.a + f * other.c + other.e,
        e * other.b + f * other.d + other.f,
      );

  /// Pre-rotate this matrix.
  Matrix preRotate(double degrees) => Matrix.rotation(degrees).concat(this);

  /// Pre-scale this matrix.
  Matrix preScale(double sx, double sy) => Matrix.scale(sx, sy).concat(this);

  /// Pre-translate this matrix.
  Matrix preTranslate(double tx, double ty) =>
      Matrix.translation(tx, ty).concat(this);

  Matrix operator *(Matrix other) => concat(other);

  @override
  bool operator ==(Object other) =>
      other is Matrix &&
      a == other.a &&
      b == other.b &&
      c == other.c &&
      d == other.d &&
      e == other.e &&
      f == other.f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);

  List<double> toList() => [a, b, c, d, e, f];

  @override
  String toString() => 'Matrix($a, $b, $c, $d, $e, $f)';
}
