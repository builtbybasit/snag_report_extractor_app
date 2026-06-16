import '../geometry/rect.dart';

/// A text block extracted from a PDF page.
///
/// Equivalent to items returned by PyMuPDF's `page.get_text("blocks")`.
class TextBlock {
  /// Bounding box x0.
  final double x0;

  /// Bounding box y0.
  final double y0;

  /// Bounding box x1.
  final double x1;

  /// Bounding box y1.
  final double y1;

  /// The text content of this block.
  final String text;

  /// Block number (sequence index on page).
  final int blockNumber;

  /// Block type: 0 = text, 1 = image.
  final int blockType;

  const TextBlock({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.text,
    required this.blockNumber,
    this.blockType = 0,
  });

  /// Bounding rectangle.
  Rect get rect => Rect(x0, y0, x1, y1);

  /// Whether this is an image block.
  bool get isImage => blockType == 1;

  /// Convert to tuple-like list as in PyMuPDF: (x0, y0, x1, y1, text, block_n, type).
  List<dynamic> toList() => [x0, y0, x1, y1, text, blockNumber, blockType];

  @override
  String toString() =>
      'TextBlock(rect: ${rect}, text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}")';
}
