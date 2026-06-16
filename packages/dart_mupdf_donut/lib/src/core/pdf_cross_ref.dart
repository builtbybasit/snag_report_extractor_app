import 'dart:typed_data';
import 'pdf_objects.dart';

/// Represents the cross-reference table of a PDF.
///
/// This tracks all indirect objects and their byte offsets.
class PdfCrossRefTable {
  /// Map of object number -> cross reference entry.
  final Map<int, CrossRefEntry> entries = {};

  /// The trailer dictionary.
  PdfDict trailer = PdfDict();

  /// Add an entry.
  void addEntry(int objectNumber, CrossRefEntry entry) {
    entries[objectNumber] = entry;
  }

  /// Get the offset for an object number.
  int? getOffset(int objectNumber) {
    return entries[objectNumber]?.offset;
  }

  /// Get all live (in-use) object numbers.
  List<int> get liveObjectNumbers {
    return entries.entries
        .where((e) => e.value.inUse)
        .map((e) => e.key)
        .toList()
      ..sort();
  }

  /// Total number of objects.
  int get size => entries.length;

  /// Merge another cross-reference table (for incremental updates).
  void merge(PdfCrossRefTable other) {
    entries.addAll(other.entries);
    // Newer trailer takes precedence, but keep /Prev chain
    final mergedTrailer = PdfDict(Map.from(other.trailer.map));
    for (final key in trailer.keys) {
      if (!mergedTrailer.containsKey(key)) {
        mergedTrailer[key] = trailer[key]!;
      }
    }
    trailer = mergedTrailer;
  }
}

/// A single cross-reference entry.
class CrossRefEntry {
  /// Byte offset in the file (for uncompressed objects).
  final int offset;

  /// Generation number.
  final int generation;

  /// Whether this object is in use (vs. free).
  final bool inUse;

  /// For compressed objects: the object number of the object stream.
  final int? objectStreamNumber;

  /// For compressed objects: index within the object stream.
  final int? objectStreamIndex;

  const CrossRefEntry({
    required this.offset,
    this.generation = 0,
    this.inUse = true,
    this.objectStreamNumber,
    this.objectStreamIndex,
  });

  /// Whether this is a compressed object (in an object stream).
  bool get isCompressed => objectStreamNumber != null;

  @override
  String toString() {
    if (isCompressed) {
      return 'CrossRefEntry(compressed in $objectStreamNumber[$objectStreamIndex])';
    }
    return 'CrossRefEntry(offset: $offset, gen: $generation, ${inUse ? "in-use" : "free"})';
  }
}

/// Parse a traditional cross-reference table from bytes.
PdfCrossRefTable parseCrossRefTable(Uint8List data, int startOffset) {
  final table = PdfCrossRefTable();
  int pos = startOffset;

  // Skip 'xref' keyword and whitespace
  while (pos < data.length &&
      (data[pos] == 0x20 || data[pos] == 0x0A || data[pos] == 0x0D)) {
    pos++;
  }

  // Read subsections
  while (pos < data.length) {
    // Check if we hit 'trailer'
    if (_matchesAt(data, pos, 'trailer')) break;

    // Read subsection header: startObj count
    final headerEnd = _findLineEnd(data, pos);
    final headerStr = String.fromCharCodes(data.sublist(pos, headerEnd)).trim();
    if (headerStr.isEmpty || headerStr.startsWith('trailer')) break;

    final parts = headerStr.split(RegExp(r'\s+'));
    if (parts.length < 2) break;

    final startObj = int.tryParse(parts[0]);
    final count = int.tryParse(parts[1]);
    if (startObj == null || count == null) break;

    pos = _skipLineEnd(data, headerEnd);

    // Read entries: each is exactly 20 bytes
    for (int i = 0; i < count && pos + 19 < data.length; i++) {
      final entryStr = String.fromCharCodes(data.sublist(pos, pos + 20)).trim();
      final entryParts = entryStr.split(RegExp(r'\s+'));
      if (entryParts.length >= 3) {
        final offset = int.tryParse(entryParts[0]) ?? 0;
        final gen = int.tryParse(entryParts[1]) ?? 0;
        final inUse = entryParts[2] == 'n';
        table.addEntry(
          startObj + i,
          CrossRefEntry(offset: offset, generation: gen, inUse: inUse),
        );
      }
      pos += 20;
    }
  }

  return table;
}

/// Parse a cross-reference stream.
PdfCrossRefTable parseCrossRefStream(PdfDict dict, Uint8List decodedData) {
  final table = PdfCrossRefTable();
  table.trailer = dict;

  final wArray = dict.getArray('W');
  if (wArray == null || wArray.length < 3) return table;

  final w = wArray.toIntList();
  final w0 = w[0]; // type field width
  final w1 = w[1]; // field 2 width
  final w2 = w[2]; // field 3 width
  final entrySize = w0 + w1 + w2;

  // Determine index ranges
  List<int> index;
  final indexArray = dict.getArray('Index');
  if (indexArray != null) {
    index = indexArray.toIntList();
  } else {
    final size = dict.getInt('Size') ?? 0;
    index = [0, size];
  }

  int dataPos = 0;
  for (int r = 0; r < index.length - 1; r += 2) {
    final startObj = index[r];
    final count = index[r + 1];

    for (int i = 0;
        i < count && dataPos + entrySize <= decodedData.length;
        i++) {
      int type = 1; // default type
      if (w0 > 0) {
        type = _readInt(decodedData, dataPos, w0);
      }
      final field2 = _readInt(decodedData, dataPos + w0, w1);
      final field3 = _readInt(decodedData, dataPos + w0 + w1, w2);

      switch (type) {
        case 0: // free object
          table.addEntry(
            startObj + i,
            CrossRefEntry(offset: field2, generation: field3, inUse: false),
          );
          break;
        case 1: // uncompressed object
          table.addEntry(
            startObj + i,
            CrossRefEntry(offset: field2, generation: field3, inUse: true),
          );
          break;
        case 2: // compressed object
          table.addEntry(
            startObj + i,
            CrossRefEntry(
              offset: 0,
              generation: 0,
              inUse: true,
              objectStreamNumber: field2,
              objectStreamIndex: field3,
            ),
          );
          break;
      }

      dataPos += entrySize;
    }
  }

  return table;
}

/// Read a big-endian integer from bytes.
int _readInt(Uint8List data, int offset, int width) {
  int result = 0;
  for (int i = 0; i < width; i++) {
    result = (result << 8) | data[offset + i];
  }
  return result;
}

bool _matchesAt(Uint8List data, int pos, String text) {
  if (pos + text.length > data.length) return false;
  for (int i = 0; i < text.length; i++) {
    if (data[pos + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

int _findLineEnd(Uint8List data, int pos) {
  while (pos < data.length && data[pos] != 0x0A && data[pos] != 0x0D) {
    pos++;
  }
  return pos;
}

int _skipLineEnd(Uint8List data, int pos) {
  if (pos < data.length && data[pos] == 0x0D) pos++;
  if (pos < data.length && data[pos] == 0x0A) pos++;
  return pos;
}
