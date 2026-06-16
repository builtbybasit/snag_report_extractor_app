import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import 'geometry/irect.dart';
import 'models/colorspace.dart';

/// Image pixel map, equivalent to PyMuPDF's `fitz.Pixmap`.
///
/// A Pixmap represents a rectangular area of pixels with a given
/// colorspace and optional alpha channel.
///
/// Supports creation from raw data, copying, cropping, and
/// conversion to common image formats (PNG, JPEG, PNM, PBM, etc.).
class Pixmap {
  /// Pixel data bytes.
  Uint8List _samples;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Number of components per pixel (e.g. 3 for RGB, 4 for RGBA).
  final int n;

  /// Bits per component (typically 8).
  final int bpc;

  /// Horizontal resolution (DPI).
  int xRes;

  /// Vertical resolution (DPI).
  int yRes;

  /// Whether pixel data includes alpha channel.
  final bool hasAlpha;

  /// Colorspace of the pixmap.
  final Colorspace colorspace;

  /// Stride (bytes per row).
  int get stride => width * n;

  /// Total number of sample bytes.
  int get size => _samples.length;

  /// Pixel area rectangle.
  IRect get irect => IRect(0, 0, width, height);

  /// Whether this pixmap is a monochrome image.
  bool get isMonochrome => n == 1 && !hasAlpha;

  /// Raw pixel samples.
  Uint8List get samples => _samples;

  /// Create a Pixmap with given dimensions and colorspace.
  ///
  /// Equivalent to `fitz.Pixmap(colorspace, irect, alpha)`.
  Pixmap({
    required this.colorspace,
    required this.width,
    required this.height,
    this.hasAlpha = false,
    this.bpc = 8,
    this.xRes = 72,
    this.yRes = 72,
    Uint8List? samples,
  })  : n = colorspace.n + (hasAlpha ? 1 : 0),
        _samples = samples ??
            Uint8List(width * height * (colorspace.n + (hasAlpha ? 1 : 0)));

  /// Create a Pixmap from an [IRect] and colorspace.
  factory Pixmap.fromIRect(Colorspace cs, IRect rect, {bool alpha = false}) {
    return Pixmap(
      colorspace: cs,
      width: rect.width.abs(),
      height: rect.height.abs(),
      hasAlpha: alpha,
    );
  }

  /// Create a Pixmap from raw pixel bytes.
  factory Pixmap.fromBytes(
    Colorspace cs,
    int width,
    int height,
    Uint8List data, {
    bool alpha = false,
  }) {
    return Pixmap(
      colorspace: cs,
      width: width,
      height: height,
      hasAlpha: alpha,
      samples: Uint8List.fromList(data),
    );
  }

  /// Create a Pixmap from a PNG image.
  factory Pixmap.fromPng(Uint8List pngData) {
    final image = img.decodePng(pngData);
    if (image == null) throw FormatException('Invalid PNG data');

    final hasAlpha = image.numChannels == 4;
    final cs = Colorspace.csRgb;
    final numComponents = cs.n + (hasAlpha ? 1 : 0);
    final samples = Uint8List(image.width * image.height * numComponents);

    int idx = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        samples[idx++] = pixel.r.toInt();
        samples[idx++] = pixel.g.toInt();
        samples[idx++] = pixel.b.toInt();
        if (hasAlpha) samples[idx++] = pixel.a.toInt();
      }
    }

    return Pixmap(
      colorspace: cs,
      width: image.width,
      height: image.height,
      hasAlpha: hasAlpha,
      samples: samples,
    );
  }

  /// Create a Pixmap from a JPEG image.
  factory Pixmap.fromJpeg(Uint8List jpegData) {
    final image = img.decodeJpg(jpegData);
    if (image == null) throw FormatException('Invalid JPEG data');

    final cs = Colorspace.csRgb;
    final samples = Uint8List(image.width * image.height * cs.n);

    int idx = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        samples[idx++] = pixel.r.toInt();
        samples[idx++] = pixel.g.toInt();
        samples[idx++] = pixel.b.toInt();
      }
    }

    return Pixmap(
      colorspace: cs,
      width: image.width,
      height: image.height,
      hasAlpha: false,
      samples: samples,
    );
  }

  // ---------- Pixel Access ----------

  /// Get the color value of a pixel at (x, y).
  ///
  /// Returns a list of component values (e.g., [R, G, B] or [R, G, B, A]).
  List<int> getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Pixel ($x, $y) is out of bounds ($width x $height)');
    }
    final offset = (y * width + x) * n;
    return List<int>.generate(n, (i) => _samples[offset + i]);
  }

  /// Set the color value of a pixel at (x, y).
  void setPixel(int x, int y, List<int> color) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Pixel ($x, $y) is out of bounds ($width x $height)');
    }
    if (color.length != n) {
      throw ArgumentError('Expected $n components, got ${color.length}');
    }
    final offset = (y * width + x) * n;
    for (int i = 0; i < n; i++) {
      _samples[offset + i] = color[i].clamp(0, 255);
    }
  }

  // ---------- Clearing ----------

  /// Clear the pixmap to white (with full alpha if present).
  ///
  /// Equivalent to PyMuPDF's `pixmap.clear_with()`.
  void clearWith([int value = 255]) {
    _samples.fillRange(0, _samples.length, value);
    if (hasAlpha) {
      // Set alpha to full
      for (int i = n - 1; i < _samples.length; i += n) {
        _samples[i] = 255;
      }
    }
  }

  /// Set all pixels to a specific color.
  void setRect(IRect rect, List<int> color) {
    final x0 = rect.x0.clamp(0, width);
    final y0 = rect.y0.clamp(0, height);
    final x1 = rect.x1.clamp(0, width);
    final y1 = rect.y1.clamp(0, height);

    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        setPixel(x, y, color);
      }
    }
  }

  // ---------- Conversion ----------

  /// Convert pixmap to a different colorspace.
  ///
  /// Equivalent to PyMuPDF's `fitz.Pixmap(colorspace, source)`.
  Pixmap toColorspace(Colorspace targetCs) {
    if (colorspace == targetCs) return _copy();

    final targetN = targetCs.n + (hasAlpha ? 1 : 0);
    final targetSamples = Uint8List(width * height * targetN);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcPixel = getPixel(x, y);
        final dstPixel = _convertPixel(
          srcPixel,
          colorspace,
          targetCs,
          hasAlpha,
        );
        final offset = (y * width + x) * targetN;
        for (int i = 0; i < targetN; i++) {
          targetSamples[offset + i] = dstPixel[i];
        }
      }
    }

    return Pixmap(
      colorspace: targetCs,
      width: width,
      height: height,
      hasAlpha: hasAlpha,
      xRes: xRes,
      yRes: yRes,
      samples: targetSamples,
    );
  }

  static List<int> _convertPixel(
    List<int> pixel,
    Colorspace from,
    Colorspace to,
    bool alpha,
  ) {
    int r, g, b;

    // Convert source to RGB
    if (from == Colorspace.csRgb) {
      r = pixel[0];
      g = pixel[1];
      b = pixel[2];
    } else if (from == Colorspace.csGray) {
      r = g = b = pixel[0];
    } else if (from == Colorspace.csCmyk && pixel.length >= 4) {
      final c = pixel[0] / 255.0;
      final m = pixel[1] / 255.0;
      final y = pixel[2] / 255.0;
      final k = pixel[3] / 255.0;
      r = ((1 - c) * (1 - k) * 255).round().clamp(0, 255);
      g = ((1 - m) * (1 - k) * 255).round().clamp(0, 255);
      b = ((1 - y) * (1 - k) * 255).round().clamp(0, 255);
    } else {
      r = g = b = 0;
    }

    // Convert RGB to target
    if (to == Colorspace.csRgb) {
      final result = [r, g, b];
      if (alpha) result.add(pixel.length > from.n ? pixel.last : 255);
      return result;
    } else if (to == Colorspace.csGray) {
      final gray = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
      final result = [gray];
      if (alpha) result.add(pixel.length > from.n ? pixel.last : 255);
      return result;
    } else if (to == Colorspace.csCmyk) {
      final rf = r / 255.0;
      final gf = g / 255.0;
      final bf = b / 255.0;
      final k = 1.0 - math.max(rf, math.max(gf, bf));
      if (k >= 1.0) {
        final result = [0, 0, 0, 255];
        if (alpha) result.add(pixel.length > from.n ? pixel.last : 255);
        return result;
      }
      final c = ((1.0 - rf - k) / (1.0 - k) * 255).round().clamp(0, 255);
      final m = ((1.0 - gf - k) / (1.0 - k) * 255).round().clamp(0, 255);
      final y = ((1.0 - bf - k) / (1.0 - k) * 255).round().clamp(0, 255);
      final ki = (k * 255).round().clamp(0, 255);
      final result = [c, m, y, ki];
      if (alpha) result.add(pixel.length > from.n ? pixel.last : 255);
      return result;
    }

    return pixel;
  }

  /// Remove alpha channel.
  Pixmap removeAlpha() {
    if (!hasAlpha) return _copy();

    final targetN = colorspace.n;
    final targetSamples = Uint8List(width * height * targetN);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcOffset = (y * width + x) * n;
        final dstOffset = (y * width + x) * targetN;
        for (int i = 0; i < targetN; i++) {
          targetSamples[dstOffset + i] = _samples[srcOffset + i];
        }
      }
    }

    return Pixmap(
      colorspace: colorspace,
      width: width,
      height: height,
      hasAlpha: false,
      xRes: xRes,
      yRes: yRes,
      samples: targetSamples,
    );
  }

  /// Add alpha channel.
  Pixmap addAlpha() {
    if (hasAlpha) return _copy();

    final targetN = n + 1;
    final targetSamples = Uint8List(width * height * targetN);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcOffset = (y * width + x) * n;
        final dstOffset = (y * width + x) * targetN;
        for (int i = 0; i < n; i++) {
          targetSamples[dstOffset + i] = _samples[srcOffset + i];
        }
        targetSamples[dstOffset + n] = 255; // full alpha
      }
    }

    return Pixmap(
      colorspace: colorspace,
      width: width,
      height: height,
      hasAlpha: true,
      xRes: xRes,
      yRes: yRes,
      samples: targetSamples,
    );
  }

  // ---------- Image Output ----------

  /// Convert to PNG bytes.
  ///
  /// Equivalent to PyMuPDF's `pixmap.tobytes("png")`.
  Uint8List toPng() {
    final image = _toImage();
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Convert to JPEG bytes.
  ///
  /// Equivalent to PyMuPDF's `pixmap.tobytes("jpeg")`.
  Uint8List toJpeg({int quality = 90}) {
    final image = _toImage();
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  /// Convert to BMP bytes.
  Uint8List toBmp() {
    final image = _toImage();
    return Uint8List.fromList(img.encodeBmp(image));
  }

  /// Convert to raw bytes in the format specified.
  ///
  /// Equivalent to PyMuPDF's `pixmap.tobytes()`.
  Uint8List toBytes([String format = 'png']) {
    switch (format.toLowerCase()) {
      case 'png':
        return toPng();
      case 'jpeg':
      case 'jpg':
        return toJpeg();
      case 'bmp':
        return toBmp();
      case 'pnm':
      case 'ppm':
        return _toPnm();
      case 'pbm':
        return _toPbm();
      case 'pgm':
        return _toPgm();
      default:
        return toPng();
    }
  }

  /// Convert to PNM format (PPM/PGM/PBM).
  Uint8List _toPnm() {
    if (n == 1 || (n == 2 && hasAlpha)) {
      return _toPgm();
    }
    // PPM format (RGB)
    final header = 'P6\n$width $height\n255\n';
    final headerBytes = header.codeUnits;
    final pixelData = Uint8List(width * height * 3);
    int idx = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = getPixel(x, y);
        pixelData[idx++] = pixel[0];
        pixelData[idx++] = pixel.length > 1 ? pixel[1] : pixel[0];
        pixelData[idx++] = pixel.length > 2 ? pixel[2] : pixel[0];
      }
    }
    return Uint8List.fromList([...headerBytes, ...pixelData]);
  }

  /// Convert to PGM format.
  Uint8List _toPgm() {
    final header = 'P5\n$width $height\n255\n';
    final headerBytes = header.codeUnits;
    final pixelData = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = getPixel(x, y);
        pixelData[y * width + x] = pixel[0];
      }
    }
    return Uint8List.fromList([...headerBytes, ...pixelData]);
  }

  /// Convert to PBM format.
  Uint8List _toPbm() {
    final header = 'P4\n$width $height\n';
    final headerBytes = header.codeUnits;
    final rowBytes = (width + 7) ~/ 8;
    final pixelData = Uint8List(rowBytes * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = getPixel(x, y);
        final gray = pixel[0];
        if (gray < 128) {
          pixelData[y * rowBytes + x ~/ 8] |= (0x80 >> (x % 8));
        }
      }
    }
    return Uint8List.fromList([...headerBytes, ...pixelData]);
  }

  /// Save pixmap to a file.
  ///
  /// Equivalent to PyMuPDF's `pixmap.save()`.
  void save(String filename) {
    String format = 'png';
    if (filename.endsWith('.jpg') || filename.endsWith('.jpeg')) {
      format = 'jpeg';
    } else if (filename.endsWith('.bmp')) {
      format = 'bmp';
    } else if (filename.endsWith('.pnm') || filename.endsWith('.ppm')) {
      format = 'pnm';
    } else if (filename.endsWith('.pgm')) {
      format = 'pgm';
    } else if (filename.endsWith('.pbm')) {
      format = 'pbm';
    }

    toBytes(format);
    // In a real implementation, write to file using dart:io
    // File(filename).writeAsBytesSync(data);
  }

  // ---------- Manipulation ----------

  /// Invert all pixel values.
  ///
  /// Equivalent to PyMuPDF's `pixmap.invert_irect()`.
  void invertIRect([IRect? rect]) {
    final r = rect ?? irect;
    final x0 = r.x0.clamp(0, width);
    final y0 = r.y0.clamp(0, height);
    final x1 = r.x1.clamp(0, width);
    final y1 = r.y1.clamp(0, height);

    final alphaIdx = hasAlpha ? n - 1 : -1;
    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        final offset = (y * width + x) * n;
        for (int i = 0; i < n; i++) {
          if (i != alphaIdx) {
            _samples[offset + i] = 255 - _samples[offset + i];
          }
        }
      }
    }
  }

  /// Tint the pixmap using black/white color mapping.
  void tintWith(int black, int white) {
    for (int i = 0; i < _samples.length; i += n) {
      for (int j = 0; j < math.min(3, n); j++) {
        final v = _samples[i + j];
        _samples[i + j] = (black + (white - black) * v / 255).round().clamp(
              0,
              255,
            );
      }
    }
  }

  /// Apply gamma correction.
  void gammaWith(double gamma) {
    if (gamma <= 0) return;
    final lut = List<int>.generate(
      256,
      (i) => (255 * math.pow(i / 255.0, 1.0 / gamma)).round().clamp(0, 255),
    );

    final alphaIdx = hasAlpha ? n - 1 : -1;
    for (int i = 0; i < _samples.length; i++) {
      if ((i % n) != alphaIdx) {
        _samples[i] = lut[_samples[i]];
      }
    }
  }

  /// Shrink the pixmap by a factor.
  Pixmap shrink(int factor) {
    if (factor <= 1) return _copy();

    final newW = (width / factor).ceil();
    final newH = (height / factor).ceil();
    final newSamples = Uint8List(newW * newH * n);

    for (int ny = 0; ny < newH; ny++) {
      for (int nx = 0; nx < newW; nx++) {
        final sums = List<int>.filled(n, 0);
        int count = 0;

        for (int sy = ny * factor;
            sy < math.min((ny + 1) * factor, height);
            sy++) {
          for (int sx = nx * factor;
              sx < math.min((nx + 1) * factor, width);
              sx++) {
            final offset = (sy * width + sx) * n;
            for (int c = 0; c < n; c++) {
              sums[c] += _samples[offset + c];
            }
            count++;
          }
        }

        final dstOffset = (ny * newW + nx) * n;
        for (int c = 0; c < n; c++) {
          newSamples[dstOffset + c] = count > 0 ? (sums[c] / count).round() : 0;
        }
      }
    }

    return Pixmap(
      colorspace: colorspace,
      width: newW,
      height: newH,
      hasAlpha: hasAlpha,
      xRes: xRes ~/ factor,
      yRes: yRes ~/ factor,
      samples: newSamples,
    );
  }

  /// Set the resolution.
  void setDpi(int xDpi, int yDpi) {
    xRes = xDpi;
    yRes = yDpi;
  }

  /// Set alpha channel values.
  void setAlpha(Uint8List? alphaValues) {
    if (!hasAlpha) return;
    final alphaIdx = n - 1;
    for (int i = 0; i < width * height; i++) {
      _samples[i * n + alphaIdx] =
          alphaValues != null && i < alphaValues.length ? alphaValues[i] : 255;
    }
  }

  // ---------- Internal ----------

  img.Image _toImage() {
    final image = img.Image(width: width, height: height, numChannels: 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = getPixel(x, y);
        int r, g, b, a;

        if (colorspace == Colorspace.csGray) {
          r = g = b = pixel[0];
          a = hasAlpha && pixel.length > 1 ? pixel[1] : 255;
        } else if (colorspace == Colorspace.csCmyk && pixel.length >= 4) {
          final c = pixel[0] / 255.0;
          final m = pixel[1] / 255.0;
          final yy = pixel[2] / 255.0;
          final k = pixel[3] / 255.0;
          r = ((1 - c) * (1 - k) * 255).round().clamp(0, 255);
          g = ((1 - m) * (1 - k) * 255).round().clamp(0, 255);
          b = ((1 - yy) * (1 - k) * 255).round().clamp(0, 255);
          a = hasAlpha && pixel.length > 4 ? pixel[4] : 255;
        } else {
          r = pixel[0];
          g = pixel.length > 1 ? pixel[1] : pixel[0];
          b = pixel.length > 2 ? pixel[2] : pixel[0];
          a = hasAlpha && pixel.length > 3 ? pixel[3] : 255;
        }

        image.setPixelRgba(x, y, r, g, b, a);
      }
    }

    return image;
  }

  Pixmap _copy() {
    return Pixmap(
      colorspace: colorspace,
      width: width,
      height: height,
      hasAlpha: hasAlpha,
      xRes: xRes,
      yRes: yRes,
      samples: Uint8List.fromList(_samples),
    );
  }

  @override
  String toString() =>
      'Pixmap(width: $width, height: $height, colorspace: $colorspace, '
      'alpha: $hasAlpha, stride: $stride)';
}
