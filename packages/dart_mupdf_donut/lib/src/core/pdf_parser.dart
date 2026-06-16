import 'dart:typed_data';
import 'pdf_objects.dart';
import 'pdf_cross_ref.dart';
import 'pdf_stream.dart';
import 'pdf_encryption.dart';

/// Low-level PDF parser — reads PDF bytes and produces PDF objects.
///
/// This is the engine that powers the entire library, handling:
/// - PDF header parsing
/// - Cross-reference table reading (traditional + streams)
/// - Indirect object parsing
/// - Stream decompression
/// - Object resolution
/// - Incremental update handling
class PdfParser {
  /// The raw PDF bytes.
  final Uint8List data;

  /// Parsed cross-reference table.
  late PdfCrossRefTable crossRef;

  /// Cache of parsed indirect objects.
  final Map<int, PdfIndirectObject> _objectCache = {};

  /// Encryption handler (null if no encryption).
  PdfEncryption? encryption;

  /// PDF version string.
  String pdfVersion = '1.0';

  /// Whether the PDF is linearized.
  bool isLinearized = false;

  PdfParser(this.data) {
    _parse();
  }

  /// Parse the PDF structure.
  void _parse() {
    _parseHeader();
    final xrefOffset = _findXRefOffset();
    crossRef = _parseCrossRef(xrefOffset);
    _detectEncryption();
    _detectLinearization();
  }

  /// Parse PDF header to get version.
  void _parseHeader() {
    // Look for %PDF-x.y
    final headerEnd = _indexOf(data, 0x0A, 0) ?? 20;
    final header =
        String.fromCharCodes(data.sublist(0, headerEnd.clamp(0, 20)));
    final match = RegExp(r'%PDF-(\d+\.\d+)').firstMatch(header);
    if (match != null) {
      pdfVersion = match.group(1)!;
    }
  }

  /// Find the xref offset from the end of file.
  int _findXRefOffset() {
    // Search backwards for 'startxref'
    final searchStart = (data.length - 1024).clamp(0, data.length);
    final tail = String.fromCharCodes(data.sublist(searchStart));
    final idx = tail.lastIndexOf('startxref');
    if (idx < 0) {
      throw FormatException('Cannot find startxref in PDF');
    }

    final afterStartxref = tail.substring(idx + 9).trim();
    final lines = afterStartxref.split(RegExp(r'\s+'));
    final offset = int.tryParse(lines[0]);
    if (offset == null) {
      throw FormatException('Invalid startxref offset');
    }
    return offset;
  }

  /// Parse cross-reference table (handles both traditional and stream format).
  PdfCrossRefTable _parseCrossRef(int offset) {
    // Check if it's a traditional xref table or an xref stream
    int pos = offset;
    while (pos < data.length && _isWhitespace(data[pos])) pos++;

    if (_matchesAt(pos, 'xref')) {
      // Traditional xref table
      pos += 4;
      final table = parseCrossRefTable(data, pos);

      // Parse trailer
      final trailerPos = _findString(offset, 'trailer');
      if (trailerPos >= 0) {
        int dictStart = trailerPos + 7;
        while (dictStart < data.length && _isWhitespace(data[dictStart])) {
          dictStart++;
        }
        table.trailer = _parseObjectAt(dictStart).$1 as PdfDict;
      }

      // Handle /Prev for incremental updates
      final prevOffset = table.trailer.getInt('Prev');
      if (prevOffset != null && prevOffset > 0 && prevOffset < data.length) {
        try {
          final prevTable = _parseCrossRef(prevOffset);
          prevTable.merge(table);
          return prevTable;
        } catch (_) {
          // Ignore errors in previous xref tables
        }
      }

      return table;
    } else {
      // Cross-reference stream
      final (obj, _) = _parseObjectAt(pos);
      if (obj is PdfIndirectObject && obj.object is PdfStream) {
        final stream = obj.object as PdfStream;
        final decodedData = PdfStreamCodec.decode(stream.data, stream.filters);
        final table = parseCrossRefStream(stream.dict, decodedData);

        // Handle /Prev
        final prevOffset = table.trailer.getInt('Prev');
        if (prevOffset != null && prevOffset > 0 && prevOffset < data.length) {
          try {
            final prevTable = _parseCrossRef(prevOffset);
            prevTable.merge(table);
            return prevTable;
          } catch (_) {}
        }

        return table;
      }
      throw FormatException('Invalid cross-reference at offset $offset');
    }
  }

  /// Detect and set up encryption.
  void _detectEncryption() {
    final encryptRef = crossRef.trailer.getRef('Encrypt');
    if (encryptRef == null && !crossRef.trailer.containsKey('Encrypt')) return;

    PdfDict? encryptDict;
    if (encryptRef != null) {
      final obj = getObject(encryptRef.objectNumber);
      encryptDict = obj?.dict;
    } else {
      encryptDict = crossRef.trailer.getDict('Encrypt');
    }

    if (encryptDict == null) return;

    // Get document ID
    Uint8List docId = Uint8List(0);
    final idArray = crossRef.trailer.getArray('ID');
    if (idArray != null && idArray.length > 0) {
      final first = idArray[0];
      if (first is PdfString) {
        docId = first.bytes;
      }
    }

    encryption = PdfEncryption(encryptDict: encryptDict, documentId: docId);
  }

  /// Detect linearization.
  void _detectLinearization() {
    // Check first object for /Linearized key
    try {
      final firstObjects = crossRef.liveObjectNumbers;
      if (firstObjects.isNotEmpty) {
        final obj = getObject(firstObjects.first);
        if (obj?.dict?.containsKey('Linearized') == true) {
          isLinearized = true;
        }
      }
    } catch (_) {}
  }

  /// Get a resolved indirect object by object number.
  PdfIndirectObject? getObject(int objectNumber) {
    // Check cache first
    if (_objectCache.containsKey(objectNumber)) {
      return _objectCache[objectNumber];
    }

    final entry = crossRef.entries[objectNumber];
    if (entry == null || !entry.inUse) return null;

    PdfIndirectObject? obj;

    if (entry.isCompressed) {
      // Object is in an object stream
      obj = _getCompressedObject(
        objectNumber,
        entry.objectStreamNumber!,
        entry.objectStreamIndex!,
      );
    } else {
      // Regular uncompressed object
      try {
        final (parsed, _) = _parseObjectAt(entry.offset);
        if (parsed is PdfIndirectObject) {
          obj = parsed;
        }
      } catch (e) {
        return null;
      }
    }

    if (obj != null) {
      _objectCache[objectNumber] = obj;
    }
    return obj;
  }

  /// Get an object from an object stream.
  PdfIndirectObject? _getCompressedObject(
      int objectNumber, int streamObjNum, int index) {
    final streamObj = getObject(streamObjNum);
    if (streamObj == null || !streamObj.isStream) return null;

    final stream = streamObj.object as PdfStream;
    final decodedData = PdfStreamCodec.decode(stream.data, stream.filters);
    /* n = */ stream.dict.getInt('N') ?? 0;
    final first = stream.dict.getInt('First') ?? 0;

    // Parse the object number/offset pairs
    final header = String.fromCharCodes(decodedData.sublist(0, first));
    final parts = header.trim().split(RegExp(r'\s+'));

    int? targetOffset;
    int? nextOffset;
    for (int i = 0; i < parts.length - 1; i += 2) {
      final objNum = int.tryParse(parts[i]);
      final offset = int.tryParse(parts[i + 1]);
      if (objNum == objectNumber && offset != null) {
        targetOffset = first + offset;
        // Find the next object's offset for bounds
        if (i + 3 < parts.length) {
          nextOffset =
              first + (int.tryParse(parts[i + 3]) ?? decodedData.length);
        }
        break;
      }
    }

    if (targetOffset == null) return null;

    // Parse the object from the decoded stream data
    final end = nextOffset ?? decodedData.length;
    final objData = decodedData.sublist(targetOffset, end);
    try {
      final (parsed, _) = _parseValue(objData, 0);
      return PdfIndirectObject(objectNumber, 0, parsed);
    } catch (_) {
      return null;
    }
  }

  /// Resolve a PdfRef to its actual object.
  PdfObject resolve(PdfObject obj) {
    if (obj is PdfRef) {
      final indirect = getObject(obj.objectNumber);
      if (indirect != null) return indirect.object;
      return PdfNull();
    }
    return obj;
  }

  /// Resolve a reference, returning the dict if it's a stream.
  PdfObject resolveDeep(PdfObject obj) {
    var resolved = resolve(obj);
    if (resolved is PdfStream) return resolved.dict;
    return resolved;
  }

  /// Get the trailer dictionary.
  PdfDict get trailer => crossRef.trailer;

  /// Get the root (catalog) dictionary.
  PdfDict? get catalog {
    final rootRef = trailer.getRef('Root');
    if (rootRef == null) return null;
    final obj = getObject(rootRef.objectNumber);
    return obj?.dict;
  }

  /// Get the Info dictionary.
  PdfDict? get info {
    final infoRef = trailer.getRef('Info');
    if (infoRef == null) return null;
    final obj = getObject(infoRef.objectNumber);
    return obj?.dict;
  }

  /// Get number of objects.
  int get objectCount => crossRef.size;

  /// Get all page object numbers in order.
  List<int> getPageObjectNumbers() {
    final pages = <int>[];
    final cat = catalog;
    if (cat == null) return pages;

    final pagesRef = cat.getRef('Pages');
    if (pagesRef == null) return pages;

    _collectPages(pagesRef.objectNumber, pages);
    return pages;
  }

  void _collectPages(int objNum, List<int> pages) {
    final obj = getObject(objNum);
    if (obj == null) return;

    final dict = obj.dict;
    if (dict == null) return;

    final type = dict.getName('Type');
    if (type == 'Page') {
      pages.add(objNum);
    } else if (type == 'Pages') {
      final kids = dict.getArray('Kids');
      if (kids != null) {
        for (final kid in kids.items) {
          if (kid is PdfRef) {
            _collectPages(kid.objectNumber, pages);
          }
        }
      }
    }
  }

  /// Get a page dict by 0-based index.
  PdfDict? getPageDict(int pageIndex) {
    final pageNums = getPageObjectNumbers();
    if (pageIndex < 0 || pageIndex >= pageNums.length) return null;
    return getObject(pageNums[pageIndex])?.dict;
  }

  /// Get page count.
  int get pageCount {
    final cat = catalog;
    if (cat == null) return 0;
    final pagesRef = cat.getRef('Pages');
    if (pagesRef == null) return 0;
    final pagesObj = getObject(pagesRef.objectNumber);
    return pagesObj?.dict?.getInt('Count') ?? 0;
  }

  /// Get decoded stream data for an object.
  Uint8List? getStreamData(int objectNumber) {
    final obj = getObject(objectNumber);
    if (obj == null || !obj.isStream) return null;

    final stream = obj.object as PdfStream;
    var streamData = stream.data;

    // Decrypt if needed
    if (encryption != null && encryption!.isAuthenticated) {
      streamData =
          encryption!.decrypt(streamData, objectNumber, obj.generation);
    }

    // Decompress
    final filters = stream.filters;
    if (filters.isNotEmpty) {
      // Get DecodeParms
      Map<String, dynamic>? decodeParms;
      final dp = stream.dict['DecodeParms'];
      if (dp is PdfDict) {
        decodeParms = {};
        for (final key in dp.keys) {
          final val = dp[key];
          if (val is PdfInt) decodeParms[key] = val.value;
          if (val is PdfBool) decodeParms[key] = val.value;
        }
      }
      return PdfStreamCodec.decode(streamData, filters,
          decodeParms: decodeParms);
    }

    return streamData;
  }

  // --- Tokenizer / Parser ---

  /// Parse a PDF value starting at the given offset.
  (PdfObject, int) _parseObjectAt(int offset) {
    int pos = offset;
    while (pos < data.length && _isWhitespace(data[pos])) pos++;

    // Try to parse as indirect object: "N G obj ... endobj"
    final savedPos = pos;
    final objNum = _readInt(pos);
    if (objNum != null) {
      pos = objNum.$2;
      while (pos < data.length && _isWhitespace(data[pos])) pos++;
      final gen = _readInt(pos);
      if (gen != null) {
        pos = gen.$2;
        while (pos < data.length && _isWhitespace(data[pos])) pos++;
        if (_matchesAt(pos, 'obj')) {
          pos += 3;
          while (pos < data.length && _isWhitespace(data[pos])) pos++;

          final (value, nextPos) = _parseValue(data, pos);
          pos = nextPos;
          while (pos < data.length && _isWhitespace(data[pos])) pos++;

          // Check for stream
          if (_matchesAt(pos, 'stream')) {
            pos += 6;
            // Skip \r\n or \n after 'stream'
            if (pos < data.length && data[pos] == 0x0D) pos++;
            if (pos < data.length && data[pos] == 0x0A) pos++;

            final dict = value is PdfDict ? value : PdfDict();
            int streamLength = dict.getInt('Length') ?? 0;

            // Resolve indirect length
            final lengthRef = dict.getRef('Length');
            if (lengthRef != null) {
              final lenObj = getObject(lengthRef.objectNumber);
              if (lenObj?.object is PdfInt) {
                streamLength = (lenObj!.object as PdfInt).value;
              }
            }

            // Bound check
            if (pos + streamLength > data.length) {
              streamLength = data.length - pos;
            }

            final streamData = data.sublist(pos, pos + streamLength);
            pos += streamLength;

            final stream = PdfStream(dict, Uint8List.fromList(streamData));
            return (PdfIndirectObject(objNum.$1, gen.$1, stream), pos);
          }

          return (PdfIndirectObject(objNum.$1, gen.$1, value), pos);
        }
      }
    }

    // Not an indirect object, parse as value
    return _parseValue(data, savedPos);
  }

  /// Parse a single PDF value from bytes.
  (PdfObject, int) _parseValue(Uint8List bytes, int pos) {
    while (pos < bytes.length && _isWhitespace(bytes[pos])) pos++;
    if (pos >= bytes.length) return (PdfNull(), pos);

    // Comment
    if (bytes[pos] == 0x25) {
      // %
      while (pos < bytes.length && bytes[pos] != 0x0A && bytes[pos] != 0x0D) {
        pos++;
      }
      while (pos < bytes.length && _isWhitespace(bytes[pos])) pos++;
      return _parseValue(bytes, pos);
    }

    // Dictionary or hex string
    if (bytes[pos] == 0x3C) {
      // <
      if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3C) {
        // <<  — dictionary
        return _parseDict(bytes, pos + 2);
      }
      // Hex string
      return _parseHexString(bytes, pos + 1);
    }

    // Array
    if (bytes[pos] == 0x5B) {
      // [
      return _parseArray(bytes, pos + 1);
    }

    // Literal string
    if (bytes[pos] == 0x28) {
      // (
      return _parseLiteralString(bytes, pos + 1);
    }

    // Name
    if (bytes[pos] == 0x2F) {
      // /
      return _parseName(bytes, pos + 1);
    }

    // Boolean true
    if (_matchesBytesAt(bytes, pos, 'true')) {
      return (PdfBool(true), pos + 4);
    }

    // Boolean false
    if (_matchesBytesAt(bytes, pos, 'false')) {
      return (PdfBool(false), pos + 5);
    }

    // Null
    if (_matchesBytesAt(bytes, pos, 'null')) {
      return (PdfNull(), pos + 4);
    }

    // Number or indirect reference
    return _parseNumberOrRef(bytes, pos);
  }

  (PdfDict, int) _parseDict(Uint8List bytes, int pos) {
    final dict = PdfDict();

    while (pos < bytes.length) {
      while (pos < bytes.length && _isWhitespace(bytes[pos])) pos++;

      // Check for >>
      if (pos + 1 < bytes.length &&
          bytes[pos] == 0x3E &&
          bytes[pos + 1] == 0x3E) {
        return (dict, pos + 2);
      }

      // Skip comments
      if (bytes[pos] == 0x25) {
        while (pos < bytes.length && bytes[pos] != 0x0A && bytes[pos] != 0x0D) {
          pos++;
        }
        continue;
      }

      // Parse key (must be a name)
      if (bytes[pos] != 0x2F) break; // not a name
      final (key, keyEnd) = _parseName(bytes, pos + 1);
      pos = keyEnd;

      // Parse value
      final (value, valueEnd) = _parseValue(bytes, pos);
      pos = valueEnd;

      dict[key.value] = value;
    }

    return (dict, pos);
  }

  (PdfArray, int) _parseArray(Uint8List bytes, int pos) {
    final items = <PdfObject>[];

    while (pos < bytes.length) {
      while (pos < bytes.length && _isWhitespace(bytes[pos])) pos++;

      if (pos >= bytes.length) break;
      if (bytes[pos] == 0x5D) {
        // ]
        return (PdfArray(items), pos + 1);
      }

      final (value, valueEnd) = _parseValue(bytes, pos);
      pos = valueEnd;
      items.add(value);
    }

    return (PdfArray(items), pos);
  }

  (PdfName, int) _parseName(Uint8List bytes, int pos) {
    final start = pos;
    while (pos < bytes.length &&
        !_isWhitespace(bytes[pos]) &&
        !_isDelimiter(bytes[pos])) {
      pos++;
    }
    var name = String.fromCharCodes(bytes.sublist(start, pos));
    // Handle #xx hex escapes
    name = name.replaceAllMapped(RegExp(r'#([0-9a-fA-F]{2})'), (m) {
      return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
    });
    return (PdfName('/$name'), pos);
  }

  (PdfString, int) _parseLiteralString(Uint8List bytes, int pos) {
    final buffer = <int>[];
    int parenDepth = 1;
    bool escape = false;

    while (pos < bytes.length && parenDepth > 0) {
      if (escape) {
        switch (bytes[pos]) {
          case 0x6E: // n
            buffer.add(0x0A);
            break;
          case 0x72: // r
            buffer.add(0x0D);
            break;
          case 0x74: // t
            buffer.add(0x09);
            break;
          case 0x62: // b
            buffer.add(0x08);
            break;
          case 0x66: // f
            buffer.add(0x0C);
            break;
          case 0x28: // (
            buffer.add(0x28);
            break;
          case 0x29: // )
            buffer.add(0x29);
            break;
          case 0x5C: // backslash
            buffer.add(0x5C);
            break;
          case 0x0D: // \r — line continuation
            if (pos + 1 < bytes.length && bytes[pos + 1] == 0x0A) pos++;
            break;
          case 0x0A: // \n — line continuation
            break;
          default:
            // Octal escape
            if (bytes[pos] >= 0x30 && bytes[pos] <= 0x37) {
              int octal = bytes[pos] - 0x30;
              if (pos + 1 < bytes.length &&
                  bytes[pos + 1] >= 0x30 &&
                  bytes[pos + 1] <= 0x37) {
                octal = octal * 8 + (bytes[++pos] - 0x30);
                if (pos + 1 < bytes.length &&
                    bytes[pos + 1] >= 0x30 &&
                    bytes[pos + 1] <= 0x37) {
                  octal = octal * 8 + (bytes[++pos] - 0x30);
                }
              }
              buffer.add(octal & 0xFF);
            } else {
              buffer.add(bytes[pos]);
            }
        }
        escape = false;
        pos++;
        continue;
      }

      if (bytes[pos] == 0x5C) {
        escape = true;
        pos++;
        continue;
      }

      if (bytes[pos] == 0x28) parenDepth++;
      if (bytes[pos] == 0x29) {
        parenDepth--;
        if (parenDepth == 0) {
          pos++;
          break;
        }
      }

      buffer.add(bytes[pos]);
      pos++;
    }

    return (PdfString(String.fromCharCodes(buffer)), pos);
  }

  (PdfString, int) _parseHexString(Uint8List bytes, int pos) {
    final hexChars = <int>[];
    while (pos < bytes.length && bytes[pos] != 0x3E) {
      if (!_isWhitespace(bytes[pos])) {
        hexChars.add(bytes[pos]);
      }
      pos++;
    }
    if (pos < bytes.length) pos++; // skip >

    final hex = String.fromCharCodes(hexChars);
    final padded = hex.length.isOdd ? '${hex}0' : hex;
    final buffer = <int>[];
    for (int i = 0; i < padded.length; i += 2) {
      buffer.add(int.parse(padded.substring(i, i + 2), radix: 16));
    }
    return (PdfString(String.fromCharCodes(buffer), isHex: true), pos);
  }

  (PdfObject, int) _parseNumberOrRef(Uint8List bytes, int pos) {
    final numStart = pos;
    bool hasDecimal = false;
    bool hasMinus = false;
    bool hasPlus = false;

    if (pos < bytes.length && (bytes[pos] == 0x2D || bytes[pos] == 0x2B)) {
      if (bytes[pos] == 0x2D) hasMinus = true;
      if (bytes[pos] == 0x2B) hasPlus = true;
      pos++;
    }

    while (pos < bytes.length &&
        ((bytes[pos] >= 0x30 && bytes[pos] <= 0x39) || bytes[pos] == 0x2E)) {
      if (bytes[pos] == 0x2E) hasDecimal = true;
      pos++;
    }

    if (pos == numStart || (pos == numStart + 1 && (hasMinus || hasPlus))) {
      // Not a number — return as-is, skip token
      while (pos < bytes.length &&
          !_isWhitespace(bytes[pos]) &&
          !_isDelimiter(bytes[pos])) {
        pos++;
      }
      return (PdfNull(), pos);
    }

    final numStr = String.fromCharCodes(bytes.sublist(numStart, pos));

    if (hasDecimal) {
      return (PdfReal(double.tryParse(numStr) ?? 0.0), pos);
    }

    final intVal = int.tryParse(numStr) ?? 0;

    // Check if this is an indirect reference: N G R
    final savedPos2 = pos;
    while (pos < bytes.length && _isWhitespace(bytes[pos])) pos++;

    if (pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
      final genStart = pos;
      while (pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
        pos++;
      }
      final genStr = String.fromCharCodes(bytes.sublist(genStart, pos));
      while (pos < bytes.length && _isWhitespace(bytes[pos])) pos++;

      if (pos < bytes.length && bytes[pos] == 0x52) {
        // 'R'
        // Check it's followed by whitespace or delimiter
        if (pos + 1 >= bytes.length ||
            _isWhitespace(bytes[pos + 1]) ||
            _isDelimiter(bytes[pos + 1])) {
          return (PdfRef(intVal, int.tryParse(genStr) ?? 0), pos + 1);
        }
      }
    }

    // Just a number
    return (PdfInt(intVal), savedPos2);
  }

  // --- Helper methods ---

  (int, int)? _readInt(int pos) {
    while (pos < data.length && _isWhitespace(data[pos])) pos++;
    final start = pos;
    if (pos < data.length && (data[pos] == 0x2D || data[pos] == 0x2B)) pos++;
    while (pos < data.length && data[pos] >= 0x30 && data[pos] <= 0x39) {
      pos++;
    }
    if (pos == start) return null;
    final val = int.tryParse(String.fromCharCodes(data.sublist(start, pos)));
    if (val == null) return null;
    return (val, pos);
  }

  bool _matchesAt(int pos, String text) {
    if (pos + text.length > data.length) return false;
    for (int i = 0; i < text.length; i++) {
      if (data[pos + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static bool _matchesBytesAt(Uint8List bytes, int pos, String text) {
    if (pos + text.length > bytes.length) return false;
    for (int i = 0; i < text.length; i++) {
      if (bytes[pos + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  int _findString(int startPos, String text) {
    final textBytes = text.codeUnits;
    for (int i = startPos; i < data.length - textBytes.length; i++) {
      bool found = true;
      for (int j = 0; j < textBytes.length; j++) {
        if (data[i + j] != textBytes[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  static int? _indexOf(Uint8List data, int byte, int start) {
    for (int i = start; i < data.length; i++) {
      if (data[i] == byte) return i;
    }
    return null;
  }

  static bool _isWhitespace(int byte) =>
      byte == 0x00 ||
      byte == 0x09 ||
      byte == 0x0A ||
      byte == 0x0C ||
      byte == 0x0D ||
      byte == 0x20;

  static bool _isDelimiter(int byte) =>
      byte == 0x28 || // (
      byte == 0x29 || // )
      byte == 0x3C || // <
      byte == 0x3E || // >
      byte == 0x5B || // [
      byte == 0x5D || // ]
      byte == 0x7B || // {
      byte == 0x7D || // }
      byte == 0x2F || // /
      byte == 0x25; // %
}
