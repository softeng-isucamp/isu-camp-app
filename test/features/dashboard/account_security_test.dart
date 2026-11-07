import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/auth/widgets/otp_code_input.dart';
import 'package:isu_camp_app/features/dashboard/screens/user_info_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'remembered_access_token': 'signed-session',
      'remembered_username': 'Karl',
      'remembered_email': 'karl@example.com',
    });
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: UserInfoScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openFromEditProfile(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const ValueKey('edit_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  const profileJson = '{"username":"Karl","email":"karl@example.com"}';

  testWidgets('account changes live in Edit Profile, not a separate card',
      (tester) async {
    UserSession.setLoggedInUser(username: 'Karl', token: 'signed-session');
    addTearDown(UserSession.logout);
    await http.runWithClient(() async {
      await pumpScreen(tester);
      expect(find.text('Change Password'), findsNothing);
      expect(find.text('Change Email'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('edit_profile')));
      await tester.pumpAndSettle();
      expect(find.text('Password'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('profile_change_email')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile_change_password')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => http.Response(profileJson, 200)));
  });

  testWidgets(
      'change password sends a code, verifies it, and saves the new password',
      (tester) async {
    UserSession.setLoggedInUser(
        username: 'Karl', token: 'signed-session', email: 'karl@example.com');
    addTearDown(UserSession.logout);
    final calls = <String>[];
    Map<String, dynamic>? saved;
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await openFromEditProfile(tester, 'profile_change_password');
      expect(find.text('Edit Profile'), findsNothing);
      expect(find.textContaining('sent to k***@example.com'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('otp_code_input')), '123456');
      await tester.pumpAndSettle();
      expect(find.text('Set New Password'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'NewPass2@');
      await tester.enterText(find.byType(TextField).at(1), 'Mismatch2@');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();
      // Errors appear inside the sheet, where a snackbar would be hidden.
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('set_password_error')))
              .data,
          'Passwords do not match.');
      expect(calls, isNot(contains('/profile/password')));
      await tester.enterText(find.byType(TextField).at(1), 'NewPass2@');
      await tester.pump();
      expect(find.byKey(const ValueKey('set_password_error')), findsNothing);
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();

      expect(find.text('Set New Password'), findsNothing);
      expect(find.text('Password updated.'), findsOneWidget);
      // Still logged in.
      expect(UserSession.accessToken, 'signed-session');
      expect(calls, [
        '/profile/password/request-otp',
        '/profile/password/verify-otp',
        '/profile/password',
      ]);
      expect(saved, {'password': 'NewPass2@', 'confirm_password': 'NewPass2@'});
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(profileJson, 200);
              }
              calls.add(
                  request.headers['Authorization'] == 'Bearer signed-session'
                      ? request.url.path
                      : 'unauthenticated ${request.url.path}');
              if (request.url.path == '/profile/password/request-otp') {
                return http.Response(
                    '{"success":true,"sent_to":"k***@example.com"}', 200);
              }
              if (request.url.path == '/profile/password') {
                saved = jsonDecode(request.body) as Map<String, dynamic>;
              }
              return http.Response('{"success":true}', 200);
            }));
  });

  testWidgets('a rejected new password shows the server reason in the sheet',
      (tester) async {
    UserSession.setLoggedInUser(username: 'Karl', token: 'signed-session');
    addTearDown(UserSession.logout);
    const reason = 'New password must be different from your current password.';
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await openFromEditProfile(tester, 'profile_change_password');
      await tester.enterText(
          find.byKey(const ValueKey('otp_code_input')), '123456');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'NewPass2@');
      await tester.enterText(find.byType(TextField).at(1), 'NewPass2@');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();
      expect(find.text(reason), findsOneWidget);
      expect(find.text('Set New Password'), findsOneWidget);
      // Closing the sheet ends the flow and stops its timers.
      Navigator.of(tester.element(find.text('Set New Password'))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async => switch (request.url.path) {
              '/profile' => http.Response(profileJson, 200),
              '/profile/password' => http.Response('{"detail":"$reason"}', 400),
              _ =>
                http.Response('{"success":true,"sent_to":"k***@x.com"}', 200),
            }));
  });

  testWidgets('change password shows server errors without opening the code',
      (tester) async {
    UserSession.setLoggedInUser(username: 'Karl', token: 'signed-session');
    addTearDown(UserSession.logout);
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await openFromEditProfile(tester, 'profile_change_password');
      expect(find.byType(OtpCodeInput), findsNothing);
      expect(find.text('Please wait before requesting another code.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async => request.method == 'GET'
            ? http.Response(profileJson, 200)
            : http.Response(
                '{"detail":"Please wait before requesting another code."}', 429,
                headers: {'retry-after': '42'})));
  });

  testWidgets(
      'change email validates, confirms the code sent to the new address, and updates the session',
      (tester) async {
    UserSession.setLoggedInUser(
        username: 'Karl', token: 'signed-session', email: 'karl@example.com');
    addTearDown(UserSession.logout);
    var verifications = 0;
    String? requestedEmail;
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await openFromEditProfile(tester, 'profile_change_email');
      expect(find.text('Change Email'), findsOneWidget);

      final input = find.byKey(const ValueKey('change_email_input'));
      await tester.enterText(input, 'not-an-email');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(input, 'KARL@example.com');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();
      expect(find.text('That is already your email.'), findsOneWidget);
      expect(requestedEmail, isNull);

      await tester.enterText(input, '');
      await tester.pumpAndSettle();
      expect(find.text('That is already your email.'), findsNothing);
      expect(requestedEmail, isNull);

      await tester.enterText(input, 'new@example.com');
      await tester.tap(find.text('Send Code'));
      await tester.pumpAndSettle();
      expect(requestedEmail, 'new@example.com');
      expect(find.textContaining('sent to new@example.com'), findsOneWidget);

      final code = find.byKey(const ValueKey('otp_code_input'));
      await tester.enterText(code, '111111');
      await tester.pumpAndSettle();
      expect(find.text('Invalid OTP. 4 attempt(s) remaining.'), findsOneWidget);
      expect(UserSession.currentEmail, 'karl@example.com');

      await tester.enterText(code, '123456');
      await tester.pumpAndSettle();
      expect(find.byType(OtpCodeInput), findsNothing);
      expect(find.text('Email updated to new@example.com.'), findsOneWidget);
      expect(UserSession.currentEmail, 'new@example.com');
      expect(await const FlutterSecureStorage().read(key: 'remembered_email'),
          'new@example.com');
      expect(verifications, 2);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                    '{"username":"Karl","email":"karl@example.com"}', 200);
              }
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              if (request.url.path == '/profile/email/request-otp') {
                requestedEmail = body['email'] as String;
                return http.Response(
                    '{"success":true,"sent_to":"new@example.com"}', 200);
              }
              verifications++;
              if (body['email'] != 'new@example.com') {
                return http.Response('{"detail":"wrong email"}', 500);
              }
              if (body['otp'] != 123456) {
                return http.Response(
                    '{"detail":"Invalid OTP. 4 attempt(s) remaining."}', 400);
              }
              return http.Response(
                  '{"username":"Karl","email":"new@example.com"}', 200);
            }));
  });
}
