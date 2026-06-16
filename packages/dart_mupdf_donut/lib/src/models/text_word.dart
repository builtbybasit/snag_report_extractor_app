import '../geometry/rect.dart';

/// A single word extracted from a PDF page with position info.
///
/// Equivalent to items returned by PyMuPDF's `page.get_text("words")`.
class TextWord {
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  /// The word text.
  final String word;

  /// Block number this word belongs to.
  final int blockNumber;

  /// Line number within the block.
  final int lineNumber;

  /// Word number within the line.
  final int wordNumber;

  const TextWord({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.word,
    required this.blockNumber,
    required this.lineNumber,
    required this.wordNumber,
  });

  Rect get rect => Rect(x0, y0, x1, y1);

  /// Convert to list as in PyMuPDF: (x0, y0, x1, y1, word, block_n, line_n, word_n).
  List<dynamic> toList() =>
      [x0, y0, x1, y1, word, blockNumber, lineNumber, wordNumber];

  @override
  String toString() => 'TextWord("$word" at ${rect})';
}
