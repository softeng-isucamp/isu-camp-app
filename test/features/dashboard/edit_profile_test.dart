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
                    '{"username":"Karl","email":"karl@example.com"}', 200);
              updates++;
              final data = jsonDecode(request.body);
              expect(data.keys.toList(), ['username']);
              if (updates == 1)
                return http.Response(
                    '{"detail":"Username is already taken."}', 409);
              return http.Response(
                  '{"username":"Karl_New","email":"karl@example.com"}', 200);
            }));
  });
}
