import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'len_file.dart';

/// Thrown for invalid file-system operations (bad name, path already taken, ...).
class FileSystemException implements Exception {
  FileSystemException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The LenOS virtual file system: a flat list of [LenFile]s plus a set of
/// explicitly created folders, saved to shared preferences as JSON.
///
/// Paths are absolute and use `/` (root is `/`). A folder exists if it was
/// created explicitly or if any file lives inside it.
class FileSystemModel extends ChangeNotifier {
  static const _storageKey = 'lenos.fs.v1';

  final List<LenFile> _files = [];
  final Set<String> _folders = {};
  bool _loaded = false;
  Object? _loadError;
  int _idCounter = 0;

  bool get isLoaded => _loaded;

  /// Set if storage could not be opened (e.g. the app was hot-restarted
  /// after adding the shared_preferences plugin instead of fully rebuilt).
  Object? get loadError => _loadError;
  List<LenFile> get files => List.unmodifiable(_files);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, Object?>;
        _files
          ..clear()
          ..addAll((json['files'] as List).map(
              (f) => LenFile.fromJson((f as Map).cast<String, Object?>())));
        _folders
          ..clear()
          ..addAll((json['folders'] as List).cast<String>());
      }
      _loadError = null;
    } catch (e) {
      debugPrint('Could not load the file system: $e');
      _loadError = e;
    } finally {
      // Always finish loading so the UI never waits forever.
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    notifyListeners();
    // Never replace stored files that could not be read with this partial copy.
    if (_loadError != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'files': [for (final f in _files) f.toJson()],
          'folders': _folders.toList(),
        }),
      );
    } catch (e) {
      debugPrint('Could not save the file system: $e');
    }
  }

  // --- Paths --------------------------------------------------------------

  /// Joins a folder and a name into a normalized absolute path.
  static String join(String folder, String name) =>
      normalize(folder == '/' ? '/$name' : '$folder/$name');

  /// Collapses duplicate slashes, removes a trailing slash, ensures a leading one.
  static String normalize(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty);
    return '/${parts.join('/')}';
  }

  static String parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  static String nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  /// Returns an error message for an invalid file/folder name, else null.
  static String? validateName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Name cannot be empty';
    if (n.contains('/')) return 'Name cannot contain "/"';
    if (n == '.' || n == '..') return 'Invalid name';
    return null;
  }

  static bool _isInside(String path, String folder) =>
      folder == '/' ? path != '/' : path.startsWith('$folder/');

  // --- Queries ------------------------------------------------------------

  LenFile? byId(String id) {
    for (final f in _files) {
      if (f.id == id) return f;
    }
    return null;
  }

  LenFile? fileAt(String path) {
    for (final f in _files) {
      if (f.path == path) return f;
    }
    return null;
  }

  bool folderExists(String path) =>
      path == '/' ||
      _folders.contains(path) ||
      _files.any((f) => _isInside(f.path, path)) ||
      _folders.any((d) => _isInside(d, path));

  bool exists(String path) => fileAt(path) != null || folderExists(path);

  /// Every folder in the file system, sorted (including `/`).
  List<String> allFolders() {
    final result = <String>{'/'};
    void addWithParents(String p) {
      while (p != '/') {
        result.add(p);
        p = parentOf(p);
      }
    }
    _folders.forEach(addWithParents);
    for (final f in _files) {
      addWithParents(f.folder);
    }
    return result.toList()..sort();
  }

  /// Direct subfolders of [folder], sorted by name.
  List<String> subfoldersOf(String folder) =>
      allFolders().where((d) => d != '/' && parentOf(d) == folder).toList();

  /// Files directly inside [folder], sorted by name.
  List<LenFile> filesIn(String folder) => _files
      .where((f) => f.folder == folder)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  // --- Files --------------------------------------------------------------

  LenFile createFile(String path, NdefRecord record, {String? sourceUid}) {
    path = normalize(path);
    final error = validateName(nameOf(path));
    if (error != null) throw FileSystemException(error);
    if (exists(path)) throw FileSystemException('"$path" already exists');
    final now = DateTime.now();
    final file = LenFile(
      id: '${now.microsecondsSinceEpoch}-${_idCounter++}',
      path: path,
      record: record,
      sourceUid: sourceUid,
      created: now,
      modified: now,
    );
    _files.add(file);
    _save();
    return file;
  }

  void updateRecord(String id, NdefRecord record) {
    final file = byId(id);
    if (file == null) throw FileSystemException('File no longer exists');
    file
      ..record = record
      ..modified = DateTime.now();
    _save();
  }

  /// Renames and/or moves a file to [newPath].
  void moveFile(String id, String newPath) {
    final file = byId(id);
    if (file == null) throw FileSystemException('File no longer exists');
    newPath = normalize(newPath);
    if (newPath == file.path) return;
    final error = validateName(nameOf(newPath));
    if (error != null) throw FileSystemException(error);
    if (exists(newPath)) throw FileSystemException('"$newPath" already exists');
    file
      ..path = newPath
      ..modified = DateTime.now();
    _save();
  }

  void deleteFile(String id) {
    _files.removeWhere((f) => f.id == id);
    _save();
  }

  // --- Folders ------------------------------------------------------------

  void createFolder(String path) {
    path = normalize(path);
    final error = validateName(nameOf(path));
    if (error != null) throw FileSystemException(error);
    if (exists(path)) throw FileSystemException('"$path" already exists');
    _folders.add(path);
    _save();
  }

  /// Renames and/or moves a folder and everything inside it.
  void moveFolder(String oldPath, String newPath) {
    oldPath = normalize(oldPath);
    newPath = normalize(newPath);
    if (oldPath == '/') throw FileSystemException('Cannot move the root folder');
    if (newPath == oldPath) return;
    final error = validateName(nameOf(newPath));
    if (error != null) throw FileSystemException(error);
    if (_isInside(newPath, oldPath)) {
      throw FileSystemException('Cannot move a folder into itself');
    }
    if (exists(newPath)) throw FileSystemException('"$newPath" already exists');

    String rebase(String p) => newPath + p.substring(oldPath.length);
    for (final f in _files) {
      if (_isInside(f.path, oldPath)) f.path = rebase(f.path);
    }
    final moved = _folders
        .where((d) => d == oldPath || _isInside(d, oldPath))
        .toList();
    _folders
      ..removeAll(moved)
      ..addAll(moved.map(rebase))
      ..add(newPath);
    _save();
  }

  /// Deletes a folder and everything inside it.
  void deleteFolder(String path) {
    path = normalize(path);
    if (path == '/') throw FileSystemException('Cannot delete the root folder');
    _files.removeWhere((f) => _isInside(f.path, path));
    _folders.removeWhere((d) => d == path || _isInside(d, path));
    _save();
  }

  /// Number of files anywhere inside [folder].
  int fileCountUnder(String folder) =>
      _files.where((f) => _isInside(f.path, folder)).length;
}
