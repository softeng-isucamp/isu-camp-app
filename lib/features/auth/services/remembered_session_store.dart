import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user_session.dart';

class RememberedSessionStore {
  static const _storage = FlutterSecureStorage();
  static const _usernameKey = 'remembered_username';
  static const _tokenKey = 'remembered_access_token';
  static const _emailKey = 'remembered_email';

  /// Never persists a password. An unchecked box removes any previous session.
  static Future<void> save({
    required String username,
    required String? token,
    required bool keepSignedIn,
    String email = '',
  }) async {
    if (!keepSignedIn || token == null || token.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _emailKey, value: email);
  }

  static Future<bool> restore() async {
    try {
      final username = await _storage.read(key: _usernameKey);
      final token = await _storage.read(key: _tokenKey);
      if (username == null ||
          username.isEmpty ||
          token == null ||
          !_isValidToken(token)) {
        await clear();
        return false;
      }
      UserSession.setLoggedInUser(
          username: username,
          token: token,
          email: await _storage.read(key: _emailKey) ?? '');
      return true;
    } catch (_) {
      // Storage can be unavailable (for example after an OS restore).
      return false;
    }
  }

  static bool _isValidToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final expiry = payload['exp'];
      return expiry is num &&
          DateTime.fromMillisecondsSinceEpoch((expiry * 1000).toInt(),
                  isUtc: true)
              .isAfter(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _emailKey);
  }

  /// Update an existing remembered session without opting an unsaved user in.
  static Future<void> updateProfile(
      {required String username, required String email}) async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token != UserSession.accessToken) return;
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _emailKey, value: email);
  }
}
