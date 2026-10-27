import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Web stand-in for the download cache. Browsers already cache the campus map
/// themselves, so the offline pack is only offered on installed platforms.
class OfflineFileStore {
  OfflineFileStore({String? rootPath});

  bool get isSupported => false;

  Future<bool> open() async => false;

  Set<String> get storedPaths => const {};

  bool contains(String path) => false;

  Future<void> write(String path, Uint8List bytes) async {}

  Future<void> writeText(String path, String contents) async {}

  Future<Uint8List?> readBytes(String path) async => null;

  Future<bool> matches(String path, int sizeBytes, String checksum) async =>
      false;

  Future<String?> readText(String path) async => null;

  ImageProvider? imageFor(String path) => null;

  Future<int> bytesOnDisk() async => 0;

  Future<void> deletePrefix(String prefix) async {}

  Future<void> deleteAll() async {}
}
