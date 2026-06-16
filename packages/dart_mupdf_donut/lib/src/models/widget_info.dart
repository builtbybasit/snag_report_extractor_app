import '../geometry/rect.dart';

/// A PDF form widget (form field), equivalent to PyMuPDF's `Widget` class.
class WidgetInfo {
  /// Widget types.
  static const int typeUnknown = 0;
  static const int typeButton = 1;
  static const int typeText = 2;
  static const int typeChoice = 3;
  static const int typeSignature = 4;

  /// Cross-reference number.
  final int xref;

  /// Field type.
  final int fieldType;

  /// Field name.
  final String fieldName;

  /// Field value.
  final String? fieldValue;

  /// Default value.
  final String? defaultValue;

  /// Bounding rectangle.
  final Rect rect;

  /// Field flags.
  final int fieldFlags;

  /// Choice options (for dropdown/listbox).
  final List<String>? choiceOptions;

  /// Maximum length (for text fields).
  final int? maxLen;

  /// Whether this is read-only.
  final bool readOnly;

  /// Whether this is required.
  final bool required;

  /// Button caption.
  final String? buttonCaption;

  /// Text color.
  final List<double>? textColor;

  /// Fill color.
  final List<double>? fillColor;

  /// Font name.
  final String? fontName;

  /// Font size.
  final double? fontSize;

  const WidgetInfo({
    required this.xref,
    required this.fieldType,
    required this.fieldName,
    this.fieldValue,
    this.defaultValue,
    required this.rect,
    this.fieldFlags = 0,
    this.choiceOptions,
    this.maxLen,
    this.readOnly = false,
    this.required = false,
    this.buttonCaption,
    this.textColor,
    this.fillColor,
    this.fontName,
    this.fontSize,
  });

  String get fieldTypeName {
    switch (fieldType) {
      case typeButton:
        return 'Button';
      case typeText:
        return 'Text';
      case typeChoice:
        return 'Choice';
      case typeSignature:
        return 'Signature';
      default:
        return 'Unknown';
    }
  }

  Map<String, dynamic> toMap() => {
        'xref': xref,
        'field_type': fieldType,
        'field_type_name': fieldTypeName,
        'field_name': fieldName,
        'field_value': fieldValue,
        'rect': rect.toList(),
        'read_only': readOnly,
      };

  @override
  String toString() =>
      'WidgetInfo($fieldTypeName "$fieldName" = "$fieldValue")';
}
