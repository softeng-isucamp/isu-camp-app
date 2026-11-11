import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/services/account_session.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/services/user_session.dart';

/// Account types a user can pick. Self-declared at signup and not verified.
const accountTypes = ['Student', 'Staff', 'Visitor'];

class AccountProfile {
  const AccountProfile(
      {required this.username, required this.email, this.userType});
  final String username;
  final String email;

  /// Null for older accounts that never chose a type.
  final String? userType;

  factory AccountProfile.fromJson(Map<String, dynamic> data) => AccountProfile(
      username: data['username'] as String,
      email: data['email'] as String,
      userType: accountTypes.contains(data['user_type'])
          ? data['user_type'] as String
          : null);
}

class ProfileException implements Exception {
  const ProfileException(this.message);
  final String message;

  @override
  String toString() => message;
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

  static Future<AccountProfile> _decode(http.Response response) async {
    await AccountSession.checkResponse(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200)
      throw ProfileException(data['detail'] is String
          ? data['detail']
          : 'Could not update your profile. Please try again.');
    return AccountProfile.fromJson(data);
  }

  static Future<AccountProfile> load() async => _decode(await http
      .get(
        Uri.parse('${AuthService.baseUrl}/profile'),
        headers: _headers(),
      )
      .timeout(const Duration(seconds: 15)));

  /// Saves the username and, when chosen, the account type.
  static Future<AccountProfile> update(
          {required String username, String? userType}) async =>
      _decode(await http
          .patch(
            Uri.parse('${AuthService.baseUrl}/profile'),
            headers: _headers(),
            body: jsonEncode({
              'username': username.trim(),
              if (userType != null) 'user_type': userType,
            }),
          )
          .timeout(const Duration(seconds: 15)));

  // Account changes: codes are emailed and the account comes from the session.

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic>? body, String fallback,
      {bool codeStep = false}) async {
    final response = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/profile$path'),
          headers: _headers(),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    await AccountSession.checkResponse(response);
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (response.statusCode == 200 && data is Map<String, dynamic>) return data;
    if (codeStep) throw AuthService.otpException(response, data, fallback);
    throw ProfileException(AuthService.errorMessage(data, fallback));
  }

  /// Emails a code to the account's address and returns it partly hidden.
  static Future<String> requestPasswordChangeCode() async =>
      (await _post('/password/request-otp', null,
          'Could not send the verification code.',
          codeStep: true))['sent_to'] as String? ??
      'your email';

  static Future<void> verifyPasswordChangeCode(int otp) =>
      _post('/password/verify-otp', {'otp': otp}, 'Could not verify the code. Please try again.',
          codeStep: true);

  static Future<void> changePassword(
          String password, String confirm, String currentPassword) =>
      _post(
          '/password',
          {
            'current_password': currentPassword,
            'password': password,
            'confirm_password': confirm
          },
          'Could not update your password.');

  static Future<void> requestEmailChangeCode(String email) => _post(
      '/email/request-otp',
      {'email': email.trim()},
      'Could not send the verification code.',
      codeStep: true);

  static Future<AccountProfile> confirmEmailChange(
      String email, int otp) async {
    final data = await _post('/email/verify-otp',
        {'email': email.trim(), 'otp': otp}, 'Could not verify the code. Please try again.',
        codeStep: true);
    return AccountProfile(
        username: data['username'] as String, email: data['email'] as String);
  }
}
