/// PDF Colorspace, equivalent to PyMuPDF's `fitz.Colorspace`.
class Colorspace {
  final int n; // number of components
  final String name;

  const Colorspace._(this.n, this.name);

  /// Device Gray (1 component).
  static const Colorspace csGray = Colorspace._(1, 'DeviceGray');

  /// Device RGB (3 components).
  static const Colorspace csRgb = Colorspace._(3, 'DeviceRGB');

  /// Device CMYK (4 components).
  static const Colorspace csCmyk = Colorspace._(4, 'DeviceCMYK');

  /// Get colorspace from name.
  static Colorspace fromName(String name) {
    switch (name) {
      case 'DeviceGray':
      case 'CalGray':
      case 'G':
        return csGray;
      case 'DeviceRGB':
      case 'CalRGB':
      case 'RGB':
        return csRgb;
      case 'DeviceCMYK':
      case 'CMYK':
        return csCmyk;
      default:
        return Colorspace._(3, name); // default to 3 components
    }
  }

  @override
  String toString() => 'Colorspace($name, n=$n)';
}
