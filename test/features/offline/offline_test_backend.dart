import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/data/campus_dataset.dart';
import 'package:isu_camp_app/features/offline/services/offline_pack_service.dart';
import 'package:isu_camp_app/features/offline/services/offline_tile_math.dart';

const String testBaseUrl = 'http://api.test';
const String buildingPhoto = '$testBaseUrl/campus/photos/building/4';
const String roomPhoto = '$testBaseUrl/campus/photos/location/9';

Map<String, dynamic> fixtureBundle(String version,
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
          'imageUrl': buildingPhoto,
          'rooms': [
            {
              'id': '9',
              'title': 'Registrar',
              'category': 'office',
              'floor': 'Ground Floor',
              'imageUrl': roomPhoto,
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

class PublishedPackFixture {
  final String version;
  final Map<String, List<int>> files = {};
  late final Map<String, dynamic> manifest;

  PublishedPackFixture(this.version,
      {Map<String, dynamic>? bundle,
      int maxZoom = 15,
      Map<String, List<int>> overrides = const {}}) {
    final data = jsonDecode(jsonEncode(bundle ?? fixtureBundle(version)))
        as Map<String, dynamic>;
    data['version'] = version;
    files['bundle.json'] = utf8.encode(jsonEncode(data));
    for (final building in data['buildings'] as List) {
      for (final url in [
        building['imageUrl'],
        ...(building['rooms'] as List).map((room) => room['imageUrl'])
      ]) {
        if (url is String && url.startsWith('http')) {
          files[offlinePhotoPath(url)] = [0xFF, 0xD8, 0xFF];
        }
      }
    }
    for (final tile in tilesForBounds(
        south: isuCampusSouth,
        west: isuCampusWest,
        north: isuCampusNorth,
        east: isuCampusEast,
        minZoom: 15,
        maxZoom: maxZoom)) {
      files[tile.path] = [0x89, 0x50, 0x4E, 0x47];
    }
    files.addAll(overrides);
    manifest = {
      'schemaVersion': 1,
      'version': version,
      'generatedAt': '2026-10-14T00:00:00Z',
      'totalBytes': totalBytes,
      'files': files.entries
          .map((entry) => {
                'path': entry.key,
                'bytes': entry.value.length,
                'sha256': sha256.convert(entry.value).toString(),
              })
          .toList(),
    };
  }

  int get totalBytes =>
      files.values.fold(0, (sum, bytes) => sum + bytes.length);
}

class PackBackend {
  final Map<String, PublishedPackFixture> versions;
  PublishedPackFixture current;
  final List<http.BaseRequest> requests = [];
  Future<http.StreamedResponse?> Function(http.BaseRequest)? intercept;
  late final http.Client client = MockClient.streaming((request, _) async {
    requests.add(request);
    final response = await intercept?.call(request);
    if (response != null) return response;
    if (request.method != 'GET')
      return http.StreamedResponse(const Stream.empty(), 405);
    if (request.url.path == '/campus/offline/manifest') {
      return bytes(utf8.encode(jsonEncode(current.manifest)));
    }
    for (final pack in versions.values) {
      final prefix = '/campus/offline/packs/${pack.version}/';
      if (request.url.path.startsWith(prefix)) {
        final content = pack.files[request.url.path.substring(prefix.length)];
        if (content != null) return bytes(content);
      }
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  });

  PackBackend(this.current, {List<PublishedPackFixture> retained = const []})
      : versions = {
          current.version: current,
          for (final pack in retained) pack.version: pack
        };

  static http.StreamedResponse bytes(List<int> content) =>
      http.StreamedResponse(Stream.value(content), 200,
          contentLength: content.length);
}
