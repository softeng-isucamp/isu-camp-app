import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
