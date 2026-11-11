import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/core/error_messages.dart';
import 'package:isu_camp_app/features/auth/screens/login_screen.dart';
import 'package:isu_camp_app/features/auth/services/account_session.dart';
import 'package:isu_camp_app/features/auth/services/remembered_session_store.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/dashboard/services/navigation_history_service.dart';
import 'package:isu_camp_app/features/dashboard/services/profile_service.dart';

const _detail = AccountSession.deactivatedMessage;

String _token() {
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp}))).replaceAll('=', '');
  return 'header.$payload.signature';
}

http.Response _deactivated() => http.Response(jsonEncode({'detail': _detail}), 403,
    headers: {'x-account-status': 'inactive', 'content-type': 'application/json'});

Future<void> _rememberSignedInUser() async {
  final token = _token();
  UserSession.setLoggedInUser(username: 'Karl', token: token, email: 'karl@example.com');
  await RememberedSessionStore.save(
      username: 'Karl', token: token, email: 'karl@example.com', keepSignedIn: true);
}

Future<String?> _storedToken() =>
    const FlutterSecureStorage().read(key: 'remembered_access_token');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.logout();
    await _rememberSignedInUser();
  });
  tearDown(UserSession.logout);

  test('only a 403 marked inactive counts as a deactivation', () {
    expect(AccountSession.isDeactivated(_deactivated()), isTrue);
    expect(AccountSession.isDeactivated(http.Response('{}', 403)), isFalse);
    expect(AccountSession.isDeactivated(
        http.Response('{}', 401, headers: {'x-account-status': 'inactive'})), isFalse);
    expect(ErrorMessages.present(const AccountDeactivatedException(), 'fallback'), _detail);
  });

  test('profile and history calls sign out on deactivation', () async {
    await http.runWithClient(() async {
      await expectLater(ProfileService.load(), throwsA(isA<AccountDeactivatedException>()));
    }, () => MockClient((_) async => _deactivated()));
    expect(UserSession.accessToken, isNull);
    expect(await _storedToken(), isNull);

    await _rememberSignedInUser();
    await http.runWithClient(() async {
      await expectLater(NavigationHistoryService.load(), throwsA(isA<AccountDeactivatedException>()));
    }, () => MockClient((_) async => _deactivated()));
    expect(UserSession.accessToken, isNull);
    expect(await _storedToken(), isNull);
  });

  test('other refusals keep the session', () async {
    final token = UserSession.accessToken;
    await http.runWithClient(() async {
      await expectLater(ProfileService.load(), throwsA(isA<ProfileException>()));
    }, () => MockClient((_) async => http.Response('{"detail":"Forbidden."}', 403)));
    expect(UserSession.accessToken, token);
    expect(await _storedToken(), token);
  });

  testWidgets('a mid-session deactivation returns to login with the message', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        navigatorKey: AccountSession.navigatorKey,
        home: const Scaffold(body: Text('Dashboard'))));

    await tester.runAsync(() => http.runWithClient(() async {
          // Two requests refused together still open a single login screen.
          await Future.wait([
            ProfileService.load().then((_) {}, onError: (_) {}),
            NavigationHistoryService.load().then((_) {}, onError: (_) {}),
          ]);
        }, () => MockClient((_) async => _deactivated())));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text(_detail), findsOneWidget);
    expect(UserSession.accessToken, isNull);
  });

  group('launch with a remembered session', () {
    test('signs out only when the server reports a deactivation', () async {
      final result = await http.runWithClient(AccountSession.restoreOnLaunch, () => MockClient((request) async {
            expect(request.url.path, '/profile');
            expect(request.headers['Authorization'], startsWith('Bearer '));
            return _deactivated();
          }));
      expect(result, LaunchSession.deactivated);
      expect(UserSession.accessToken, isNull);
      expect(await _storedToken(), isNull);
    });

    test('offline, timeouts and server errors keep the session', () async {
      final token = UserSession.accessToken;
      final responses = <Future<http.Response> Function()>[
        () async => throw http.ClientException('offline'),
        () async => http.Response('{"detail":"Could not check your account right now. Please try again."}', 503),
        () => Future.delayed(const Duration(seconds: 1), () => _deactivated()),
      ];
      for (final respond in responses) {
        final result = await http.runWithClient(
            () => AccountSession.restoreOnLaunch(timeout: const Duration(milliseconds: 100)),
            () => MockClient((_) => respond()));
        expect(result, LaunchSession.signedIn);
        expect(UserSession.accessToken, token);
        expect(await _storedToken(), token);
      }
    });

    test('an active account opens signed in', () async {
      final result = await http.runWithClient(AccountSession.restoreOnLaunch,
          () => MockClient((_) async => http.Response('{"username":"Karl","email":"k@e.com"}', 200)));
      expect(result, LaunchSession.signedIn);
    });

    test('no remembered session opens signed out without a request', () async {
      await RememberedSessionStore.clear();
      UserSession.logout();
      final result = await http.runWithClient(AccountSession.restoreOnLaunch,
          () => MockClient((_) async => fail('should not call the server')));
      expect(result, LaunchSession.signedOut);
    });
  });
}
