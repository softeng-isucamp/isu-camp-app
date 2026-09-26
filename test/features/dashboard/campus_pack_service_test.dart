import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/services/campus_pack_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final catalog = utf8.encode(jsonEncode({
    'buildings': [
      {
        'id': '7',
        'name': 'Library',
        'keywords': 'aklatan',
        'description': 'Books and study',
        'latitude': 16.72,
        'longitude': 121.69,
        'rooms': [
          {
            'id': '8',
            'title': 'Reading Room',
            'category': 'room',
            'floor': '1st Floor',
            'keywords': 'study'
          }
        ]
      }
    ]
  }));
  final hash = sha256.convert(catalog).toString();

  MockClient server(
          {bool corrupt = false,
          bool fail = false,
          bool interrupted = false,
          bool incompatible = false}) =>
      MockClient((request) async {
        if (fail) throw Exception('airplane mode');
        if (request.url.path.endsWith('/manifest')) {
          return http.Response(
              jsonEncode({
                'schemaVersion': 1,
                'catalogVersion': hash,
                'minClientSchema': incompatible ? 2 : 1,
                'maxClientSchema': incompatible ? 2 : 1,
                'files': [
                  {
                    'path': 'catalog.json',
                    'url': '/campus/pack/catalog?version=$hash',
                    'size': catalog.length,
                    'sha256': hash
                  }
                ]
              }),
              200);
        }
        return http.Response.bytes(
            corrupt
                ? utf8.encode('broken')
                : interrupted
                    ? catalog.sublist(0, catalog.length ~/ 2)
                    : catalog,
            200);
      });

  test('install survives restart and is readable without network', () async {
    final progress = <int>[];
    final service =
        CampusPackService(client: server(), baseUrl: 'https://example.test');
    final pack = await service.install(
        onProgress: (received, _) => progress.add(received));
    expect(progress.last, catalog.length);
    expect(pack.buildings.single.keywords, 'aklatan');
    final restarted = CampusPackService(
        client: server(fail: true), baseUrl: 'https://example.test');
    final offline = await restarted.installed();
    expect(offline?.buildings.single.rooms.single.keywords, 'study');
    final saved =
        (await SharedPreferences.getInstance()).getString('campus_pack_v1')!;
    expect(offline?.storedBytes, utf8.encode(saved).length);
    await restarted.remove();
    expect(await restarted.installed(), isNull);
  });

  test('corrupt update keeps previously installed catalog', () async {
    final good =
        CampusPackService(client: server(), baseUrl: 'https://example.test');
    await good.install();
    final bad = CampusPackService(
        client: server(corrupt: true), baseUrl: 'https://example.test');
    await expectLater(bad.install(), throwsException);
    expect((await bad.installed())?.buildings.single.name, 'Library');
  });

  test('interrupted and incompatible updates preserve the saved pack',
      () async {
    final good =
        CampusPackService(client: server(), baseUrl: 'https://example.test');
    await good.install();
    for (final client in [
      server(interrupted: true),
      server(incompatible: true)
    ]) {
      final update =
          CampusPackService(client: client, baseUrl: 'https://example.test');
      await expectLater(update.install(), throwsException);
      expect((await update.installed())?.version, hash);
    }
  });

  test('evicted or tampered browser storage is treated as not installed',
      () async {
    final good =
        CampusPackService(client: server(), baseUrl: 'https://example.test');
    await good.install();
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('campus_pack_v1')!;
    await preferences.setString(
        'campus_pack_v1', saved.replaceFirst(hash, '0' * 64));
    expect(await good.installed(), isNull);
    await preferences.remove('campus_pack_v1');
    expect(await good.installed(), isNull);
  });
}
