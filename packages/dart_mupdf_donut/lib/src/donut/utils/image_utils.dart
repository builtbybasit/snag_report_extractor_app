/// Image preprocessing utilities for Donut — pure Dart implementation.
///
/// Handles all image preparation needed before feeding to the Swin Transformer
/// encoder: decoding, resizing, normalization, and tensor conversion.
///
/// Uses ImageNet normalization (same as original Donut model):
///   mean = [0.485, 0.456, 0.406]
///   std  = [0.229, 0.224, 0.225]
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../tensor/tensor.dart';
import '../donut_config.dart';

/// Image preprocessing pipeline for Donut.
///
/// Converts raw image files or decoded images into normalized tensors
/// suitable for the Swin Transformer encoder.
///
/// The pipeline follows the original Donut preprocessing:
/// 1. Decode image bytes to RGB
/// 2. Optionally rotate if height > width (align long axis)
/// 3. Resize to target size while maintaining aspect ratio
/// 4. Pad to exact target dimensions with white pixels
/// 5. Normalize with ImageNet mean/std
/// 6. Convert to tensor (batch, channels, height, width)
class DonutImageUtils {
  /// ImageNet normalization mean (RGB).
  static const List<double> mean = [0.485, 0.456, 0.406];

  /// ImageNet normalization std (RGB).
  static const List<double> std = [0.229, 0.224, 0.225];

  /// Preprocess raw image bytes for Donut inference.
  ///
  /// [imageBytes]: raw image file bytes (PNG, JPEG, BMP, etc.)
  /// [config]: Donut configuration containing input size and align settings
  ///
  /// Returns a tensor of shape (1, 3, height, width).
  static Tensor preprocessBytes(List<int> imageBytes, DonutConfig config) {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw ArgumentError('Failed to decode image');
    }
    return preprocessImage(decoded, config);
  }

  /// Preprocess a decoded image for Donut inference.
  ///
  /// [image]: decoded image
  /// [config]: Donut configuration
  ///
  /// Returns a tensor of shape (1, 3, height, width).
  static Tensor preprocessImage(img.Image image, DonutConfig config) {
    final targetH = config.inputSize[0];
    final targetW = config.inputSize[1];

    var processed = image;

    // Ensure RGB format (convert grayscale by duplicating channels)
    if (processed.numChannels < 3) {
      final rgb = img.Image(width: processed.width, height: processed.height);
      for (int y = 0; y < processed.height; y++) {
        for (int x = 0; x < processed.width; x++) {
          final p = processed.getPixel(x, y);
          final gray = p.r;
          rgb.setPixelRgb(x, y, gray, gray, gray);
        }
      }
      processed = rgb;
    }

    // Align long axis: rotate if needed
    if (config.alignLongAxis) {
      final isLandscape = processed.width > processed.height;
      final targetIsLandscape = targetW > targetH;
      if (isLandscape != targetIsLandscape) {
        processed = img.copyRotate(processed, angle: 90);
      }
    }

    // Resize maintaining aspect ratio
    processed = _resizeMaintainAspect(processed, targetW, targetH);

    // Pad to exact target size
    processed = _padToSize(processed, targetW, targetH);

    // Convert to normalized tensor
    return _imageToTensor(processed);
  }

  /// Resize image to fit within (targetW, targetH) while maintaining aspect ratio.
  static img.Image _resizeMaintainAspect(
      img.Image image, int targetW, int targetH) {
    final scaleW = targetW / image.width;
    final scaleH = targetH / image.height;
    final scale = math.min(scaleW, scaleH);

    final newW = (image.width * scale).round();
    final newH = (image.height * scale).round();

    if (newW == image.width && newH == image.height) {
      return image;
    }

    return img.copyResize(
      image,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Pad image to exactly (targetW, targetH) with white pixels (centered).
  static img.Image _padToSize(img.Image image, int targetW, int targetH) {
    if (image.width == targetW && image.height == targetH) {
      return image;
    }

    // Create white canvas
    final padded = img.Image(width: targetW, height: targetH);
    img.fill(padded, color: img.ColorFloat32.rgb(255, 255, 255));

    // Calculate padding offsets (center the image)
    final offsetX = (targetW - image.width) ~/ 2;
    final offsetY = (targetH - image.height) ~/ 2;

    // Composite the image onto the padded canvas
    img.compositeImage(padded, image, dstX: offsetX, dstY: offsetY);

    return padded;
  }

  /// Convert an image to a normalized NCHW tensor.
  ///
  /// Returns a tensor of shape (1, 3, height, width) with pixel values
  /// normalized using ImageNet mean and std.
  static Tensor _imageToTensor(img.Image image) {
    final h = image.height;
    final w = image.width;
    final data = Float32List(3 * h * w);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);

        // Get RGB values normalized to [0, 1]
        final r = pixel.rNormalized;
        final g = pixel.gNormalized;
        final b = pixel.bNormalized;

        // Apply ImageNet normalization: (value - mean) / std
        final idx = y * w + x;
        data[0 * h * w + idx] = ((r - mean[0]) / std[0]); // R channel
        data[1 * h * w + idx] = ((g - mean[1]) / std[1]); // G channel
        data[2 * h * w + idx] = ((b - mean[2]) / std[2]); // B channel
      }
    }

    return Tensor(data, [1, 3, h, w]);
  }

  /// Convert a tensor back to an image (for debugging/visualization).
  ///
  /// [tensor]: (1, 3, H, W) or (3, H, W) normalized tensor
  /// Returns a decoded image.
  static img.Image tensorToImage(Tensor tensor) {
    List<int> shape;
    Float32List data;

    if (tensor.shape.length == 4) {
      shape = [tensor.shape[2], tensor.shape[3]]; // H, W
      data = tensor[0].data; // remove batch dim
    } else if (tensor.shape.length == 3) {
      shape = [tensor.shape[1], tensor.shape[2]]; // H, W
      data = tensor.data;
    } else {
      throw ArgumentError('Expected 3D or 4D tensor, got ${tensor.shape}');
    }

    final h = shape[0];
    final w = shape[1];

    final image = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;

        // Denormalize: value * std + mean, then clamp to [0, 1]
        final r = (data[0 * h * w + idx] * std[0] + mean[0]).clamp(0.0, 1.0);
        final g = (data[1 * h * w + idx] * std[1] + mean[1]).clamp(0.0, 1.0);
        final b = (data[2 * h * w + idx] * std[2] + mean[2]).clamp(0.0, 1.0);

        image.setPixelRgb(
          x,
          y,
          (r * 255).round(),
          (g * 255).round(),
          (b * 255).round(),
        );
      }
    }

    return image;
  }

  /// Create a tensor from RGB pixel values (not normalized).
  ///
  /// [pixels]: flat array of RGB values [R, G, B, R, G, B, ...]
  ///   in row-major order, values in range [0, 255]
  /// [width]: image width
  /// [height]: image height
  ///
  /// Returns normalized tensor of shape (1, 3, height, width).
  static Tensor fromPixels(List<int> pixels, int width, int height) {
    assert(pixels.length == width * height * 3);
    final data = Float32List(3 * height * width);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcIdx = (y * width + x) * 3;
        final dstIdx = y * width + x;

        final r = pixels[srcIdx] / 255.0;
        final g = pixels[srcIdx + 1] / 255.0;
        final b = pixels[srcIdx + 2] / 255.0;

        data[0 * height * width + dstIdx] = (r - mean[0]) / std[0];
        data[1 * height * width + dstIdx] = (g - mean[1]) / std[1];
        data[2 * height * width + dstIdx] = (b - mean[2]) / std[2];
      }
    }

    return Tensor(data, [1, 3, height, width]);
  }

  /// Get a summary of image preprocessing that will be applied.
  static String describePipeline(DonutConfig config) {
    return 'DonutImageUtils Pipeline:\n'
        '  1. Decode image to RGB\n'
        '  2. ${config.alignLongAxis ? "Rotate if needed (align long axis)" : "No rotation"}\n'
        '  3. Resize to fit ${config.inputSize[1]}x${config.inputSize[0]} (maintain aspect ratio)\n'
        '  4. Pad with white to exact ${config.inputSize[1]}x${config.inputSize[0]}\n'
        '  5. Normalize: (pixel/255 - $mean) / $std\n'
        '  6. Convert to tensor [1, 3, ${config.inputSize[0]}, ${config.inputSize[1]}]';
  }
}
