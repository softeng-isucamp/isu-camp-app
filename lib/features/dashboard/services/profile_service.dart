import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/services/auth_service.dart';
import '../../auth/services/user_session.dart';

class AccountProfile {
  const AccountProfile({required this.username, required this.email});
  final String username;
  final String email;
}

class ProfileException implements Exception {
  const ProfileException(this.message);
  final String message;
}

class ProfileService {
  static Map<String, String> _headers() {
    final token = UserSession.accessToken;
    if (token == null || token.isEmpty)
      throw const ProfileException('Please log in again to edit your profile.');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
  }

  static AccountProfile _decode(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200)
      throw ProfileException(data['detail'] is String
          ? data['detail']
          : 'Could not update your profile. Please try again.');
    return AccountProfile(
        username: data['username'] as String, email: data['email'] as String);
  }

  static Future<AccountProfile> load() async => _decode(await http
      .get(
        Uri.parse('${AuthService.baseUrl}/profile'),
        headers: _headers(),
      )
      .timeout(const Duration(seconds: 15)));

  static Future<AccountProfile> updateUsername(String username) async =>
      _decode(await http
          .patch(
            Uri.parse('${AuthService.baseUrl}/profile'),
            headers: _headers(),
            body: jsonEncode({'username': username.trim()}),
          )
          .timeout(const Duration(seconds: 15)));
}
