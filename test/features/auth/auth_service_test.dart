import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/auth_service.dart';

void main() {
  test('login forwards the real CAPTCHA token to the backend', () async {
    await http.runWithClient(() async {
      await AuthService.login(
          identifier: 'Karl',
          password: 'password',
          captchaToken: 'provider-token');
    },
        () => MockClient((request) async {
              expect(
                  jsonDecode(request.body)['captcha_token'], 'provider-token');
              return http.Response('{"success":true}', 200);
            }));
  });

  Future<void> expectLoginError(dynamic body, String message,
      {Map<String, String> headers = const {}}) async {
    await http.runWithClient(() async {
      await expectLater(
        AuthService.login(identifier: 'test-user', password: 'test-password'),
        throwsA(isA<LoginException>().having(
          (error) => error.message,
          'message',
          message,
        )),
      );
    },
        () => MockClient((_) async =>
            http.Response(jsonEncode(body), 422, headers: headers)));
  }

  test('login extracts validation messages without exposing submitted input',
      () async {
    await expectLoginError({
      'detail': [
        {'msg': 'Field required', 'input': 'secret-password'},
        {'msg': 'Invalid value', 'input': 'secret-password'},
      ],
    }, 'Field required\nInvalid value');
  });

  test('login preserves plain error messages', () async {
    await expectLoginError(
        {'detail': 'Invalid credentials'}, 'Invalid credentials');
  });

  test('login handles structured messages', () async {
    await expectLoginError({
      'detail': {'message': 'Account unavailable'},
    }, 'Account unavailable');
  });

  test('login falls back for missing or unsupported error details', () async {
    for (final body in [
      null,
      <String, dynamic>{},
      {'detail': []},
      {'detail': 42},
      {'detail': '   '},
      {
        'detail': [
          {'input': 'secret-password'}
        ]
      },
    ]) {
      await expectLoginError(body, 'Login failed.');
    }
  });

  test('login keeps lockout metadata with validation errors', () async {
    await http.runWithClient(() async {
      await expectLater(
        AuthService.login(identifier: 'test-user', password: 'test-password'),
        throwsA(isA<LoginException>()
            .having((error) => error.message, 'message', 'Try later')
            .having((error) => error.retryAfterSeconds, 'retry', 60)
            .having((error) => error.failedAttempts, 'failed', 6)
            .having((error) => error.remainingAttempts, 'remaining', 0)),
      );
    },
        () => MockClient((_) async => http.Response(
              jsonEncode({
                'detail': [
                  {'msg': 'Try later'}
                ]
              }),
              429,
              headers: {
                'retry-after': '60',
                'x-login-attempts': '6',
                'x-login-attempts-remaining': '0',
              },
            )));
  });
}
