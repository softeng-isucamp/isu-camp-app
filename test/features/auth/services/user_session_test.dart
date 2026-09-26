import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';

class MemorySessionStore implements SessionStore {
  String? value;
  bool failDelete = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('storage unavailable');
    value = null;
  }
}

void main() {
  late SessionStore originalStore;
  late MemorySessionStore store;

  setUp(() {
    originalStore = UserSession.store;
    store = MemorySessionStore();
    UserSession.store = store;
    UserSession.clearMemory();
  });

  tearDown(() {
    UserSession.clearMemory();
    UserSession.store = originalStore;
  });

  test('login survives a new app process and restores the account', () async {
    await UserSession.rememberLoggedInUser(
      username: 'student',
      email: 'student@example.com',
      token: 'signed-session',
    );

    UserSession.clearMemory(); // Simulate a stopped app process.
    expect(await UserSession.restore(), isTrue);
    expect(UserSession.isLoggedIn, isTrue);
    expect(UserSession.currentUsername, 'student');
    expect(UserSession.currentEmail, 'student@example.com');
    expect(UserSession.accessToken, 'signed-session');
  });

  test('explicit logout removes the remembered session', () async {
    await UserSession.rememberLoggedInUser(
        username: 'student', token: 'signed-session');

    await UserSession.logout();
    expect(UserSession.isLoggedIn, isFalse);
    expect(await UserSession.restore(), isFalse);
    expect(UserSession.accessToken, isNull);
  });

  test('invalid saved data cannot sign in a user', () async {
    store.value = '{"username":"student","accessToken":""}';
    expect(await UserSession.restore(), isFalse);
    expect(store.value, isNull);
    expect(UserSession.isLoggedIn, isFalse);
  });

  test('failed storage deletion keeps the session available for retry',
      () async {
    await UserSession.rememberLoggedInUser(
        username: 'student', token: 'signed-session');
    store.failDelete = true;

    await expectLater(UserSession.logout(), throwsStateError);
    expect(UserSession.isLoggedIn, isTrue);
    expect(store.value, isNotNull);
  });

  test('renewal saves the new access token for the next app start', () async {
    await UserSession.rememberLoggedInUser(
        username: 'student', token: 'expired', refreshToken: 'refresh-secret');
    final sessionIdentity = UserSession.sessionIdentity;
    await http.runWithClient(() async {
      expect(await UserSession.renewAccessToken(), 'renewed');
    },
        () => MockClient((request) async {
              expect(request.url.path, '/auth/refresh');
              expect(
                  jsonDecode(request.body)['refresh_token'], 'refresh-secret');
              return http.Response(
                  '{"access_token":"renewed","refresh_token":"replacement"}',
                  200);
    }));
    expect(UserSession.sessionIdentity, sessionIdentity);

    UserSession.clearMemory();
    expect(await UserSession.restore(), isTrue);
    expect(UserSession.accessToken, 'renewed');
    expect(UserSession.refreshToken, 'replacement');
    expect(UserSession.sessionIdentity, isNot(sessionIdentity));
  });

  test('logout revokes refresh access after clearing local storage', () async {
    await UserSession.rememberLoggedInUser(
        username: 'student', token: 'signed', refreshToken: 'refresh-secret');
    await http.runWithClient(() async {
      await UserSession.logout();
    },
        () => MockClient((request) async {
              expect(request.url.path, '/auth/logout');
              expect(
                  jsonDecode(request.body)['refresh_token'], 'refresh-secret');
              expect(store.value, isNull);
              return http.Response('{"success":true}', 200);
            }));
    expect(await UserSession.restore(), isFalse);
  });
}
