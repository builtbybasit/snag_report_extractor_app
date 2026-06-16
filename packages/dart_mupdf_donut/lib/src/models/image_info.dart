import 'dart:typed_data';

/// Information about an image found on a PDF page.
///
/// Equivalent to items returned by PyMuPDF's `page.get_images()`.
class PdfImageInfo {
  /// Cross-reference number of the image object.
  final int xref;

  /// Image type indicator.
  final int smask;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Bits per component.
  final int bpc;

  /// Colorspace name (e.g., "DeviceRGB", "DeviceGray").
  final String colorspace;

  /// Alternative colorspace name.
  final String altColorspace;

  /// Image name reference.
  final String name;

  /// Image filter (compression method).
  final String filter;

  const PdfImageInfo({
    required this.xref,
    this.smask = 0,
    required this.width,
    required this.height,
    required this.bpc,
    required this.colorspace,
    this.altColorspace = '',
    this.name = '',
    this.filter = '',
  });

  /// Number of color components.
  int get components {
    switch (colorspace) {
      case 'DeviceRGB':
      case 'CalRGB':
        return 3;
      case 'DeviceCMYK':
        return 4;
      case 'DeviceGray':
      case 'CalGray':
        return 1;
      default:
        return 3;
    }
  }

  /// Convert to list as in PyMuPDF: (xref, smask, width, height, bpc, colorspace, ...).
  List<dynamic> toList() => [
        xref,
        smask,
        width,
        height,
        bpc,
        colorspace,
        altColorspace,
        name,
        filter,
      ];

  @override
  String toString() =>
      'PdfImageInfo(xref: $xref, ${width}x$height, $colorspace, $bpc bpc)';
}

/// Extracted image data.
class ExtractedImage {
  /// Cross-reference number.
  final int xref;

  /// Image extension (e.g., "png", "jpeg").
  final String ext;

  /// Colorspace components.
  final int colorspace;

  /// Image width.
  final int width;

  /// Image height.
  final int height;

  /// Bits per component.
  final int bpc;

  /// The raw image bytes.
  final Uint8List image;

  const ExtractedImage({
    required this.xref,
    required this.ext,
    required this.colorspace,
    required this.width,
    required this.height,
    required this.bpc,
    required this.image,
  });

  /// Size in bytes.
  int get size => image.length;

  Map<String, dynamic> toMap() => {
        'xref': xref,
        'ext': ext,
        'colorspace': colorspace,
        'width': width,
        'height': height,
        'bpc': bpc,
        'size': size,
        'image': image,
      };

  @override
  String toString() =>
      'ExtractedImage(xref: $xref, ${width}x$height, $ext, ${size} bytes)';
}
