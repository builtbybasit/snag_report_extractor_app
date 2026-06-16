import 'dart:typed_data';

/// An embedded file within a PDF, equivalent to PyMuPDF's embedded file methods.
class EmbeddedFile {
  /// File name.
  final String name;

  /// File description.
  final String? description;

  /// Original filename.
  final String? filename;

  /// Unicode filename.
  final String? ufilename;

  /// File content.
  final Uint8List content;

  /// Creation date.
  final String? creationDate;

  /// Modification date.
  final String? modDate;

  /// Size of the uncompressed content.
  final int size;

  const EmbeddedFile({
    required this.name,
    this.description,
    this.filename,
    this.ufilename,
    required this.content,
    this.creationDate,
    this.modDate,
    required this.size,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'filename': filename ?? name,
        'ufilename': ufilename ?? name,
        'size': size,
        'creationDate': creationDate,
        'modDate': modDate,
      };

  @override
  String toString() => 'EmbeddedFile("$name", $size bytes)';
}
