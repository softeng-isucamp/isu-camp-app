import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/dashboard/screens/user_info_screen.dart';

void main() {
  testWidgets(
      'profile editor loads real email, handles duplicate name and saves to API',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.setLoggedInUser(username: 'Karl', token: 'signed-session');
    addTearDown(UserSession.logout);
    var updates = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: UserInfoScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('edit_profile')));
      await tester.pumpAndSettle();
      expect(find.text('karl@example.com'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).last).readOnly,
          isTrue);
      final username = find.byKey(const ValueKey('profile_username'));
      await tester.enterText(username, 'TakenName');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Username is already taken.'), findsOneWidget);
      expect(UserSession.currentUsername, 'Karl');
      await tester.enterText(username, 'Karl_New');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Karl_New'), findsOneWidget);
      expect(UserSession.currentEmail, 'karl@example.com');
      expect(UserSession.currentUserType, 'Student');
      expect(updates, 2);
      expect(
          await const FlutterSecureStorage()
              .read(key: 'remembered_access_token'),
          isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              expect(request.headers['Authorization'], 'Bearer signed-session');
              if (request.method == 'GET')
                return http.Response(
                    '{"username":"Karl","email":"karl@example.com","user_type":"Student"}', 200);
              updates++;
              final data = jsonDecode(request.body);
              expect(data, {'username': updates == 1 ? 'TakenName' : 'Karl_New', 'user_type': 'Student'});
              if (updates == 1)
                return http.Response(
                    '{"detail":"Username is already taken."}', 409);
              return http.Response(
                  '{"username":"Karl_New","email":"karl@example.com","user_type":"Student"}', 200);
            }));
  });

  testWidgets('account type shows in the header and can be changed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.setLoggedInUser(username: 'Karl', token: 'signed-session');
    addTearDown(UserSession.logout);
    Map<String, dynamic>? sent;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: UserInfoScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile_account_type_label')),
          findsOneWidget);
      expect(find.text('Visitor'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit_profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile_account_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(sent, {'username': 'Karl', 'user_type': 'Student'});
      expect(UserSession.currentUserType, 'Student');
      final label = tester.widget<Text>(
          find.byKey(const ValueKey('profile_account_type_label')));
      expect(label.data, 'Student');
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'GET')
                return http.Response(
                    '{"username":"Karl","email":"karl@example.com","user_type":"Visitor"}', 200);
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                  '{"username":"Karl","email":"karl@example.com","user_type":"Student"}', 200);
            }));
  });

  testWidgets('older accounts without a type show Not set and send none',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.setLoggedInUser(username: 'Karl', token: 'signed-session');
    addTearDown(UserSession.logout);
    Map<String, dynamic>? sent;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: UserInfoScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile_account_type_label')),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('edit_profile')));
      await tester.pumpAndSettle();
      expect(find.text('Not set'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(sent, {'username': 'Karl'});
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'GET')
                return http.Response(
                    '{"username":"Karl","email":"karl@example.com","user_type":null}', 200);
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                  '{"username":"Karl","email":"karl@example.com","user_type":null}', 200);
            }));
  });
}
