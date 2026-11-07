import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/screens/login_screen.dart';

void main() {
  Widget buildSubject() {
    return const MaterialApp(home: LoginScreen());
  }

  testWidgets('renders the login form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(buildSubject());

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in as'), findsNothing);
    expect(find.text('Keep me signed in'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('forgot password requires an account identifier', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(buildSubject());
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Password'), findsOneWidget);
    await tester.tap(find.text('Request Reset Code'));
    await tester.pump();

    expect(
      find.text('Please enter your username or email.'),
      findsOneWidget,
    );
    expect(find.text('Reset Password'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('reset request errors stay inside the sheet and clear on edit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const message = 'Please wait before requesting another code.';
    await http.runWithClient(() async {
      await tester.pumpWidget(buildSubject());
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Karl');
      await tester.tap(find.text('Request Reset Code'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.text(message)),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'Other');
      await tester.pump();
      expect(find.text(message), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient(
            (_) async => http.Response('{"detail":"$message"}', 429)));
  });

  testWidgets('forgot password keeps the original bottom-sheet design',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(buildSubject());
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Request Reset Code'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
      'a finished reset stops its timers and never closes the login screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('open login')))));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Karl');
      await tester.tap(find.text('Request Reset Code'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('otp_code_input')), '123456');
      await tester.pumpAndSettle();
      expect(find.text('Current Password'), findsNothing);
      await tester.enterText(find.byType(TextField).at(2), 'NewPass2@');
      await tester.enterText(find.byType(TextField).at(3), 'NewPass2@');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();
      expect(find.text('Set New Password'), findsNothing);

      await tester.pump(const Duration(minutes: 4));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('no activity'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => http.Response('{"success":true}', 200)));
  });
}
