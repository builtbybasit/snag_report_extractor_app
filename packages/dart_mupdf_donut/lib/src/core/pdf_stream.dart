import 'dart:typed_data';
import 'dart:io';

/// PDF stream decompression and compression utilities.
class PdfStreamCodec {
  /// Decode (decompress) a PDF stream given its filter name(s).
  static Uint8List decode(Uint8List data, List<String> filters,
      {Map<String, dynamic>? decodeParms}) {
    var result = data;
    for (final filter in filters) {
      result = _decodeSingle(result, filter, decodeParms: decodeParms);
    }
    return result;
  }

  /// Encode (compress) data with a filter.
  static Uint8List encode(Uint8List data, String filter) {
    switch (filter) {
      case 'FlateDecode':
      case 'Fl':
        return _flateEncode(data);
      case 'ASCIIHexDecode':
      case 'AHx':
        return _asciiHexEncode(data);
      case 'ASCII85Decode':
      case 'A85':
        return _ascii85Encode(data);
      default:
        return data;
    }
  }

  static Uint8List _decodeSingle(Uint8List data, String filter,
      {Map<String, dynamic>? decodeParms}) {
    switch (filter) {
      case 'FlateDecode':
      case 'Fl':
        final decoded = _flateDecode(data);
        if (decodeParms != null) {
          return _applyPredictor(decoded, decodeParms);
        }
        return decoded;
      case 'ASCIIHexDecode':
      case 'AHx':
        return _asciiHexDecode(data);
      case 'ASCII85Decode':
      case 'A85':
        return _ascii85Decode(data);
      case 'LZWDecode':
      case 'LZW':
        return _lzwDecode(data);
      case 'RunLengthDecode':
      case 'RL':
        return _runLengthDecode(data);
      case 'DCTDecode':
      case 'DCT':
        return data; // JPEG — return as-is
      case 'JPXDecode':
        return data; // JPEG2000 — return as-is
      case 'CCITTFaxDecode':
      case 'CCF':
        return data; // CCITT fax — return as-is
      case 'JBIG2Decode':
        return data; // JBIG2 — return as-is
      case 'Crypt':
        return data; // Crypt filter — handled by encryption layer
      default:
        return data; // Unknown filter, return raw
    }
  }

  /// Deflate decompression (zlib).
  static Uint8List _flateDecode(Uint8List data) {
    try {
      return Uint8List.fromList(zlib.decode(data));
    } catch (e) {
      // Try raw deflate (no zlib header)
      try {
        final codec = ZLibCodec(raw: true);
        return Uint8List.fromList(codec.decode(data));
      } catch (_) {
        return data; // Return raw if decompression fails
      }
    }
  }

  /// Deflate compression.
  static Uint8List _flateEncode(Uint8List data) {
    return Uint8List.fromList(zlib.encode(data));
  }

  /// ASCII Hex decoding.
  static Uint8List _asciiHexDecode(Uint8List data) {
    final hex = String.fromCharCodes(data).replaceAll(RegExp(r'\s'), '');
    final end = hex.indexOf('>');
    final cleanHex = end >= 0 ? hex.substring(0, end) : hex;
    final padded = cleanHex.length.isOdd ? '${cleanHex}0' : cleanHex;
    final result = Uint8List(padded.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// ASCII Hex encoding.
  static Uint8List _asciiHexEncode(Uint8List data) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    return Uint8List.fromList('$hex>'.codeUnits);
  }

  /// ASCII85 (Base85) decoding.
  static Uint8List _ascii85Decode(Uint8List data) {
    String input = String.fromCharCodes(data).trim();
    if (input.startsWith('<~')) input = input.substring(2);
    if (input.endsWith('~>')) input = input.substring(0, input.length - 2);

    final result = <int>[];
    int i = 0;
    while (i < input.length) {
      if (input[i] == 'z') {
        result.addAll([0, 0, 0, 0]);
        i++;
        continue;
      }

      final group = <int>[];
      while (group.length < 5 && i < input.length) {
        final c = input.codeUnitAt(i);
        if (c >= 33 && c <= 117) {
          group.add(c - 33);
        }
        i++;
      }

      if (group.isEmpty) break;

      // Pad with 'u' (84)
      final padCount = 5 - group.length;
      while (group.length < 5) {
        group.add(84);
      }

      int value = 0;
      for (int j = 0; j < 5; j++) {
        value = value * 85 + group[j];
      }

      final bytes = [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
      result.addAll(bytes.sublist(0, 4 - padCount));
    }

    return Uint8List.fromList(result);
  }

  /// ASCII85 encoding.
  static Uint8List _ascii85Encode(Uint8List data) {
    final result = StringBuffer('<~');
    int i = 0;
    while (i < data.length) {
      int value = 0;
      int count = 0;
      for (int j = 0; j < 4 && i + j < data.length; j++) {
        value = (value << 8) | data[i + j];
        count++;
      }
      // Pad remaining bytes
      for (int j = count; j < 4; j++) {
        value <<= 8;
      }

      if (value == 0 && count == 4) {
        result.write('z');
      } else {
        final encoded = <int>[];
        for (int j = 4; j >= 0; j--) {
          encoded.insert(0, (value % 85) + 33);
          value ~/= 85;
        }
        result.write(String.fromCharCodes(encoded.sublist(0, count + 1)));
      }
      i += 4;
    }
    result.write('~>');
    return Uint8List.fromList(result.toString().codeUnits);
  }

  /// LZW decompression.
  static Uint8List _lzwDecode(Uint8List data) {
    // Basic LZW implementation
    final result = <int>[];
    int bitPos = 0;
    int codeSize = 9;
    final clearCode = 256;
    final endCode = 257;
    var nextCode = 258;
    final maxCode = 4096;

    final table = <int, List<int>>{};
    for (int i = 0; i < 256; i++) {
      table[i] = [i];
    }

    int readBits(int count) {
      int result = 0;
      for (int i = 0; i < count; i++) {
        final byteIndex = (bitPos + i) ~/ 8;
        final bitIndex = 7 - ((bitPos + i) % 8);
        if (byteIndex < data.length) {
          result = (result << 1) | ((data[byteIndex] >> bitIndex) & 1);
        }
      }
      bitPos += count;
      return result;
    }

    var code = readBits(codeSize);
    if (code == clearCode) {
      codeSize = 9;
      nextCode = 258;
      table.clear();
      for (int i = 0; i < 256; i++) {
        table[i] = [i];
      }
      code = readBits(codeSize);
    }
    if (code == endCode || !table.containsKey(code))
      return Uint8List.fromList(result);

    var prevEntry = List<int>.from(table[code]!);
    result.addAll(prevEntry);

    while (bitPos < data.length * 8) {
      code = readBits(codeSize);
      if (code == endCode) break;
      if (code == clearCode) {
        codeSize = 9;
        nextCode = 258;
        table.clear();
        for (int i = 0; i < 256; i++) {
          table[i] = [i];
        }
        code = readBits(codeSize);
        if (code == endCode) break;
        if (!table.containsKey(code)) break;
        prevEntry = List<int>.from(table[code]!);
        result.addAll(prevEntry);
        continue;
      }

      List<int> entry;
      if (table.containsKey(code)) {
        entry = table[code]!;
      } else if (code == nextCode) {
        entry = [...prevEntry, prevEntry[0]];
      } else {
        break;
      }

      result.addAll(entry);
      if (nextCode < maxCode) {
        table[nextCode] = [...prevEntry, entry[0]];
        nextCode++;
        if (nextCode >= (1 << codeSize) && codeSize < 12) {
          codeSize++;
        }
      }
      prevEntry = List<int>.from(entry);
    }

    return Uint8List.fromList(result);
  }

  /// RunLength decoding.
  static Uint8List _runLengthDecode(Uint8List data) {
    final result = <int>[];
    int i = 0;
    while (i < data.length) {
      final length = data[i];
      if (length == 128) break; // EOD
      if (length < 128) {
        // Copy next length+1 bytes
        final count = length + 1;
        for (int j = 0; j < count && i + 1 + j < data.length; j++) {
          result.add(data[i + 1 + j]);
        }
        i += 1 + count;
      } else {
        // Repeat next byte (257-length) times
        final count = 257 - length;
        if (i + 1 < data.length) {
          for (int j = 0; j < count; j++) {
            result.add(data[i + 1]);
          }
        }
        i += 2;
      }
    }
    return Uint8List.fromList(result);
  }

  /// Apply PNG predictor to decoded data.
  static Uint8List _applyPredictor(Uint8List data, Map<String, dynamic> parms) {
    final predictor = parms['Predictor'] as int? ?? 1;
    if (predictor == 1) return data; // No predictor

    final columns = parms['Columns'] as int? ?? 1;
    final colors = parms['Colors'] as int? ?? 1;
    final bpc = parms['BitsPerComponent'] as int? ?? 8;
    final bytesPerPixel = (colors * bpc + 7) ~/ 8;
    final rowBytes = (columns * colors * bpc + 7) ~/ 8;

    if (predictor == 2) {
      // TIFF predictor
      return _tiffPredictor(data, columns, colors, bpc);
    }

    if (predictor >= 10 && predictor <= 15) {
      // PNG predictors
      return _pngPredictor(data, rowBytes, bytesPerPixel);
    }

    return data;
  }

  static Uint8List _tiffPredictor(
      Uint8List data, int columns, int colors, int bpc) {
    // Simplified TIFF predictor for 8-bit components
    if (bpc != 8) return data;
    final rowBytes = columns * colors;
    final result = Uint8List(data.length);
    for (int row = 0; row * rowBytes < data.length; row++) {
      final rowStart = row * rowBytes;
      for (int i = 0; i < rowBytes && rowStart + i < data.length; i++) {
        final left = i >= colors ? result[rowStart + i - colors] : 0;
        result[rowStart + i] = (data[rowStart + i] + left) & 0xFF;
      }
    }
    return result;
  }

  static Uint8List _pngPredictor(
      Uint8List data, int rowBytes, int bytesPerPixel) {
    final result = <int>[];
    int pos = 0;
    Uint8List? prevRow;

    while (pos < data.length) {
      if (pos >= data.length) break;
      final filterByte = data[pos++];
      final row = Uint8List(rowBytes);
      final endPos = pos + rowBytes;

      for (int i = 0; i < rowBytes && pos < data.length && pos < endPos; i++) {
        final raw = data[pos++];
        final left = i >= bytesPerPixel ? row[i - bytesPerPixel] : 0;
        final up = prevRow != null ? prevRow[i] : 0;
        final upLeft = (prevRow != null && i >= bytesPerPixel)
            ? prevRow[i - bytesPerPixel]
            : 0;

        switch (filterByte) {
          case 0: // None
            row[i] = raw;
            break;
          case 1: // Sub
            row[i] = (raw + left) & 0xFF;
            break;
          case 2: // Up
            row[i] = (raw + up) & 0xFF;
            break;
          case 3: // Average
            row[i] = (raw + ((left + up) >> 1)) & 0xFF;
            break;
          case 4: // Paeth
            row[i] = (raw + _paeth(left, up, upLeft)) & 0xFF;
            break;
          default:
            row[i] = raw;
        }
      }

      result.addAll(row);
      prevRow = row;
    }

    return Uint8List.fromList(result);
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }
}
