import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/services/offline_map_tile_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('offline-tiles-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Uint8List createArchive({bool includeBothLayers = true}) {
    final archive = Archive();
    final manifest = utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'layers': {
        'osm': {
          'minZoom': 15,
          'maxZoom': 18,
          'bounds': [121.683, 16.712, 121.701, 16.731],
          'attribution': '© OpenStreetMap contributors',
          'source': 'OSM data rendered for the test campus area',
        },
        'satellite': {
          'minZoom': 15,
          'maxZoom': 17,
          'bounds': [121.683, 16.712, 121.701, 16.731],
          'attribution': 'Copernicus Sentinel data',
          'source': 'Sentinel-2 true color imagery',
        },
      }
    }));
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final tile = [1, 2, 3, 4];
    archive.addFile(ArchiveFile('osm/15/0/0.png', tile.length, tile));
    if (includeBothLayers) {
      archive.addFile(ArchiveFile('satellite/15/0/0.png', tile.length, tile));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('extracts both XYZ layers and their attribution metadata', () async {
    final bytes = createArchive();
    final bundle = await OfflineMapTileBundle.extract(
      bytes,
      destination: temporaryDirectory,
    );

    expect(bundle, isNotNull);
    expect(bundle!['osm']?.maxZoom, 18);
    expect(bundle['satellite']?.maxZoom, 17);
    expect(bundle['osm']?.attribution, contains('OpenStreetMap'));
    expect(bundle['satellite']?.attribution, contains('Copernicus'));
    expect(bundle.tilePath('osm'), endsWith('/osm/{z}/{x}/{y}.png'));
    expect(
      await File('${bundle.directory.path}/osm/15/0/0.png').readAsBytes(),
      [1, 2, 3, 4],
    );
    expect(await File('${bundle.directory.path}/.complete').exists(), isTrue);
  });

  test('the bundled test map archive extracts its OSM and satellite layers',
      () async {
    final bundle = await OfflineMapTileBundle.load(
      supportDirectory: temporaryDirectory,
    );

    expect(bundle, isNotNull);
    expect(bundle!['osm']?.minZoom, 15);
    expect(bundle['osm']?.maxZoom, 18);
    expect(bundle['satellite']?.minZoom, 15);
    expect(bundle['satellite']?.maxZoom, 17);
    expect(bundle['osm']?.bounds, [121.683, 16.712, 121.701, 16.731]);
    expect(bundle['osm']?.attribution, contains('OpenStreetMap'));
    expect(bundle['satellite']?.attribution, contains('Copernicus'));
    final osmTiles = Directory('${bundle.directory.path}/osm')
        .list(recursive: true)
        .where((entity) => entity is File)
        .length;
    expect(await osmTiles, greaterThan(0));
    expect(
      await File('${bundle.directory.path}/satellite/17/109845/59362.png')
          .exists(),
      isTrue,
    );
  });

  test('rejects incomplete and path-traversal archives without installing',
      () async {
    final incomplete = await OfflineMapTileBundle.extract(
      createArchive(includeBothLayers: false),
      destination: temporaryDirectory,
    );
    expect(incomplete, isNull);
    expect(await temporaryDirectory.list().isEmpty, isTrue);

    final archive = Archive();
    final manifest = utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'layers': {},
    }));
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    const contents = [5];
    archive.addFile(ArchiveFile('../outside.png', contents.length, contents));
    final traversalBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final traversal = await OfflineMapTileBundle.extract(
      traversalBytes,
      destination: temporaryDirectory,
    );
    expect(traversal, isNull);
    expect(await File('${temporaryDirectory.parent.path}/outside.png').exists(),
        isFalse);
    expect(await temporaryDirectory.list().isEmpty, isTrue);
  });

  test('reuses an already completed extraction for the same archive', () async {
    final bytes = createArchive();
    final first = await OfflineMapTileBundle.extract(
      bytes,
      destination: temporaryDirectory,
    );
    final second = await OfflineMapTileBundle.extract(
      bytes,
      destination: temporaryDirectory,
    );

    expect(second?.directory.path, first?.directory.path);
    expect(second?.layers.keys, containsAll(['osm', 'satellite']));
  });
}
