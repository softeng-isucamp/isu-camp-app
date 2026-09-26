import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const offlineMapTileArchiveAsset = 'assets/offline_tiles/campus_tiles.zip';
const _maxArchiveBytes = 100 * 1024 * 1024;
const _maxExpandedBytes = 150 * 1024 * 1024;
const _maxTileCount = 10000;

class OfflineMapTileLayer {
  final String id;
  final int minZoom;
  final int maxZoom;
  final List<double> bounds;
  final String attribution;
  final String source;

  const OfflineMapTileLayer({
    required this.id,
    required this.minZoom,
    required this.maxZoom,
    required this.bounds,
    required this.attribution,
    required this.source,
  });

  factory OfflineMapTileLayer.fromJson(String id, Map<String, dynamic> json) {
    final minZoom = json['minZoom'];
    final maxZoom = json['maxZoom'];
    final rawBounds = json['bounds'];
    final attribution = json['attribution'];
    final source = json['source'];
    if (minZoom is! int ||
        maxZoom is! int ||
        minZoom < 0 ||
        maxZoom < minZoom ||
        rawBounds is! List ||
        rawBounds.length != 4 ||
        rawBounds.any((value) => value is! num) ||
        attribution is! String ||
        attribution.trim().isEmpty ||
        source is! String ||
        source.trim().isEmpty) {
      throw const FormatException('Invalid offline map layer metadata.');
    }
    final bounds = rawBounds.map((value) => (value as num).toDouble()).toList();
    if (bounds[0] >= bounds[2] || bounds[1] >= bounds[3]) {
      throw const FormatException('Invalid offline map layer bounds.');
    }
    return OfflineMapTileLayer(
      id: id,
      minZoom: minZoom,
      maxZoom: maxZoom,
      bounds: List.unmodifiable(bounds),
      attribution: attribution,
      source: source,
    );
  }
}

class OfflineMapTileBundle {
  final Directory directory;
  final Map<String, OfflineMapTileLayer> layers;

  const OfflineMapTileBundle({required this.directory, required this.layers});

  OfflineMapTileLayer? operator [](String layerId) => layers[layerId];

  String tilePath(String layerId) =>
      '${directory.path}/$layerId/{z}/{x}/{y}.png';

  static Future<OfflineMapTileBundle?> load({
    AssetBundle? assets,
    Directory? supportDirectory,
  }) async {
    try {
      final archiveData =
          await (assets ?? rootBundle).load(offlineMapTileArchiveAsset);
      if (archiveData.lengthInBytes > _maxArchiveBytes) return null;
      final bytes = archiveData.buffer
          .asUint8List(archiveData.offsetInBytes, archiveData.lengthInBytes);
      final destination = supportDirectory ??
          Directory(
              '${(await getApplicationSupportDirectory()).path}/offline_tiles');
      return await extract(bytes, destination: destination);
    } catch (_) {
      // Missing or malformed optional tile assets leave the vector campus map usable.
      return null;
    }
  }

  static Future<OfflineMapTileBundle?> extract(
    Uint8List archiveBytes, {
    required Directory destination,
  }) async {
    if (archiveBytes.length > _maxArchiveBytes) return null;
    final archiveHash = sha256.convert(archiveBytes).toString();
    final installedDirectory = Directory('${destination.path}/$archiveHash');
    final completeMarker = File('${installedDirectory.path}/.complete');
    if (await completeMarker.exists()) {
      return _bundleFromDirectory(installedDirectory);
    }

    try {
      final decoded = ZipDecoder().decodeBytes(archiveBytes);
      if (decoded.files.length > _maxTileCount + 1) return null;
      var expandedBytes = 0;
      var tileCount = 0;
      final tileLayers = <String>{};
      final entries = <String, List<int>>{};
      for (final file in decoded.files) {
        if (!file.isFile) continue;
        final name = file.name;
        if (name == 'manifest.json') {
          // accepted below
        } else if (RegExp(r'^(osm|satellite)/\d{1,2}/\d+/\d+\.png$')
            .hasMatch(name)) {
          tileCount++;
          tileLayers.add(name.split('/').first);
        } else {
          throw const FormatException('Unexpected offline tile archive entry.');
        }
        final content = file.content;
        expandedBytes += content.length;
        if (expandedBytes > _maxExpandedBytes || tileCount > _maxTileCount) {
          throw const FormatException('Offline tile archive is too large.');
        }
        entries[name] = content;
      }
      if (!entries.containsKey('manifest.json') ||
          tileCount == 0 ||
          !tileLayers.containsAll(const ['osm', 'satellite'])) {
        throw const FormatException('Offline tile archive is incomplete.');
      }
      final manifest = _parseManifest(utf8.decode(entries['manifest.json']!));
      await installedDirectory.create(recursive: true);
      for (final entry in entries.entries) {
        final file = File('${installedDirectory.path}/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      await completeMarker.writeAsString(archiveHash, flush: true);
      return OfflineMapTileBundle(
          directory: installedDirectory, layers: manifest);
    } catch (_) {
      if (await installedDirectory.exists()) {
        await installedDirectory.delete(recursive: true);
      }
      return null;
    }
  }

  static Future<OfflineMapTileBundle?> _bundleFromDirectory(
      Directory directory) async {
    try {
      final raw = await File('${directory.path}/manifest.json').readAsString();
      return OfflineMapTileBundle(
          directory: directory, layers: _parseManifest(raw));
    } catch (_) {
      await directory.delete(recursive: true);
      return null;
    }
  }

  static Map<String, OfflineMapTileLayer> _parseManifest(String raw) {
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    if (manifest['schemaVersion'] != 1 || manifest['layers'] is! Map) {
      throw const FormatException('Unsupported offline tile manifest.');
    }
    final rawLayers = Map<String, dynamic>.from(manifest['layers'] as Map);
    final layers = <String, OfflineMapTileLayer>{};
    for (final id in const ['osm', 'satellite']) {
      final value = rawLayers[id];
      if (value is Map) {
        layers[id] =
            OfflineMapTileLayer.fromJson(id, Map<String, dynamic>.from(value));
      }
    }
    if (layers.length != 2) {
      throw const FormatException(
          'Offline tile archive needs both map layers.');
    }
    return Map.unmodifiable(layers);
  }
}
