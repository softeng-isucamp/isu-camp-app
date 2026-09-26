import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/dashboard/services/history_local_store.dart';
import 'package:isu_camp_app/features/dashboard/services/navigation_history_service.dart';

class MemoryHistoryStore implements HistoryLocalStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String account) async => values[account];

  @override
  Future<void> write(String account, String value) async {
    values[account] = value;
  }
}

void main() {
  late HistoryLocalStore originalStore;
  late MemoryHistoryStore local;
  setUp(() {
    originalStore = NavigationHistoryService.store;
    local = MemoryHistoryStore();
    NavigationHistoryService.store = local;
    UserSession.setLoggedInUser(username: 'student', token: 'signed-session');
  });
  tearDown(() {
    NavigationHistoryService.store = originalStore;
    UserSession.clearMemory();
  });

  test('loads joined database names with the session and handles pagination',
      () async {
    var calls = 0;
    await http.runWithClient(() async {
      final entries = await NavigationHistoryService.load();
      expect(entries, hasLength(101));
      expect(entries.first.roomName, 'Lab');
      expect(entries.first.destinationName, 'CCSICT');
      expect(calls, 2);
    },
        () => MockClient((request) async {
              expect(request.headers['Authorization'], 'Bearer signed-session');
              expect(request.url.queryParameters['offset'],
                  calls == 0 ? '0' : '100');
              calls++;
              return http.Response(
                  jsonEncode({
                    'entries': List.generate(
                        calls == 1 ? 100 : 1,
                        (i) => {
                              'id': '${calls * 100 + i}',
                              'destinationId': '8',
                              'destinationName': 'CCSICT',
                              'destinationAcronym': 'CCS',
                              'roomId': '9',
                              'roomName': 'Lab',
                              'createdAt': '2026-09-20T01:00:00Z',
                            })
                  }),
                  200);
            }));
  });

  test('record persists before sending foreign keys with an idempotency key',
      () async {
    await http.runWithClient(() async {
      await NavigationHistoryService.record(
          buildingId: '8', destinationName: 'CCSICT');
      expect(jsonDecode(local.values['student']!)['pending'], hasLength(1));
      await NavigationHistoryService.syncPending();
      expect(jsonDecode(local.values['student']!)['pending'], isEmpty);
    },
        () => MockClient((request) async {
              expect(request.method, 'POST');
              expect(request.headers['Authorization'], 'Bearer signed-session');
              final body = jsonDecode(request.body);
              expect(body['buildingId'], 8);
              expect(body['locationId'], isNull);
              expect(
                  body['clientEventId'],
                  matches(RegExp(
                      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
              return http.Response('{"id":"1"}', 201);
            }));
  });

  test('offline History survives restart and retries the same event', () async {
    await NavigationHistoryService.record(
        buildingId: '8', destinationName: 'CCSICT');
    final eventId =
        jsonDecode(local.values['student']!)['pending'][0]['clientEventId'];
    UserSession.clearMemory();
    UserSession.setLoggedInUser(username: 'student', token: 'signed-session');
    await http.runWithClient(() async {
      final entries = await NavigationHistoryService.load();
      expect(entries.single.id, 'local:$eventId');
      expect(entries.single.destinationName, 'CCSICT');
    }, () => MockClient((_) async => throw Exception('offline')));

    final sentIds = <String>[];
    await http.runWithClient(() async {
      await NavigationHistoryService.syncPending();
      expect(jsonDecode(local.values['student']!)['pending'], isEmpty);
      final entries = await NavigationHistoryService.load();
      expect(entries, hasLength(1));
      expect(entries.single.id, '42');
    },
        () => MockClient((request) async {
              if (request.method == 'POST') {
                sentIds
                    .add(jsonDecode(request.body)['clientEventId'] as String);
                return http.Response('{"id":"42"}', 201);
              }
              return http.Response(
                  jsonEncode({
                    'entries': [
                      {
                        'id': '42',
                        'destinationId': '8',
                        'destinationName': 'CCSICT',
                        'destinationAcronym': 'CCS',
                        'roomId': null,
                        'roomName': null,
                        'clientEventId': eventId,
                        'createdAt': '2026-09-20T01:00:00Z'
                      }
                    ]
                  }),
                  200);
            }));
    expect(sentIds, [eventId]);
  });

  test('failed upload stays queued and retries with the same UUID', () async {
    await NavigationHistoryService.record(
        buildingId: '8', destinationName: 'CCSICT');
    final sentIds = <String>[];
    var attempts = 0;
    await http.runWithClient(() async {
      await NavigationHistoryService.syncPending();
      expect(jsonDecode(local.values['student']!)['pending'], hasLength(1));
      await NavigationHistoryService.syncPending();
      expect(jsonDecode(local.values['student']!)['pending'], isEmpty);
    },
        () => MockClient((request) async {
              sentIds.add(jsonDecode(request.body)['clientEventId'] as String);
              attempts++;
              return attempts == 1
                  ? http.Response('{"detail":"temporary"}', 503)
                  : http.Response('{"id":"42"}', 201);
            }));
    expect(sentIds, [sentIds.first, sentIds.first]);
  });

  test('pending History remains private to the signed-in account', () async {
    await NavigationHistoryService.record(
        buildingId: '8', destinationName: 'CCSICT');
    UserSession.setLoggedInUser(username: 'other', token: 'other-token');
    await http.runWithClient(() async {
      await expectLater(NavigationHistoryService.load(), throwsException);
    }, () => MockClient((_) async => throw Exception('offline')));
    expect(local.values['student'], isNotNull);
    expect(local.values['other'], isNull);
  });

  test('delete and clear use authenticated endpoints', () async {
    final paths = <String>[];
    await http.runWithClient(() async {
      await NavigationHistoryService.delete('15');
      await NavigationHistoryService.clear();
      expect(paths, ['/history/15', '/history']);
    },
        () => MockClient((request) async {
              expect(request.method, 'DELETE');
              expect(request.headers['Authorization'], 'Bearer signed-session');
              paths.add(request.url.path);
              return http.Response('{"success":true}', 200);
            }));
  });

  test('expired and missing sessions report errors rather than empty history',
      () async {
    await http.runWithClient(() async {
      await expectLater(NavigationHistoryService.load(), throwsException);
    },
        () => MockClient((_) async =>
            http.Response('{"detail":"Please log in again."}', 401)));
    await UserSession.logout();
    await expectLater(NavigationHistoryService.load(), throwsException);
  });

  test('expired access is renewed and History retries with the new token',
      () async {
    UserSession.setLoggedInUser(
        username: 'student', token: 'expired', refreshToken: 'refresh-secret');
    final paths = <String>[];
    await http.runWithClient(() async {
      final entries = await NavigationHistoryService.load();
      expect(entries, isEmpty);
      expect(paths, ['/history', '/auth/refresh', '/history']);
      expect(UserSession.accessToken, 'renewed');
      expect(UserSession.refreshToken, 'replacement');
    },
        () => MockClient((request) async {
              paths.add(request.url.path);
              if (request.url.path == '/auth/refresh') {
                expect(jsonDecode(request.body)['refresh_token'],
                    'refresh-secret');
                return http.Response(
                    '{"access_token":"renewed","refresh_token":"replacement"}',
                    200);
              }
              if (request.headers['Authorization'] == 'Bearer expired') {
                return http.Response('{"detail":"expired"}', 401);
              }
              expect(request.headers['Authorization'], 'Bearer renewed');
              return http.Response('{"entries":[]}', 200);
            }));
  });
}
