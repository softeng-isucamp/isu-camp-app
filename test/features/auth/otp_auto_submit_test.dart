import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/screens/login_screen.dart';
import 'package:isu_camp_app/features/auth/screens/register_screen.dart';
import 'package:isu_camp_app/features/auth/widgets/otp_code_input.dart';

void main() {
  testWidgets('signup submits a pasted code once and moves to password setup',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final verified = Completer<http.Response>();
    var submissions = 0;
    Object? submittedCode;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Karl');
      await tester.enterText(find.byType(TextField).at(1), 'karl@example.com');
      await tester.tap(find.byKey(const ValueKey('signup_role_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue & Send Code'));
      await tester.pumpAndSettle();
      expect(find.byType(OtpCodeInput), findsOneWidget);
      expect(find.text('Verify & Continue'), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('otp_code_input')), '12345');
      await tester.pump();
      expect(submissions, 0);
      await tester.enterText(
          find.byKey(const ValueKey('otp_code_input')), '123456');
      await tester.pump();
      expect(submissions, 1);
      expect(submittedCode, 123456);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          tester.widget<OtpCodeInput>(find.byType(OtpCodeInput)).busy, isTrue,
          reason: tester.widget<OtpCodeInput>(find.byType(OtpCodeInput)).error);
      expect(find.text('Verifying code…'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('otp_code_input')))
              .enabled,
          isFalse);
      verified.complete(http.Response('{"success":true}', 200));
      await tester.pumpAndSettle();
      expect(find.text('Set Password'), findsOneWidget);
      expect(submissions, 1);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.url.path.endsWith('/verify-otp')) {
                submissions++;
                submittedCode = jsonDecode(request.body)['otp'];
                return verified.future;
              }
              return http.Response('{"success":true}', 200);
            }));
  });

  testWidgets(
      'forgot-password auto submit allows retry and ignores network failures for attempts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var submissions = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Karl');
      await tester.tap(find.text('Request Reset Code'));
      await tester.pumpAndSettle();
      expect(find.text('Verify and Continue'), findsNothing);
      final input = find.byKey(const ValueKey('otp_code_input'));
      await tester.enterText(input, '123456');
      await tester.pumpAndSettle();
      expect(find.textContaining('5 attempts left'), findsOneWidget);
      expect(find.text('Service unavailable'), findsOneWidget);
      await tester.enterText(input, '654321');
      await tester.pumpAndSettle();
      expect(find.textContaining('4 attempts left'), findsOneWidget);
      expect(find.text('Invalid OTP. 4 attempt(s) remaining.'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.enterText(input, '111111');
      await tester.pumpAndSettle();
      expect(find.byType(OtpCodeInput), findsNothing);
      expect(submissions, 3);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (!request.url.path.endsWith('/verify-otp'))
                return http.Response('{"success":true}', 200);
              submissions++;
              if (submissions == 1)
                return http.Response('{"detail":"Service unavailable"}', 503);
              if (submissions == 2)
                return http.Response(
                    '{"detail":"Invalid OTP. 4 attempt(s) remaining."}', 400);
              return http.Response('{"success":true}', 200);
            }));
  });
}
