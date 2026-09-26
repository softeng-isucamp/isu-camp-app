import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

const _sessionKey = 'user_session_v1';

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureSessionStore implements SessionStore {
  const SecureSessionStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _sessionKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: _sessionKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _sessionKey);
}

class UserSession {
  static SessionStore store = const SecureSessionStore();
  static bool _hasSavedSession = false;
  static String currentUsername = 'UserA1B2c3';
  static String currentEmail = 'user@gmail.com';
  static String? accessToken;
  static String? refreshToken;
  static Future<String>? _inFlightRefresh;
  static int _generation = 0;
  static String? _sessionIdentity;

  static bool get isLoggedIn => accessToken?.isNotEmpty ?? false;
  static String? get sessionIdentity => _sessionIdentity;

  static void setRegisteredUser({
    required String username,
    String email = '',
  }) {
    currentUsername = username.isNotEmpty ? username : 'UserA1B2c3';
    if (email.isNotEmpty) currentEmail = email;
  }

  static void setLoggedInUser({
    required String username,
    String? token,
    String? refreshToken,
    String email = '',
  }) {
    _generation++;
    accessToken = token;
    UserSession.refreshToken = refreshToken;
    _sessionIdentity = '${DateTime.now().microsecondsSinceEpoch}-$_generation';
    currentUsername = username.isNotEmpty ? username : 'UserA1B2c3';
    if (email.isNotEmpty) currentEmail = email;
  }

  static Future<void> rememberLoggedInUser({
    required String username,
    required String token,
    String? refreshToken,
    String email = '',
  }) async {
    if (token.isEmpty) throw StateError('Login response has no session token.');
    await store.write(jsonEncode({
      'username': username,
      'email': email,
      'accessToken': token,
      'refreshToken': refreshToken,
    }));
    setLoggedInUser(
        username: username,
        email: email,
        token: token,
        refreshToken: refreshToken);
    _hasSavedSession = true;
  }

  static Future<bool> restore() async {
    clearMemory();
    try {
      final saved = await store.read();
      if (saved == null) return false;
      final data = jsonDecode(saved);
      if (data is! Map ||
          data['username'] is! String ||
          data['accessToken'] is! String ||
          (data['accessToken'] as String).isEmpty) {
        await store.delete();
        return false;
      }
      setLoggedInUser(
        username: data['username'] as String,
        email: data['email'] is String ? data['email'] as String : '',
        token: data['accessToken'] as String,
        refreshToken: data['refreshToken'] is String
            ? data['refreshToken'] as String
            : null,
      );
      _hasSavedSession = true;
      return true;
    } catch (_) {
      // Damaged or inaccessible device storage must not prevent app startup.
      clearMemory();
      return false;
    }
  }

  static void clearMemory() {
    _generation++;
    _hasSavedSession = false;
    accessToken = null;
    refreshToken = null;
    _sessionIdentity = null;
    currentUsername = 'UserA1B2c3';
    currentEmail = 'user@gmail.com';
  }

  static Future<void> logout() async {
    final tokenToRevoke = refreshToken;
    _generation++;
    try {
      await _inFlightRefresh;
    } catch (_) {
      // A failed refresh must not prevent explicit logout.
    }
    if (_hasSavedSession) await store.delete();
    clearMemory();
    if (tokenToRevoke != null && tokenToRevoke.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('${AuthService.baseUrl}/auth/logout'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': tokenToRevoke}),
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Local logout succeeds even if the server is temporarily unreachable.
      }
    }
  }

  static Future<String> renewAccessToken() async {
    if (_inFlightRefresh != null) return _inFlightRefresh!;
    final renewal = _renewAccessToken();
    _inFlightRefresh = renewal;
    try {
      return await renewal;
    } finally {
      if (identical(_inFlightRefresh, renewal)) _inFlightRefresh = null;
    }
  }

  static Future<String> _renewAccessToken() async {
    final token = refreshToken;
    final generation = _generation;
    if (token == null || token.isEmpty) {
      throw Exception('Please log in again to access your history.');
    }
    final response = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': token}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        throw Exception('Your session has ended. Please log in again.');
      }
      throw Exception('Could not renew your session. Try again.');
    }
    final data = jsonDecode(response.body);
    final renewed = data is Map ? data['access_token'] : null;
    final replacement = data is Map ? data['refresh_token'] : null;
    if (renewed is! String || renewed.isEmpty) {
      throw Exception('Could not renew your session. Try again.');
    }
    if (replacement is! String || replacement.isEmpty) {
      throw Exception('Could not renew your session. Try again.');
    }
    if (_generation != generation || refreshToken != token) {
      throw Exception('Your session has changed. Please try again.');
    }
    if (_hasSavedSession) {
      await store.write(jsonEncode({
        'username': currentUsername,
        'email': currentEmail,
        'accessToken': renewed,
        'refreshToken': replacement,
      }));
    }
    accessToken = renewed;
    refreshToken = replacement;
    return renewed;
  }
}
