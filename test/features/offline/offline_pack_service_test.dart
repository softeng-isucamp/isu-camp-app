import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/data/campus_dataset.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/services/campus_service.dart';
import 'package:isu_camp_app/features/offline/models/offline_pack.dart';
import 'package:isu_camp_app/features/offline/services/offline_file_store.dart';
import 'package:isu_camp_app/features/offline/services/offline_pack_service.dart';
import 'package:latlong2/latlong.dart';

/// 1126 map tiles cover the campus box over zooms 15-19, plus the dataset
/// itself and its two photos.
const int _tileCount = 1126;
const int _photoCount = 2;
const int _totalFiles = 1 + _photoCount + _tileCount;

const String _baseUrl = 'http://api.test';
const String _buildingPhoto = '$_baseUrl/campus/photos/building/4';
const String _roomPhoto = '$_baseUrl/campus/photos/location/9';

Map<String, dynamic> _bundle(String version,
        {String name = 'Admin Building'}) =>
    {
      'version': version,
      'generatedAt': '2026-10-14T00:00:00Z',
      'skippedCount': 0,
      'buildings': [
        {
          'id': '5',
          'name': name,
          'acronym': 'ADM',
          'category': 'Academic Building',
          'description': 'Registrar and cashier',
          'latitude': 16.7220,
          'longitude': 121.6900,
          'imageUrl': _buildingPhoto,
          'rooms': [
            {
              'id': '9',
              'title': 'Registrar',
              'category': 'office',
              'floor': 'Ground Floor',
              'imageUrl': _roomPhoto,
            }
          ],
        }
      ],
      'graph': {
        'nodes': [
          {
            'node_id': 1,
            'building_id': null,
            'latitude': 16.7200,
            'longitude': 121.6900,
            'node_type': 'junction',
            'status': 'active',
            'name': 'Main Gate',
          },
          {
            'node_id': 3,
            'building_id': 5,
            'latitude': 16.7220,
            'longitude': 121.6900,
            'node_type': 'entrance',
            'status': 'active',
            'name': 'Admin entrance',
          },
        ],
        'pathways': [
          {
            'pathway_id': 10,
            'source_node_id': 1,
            'destination_node_id': 3,
            'status': 'active',
            'direction': 'twoway',
            'shade': 'mostly shaded',
            'name': 'Front walkway',
          }
        ],
        'modes': [
          {'pathway_id': 10, 'mode': 'Walking'}
        ],
        'points': const [],
      },
    };

/// Records what the app asked for, so a test can prove what it did not ask for.
class _Recorder {
  final List<String> requests = [];

  int get bundleRequests =>
      requests.where((url) => url.endsWith('/offline/bundle')).length;
  int get manifestRequests =>
      requests.where((url) => url.endsWith('/offline/manifest')).length;
  int get tileRequests =>
      requests.where((url) => url.contains('tile.openstreetmap.org')).length;
  int get photoRequests =>
      requests.where((url) => url.contains('/campus/photos/')).length;
}

void main() {
  late Directory root;
  late _Recorder recorder;
  final OfflinePackService liveInstance = OfflinePackService.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kumpas_offline_test');
    recorder = _Recorder();
  });

  tearDown(() {
    OfflinePackService.instance = liveInstance;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// [onTile] can pause or fail the download part way through.
  MockClient backend(
    String version, {
    String name = 'Admin Building',
    http.Response? Function(int tileNumber)? onTile,
  }) {
    var tiles = 0;
    return MockClient((request) async {
      final url = request.url.toString();
      recorder.requests.add(url);
      if (url.endsWith('/campus/offline/bundle')) {
        return http.Response(jsonEncode(_bundle(version, name: name)), 200);
      }
      if (url.endsWith('/campus/offline/manifest')) {
        return http.Response(jsonEncode({'version': version}), 200);
      }
      if (url.contains('tile.openstreetmap.org')) {
        final interrupt = onTile?.call(++tiles);
        if (interrupt != null) return interrupt;
        return http.Response.bytes([0x89, 0x50, 0x4E, 0x47], 200);
      }
      return http.Response.bytes([0xFF, 0xD8, 0xFF], 200);
    });
  }

  OfflinePackService serviceFor(http.Client client) => OfflinePackService(
        store: OfflineFileStore(rootPath: root.path),
        client: client,
        baseUrl: () => _baseUrl,
      );

  test('downloading stores the dataset, its photos, and every campus tile',
      () async {
    final service = serviceFor(backend('v1'));
    await service.load();
    expect(service.status.state, OfflinePackState.absent);

    await service.download();

    expect(service.status.state, OfflinePackState.ready);
    expect(service.status.installedVersion, 'v1');
    expect(service.status.totalFiles, _totalFiles);
    expect(service.status.completedFiles, _totalFiles);
    expect(service.status.message, isNull);
    expect(service.status.bytesOnDisk, greaterThan(0));
    expect(service.status.sizeLabel, isNot('0 MB'));

    expect(recorder.bundleRequests, 1);
    expect(recorder.photoRequests, _photoCount);
    expect(recorder.tileRequests, _tileCount);

    expect(service.buildings!.single.name, 'Admin Building');
    expect(service.buildings!.single.rooms.single.title, 'Registrar');
    expect(service.photoImage(_buildingPhoto), isNotNull);
    expect(service.photoImage(_roomPhoto), isNotNull);
    expect(service.tileImage(15, 27459, 14838), isNotNull);
    expect(service.tileImage(19, 439357, 237452), isNotNull);
    expect(service.tileImage(19, 1, 1), isNull);
  });

  for (final fail in [false, true]) {
    test(
        'live chunks are counted once and ${fail ? 'discarded on failure' : 'committed on success'}',
        () async {
      final firstChunkSeen = Completer<void>();
      final finishResponse = Completer<void>();
      late OfflinePackService service;
      var liveBytes = 0;
      Stream<List<int>> photo() async* {
        yield List.filled(128 * 1024, 1);
        await firstChunkSeen.future;
        await finishResponse.future;
        if (fail) throw http.ClientException('Connection lost');
        yield List.filled(128 * 1024, 2);
      }

      service = OfflinePackService(
        store: OfflineFileStore(rootPath: root.path),
        maxTileZoom: 15,
        baseUrl: () => _baseUrl,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/offline/bundle')) {
            return http.StreamedResponse(
                Stream.value(utf8.encode(jsonEncode(_bundle('v1')))), 200);
          }
          if (request.url.toString() == _buildingPhoto) {
            return http.StreamedResponse(photo(), 200);
          }
          return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
        }),
      );
      service.addListener(() {
        if (service.status.bytesInFlight >= 128 * 1024 &&
            !firstChunkSeen.isCompleted) {
          liveBytes = service.status.downloadedBytes;
          firstChunkSeen.complete();
        }
      });
      final download = service.download();
      await firstChunkSeen.future.timeout(const Duration(seconds: 5));
      expect(service.status.isBusy, isTrue);
      expect(service.photoImage(_buildingPhoto), isNull,
          reason: 'progress must advance before the file is saved');
      finishResponse.complete();
      await download;
      expect(service.status.bytesInFlight, 0);
      expect(service.status.state,
          fail ? OfflinePackState.incomplete : OfflinePackState.ready);
      if (fail) {
        expect(service.status.bytesOnDisk, lessThan(liveBytes));
        expect(service.photoImage(_buildingPhoto), isNull);
      } else {
        // One bundle, two photos and nine tiles; metadata is small.
        final payloadBytes = utf8.encode(jsonEncode(_bundle('v1'))).length +
            256 * 1024 +
            3 +
            9 * 3;
        expect(service.status.bytesOnDisk,
            inInclusiveRange(payloadBytes, payloadBytes + 1024));
        expect(service.photoImage(_buildingPhoto), isNotNull);
      }
    });
  }

  test('a stored photo is reused when only the API host changes', () async {
    final service = serviceFor(backend('v1'));
    await service.download();

    expect(
      service.photoImage('https://api.kumpas.live/campus/photos/building/4'),
      isNotNull,
    );
  });

  test('directions are computed on the device from the stored graph', () async {
    final service = serviceFor(backend('v1'));
    await service.download();
    final before = recorder.requests.length;

    final routes = service.offlineRoutes(
      origin: const NavigationOrigin(
        id: 'main_gate',
        label: 'Main Gate',
        coordinate: LatLng(16.7200, 121.6900),
        type: NavigationOriginType.mainGate,
      ),
      destination: service.buildings!.single,
      mode: TransportMode.walking,
    );

    expect(recorder.requests.length, before, reason: 'no network for routing');
    expect(routes, hasLength(2));
    expect(routes.first.type, RouteType.shortest);
    expect(routes.last.type, RouteType.comfortableShaded);
    expect(routes.first.distanceMeters, closeTo(222.39, 0.01));
    expect(routes.first.startNodeName, 'Main Gate');
    expect(routes.first.instructions, ['Follow Front walkway']);
  });

  test('an available update is announced but never downloaded', () async {
    final service = serviceFor(backend('v1'));
    await service.download();

    // The backend now publishes a different dataset.
    final updated = serviceFor(backend('v2', name: 'Admin Hall'));
    await updated.load();
    recorder.requests.clear();

    expect(await updated.checkForUpdate(), isTrue);
    expect(updated.status.hasUpdate, isTrue);
    expect(updated.status.updateVersion, 'v2');
    expect(updated.status.lastCheckedAt, isNotNull);
    // Nothing was replaced: the stored map still answers with the old data.
    expect(updated.status.installedVersion, 'v1');
    expect(updated.buildings!.single.name, 'Admin Building');
    expect(recorder.manifestRequests, 1);
    expect(recorder.bundleRequests, 0);
    expect(recorder.tileRequests, 0);

    // The notice survives a restart so the user can act on it later.
    final restarted = serviceFor(backend('v2', name: 'Admin Hall'));
    await restarted.load();
    expect(restarted.status.hasUpdate, isTrue);
  });

  test('accepting the update replaces the dataset and clears the notice',
      () async {
    final service = serviceFor(backend('v1'));
    await service.download();

    final updated = serviceFor(backend('v2', name: 'Admin Hall'));
    await updated.load();
    await updated.checkForUpdate();
    recorder.requests.clear();

    await updated.download();

    expect(updated.status.installedVersion, 'v2');
    expect(updated.status.hasUpdate, isFalse);
    expect(updated.status.state, OfflinePackState.ready);
    expect(updated.buildings!.single.name, 'Admin Hall');
    // Photos belong to their dataset and are fetched again; tiles do not change.
    expect(recorder.photoRequests, _photoCount);
    expect(recorder.tileRequests, 0);
  });

  test('up-to-date means no notice and no download', () async {
    final service = serviceFor(backend('v1'));
    await service.download();
    recorder.requests.clear();

    expect(await service.checkForUpdate(), isFalse);
    expect(service.status.hasUpdate, isFalse);
    expect(service.status.lastCheckedAt, isNotNull);
    expect(recorder.bundleRequests, 0);
  });

  test('pausing keeps finished files and resuming downloads only the rest',
      () async {
    late OfflinePackService service;
    service = serviceFor(backend('v1', onTile: (number) {
      if (number == 60) service.pause();
      return null;
    }));

    await service.download();

    expect(service.status.state, OfflinePackState.incomplete);
    expect(service.status.completedFiles, lessThan(_totalFiles));
    expect(service.status.completedFiles, greaterThan(_photoCount));
    expect(service.status.message, contains('Paused'));
    final savedBytes = service.status.bytesOnDisk;
    expect(service.status.bytesInFlight, 0);
    final downloadedSoFar = recorder.tileRequests;
    expect(downloadedSoFar, lessThan(_tileCount));

    recorder.requests.clear();
    final resumedBytes = <int>[];
    service.addListener(() {
      if (service.status.isBusy)
        resumedBytes.add(service.status.downloadedBytes);
    });
    await service.download();

    expect(resumedBytes.first, savedBytes);
    expect(service.status.state, OfflinePackState.ready);
    expect(service.status.completedFiles, _totalFiles);
    expect(recorder.photoRequests, 0, reason: 'photos were already stored');
    expect(recorder.tileRequests, _tileCount - downloadedSoFar);
  });

  test('a half-finished download is still pending after a restart', () async {
    late OfflinePackService service;
    service = serviceFor(backend('v1', onTile: (number) {
      if (number == 60) service.pause();
      return null;
    }));
    await service.download();

    final restarted = serviceFor(backend('v1'));
    await restarted.load();

    expect(restarted.status.state, OfflinePackState.incomplete);
    expect(restarted.status.installedVersion, 'v1');
    expect(restarted.status.message, contains('Resume'));
  });

  test('a failing tile host stops the download instead of hammering it',
      () async {
    final service = serviceFor(
        backend('v1', onTile: (_) => http.Response('rate limited', 429)));

    await service.download();

    expect(service.status.state, OfflinePackState.incomplete);
    expect(service.status.message, contains('connection problem'));
    // The failure budget stops it long before all 1126 tiles are attempted.
    expect(recorder.tileRequests, lessThan(40));
  });

  test('an unreachable backend leaves an installed pack usable', () async {
    final service = serviceFor(backend('v1'));
    await service.download();

    final offline = serviceFor(MockClient((request) async {
      throw http.ClientException('Connection failed', request.url);
    }));
    await offline.load();
    expect(offline.status.state, OfflinePackState.ready);

    expect(await offline.checkForUpdate(), isFalse);
    await offline.download();

    expect(offline.status.state, OfflinePackState.ready,
        reason: 'a failed update attempt must not discard the stored map');
    expect(offline.status.message, contains('connection'));
    expect(offline.buildings!.single.name, 'Admin Building');
  });

  test('a failed update leaves a half-finished pack half-finished', () async {
    late OfflinePackService service;
    service = serviceFor(backend('v1', onTile: (number) {
      if (number == 60) service.pause();
      return null;
    }));
    await service.download();
    expect(service.status.state, OfflinePackState.incomplete);

    final offline = serviceFor(MockClient((request) async {
      throw http.ClientException('Connection failed', request.url);
    }));
    await offline.load();
    expect(offline.status.state, OfflinePackState.incomplete);

    await offline.download();

    expect(offline.status.state, OfflinePackState.incomplete,
        reason: 'an unreachable backend must not mark the pack complete');
  });

  test('deleting removes every stored file', () async {
    final service = serviceFor(backend('v1'));
    await service.download();
    expect(root.listSync(recursive: true), isNotEmpty);

    await service.delete();

    expect(service.status.state, OfflinePackState.absent);
    expect(service.status.installedVersion, isNull);
    expect(service.buildings, isNull);
    expect(service.photoImage(_buildingPhoto), isNull);
    expect(service.tileImage(15, 27459, 14838), isNull);
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('the live map reads the stored pack when the network drops', () async {
    final service = serviceFor(backend('v1'));
    await service.download();
    OfflinePackService.instance = service;

    await http.runWithClient(() async {
      final buildings = await CampusService.fetchBuildings();
      expect(buildings.single.name, 'Admin Building');

      final routes = await CampusService.fetchRoutes(
        const NavigationOrigin(
          id: 'main_gate',
          label: 'Main Gate',
          coordinate: LatLng(16.7200, 121.6900),
          type: NavigationOriginType.mainGate,
        ),
        buildings.single,
      );
      expect(routes, hasLength(2));
      expect(routes.first.distanceMeters, closeTo(222.39, 0.01));
    },
        () => MockClient((request) async {
              throw http.ClientException('Connection failed', request.url);
            }));
  });

  test('a real backend error is reported, not replaced by stored data',
      () async {
    final service = serviceFor(backend('v1'));
    await service.download();
    OfflinePackService.instance = service;

    await http.runWithClient(() async {
      await expectLater(
        CampusService.fetchRoutes(
          const NavigationOrigin(
            id: 'main_gate',
            label: 'Main Gate',
            coordinate: LatLng(16.7200, 121.6900),
            type: NavigationOriginType.mainGate,
          ),
          service.buildings!.single,
        ),
        throwsA(isA<Exception>().having((error) => error.toString(), 'message',
            contains('no active entrance'))),
      );
    },
        () => MockClient((request) async => http.Response(
            jsonEncode({'detail': 'This building has no active entrance.'}),
            404)));
  });

  test('the campus tile template and cache keys agree', () {
    expect(campusTileUrlTemplate, contains('{z}/{x}/{y}'));
    expect(offlinePhotoPath(_buildingPhoto),
        offlinePhotoPath('https://elsewhere.test/campus/photos/building/4'));
    expect(
        offlinePhotoPath(_buildingPhoto), isNot(offlinePhotoPath(_roomPhoto)));
  });
}
