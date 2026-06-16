import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:directory_bookmarks/directory_bookmarks.dart';

class DirectoryManagerException implements Exception {
  final String message;
  final dynamic originalError;

  DirectoryManagerException(this.message, [this.originalError]);

  @override
  String toString() =>
      'DirectoryManagerException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

class DocumentFile {
  final String uri;
  final String name;
  final bool isDir;
  final int length;
  final int lastModified;

  const DocumentFile({
    required this.uri,
    required this.name,
    required this.isDir,
    required this.length,
    required this.lastModified,
  });

  DocumentFile copyWith({
    String? uri,
    String? name,
    bool? isDir,
    int? length,
    int? lastModified,
  }) {
    return DocumentFile(
      uri: uri ?? this.uri,
      name: name ?? this.name,
      isDir: isDir ?? this.isDir,
      length: length ?? this.length,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  static DocumentFile fromMap(Map<dynamic, dynamic> map) {
    return DocumentFile(
      uri: map['uri'],
      name: map['name'],
      isDir: map['isDir'] ?? false,
      length: map['length'] ?? 0,
      lastModified: map['lastModified'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'DocumentFile{uri: $uri, name: $name, isDir: $isDir, length: $length, lastModified: $lastModified}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentFile &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          name == other.name &&
          isDir == other.isDir &&
          length == other.length &&
          lastModified == other.lastModified;

  @override
  int get hashCode =>
      uri.hashCode ^
      name.hashCode ^
      isDir.hashCode ^
      length.hashCode ^
      lastModified.hashCode;
}

class DirectoryManager extends Notifier<String?> {
  final _safUtilPlugin = SafUtil();
  final _safStreamPlugin = SafStream();

  @override
  String? build() {
    _loadSavedDirectory();
    return null;
  }

  String _normalizePath(String path) {
    return p.normalize(path);
  }

  // Normalize the path/URI handling
  String _normalizeUri(String uri) {
    if (uri == '/') return uri;
    if (Platform.isAndroid) {
      final uriParts = uri.split('://');
      if (uriParts.length == 2) {
        final path = p.normalize(uriParts[1]);
        return '${uriParts[0]}://$path';
      }
      throw ArgumentError("Invalid URI: $uri");
    }

    return p.normalize(uri);
  }

  Future<void> _loadSavedDirectory() async {
    if (Platform.isMacOS) {
      final bookmark = await DirectoryBookmarkHandler.resolveBookmark();
      if (bookmark == null) {
        return;
      }
      final path = bookmark.path;
      if (await checkDirectoryExists(path)) {
        state = path;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final dir = prefs.getString("selected_directory");
    if (dir == null) {
      return;
    }
    if (await checkDirectoryExists(dir)) {
      state = dir;
    }
  }

  String getDirectory() {
    if (state == null) {
      throw DirectoryManagerException("Directory not selected");
    }
    return state!;
  }

  Future<void> _saveDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("selected_directory", path);
  }

  Future<void> _saveBookmark(String path) async {
    if (Platform.isMacOS) {
      final bookmark = await DirectoryBookmarkHandler.saveBookmark(
        path,
        metadata: {'lastAccessed': DateTime.now().toIso8601String()},
      );
    }
  }

  Future<void> selectDirectory() async {
    try {
      String? directory;
      if (Platform.isAndroid) {
        // Android: Use SAF to select and persist directory
        final dir = await _safUtilPlugin.pickDirectory(
          initialUri: '',
          persistablePermission: true,
        );
        if (dir != null) {
          directory = dir.uri;
        }
      } else {
        directory = await FilePicker.getDirectoryPath();
      }
      if (directory != null) {
        await _saveBookmark(directory);
        await _saveDirectory(directory);
        state = directory;
      }
    } catch (e) {
      print("Error selecting directory: $e");
    }
  }

  Future<bool> checkDirectoryExists(String dirUri) async {
    try {
      final normalizedDir = _normalizeUri(dirUri);
      if (Platform.isAndroid) {
        return await _safUtilPlugin.exists(normalizedDir, true);
      }
      final dir = Directory(normalizedDir);
      return await dir.exists();
    } catch (e) {
      throw DirectoryManagerException("Failed to check directory exists,\n$e");
    }
  }

  Future<bool> checkFileExists(String dirUri) async {
    if (Platform.isAndroid) {
      // Android: Use SAF to check if the file exists
      return await _safUtilPlugin.exists(dirUri, false);
    }
    // print("Checking file existence: $dirUri");
    final file = File(dirUri);
    return await file.exists();
  }

  Future<List<DocumentFile>> listDocs(String directory) async {
    final normalizedDir = _normalizePath(directory);
    print("Listing files in directory: $normalizedDir");
    final currentDirectory = getDirectory();
    final dirUri = await _getDirectoryUri(currentDirectory, normalizedDir);
    print("Directory URI: $dirUri");
    if (!await checkDirectoryExists(dirUri)) {
      throw Exception("Directory not found: $normalizedDir");
    }
    if (Platform.isAndroid) {
      // Android: Use SAF to list files in the selected directory
      return await _listAndroidDocuments(dirUri);
    }
    return await _listNativeDocuments(dirUri);
  }

  Future<List<DocumentFile>> _listAndroidDocuments(String dirUri) async {
    final files = await _safUtilPlugin.list(dirUri);
    return files.map((file) {
      return DocumentFile(
        uri: file.uri,
        name: file.name,
        isDir: file.isDir,
        length: file.length,
        lastModified: file.lastModified,
      );
    }).toList();
  }

  Future<List<DocumentFile>> _listNativeDocuments(String dirUri) async {
    final dir = Directory(dirUri);
    final files = await dir.list().toList();
    return files.map((file) {
      final name = file.path.split('/').last;
      final isDir = file.statSync().type == FileSystemEntityType.directory;
      final length = isDir ? 0 : file.statSync().size;
      final lastModified = file.statSync().modified.millisecondsSinceEpoch;
      return DocumentFile(
        uri: file.path,
        name: name,
        isDir: isDir,
        length: length,
        lastModified: lastModified,
      );
    }).toList();
  }

  // List files in the selected directory
  Future<List<DocumentFile>> listFiles(String dir) async {
    final files = await listDocs(dir);
    return files.where((file) => !file.isDir).toList();
  }

  Future<Uint8List> readFileBytes(String path) async {
    if (!await checkFileExists(path)) {
      throw Exception("File not found: $path");
    }
    if (Platform.isAndroid) {
      return await _safStreamPlugin.readFileBytes(path);
    }

    final file = File(path);
    return await file.readAsBytes();
  }

  // Read file from the selected directory
  Future<String?> readFileString(String path) async {
    if (!await checkFileExists(path)) {
      throw Exception("File not found: $path");
    }

    if (Platform.isAndroid) {
      final fileBytes = await _safStreamPlugin.readFileBytes(path);
      return String.fromCharCodes(fileBytes);
    }

    final file = File(path);
    final fileContent = await file.readAsString();
    return fileContent;
  }

  Future<DocumentFile> getFileByName(String directory, String fileName) async {
    final files = await listFiles(directory);
    final file = files.firstWhere((file) => file.name == fileName);
    print("getFileByName: $file");
    return file;
  }

  Future<String> _getDirectoryUri(
      String currentDirectory, String directory) async {
    if (Platform.isAndroid) {
      if (directory == '/' || directory == '') {
        return currentDirectory;
      }
      final dir = await _safUtilPlugin
          .child(currentDirectory, [...directory.split('/')]);
      if (dir == null) {
        throw DirectoryManagerException("Directory not found: $directory");
      }
      if (dir.isDir == false) {
        throw DirectoryManagerException("Not a directory: $directory");
      }
      return dir.uri;
    }
    return "$currentDirectory/$directory";
  }

  Future<void> writeFile(
      String path, String fileName, String mime, Uint8List data) async {
    if (Platform.isAndroid) {
      await _safStreamPlugin.writeFileBytes(path, fileName, mime, data);
    } else {
      final file = File(path);
      await file.writeAsBytes(data);
    }
  }

  Future<void> clearDirectory() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("selected_directory");
  }
}

final directoryManagerProvider =
    NotifierProvider<DirectoryManager, String?>(DirectoryManager.new);

final readFileStringFutureProvider =
    FutureProvider.family<String?, String>((ref, path) {
  final notifier = ref.read(directoryManagerProvider.notifier);
  return notifier.readFileString(path);
});

final readFileBytesFutureProvider =
    FutureProvider.family<Uint8List?, String>((ref, path) {
  final notifier = ref.read(directoryManagerProvider.notifier);
  return notifier.readFileBytes(path);
});

final listDocsFutureProvider =
    FutureProvider.family<List<DocumentFile>, String>((ref, directory) {
  final notifier = ref.read(directoryManagerProvider.notifier);
  return notifier.listDocs(directory);
});

final listFilesFutureProvider =
    FutureProvider.family<List<DocumentFile>, String>((ref, directory) {
  final notifier = ref.read(directoryManagerProvider.notifier);
  return notifier.listFiles(directory);
});

class GetFileByNameParams {
  final String directory;
  final String fileName;

  const GetFileByNameParams(this.directory, this.fileName);
}

final getFileByNameFutureProvider =
    FutureProvider.family<DocumentFile, GetFileByNameParams>((ref, params) {
  final notifier = ref.read(directoryManagerProvider.notifier);
  return notifier.getFileByName(params.directory, params.fileName);
});
