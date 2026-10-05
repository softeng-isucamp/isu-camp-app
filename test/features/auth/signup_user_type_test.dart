import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/auth/services/auth_service.dart';

void main() {
  for (final type in ['Student', 'Staff', 'Visitor']) {
    test('signup sends $type as user_type in account creation', () async {
      await http.runWithClient(() async {
        final result = await AuthService.setSignupPassword(
          email: 'signup@example.com',
          password: 'Testing9!',
          confirmPassword: 'Testing9!',
          userType: type,
        );
        expect(result['success'], isTrue);
      },
          () => MockClient((request) async {
                expect(request.method, 'POST');
                expect(request.url.path, '/auth/signup/set-password');
                expect(jsonDecode(request.body)['user_type'], type);
                return http.Response(
                    '{"success":true,"access_token":"test"}', 200);
              }));
    });
  }
}
