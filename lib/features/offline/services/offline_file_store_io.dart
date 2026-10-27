import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk cache for the offline campus pack.
///
/// Paths are relative, '/'-separated keys such as `tiles/17/98304/56274.png`.
/// The set of stored keys is held in memory so widgets can decide
/// synchronously whether a tile or photo is already downloaded.
class OfflineFileStore {
  OfflineFileStore({String? rootPath}) : _rootPath = rootPath;

  String? _rootPath;
  final Set<String> _storedPaths = <String>{};
  bool _isOpen = false;

  bool get isSupported => true;

  /// Creates the cache directory and indexes what is already downloaded.
  /// Returns false when the platform denies a writable directory.
  Future<bool> open() async {
    if (_isOpen) return true;
    try {
      _rootPath ??=
          p.join((await getApplicationSupportDirectory()).path, 'offline_map');
      final root = Directory(_rootPath!);
      await root.create(recursive: true);
      _storedPaths
        ..clear()
        ..addAll(await root
            .list(recursive: true, followLinks: false)
            .where((entity) => entity is File)
            .map((entity) => p.url
                .joinAll(p.split(p.relative(entity.path, from: _rootPath!))))
            .toSet());
      _isOpen = true;
      return true;
    } catch (_) {
      // A missing plugin or a read-only sandbox means no offline pack, not a
      // crash: the app keeps working online.
      return false;
    }
  }

  Set<String> get storedPaths => Set.unmodifiable(_storedPaths);

  bool contains(String path) => _isOpen && _storedPaths.contains(path);

  Future<void> write(String path, Uint8List bytes) async {
    final file = File(_absolute(path));
    await file.parent.create(recursive: true);
    // Write beside the target first so an interrupted download never leaves a
    // truncated tile or photo behind.
    final staged = File('${file.path}.part');
    await staged.writeAsBytes(bytes, flush: true);
    await staged.rename(file.path);
    _storedPaths.add(path);
  }

  Future<void> writeText(String path, String contents) async {
    await write(path, Uint8List.fromList(utf8.encode(contents)));
  }

  Future<Uint8List?> readBytes(String path) async {
    try {
      return await File(_absolute(path)).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> matches(String path, int sizeBytes, String checksum) async {
    if (!contains(path)) return false;
    try {
      final file = File(_absolute(path));
      return await file.length() == sizeBytes &&
          (await crypto.sha256.bind(file.openRead()).first).toString() ==
              checksum;
    } on FileSystemException {
      return false;
    }
  }

  Future<String?> readText(String path) async {
    try {
      return await File(_absolute(path)).readAsString();
    } catch (_) {
      return null;
    }
  }

  ImageProvider? imageFor(String path) =>
      contains(path) ? FileImage(File(_absolute(path))) : null;

  Future<int> bytesOnDisk() async {
    if (!_isOpen) return 0;
    var total = 0;
    try {
      // Resume metadata and interrupted staging files are not pack payload.
      for (final path in _storedPaths.toList()) {
        if (path == 'meta.json' || path.endsWith('.part')) continue;
        total += await File(_absolute(path)).length();
      }
    } catch (_) {
      return total;
    }
    return total;
  }

  /// Removes every cached file whose key starts with [prefix].
  Future<void> deletePrefix(String prefix) async {
    if (!_isOpen) return;
    for (final path
        in _storedPaths.where((p) => p.startsWith(prefix)).toList()) {
      try {
        await File(_absolute(path)).delete();
      } catch (_) {
        // Already gone; dropping the index entry is all that is left to do.
      }
      _storedPaths.remove(path);
    }
  }

  Future<void> deleteAll() async {
    if (_rootPath == null) return;
    final root = Directory(_rootPath!);
    if (await root.exists()) await root.delete(recursive: true);
    _storedPaths.clear();
    await root.create(recursive: true);
  }

  String _absolute(String path) =>
      p.joinAll([_rootPath!, ...p.url.split(path)]);
}
