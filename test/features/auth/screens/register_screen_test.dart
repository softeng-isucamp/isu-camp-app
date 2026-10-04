import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/screens/register_screen.dart';

void main() {
  testWidgets('signup offers account type below username', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Account Type'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('signup_role_selector')));
    await tester.pumpAndSettle();
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Visitor'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
