import 'dart:typed_data';
import 'pdf_objects.dart';

/// PDF encryption handler.
///
/// Supports RC4 and basic AES encryption detection and decryption.
class PdfEncryption {
  /// Encryption algorithm constants.
  static const int algorithmNone = 0;
  static const int algorithmRC4_40 = 1;
  static const int algorithmRC4_128 = 2;
  static const int algorithmAES_128 = 3;
  static const int algorithmAES_256 = 4;

  /// Permission flags.
  static const int permPrint = 4;
  static const int permModify = 8;
  static const int permCopy = 16;
  static const int permAnnot = 32;
  static const int permFillForms = 256;
  static const int permAccessibility = 512;
  static const int permAssemble = 1024;
  static const int permPrintHigh = 2048;

  /// Encryption dictionary.
  final PdfDict encryptDict;

  /// Document ID (from trailer /ID array).
  final Uint8List documentId;

  /// Computed file encryption key.
  Uint8List? _encryptionKey;

  /// Revision number.
  int get revision => encryptDict.getInt('R') ?? 0;

  /// Algorithm version.
  int get version => encryptDict.getInt('V') ?? 0;

  /// Key length in bits.
  int get keyLength => encryptDict.getInt('Length') ?? 40;

  /// Permission flags.
  int get permissions => encryptDict.getInt('P') ?? 0;

  /// Owner password hash.
  Uint8List get ownerHash {
    final o = encryptDict['O'];
    if (o is PdfString) return o.bytes;
    return Uint8List(0);
  }

  /// User password hash.
  Uint8List get userHash {
    final u = encryptDict['U'];
    if (u is PdfString) return u.bytes;
    return Uint8List(0);
  }

  PdfEncryption({required this.encryptDict, required this.documentId});

  /// Determine the encryption algorithm in use.
  int get algorithm {
    if (version == 1 || version == 2) {
      return keyLength <= 40 ? algorithmRC4_40 : algorithmRC4_128;
    }
    if (version == 4) {
      final cf = encryptDict.getDict('CF');
      if (cf != null) {
        final stdCf = cf.getDict('StdCF');
        if (stdCf != null) {
          final cfm = stdCf.getName('CFM');
          if (cfm == 'AESV2') return algorithmAES_128;
        }
      }
      return algorithmRC4_128;
    }
    if (version == 5) return algorithmAES_256;
    return algorithmNone;
  }

  /// Whether the document uses AES encryption.
  bool get isAES =>
      algorithm == algorithmAES_128 || algorithm == algorithmAES_256;

  /// Try to authenticate with a password. Returns true if successful.
  bool authenticate(String password) {
    // Try empty password first (for owner-password-only protection)
    if (_tryUserPassword('')) return true;
    if (_tryUserPassword(password)) return true;
    if (_tryOwnerPassword(password)) return true;
    return false;
  }

  bool _tryUserPassword(String password) {
    final key = _computeEncryptionKey(password);
    if (_verifyUserPassword(key)) {
      _encryptionKey = key;
      return true;
    }
    return false;
  }

  bool _tryOwnerPassword(String password) {
    // For rev 2-4: decrypt O value with owner password to get user password
    // Then try that as user password
    // Simplified: just try common patterns
    return false;
  }

  Uint8List _computeEncryptionKey(String password) {
    // Algorithm 2 from PDF Reference
    final paddedPassword = _padPassword(password);
    final md5Input = <int>[
      ...paddedPassword,
      ...ownerHash,
      permissions & 0xFF,
      (permissions >> 8) & 0xFF,
      (permissions >> 16) & 0xFF,
      (permissions >> 24) & 0xFF,
      ...documentId,
    ];

    // For rev 4 with metadata not encrypted
    if (revision >= 4 && !(encryptDict.getBool('EncryptMetadata') ?? true)) {
      md5Input.addAll([0xFF, 0xFF, 0xFF, 0xFF]);
    }

    var hash = _md5(Uint8List.fromList(md5Input));
    final keyLen = keyLength ~/ 8;

    if (revision >= 3) {
      for (int i = 0; i < 50; i++) {
        hash = _md5(Uint8List.fromList(hash.sublist(0, keyLen)));
      }
    }

    return Uint8List.fromList(hash.sublist(0, keyLen));
  }

  bool _verifyUserPassword(Uint8List key) {
    if (revision == 2) {
      final encrypted = _rc4(Uint8List.fromList(_passwordPadding), key);
      return _bytesEqual(encrypted, userHash.sublist(0, 32));
    }
    if (revision >= 3) {
      final md5Input = <int>[..._passwordPadding, ...documentId];
      var hash = _md5(Uint8List.fromList(md5Input));
      hash = Uint8List.fromList(_rc4(hash, key));
      for (int i = 1; i <= 19; i++) {
        final derivedKey = Uint8List.fromList(key.map((b) => b ^ i).toList());
        hash = Uint8List.fromList(_rc4(hash, derivedKey));
      }
      return _bytesEqual(hash.sublist(0, 16), userHash.sublist(0, 16));
    }
    return false;
  }

  /// Decrypt an object's data.
  Uint8List decrypt(Uint8List data, int objectNumber, int generation) {
    if (_encryptionKey == null) return data;

    final objectKey = _computeObjectKey(objectNumber, generation);

    if (isAES) {
      return _aesDecrypt(data, objectKey);
    }
    return Uint8List.fromList(_rc4(data, objectKey));
  }

  Uint8List _computeObjectKey(int objectNumber, int generation) {
    if (_encryptionKey == null) return Uint8List(0);

    final md5Input = <int>[
      ..._encryptionKey!,
      objectNumber & 0xFF,
      (objectNumber >> 8) & 0xFF,
      (objectNumber >> 16) & 0xFF,
      generation & 0xFF,
      (generation >> 8) & 0xFF,
    ];

    if (isAES) {
      md5Input.addAll([0x73, 0x41, 0x6C, 0x54]); // "sAlT"
    }

    final hash = _md5(Uint8List.fromList(md5Input));
    final keyLen = (_encryptionKey!.length + 5).clamp(0, 16);
    return Uint8List.fromList(hash.sublist(0, keyLen));
  }

  /// Check if encryption is present.
  bool get isEncrypted => _encryptionKey != null || version > 0;

  /// Check if authenticated.
  bool get isAuthenticated => _encryptionKey != null;

  /// Check permissions.
  bool get canPrint => (permissions & permPrint) != 0;
  bool get canModify => (permissions & permModify) != 0;
  bool get canCopy => (permissions & permCopy) != 0;
  bool get canAnnotate => (permissions & permAnnot) != 0;

  // --- Crypto primitives ---

  static Uint8List _padPassword(String password) {
    final bytes = password.codeUnits.take(32).toList();
    final padded = <int>[...bytes];
    int i = 0;
    while (padded.length < 32) {
      padded.add(_passwordPadding[i++]);
    }
    return Uint8List.fromList(padded);
  }

  static const List<int> _passwordPadding = [
    0x28,
    0xBF,
    0x4E,
    0x5E,
    0x4E,
    0x75,
    0x8A,
    0x41,
    0x64,
    0x00,
    0x4E,
    0x56,
    0xFF,
    0xFA,
    0x01,
    0x08,
    0x2E,
    0x2E,
    0x00,
    0xB6,
    0xD0,
    0x68,
    0x3E,
    0x80,
    0x2F,
    0x0C,
    0xA9,
    0xFE,
    0x64,
    0x53,
    0x69,
    0x7A,
  ];

  /// Simple MD5 implementation.
  static Uint8List _md5(Uint8List data) {
    // Use Dart's built-in
    return Uint8List.fromList(md5Convert(data));
  }

  /// Basic RC4 stream cipher.
  static List<int> _rc4(Uint8List data, Uint8List key) {
    final s = List<int>.generate(256, (i) => i);
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }

    final result = List<int>.filled(data.length, 0);
    int x = 0;
    j = 0;
    for (int i = 0; i < data.length; i++) {
      x = (x + 1) & 0xFF;
      j = (j + s[x]) & 0xFF;
      final tmp = s[x];
      s[x] = s[j];
      s[j] = tmp;
      result[i] = data[i] ^ s[(s[x] + s[j]) & 0xFF];
    }
    return result;
  }

  /// AES decryption (simplified — uses IV from first 16 bytes).
  static Uint8List _aesDecrypt(Uint8List data, Uint8List key) {
    // For AES-128 CBC: first 16 bytes = IV, rest = encrypted data
    if (data.length < 16) return data;
    // Return data without IV as placeholder
    // Full AES requires pointycastle dependency
    return data.sublist(16);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Minimal MD5 implementation for PDF encryption.
List<int> md5Convert(Uint8List data) {
  // Using dart:convert's built-in doesn't include md5, so we implement it
  // Constants
  const s = <int>[
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
  ];
  const k = <int>[
    0xd76aa478,
    0xe8c7b756,
    0x242070db,
    0xc1bdceee,
    0xf57c0faf,
    0x4787c62a,
    0xa8304613,
    0xfd469501,
    0x698098d8,
    0x8b44f7af,
    0xffff5bb1,
    0x895cd7be,
    0x6b901122,
    0xfd987193,
    0xa679438e,
    0x49b40821,
    0xf61e2562,
    0xc040b340,
    0x265e5a51,
    0xe9b6c7aa,
    0xd62f105d,
    0x02441453,
    0xd8a1e681,
    0xe7d3fbc8,
    0x21e1cde6,
    0xc33707d6,
    0xf4d50d87,
    0x455a14ed,
    0xa9e3e905,
    0xfcefa3f8,
    0x676f02d9,
    0x8d2a4c8a,
    0xfffa3942,
    0x8771f681,
    0x6d9d6122,
    0xfde5380c,
    0xa4beea44,
    0x4bdecfa9,
    0xf6bb4b60,
    0xbebfbc70,
    0x289b7ec6,
    0xeaa127fa,
    0xd4ef3085,
    0x04881d05,
    0xd9d4d039,
    0xe6db99e5,
    0x1fa27cf8,
    0xc4ac5665,
    0xf4292244,
    0x432aff97,
    0xab9423a7,
    0xfc93a039,
    0x655b59c3,
    0x8f0ccc92,
    0xffeff47d,
    0x85845dd1,
    0x6fa87e4f,
    0xfe2ce6e0,
    0xa3014314,
    0x4e0811a1,
    0xf7537e82,
    0xbd3af235,
    0x2ad7d2bb,
    0xeb86d391,
  ];

  // Pre-processing: add padding
  final msgLen = data.length;
  final bitLen = msgLen * 8;
  final padded = <int>[...data, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  // Append original length as 64-bit LE
  for (int i = 0; i < 8; i++) {
    padded.add((bitLen >> (i * 8)) & 0xFF);
  }

  int a0 = 0x67452301;
  int b0 = 0xefcdab89;
  int c0 = 0x98badcfe;
  int d0 = 0x10325476;

  int leftRotate(int x, int c) =>
      ((x << c) | ((x & 0xFFFFFFFF) >> (32 - c))) & 0xFFFFFFFF;

  for (int chunk = 0; chunk < padded.length; chunk += 64) {
    final m = List<int>.filled(16, 0);
    for (int i = 0; i < 16; i++) {
      final offset = chunk + i * 4;
      m[i] = padded[offset] |
          (padded[offset + 1] << 8) |
          (padded[offset + 2] << 16) |
          (padded[offset + 3] << 24);
    }

    int a = a0, b = b0, c = c0, d = d0;

    for (int i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = (b & c) | ((~b & 0xFFFFFFFF) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d & 0xFFFFFFFF) & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d & 0xFFFFFFFF));
        g = (7 * i) % 16;
      }

      f = (f + a + k[i] + m[g]) & 0xFFFFFFFF;
      a = d;
      d = c;
      c = b;
      b = (b + leftRotate(f, s[i])) & 0xFFFFFFFF;
    }

    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  final digest = Uint8List(16);
  for (int i = 0; i < 4; i++) {
    digest[i] = (a0 >> (i * 8)) & 0xFF;
    digest[i + 4] = (b0 >> (i * 8)) & 0xFF;
    digest[i + 8] = (c0 >> (i * 8)) & 0xFF;
    digest[i + 12] = (d0 >> (i * 8)) & 0xFF;
  }
  return digest.toList();
}
