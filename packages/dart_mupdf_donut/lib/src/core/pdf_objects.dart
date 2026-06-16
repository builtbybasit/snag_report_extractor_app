import 'dart:typed_data';

/// Base class for all PDF objects.
abstract class PdfObject {
  /// Serialize this object to PDF syntax bytes.
  String toPdfString();

  /// Serialize this object to PDF syntax string.
  String serialize() => toPdfString();
}

/// PDF null object.
class PdfNull extends PdfObject {
  @override
  String toPdfString() => 'null';

  @override
  String toString() => 'null';
}

/// PDF boolean.
class PdfBool extends PdfObject {
  final bool value;
  PdfBool(this.value);

  @override
  String toPdfString() => value ? 'true' : 'false';

  @override
  String toString() => value.toString();
}

/// PDF integer.
class PdfInt extends PdfObject {
  final int value;
  PdfInt(this.value);

  @override
  String toPdfString() => value.toString();

  @override
  String toString() => value.toString();
}

/// PDF real number.
class PdfReal extends PdfObject {
  final double value;
  PdfReal(this.value);

  @override
  String toPdfString() {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    // Use up to 6 decimal places, trim trailing zeros
    String s = value.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  String toString() => value.toString();
}

/// PDF number (can be int or real).
class PdfNumber extends PdfObject {
  final num value;
  PdfNumber(this.value);

  @override
  String toPdfString() {
    if (value is int) return value.toString();
    final d = value.toDouble();
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toString();
  }

  @override
  String toString() => value.toString();
}

/// PDF string (literal or hex).
class PdfString extends PdfObject {
  final String value;
  final bool isHex;

  PdfString(this.value, {this.isHex = false});

  /// Create from raw bytes.
  factory PdfString.fromBytes(Uint8List bytes) {
    return PdfString(String.fromCharCodes(bytes));
  }

  /// Decode to Dart string, handling PDF encoding.
  String get decoded {
    if (value.startsWith('\xfe\xff')) {
      // UTF-16BE BOM
      final bytes = value.codeUnits;
      final buffer = StringBuffer();
      for (int i = 2; i < bytes.length - 1; i += 2) {
        buffer.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
      }
      return buffer.toString();
    }
    return _decodePdfDocEncoding(value);
  }

  /// Get raw bytes.
  Uint8List get bytes => Uint8List.fromList(value.codeUnits);

  @override
  String toPdfString() {
    if (isHex) {
      final hex = value.codeUnits
          .map((c) => c.toRadixString(16).padLeft(2, '0'))
          .join();
      return '<$hex>';
    }
    return '(${_escapePdfString(value)})';
  }

  @override
  String toString() => decoded;

  static String _escapePdfString(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  static String _decodePdfDocEncoding(String s) {
    // PDFDocEncoding is mostly Latin-1 with some differences in 0x80-0x9F
    // For simplicity, treat as Latin-1
    return s;
  }
}

/// PDF name object (e.g., /Type, /Page).
class PdfName extends PdfObject {
  final String name;
  PdfName(this.name);

  /// Name without leading '/'.
  String get value => name.startsWith('/') ? name.substring(1) : name;

  @override
  String toPdfString() => name.startsWith('/') ? name : '/$name';

  @override
  bool operator ==(Object other) => other is PdfName && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => name;
}

/// PDF array.
class PdfArray extends PdfObject {
  final List<PdfObject> items;

  PdfArray([List<PdfObject>? items]) : items = items ?? [];

  int get length => items.length;
  bool get isEmpty => items.isEmpty;

  PdfObject operator [](int index) => items[index];
  void operator []=(int index, PdfObject value) => items[index] = value;

  void add(PdfObject item) => items.add(item);

  /// Get as list of numbers.
  List<double> toDoubleList() {
    return items.map((item) {
      if (item is PdfInt) return item.value.toDouble();
      if (item is PdfReal) return item.value;
      if (item is PdfNumber) return item.value.toDouble();
      return 0.0;
    }).toList();
  }

  /// Get as list of ints.
  List<int> toIntList() {
    return items.map((item) {
      if (item is PdfInt) return item.value;
      if (item is PdfReal) return item.value.toInt();
      if (item is PdfNumber) return item.value.toInt();
      return 0;
    }).toList();
  }

  @override
  String toPdfString() {
    final inner = items.map((i) => i.toPdfString()).join(' ');
    return '[$inner]';
  }

  @override
  String toString() => '[${items.join(', ')}]';
}

/// PDF dictionary.
class PdfDict extends PdfObject {
  final Map<String, PdfObject> map;

  PdfDict([Map<String, PdfObject>? map]) : map = map ?? {};

  PdfObject? operator [](String key) => map[key];
  void operator []=(String key, PdfObject value) => map[key] = value;

  bool containsKey(String key) => map.containsKey(key);

  Iterable<String> get keys => map.keys;
  Iterable<PdfObject> get values => map.values;
  int get length => map.length;
  bool get isEmpty => map.isEmpty;

  void remove(String key) => map.remove(key);

  /// Get a string value.
  String? getString(String key) {
    final obj = map[key];
    if (obj is PdfString) return obj.decoded;
    if (obj is PdfName) return obj.value;
    return null;
  }

  /// Get an int value.
  int? getInt(String key) {
    final obj = map[key];
    if (obj is PdfInt) return obj.value;
    if (obj is PdfReal) return obj.value.toInt();
    if (obj is PdfNumber) return obj.value.toInt();
    return null;
  }

  /// Get a double value.
  double? getDouble(String key) {
    final obj = map[key];
    if (obj is PdfInt) return obj.value.toDouble();
    if (obj is PdfReal) return obj.value;
    if (obj is PdfNumber) return obj.value.toDouble();
    return null;
  }

  /// Get a bool value.
  bool? getBool(String key) {
    final obj = map[key];
    if (obj is PdfBool) return obj.value;
    return null;
  }

  /// Get a name value (without /).
  String? getName(String key) {
    final obj = map[key];
    if (obj is PdfName) return obj.value;
    return null;
  }

  /// Get as array.
  PdfArray? getArray(String key) {
    final obj = map[key];
    if (obj is PdfArray) return obj;
    return null;
  }

  /// Get as dict.
  PdfDict? getDict(String key) {
    final obj = map[key];
    if (obj is PdfDict) return obj;
    return null;
  }

  /// Get as reference.
  PdfRef? getRef(String key) {
    final obj = map[key];
    if (obj is PdfRef) return obj;
    return null;
  }

  @override
  String toPdfString() {
    final buffer = StringBuffer('<<\n');
    for (final entry in map.entries) {
      buffer.write('/${entry.key} ${entry.value.toPdfString()}\n');
    }
    buffer.write('>>');
    return buffer.toString();
  }

  @override
  String toString() {
    final entries = map.entries.map((e) => '/${e.key}: ${e.value}').join(', ');
    return '{$entries}';
  }
}

/// PDF indirect reference (e.g., "5 0 R").
class PdfRef extends PdfObject {
  final int objectNumber;
  final int generation;

  PdfRef(this.objectNumber, [this.generation = 0]);

  @override
  String toPdfString() => '$objectNumber $generation R';

  @override
  bool operator ==(Object other) =>
      other is PdfRef &&
      objectNumber == other.objectNumber &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(objectNumber, generation);

  @override
  String toString() => '$objectNumber $generation R';
}

/// A PDF stream (dictionary + binary data).
class PdfStream extends PdfObject {
  final PdfDict dict;
  Uint8List data;

  PdfStream(this.dict, this.data);

  int get length => data.length;

  /// Get the declared filter(s).
  List<String> get filters {
    final filter = dict['Filter'];
    if (filter is PdfName) return [filter.value];
    if (filter is PdfArray) {
      return filter.items.whereType<PdfName>().map((n) => n.value).toList();
    }
    return [];
  }

  @override
  String toPdfString() {
    dict['Length'] = PdfInt(data.length);
    return '${dict.toPdfString()}\nstream\n${String.fromCharCodes(data)}\nendstream';
  }

  @override
  String toString() => 'PdfStream(${dict}, ${data.length} bytes)';
}

/// An indirect object (objectNumber generation obj ... endobj).
class PdfIndirectObject extends PdfObject {
  final int objectNumber;
  final int generation;
  PdfObject object;

  PdfIndirectObject(this.objectNumber, this.generation, this.object);

  /// If the inner object is a stream.
  bool get isStream => object is PdfStream;

  /// If the inner object is a dict.
  bool get isDict => object is PdfDict;

  /// Get inner dict (from dict or stream).
  PdfDict? get dict {
    if (object is PdfDict) return object as PdfDict;
    if (object is PdfStream) return (object as PdfStream).dict;
    return null;
  }

  /// Get stream data (if stream).
  Uint8List? get streamData {
    if (object is PdfStream) return (object as PdfStream).data;
    return null;
  }

  @override
  String toPdfString() =>
      '$objectNumber $generation obj\n${object.toPdfString()}\nendobj';

  @override
  String toString() => 'PdfIndirectObject($objectNumber $generation: $object)';
}
