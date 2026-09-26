import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/auth/screens/get_started_screen.dart';
import 'package:isu_camp_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:isu_camp_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements SessionStore {
  String? saved;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String value) async {
    saved = value;
  }

  @override
  Future<void> delete() async {
    saved = null;
  }
}

void main() {
  testWidgets('a remembered login opens the dashboard after app restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final originalStore = UserSession.store;
    UserSession.store = _MemoryStore();
    await UserSession.rememberLoggedInUser(
        username: 'student', token: 'test-token');
    UserSession.clearMemory();
    await UserSession.restore();

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Log in'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await UserSession.logout();
    UserSession.store = originalStore;
  });

  testWidgets('an explicit logout leaves the next app start signed out',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final originalStore = UserSession.store;
    UserSession.store = _MemoryStore();
    await UserSession.rememberLoggedInUser(
        username: 'student', token: 'test-token');
    await UserSession.logout();
    await UserSession.restore();

    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.byType(GetStartedScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    UserSession.store = originalStore;
  });
}
