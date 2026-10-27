import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/captcha_service.dart';
import 'package:isu_camp_app/features/auth/screens/login_screen.dart';
import 'package:isu_camp_app/features/auth/widgets/captcha_surface.dart';
import 'package:isu_camp_app/features/auth/widgets/captcha_verification.dart';

void main() {
  testWidgets('verified popup closes and login sends its token exactly once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final loginBodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'Karl');
      await tester.enterText(find.byType(TextField).at(1), 'test-password');
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      final surface =
          tester.widget<CaptchaSurface>(find.byType(CaptchaSurface));
      surface.onMessage('{"type":"verified","token":""}');
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
      surface.onMessage('{"type":"verified","token":"provider-token"}');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Human verification completed'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(loginBodies, hasLength(1));
      expect(loginBodies.single['captcha_token'], 'provider-token');
      expect(find.text('Please complete human verification.'), findsNothing);
      // A submitted token is single-use, so even a credential failure resets it.
      expect(find.text('Human verification completed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.url.path == '/auth/login') {
                loginBodies
                    .add(jsonDecode(request.body) as Map<String, dynamic>);
                return http.Response(
                    '{"detail":"Invalid username/email or password."}', 401);
              }
              return http.Response('{"provider":"recaptcha-v2"}', 200);
            }));
  });

  testWidgets('missing server keys are not reported as an internet failure',
      (tester) async {
    String? token;
    var requests = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CaptchaVerification(onToken: (value) => token = value)),
      ));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('has not been set up yet'), findsOneWidget);
      expect(find.textContaining('check your connection'), findsNothing);
      expect(token, isNull);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(requests, 2);
    },
        () => MockClient((request) async {
              requests++;
              return http.Response(
                  '{"detail":{"code":"captcha_not_configured"}}', 503);
            }));
  });

  test('preflight sends the browser origin and reports an origin mismatch',
      () async {
    Uri? requestedUrl;
    await http.runWithClient(() async {
      await expectLater(
        CaptchaService.checkAvailability(parentOrigin: 'http://localhost:5173'),
        throwsA(isA<CaptchaException>().having(
            (error) => error.message, 'message', contains('app address'))),
      );
      expect(requestedUrl!.queryParameters['parent_origin'],
          'http://localhost:5173');
    },
        () => MockClient((request) async {
              requestedUrl = request.url;
              return http.Response(
                  '{"detail":{"code":"captcha_origin_not_allowed"}}', 403);
            }));
  });

  test(
      'old backend, proxy failure and unreachable service have distinct errors',
      () async {
    for (final entry in [
      (
        http.Response('{"detail":"Not Found"}', 404),
        'not available on this server yet'
      ),
      (
        http.Response('<html>Bad Gateway</html>', 502),
        'temporarily unavailable'
      ),
      (http.Response('{}', 200), 'temporarily unavailable'),
    ]) {
      await http.runWithClient(() async {
        await expectLater(
            CaptchaService.checkAvailability(),
            throwsA(isA<CaptchaException>().having(
                (error) => error.message, 'message', contains(entry.$2))));
      }, () => MockClient((_) async => entry.$1));
    }
    await http.runWithClient(() async {
      await expectLater(
          CaptchaService.checkAvailability(),
          throwsA(isA<CaptchaException>().having((error) => error.message,
              'message', contains('Could not reach'))));
    },
        () => MockClient(
            (_) async => throw http.ClientException('Connection refused')));
  });

  test('a configured backend allows the real challenge to open', () async {
    await http.runWithClient(() async {
      await CaptchaService.checkAvailability();
    },
        () => MockClient(
            (_) async => http.Response('{"provider":"recaptcha-v2"}', 200)));
  });
}
