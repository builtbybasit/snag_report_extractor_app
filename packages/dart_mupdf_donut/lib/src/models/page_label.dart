/// A page label entry, equivalent to PyMuPDF's page label support.
class PageLabel {
  /// Start page index (0-based).
  final int startPage;

  /// Numbering style: 'D'=decimal, 'r'=roman lower, 'R'=roman upper,
  /// 'a'=alpha lower, 'A'=alpha upper, ''=no numbering.
  final String style;

  /// Label prefix.
  final String prefix;

  /// Start value for numbering.
  final int startValue;

  const PageLabel({
    required this.startPage,
    this.style = 'D',
    this.prefix = '',
    this.startValue = 1,
  });

  Map<String, dynamic> toMap() => {
        'startpage': startPage,
        'style': style,
        'prefix': prefix,
        'startval': startValue,
      };

  @override
  String toString() =>
      'PageLabel(page: $startPage, style: "$style", prefix: "$prefix", start: $startValue)';
}
