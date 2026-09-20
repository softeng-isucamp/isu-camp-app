import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/dashboard/services/navigation_history_service.dart';

void main() {
  setUp(() => UserSession.setLoggedInUser(
      username: 'student', token: 'signed-session'));
  tearDown(UserSession.logout);

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

  test('record sends foreign keys only, including nullable room', () async {
    await http.runWithClient(() async {
      await NavigationHistoryService.record(
          buildingId: '8', token: 'captured-session');
    },
        () => MockClient((request) async {
              expect(request.method, 'POST');
              expect(
                  request.headers['Authorization'], 'Bearer captured-session');
              expect(jsonDecode(request.body),
                  {'buildingId': 8, 'locationId': null});
              return http.Response('{"id":"1"}', 201);
            }));
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
    UserSession.logout();
    await expectLater(NavigationHistoryService.load(), throwsException);
  });
}
