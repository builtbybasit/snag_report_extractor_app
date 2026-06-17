import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:directory_bookmarks/directory_bookmarks.dart';
import 'package:snag_report_extractor_app/src/logging/talker.dart';

/// Thrown when a [DirectoryManager] operation fails. Carries an optional
/// [originalError] so the underlying cause is preserved when surfaced.
class DirectoryManagerException implements Exception {
  final String message;
  final dynamic originalError;

  DirectoryManagerException(this.message, [this.originalError]);

  @override
  String toString() =>
      'DirectoryManagerException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

/// A platform-agnostic file/directory entry. On Android [uri] is a SAF
/// content URI; elsewhere it is a filesystem path.
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

/// The key under which the selected directory path/URI is persisted in
/// [SharedPreferences].
const _kSelectedDirectoryKey = "selected_directory";

/// Encapsulates every platform-specific way of working with the output
/// directory: picking it, persisting/restoring it, existence checks, and
/// listing/reading/writing files.
///
/// Two implementations exist — [AndroidSafStrategy] (Android Storage Access
/// Framework) and [NativeDirectoryStrategy] (`dart:io`, plus macOS
/// security-scoped bookmarks). [DirectoryManager] picks one once and delegates
/// to it, so no method has to branch on [Platform] itself.
abstract class DirectoryStrategy {
  /// Selects the appropriate strategy for the current platform.
  factory DirectoryStrategy.forPlatform() {
    if (Platform.isAndroid) return AndroidSafStrategy();
    return NativeDirectoryStrategy();
  }

  /// Persists [path] so it can be restored on the next launch. Implementations
  /// must store enough to survive a relaunch (e.g. a macOS bookmark).
  Future<void> persist(String path);

  /// Restores the previously persisted directory, or `null` if there is none
  /// (or it no longer exists). Implementations are responsible for their own
  /// existence verification.
  Future<String?> restore();

  /// Clears any persisted directory selection.
  Future<void> clearPersisted();

  /// Opens the platform directory picker. Returns the chosen path/URI, or
  /// `null` if the user cancelled.
  Future<String?> pickDirectory();

  /// Normalizes a directory path/URI for comparison and lookup.
  String normalizeUri(String uri);

  /// Whether the directory at [dirUri] exists.
  Future<bool> directoryExists(String dirUri);

  /// Whether the file at [path] exists.
  Future<bool> fileExists(String path);

  /// Resolves the URI/path of [directory] relative to [root].
  Future<String> resolveChildDirectory(String root, String directory);

  /// Lists the entries directly under [dirUri].
  Future<List<DocumentFile>> listDocuments(String dirUri);

  /// Reads the raw bytes of the file at [path].
  Future<Uint8List> readBytes(String path);

  /// Reads the file at [path] decoded as UTF-8.
  Future<String> readString(String path);

  /// Writes [data] as a file named [fileName] (with [mime]) at [path].
  Future<void> writeFile(
      String path, String fileName, String mime, Uint8List data);
}

/// Android implementation backed by the Storage Access Framework via
/// `saf_util` / `saf_stream`. Paths are content URIs and persistence relies on
/// SAF's persistable permissions plus a [SharedPreferences] record of the URI.
class AndroidSafStrategy implements DirectoryStrategy {
  final _safUtil = SafUtil();
  final _safStream = SafStream();

  @override
  Future<void> persist(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedDirectoryKey, path);
  }

  @override
  Future<String?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_kSelectedDirectoryKey);
    if (uri == null) return null;
    return await directoryExists(uri) ? uri : null;
  }

  @override
  Future<void> clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSelectedDirectoryKey);
  }

  @override
  Future<String?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(
      initialUri: '',
      persistablePermission: true,
    );
    return dir?.uri;
  }

  @override
  String normalizeUri(String uri) {
    if (uri == '/') return uri;
    final uriParts = uri.split('://');
    if (uriParts.length == 2) {
      final path = p.normalize(uriParts[1]);
      return '${uriParts[0]}://$path';
    }
    throw ArgumentError("Invalid URI: $uri");
  }

  @override
  Future<bool> directoryExists(String dirUri) =>
      _safUtil.exists(normalizeUri(dirUri), true);

  @override
  Future<bool> fileExists(String path) => _safUtil.exists(path, false);

  @override
  Future<String> resolveChildDirectory(String root, String directory) async {
    if (directory == '/' || directory == '') return root;
    final dir = await _safUtil.child(root, [...directory.split('/')]);
    if (dir == null) {
      throw DirectoryManagerException("Directory not found: $directory");
    }
    if (!dir.isDir) {
      throw DirectoryManagerException("Not a directory: $directory");
    }
    return dir.uri;
  }

  @override
  Future<List<DocumentFile>> listDocuments(String dirUri) async {
    final files = await _safUtil.list(dirUri);
    return files
        .map((file) => DocumentFile(
              uri: file.uri,
              name: file.name,
              isDir: file.isDir,
              length: file.length,
              lastModified: file.lastModified,
            ))
        .toList();
  }

  @override
  Future<Uint8List> readBytes(String path) => _safStream.readFileBytes(path);

  @override
  Future<String> readString(String path) async {
    final bytes = await _safStream.readFileBytes(path);
    // Decode as UTF-8 (not Latin-1) so multi-byte characters survive; tolerate
    // malformed sequences rather than throwing.
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> writeFile(
          String path, String fileName, String mime, Uint8List data) =>
      _safStream.writeFileBytes(path, fileName, mime, data);
}

/// Native implementation backed by `dart:io`. On macOS it additionally manages
/// a security-scoped bookmark (via `directory_bookmarks`) so the selected
/// folder stays accessible across launches inside the sandbox.
class NativeDirectoryStrategy implements DirectoryStrategy {
  @override
  Future<void> persist(String path) async {
    if (Platform.isMacOS) {
      await DirectoryBookmarkHandler.saveBookmark(
        path,
        metadata: {'lastAccessed': DateTime.now().toIso8601String()},
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedDirectoryKey, path);
  }

  @override
  Future<String?> restore() async {
    // On macOS the security-scoped bookmark is the source of truth: resolving
    // it re-establishes sandbox access. Restore from it ONLY and never fall
    // through to the prefs path, which could carry a stale value.
    if (Platform.isMacOS) {
      final bookmark = await DirectoryBookmarkHandler.resolveBookmark();
      final path = bookmark?.path;
      if (path == null) return null;
      return await directoryExists(path) ? path : null;
    }

    final prefs = await SharedPreferences.getInstance();
    final dir = prefs.getString(_kSelectedDirectoryKey);
    if (dir == null) return null;
    return await directoryExists(dir) ? dir : null;
  }

  @override
  Future<void> clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSelectedDirectoryKey);
  }

  @override
  Future<String?> pickDirectory() => FilePicker.getDirectoryPath();

  @override
  String normalizeUri(String uri) {
    if (uri == '/') return uri;
    return p.normalize(uri);
  }

  @override
  Future<bool> directoryExists(String dirUri) =>
      Directory(normalizeUri(dirUri)).exists();

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<String> resolveChildDirectory(String root, String directory) async =>
      p.join(root, directory);

  @override
  Future<List<DocumentFile>> listDocuments(String dirUri) async {
    final entries = await Directory(dirUri).list().toList();
    final docs = <DocumentFile>[];
    for (final entry in entries) {
      try {
        // Stat once and reuse it for type/size/modified. statSync() throws on a
        // broken symlink, so skip the bad entry instead of aborting the whole
        // listing.
        final stat = entry.statSync();
        final isDir = stat.type == FileSystemEntityType.directory;
        docs.add(DocumentFile(
          uri: entry.path,
          name: p.basename(entry.path),
          isDir: isDir,
          length: isDir ? 0 : stat.size,
          lastModified: stat.modified.millisecondsSinceEpoch,
        ));
      } catch (e, st) {
        talker.error("Skipping unreadable entry: ${entry.path}", e, st);
      }
    }
    return docs;
  }

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<String> readString(String path) => File(path).readAsString();

  @override
  Future<void> writeFile(
          String path, String fileName, String mime, Uint8List data) =>
      File(path).writeAsBytes(data);
}

/// A Riverpod notifier holding the currently selected output directory
/// (`null` = none selected) and exposing cross-platform file operations.
///
/// All platform branching lives in a [DirectoryStrategy] chosen once for the
/// running platform; this notifier simply delegates to it.
class DirectoryManager extends Notifier<String?> {
  final DirectoryStrategy _strategy = DirectoryStrategy.forPlatform();

  @override
  String? build() {
    // The persisted directory load is inherently async (security-scoped
    // bookmark resolution, SharedPreferences, directory existence checks), so
    // build() returns a well-defined synchronous initial state (null = no
    // directory selected). The async load is kicked off explicitly via init()
    // and is mount-guarded so it never writes to a disposed notifier.
    init();
    return null;
  }

  /// Loads the persisted directory and updates [state] when it resolves.
  ///
  /// Safe to await (deterministic) and safe to fire-and-forget: the state
  /// write is guarded by [Ref.mounted], so a disposal mid-load cannot mutate a
  /// stale notifier.
  Future<void> init() => _loadSavedDirectory();

  Future<void> _loadSavedDirectory() async {
    final saved = await _strategy.restore();
    if (saved == null) return;
    if (!ref.mounted) return;
    state = saved;
  }

  /// Returns the selected directory, throwing [DirectoryManagerException] if
  /// none has been selected.
  String getDirectory() {
    if (state == null) {
      throw DirectoryManagerException("Directory not selected");
    }
    return state!;
  }

  /// Opens the platform directory picker, persists the choice, and updates
  /// [state]. A user cancellation is silent; any genuine failure is logged and
  /// rethrown as a [DirectoryManagerException] so it surfaces.
  Future<void> selectDirectory() async {
    String? directory;
    try {
      directory = await _strategy.pickDirectory();
      // User cancelled the picker — not an error, stay silent.
      if (directory == null) return;
      await _strategy.persist(directory);
    } catch (e, st) {
      talker.error("Error selecting directory", e, st);
      throw DirectoryManagerException("Failed to select directory", e);
    }
    state = directory;
  }

  /// Whether the directory at [dirUri] exists.
  Future<bool> checkDirectoryExists(String dirUri) async {
    try {
      return await _strategy.directoryExists(dirUri);
    } catch (e) {
      throw DirectoryManagerException("Failed to check directory exists,\n$e");
    }
  }

  /// Whether the file at [path] exists.
  Future<bool> checkFileExists(String path) => _strategy.fileExists(path);

  /// Lists every entry (files and sub-directories) under [directory], resolved
  /// relative to the selected directory.
  Future<List<DocumentFile>> listDocs(String directory) async {
    final normalizedDir = p.normalize(directory);
    talker.debug("Listing files in directory: $normalizedDir");
    final dirUri =
        await _strategy.resolveChildDirectory(getDirectory(), normalizedDir);
    talker.debug("Directory URI: $dirUri");
    if (!await checkDirectoryExists(dirUri)) {
      throw Exception("Directory not found: $normalizedDir");
    }
    return _strategy.listDocuments(dirUri);
  }

  /// Like [listDocs] but excludes sub-directories.
  Future<List<DocumentFile>> listFiles(String dir) async {
    final files = await listDocs(dir);
    return files.where((file) => !file.isDir).toList();
  }

  /// Reads the raw bytes of the file at [path].
  Future<Uint8List> readFileBytes(String path) async {
    if (!await checkFileExists(path)) {
      throw Exception("File not found: $path");
    }
    return _strategy.readBytes(path);
  }

  /// Reads the file at [path] as a UTF-8 string.
  Future<String?> readFileString(String path) async {
    if (!await checkFileExists(path)) {
      throw Exception("File not found: $path");
    }
    return _strategy.readString(path);
  }

  /// Returns the first file named [fileName] within [directory].
  Future<DocumentFile> getFileByName(String directory, String fileName) async {
    final files = await listFiles(directory);
    final file = files.firstWhere((file) => file.name == fileName);
    talker.debug("getFileByName: $file");
    return file;
  }

  /// Writes [data] as a file named [fileName] (with [mime]) at [path].
  Future<void> writeFile(
          String path, String fileName, String mime, Uint8List data) =>
      _strategy.writeFile(path, fileName, mime, data);

  /// Clears the selection and removes any persisted directory.
  Future<void> clearDirectory() async {
    state = null;
    await _strategy.clearPersisted();
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
