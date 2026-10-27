import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:isu_camp_app/features/offline/models/offline_pack.dart';
import 'package:isu_camp_app/features/offline/services/offline_file_store.dart';
import 'package:isu_camp_app/features/offline/services/offline_pack_service.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:latlong2/latlong.dart';

import 'offline_test_backend.dart';

void main() {
  late Directory root;
  late PublishedPackFixture fixture;
  late PackBackend backend;
  OfflinePackService service() => OfflinePackService(
      store: OfflineFileStore(rootPath: root.path),
      client: backend.client,
      baseUrl: () => testBaseUrl);

  setUp(() {
    root = Directory.systemTemp.createTempSync('prebuilt_offline');
    fixture = PublishedPackFixture('v1');
    backend = PackBackend(fixture);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
      'manifest total is known before the first payload; no HEAD or live sources',
      () async {
    final pack = service();
    backend.intercept = (request) async {
      if (request.url.path.contains('/packs/')) {
        expect(pack.status.totalBytes, fixture.totalBytes);
        expect(pack.status.isBusy, isTrue);
      }
      return null;
    };
    await pack.download();
    expect(pack.status.isReady, isTrue);
    expect(pack.status.totalBytes, fixture.totalBytes);
    expect(pack.status.bytesOnDisk, fixture.totalBytes);
    expect(pack.status.progress, 1);
    expect(backend.requests.first.url.path, '/campus/offline/manifest');
    expect(backend.requests, hasLength(1 + fixture.files.length));
    expect(
        backend.requests.map((request) => request.method), everyElement('GET'));
    expect(backend.requests.map((request) => request.url.host),
        everyElement('api.test'));
    expect(pack.photoImage(buildingPhoto), isNotNull);
    expect(pack.tileImage(15, 27459, 14838), isNotNull);
    final bytes = File('${root.path}/packs/v1/bundle.json').readAsBytesSync();
    expect(bytes, fixture.files['bundle.json'],
        reason: 'JSON must not be re-encoded');
  });

  test('full campus pack includes all 1,126 tiles', () async {
    fixture = PublishedPackFixture('full', maxZoom: 19);
    backend = PackBackend(fixture);
    final pack = service();
    await pack.download();
    expect(pack.status.isReady, isTrue);
    expect(pack.status.completedFiles, 1 + 2 + 1126);
    expect(pack.tileImage(19, 439357, 237452), isNotNull);
    expect(pack.status.bytesOnDisk, fixture.totalBytes);
  });

  test('pause/restart stays pinned even when a newer pack is published',
      () async {
    final pack = service();
    backend.intercept = (request) async {
      if (request.url.path.contains('/tiles/')) pack.pause();
      return null;
    };
    await pack.download();
    expect(pack.status.state, OfflinePackState.incomplete);
    expect(pack.status.totalBytes, fixture.totalBytes);
    final savedCount = pack.status.completedFiles;
    final savedBytes = pack.status.bytesOnDisk;
    final newer = PublishedPackFixture('v2');
    backend.versions[newer.version] = newer;
    backend.current = newer;
    backend.intercept = null;
    backend.requests.clear();
    final restarted = service();
    await restarted.load();
    expect(restarted.status.totalBytes, fixture.totalBytes);
    expect(restarted.status.bytesOnDisk, savedBytes);
    await restarted.download();
    expect(restarted.status.installedVersion, 'v1');
    expect(restarted.status.isReady, isTrue);
    expect(backend.requests, hasLength(fixture.files.length - savedCount));
    expect(
        backend.requests
            .every((request) => request.url.path.contains('/packs/v1/')),
        isTrue);
  });

  test('update notices do not download; unchanged verified files are reused',
      () async {
    final pack = service();
    await pack.download();
    final updated = PublishedPackFixture('v2',
        bundle: fixtureBundle('v2', name: 'Admin Hall'));
    backend.versions[updated.version] = updated;
    backend.current = updated;
    backend.requests.clear();
    expect(await pack.checkForUpdate(), isTrue);
    expect(pack.status.hasUpdate, isTrue);
    expect(backend.requests.single.url.path, '/campus/offline/manifest');
    expect(pack.buildings!.single.name, 'Admin Building');
    backend.requests.clear();
    await pack.download(update: true);
    expect(pack.status.isReady, isTrue);
    expect(pack.status.installedVersion, 'v2');
    expect(pack.status.hasUpdate, isFalse);
    expect(pack.buildings!.single.name, 'Admin Hall');
    expect(backend.requests.map((request) => request.url.path),
        ['/campus/offline/manifest', '/campus/offline/packs/v2/bundle.json']);
  });

  test('corrupted cached file is downloaded again; correct ones are skipped',
      () async {
    final pack = service();
    await pack.download();
    final tile =
        fixture.files.keys.firstWhere((path) => path.startsWith('tiles/'));
    File('${root.path}/packs/v1/$tile').writeAsBytesSync([0, 0, 0, 0]);
    backend.requests.clear();
    await pack.download();
    expect(pack.status.isReady, isTrue);
    expect(backend.requests.map((request) => request.url.path),
        ['/campus/offline/manifest', '/campus/offline/packs/v1/$tile']);
  });

  for (final badLength in [false, true]) {
    test(
        'rejects ${badLength ? 'wrong size' : 'wrong checksum'} before cache commit',
        () async {
      final pack = service();
      final path = offlinePhotoPath(buildingPhoto);
      backend.intercept = (request) async {
        if (request.url.path.endsWith(path)) {
          return PackBackend.bytes(badLength ? [0, 0, 0, 0] : [0, 0, 0]);
        }
        return null;
      };
      await pack.download();
      expect(pack.status.state, OfflinePackState.incomplete);
      expect(pack.photoImage(buildingPhoto), isNull);
      expect(pack.status.totalBytes, fixture.totalBytes);
      expect(pack.status.bytesOnDisk,
          fixture.totalBytes - fixture.files[path]!.length);
      expect(pack.status.bytesInFlight, 0);
      expect(pack.status.message, contains('verification'));
    });
  }

  test(
      'large streamed photo updates numerator with the fixed precomputed denominator',
      () async {
    final photo = offlinePhotoPath(buildingPhoto);
    fixture = PublishedPackFixture('v1',
        overrides: {photo: List.filled(256 * 1024, 1)});
    backend = PackBackend(fixture);
    final seen = Completer<void>();
    final finish = Completer<void>();
    Stream<List<int>> stream() async* {
      yield List.filled(128 * 1024, 1);
      await finish.future;
      yield List.filled(128 * 1024, 1);
    }

    backend.intercept = (request) async => request.url.path.endsWith(photo)
        ? http.StreamedResponse(stream(), 200, contentLength: 256 * 1024)
        : null;
    final pack = service();
    pack.addListener(() {
      if (pack.status.isBusy &&
          pack.status.bytesInFlight >= 128 * 1024 &&
          !seen.isCompleted) {
        expect(pack.status.totalBytes, fixture.totalBytes);
        expect(pack.photoImage(buildingPhoto), isNull);
        seen.complete();
      }
    });
    final download = pack.download();
    await seen.future.timeout(const Duration(seconds: 5));
    finish.complete();
    await download;
    expect(pack.status.isReady, isTrue);
    expect(pack.status.totalBytes, fixture.totalBytes);
    expect(pack.status.bytesOnDisk, fixture.totalBytes);
  });

  for (final malformed in [
    'legacy',
    'total',
    'duplicate',
    'path',
    'checksum'
  ]) {
    test('rejects $malformed manifest without requesting payloads', () async {
      final manifest =
          jsonDecode(jsonEncode(fixture.manifest)) as Map<String, dynamic>;
      switch (malformed) {
        case 'legacy':
          manifest.remove('schemaVersion');
        case 'total':
          manifest['totalBytes'] = 1;
        case 'duplicate':
          (manifest['files'] as List).add(manifest['files'][0]);
        case 'path':
          manifest['files'][0]['path'] = '../meta.json';
        case 'checksum':
          manifest['files'][0]['sha256'] = 'invalid';
      }
      backend.intercept =
          (_) async => PackBackend.bytes(utf8.encode(jsonEncode(manifest)));
      final pack = service();
      await pack.download();
      expect(pack.status.isReady, isFalse);
      expect(pack.status.state, OfflinePackState.absent);
      expect(backend.requests, hasLength(1));
    });
  }

  test(
      'unavailable published pack preserves an installed pack and never probes sources',
      () async {
    final pack = service();
    await pack.download();
    backend.requests.clear();
    backend.intercept =
        (_) async => http.StreamedResponse(const Stream.empty(), 503);
    await pack.download(update: true);
    expect(pack.status.isReady, isTrue);
    expect(pack.status.installedVersion, 'v1');
    expect(pack.status.message, contains('being prepared'));
    expect(backend.requests, hasLength(1));
  });

  test('legacy ready packs remain usable and can reuse verified legacy files',
      () async {
    final old = OfflineFileStore(rootPath: root.path);
    await old.open();
    for (final entry in fixture.files.entries) {
      await old.write(entry.key, Uint8List.fromList(entry.value));
    }
    await old.writeText(
        'meta.json', jsonEncode({'version': 'v1', 'complete': true}));
    final pack = service();
    await pack.load();
    expect(pack.status.isReady, isTrue);
    expect(pack.photoImage(buildingPhoto), isNotNull);
    await pack.download();
    expect(pack.status.isReady, isTrue);
    expect(backend.requests.single.url.path, '/campus/offline/manifest');
  });

  test(
      'offline graph routes and versioned photos remain available after restart',
      () async {
    await service().download();
    final pack = service();
    await pack.load();
    final routes = pack.offlineRoutes(
        origin: const NavigationOrigin(
            id: 'main_gate',
            label: 'Main Gate',
            coordinate: LatLng(16.7200, 121.6900),
            type: NavigationOriginType.mainGate),
        destination: pack.buildings!.single,
        mode: TransportMode.walking);
    expect(routes, hasLength(2));
    expect(pack.photoImage(buildingPhoto), isNotNull);
    expect(pack.status.totalBytes, fixture.totalBytes);
    await pack.delete();
    expect(pack.status.state, OfflinePackState.absent);
    expect(pack.buildings, isNull);
    expect(pack.tileImage(15, 27459, 14838), isNull);
  });
  test('pausing while loading the manifest does not start payload downloads',
      () async {
    final ready = Completer<void>();
    final release = Completer<void>();
    backend.intercept = (request) async {
      if (request.url.path.endsWith('/manifest')) {
        ready.complete();
        await release.future;
      }
      return null;
    };
    final pack = service();
    final download = pack.download();
    await ready.future;
    pack.pause();
    release.complete();
    await download;
    expect(backend.requests, hasLength(1));
    expect(pack.status.isBusy, isFalse);
    expect(pack.status.message, contains('Paused'));
  });
}
