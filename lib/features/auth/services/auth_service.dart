import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;

/// An error the user can act on, carrying a message that is safe to display.
///
/// [toString] returns the bare message, so the screens' existing
/// `replaceFirst('Exception: ', '')` cleanup leaves it untouched.
class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class LoginException implements Exception {
  final String message;
  final int? retryAfterSeconds;
  final int? failedAttempts;
  final int? remainingAttempts;

  const LoginException(
    this.message, {
    this.retryAfterSeconds,
    this.failedAttempts,
    this.remainingAttempts,
  });

  @override
  String toString() => message;
}

class AuthService {
  /// Build-time override for the backend address, e.g. to reach the dev machine
  /// from a physical phone on the same Wi-Fi:
  ///
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.50:5000
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Port the backend listens on, i.e. the `--port` uvicorn was started with.
  static const int _port = 5000;

  /// Base URL of the FastAPI backend.
  ///
  /// The defaults below are development-only. An Android emulator reaches the
  /// host machine at 10.0.2.2 — there, 127.0.0.1 is the emulated device itself
  /// and the connection is refused. Every other target talks to the host
  /// loopback directly.
  ///
  /// Neither address means anything on a real phone, which is why a release
  /// build without [_baseUrlOverride] is reported through [configurationError]
  /// instead of failing later as a confusing "can't reach the server".
  static final String baseUrl = _baseUrlOverride.isNotEmpty
      ? _baseUrlOverride
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? 'http://10.0.2.2:$_port'
            : 'http://127.0.0.1:$_port');

  /// Why [baseUrl] cannot be used, or null when it is usable.
  static final String? configurationError = _findConfigurationError();

  static String? _findConfigurationError() {
    if (_baseUrlOverride.isNotEmpty) {
      final uri = Uri.tryParse(_baseUrlOverride);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return 'The backend address for this build is not a valid URL '
            '("$_baseUrlOverride").';
      }
      return null;
    }

    if (kReleaseMode) {
      return 'This build has no backend address, so it cannot reach the '
          'server. Rebuild with '
          '--dart-define=API_BASE_URL=http://<server-host>:$_port';
    }

    // Debug and profile builds keep the emulator/loopback defaults.
    return null;
  }

  /// The [Uri] for [path], or throws [ApiException] if this build is
  /// misconfigured.
  ///
  /// Use this instead of interpolating [baseUrl] directly, so a release build
  /// that was never given an address says so rather than timing out.
  static Uri endpoint(String path) {
    final problem = configurationError;
    if (problem != null) {
      throw ApiException(problem);
    }
    return Uri.parse('$baseUrl$path');
  }

  static const Duration _timeout = Duration(seconds: 15);

  static const String _unreachableMessage =
      "Can't reach the server. Make sure the backend is running, then try again.";

  // =========================================================
  // TRANSPORT
  // =========================================================

  /// POSTs [body] as JSON to [path].
  ///
  /// Transport failures become an [ApiException] with a readable message so a
  /// raw SocketException never reaches a snackbar.
  static Future<http.Response> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      return await http
          .post(
            endpoint(path),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      // IOClient wraps SocketException in a ClientException, so this covers
      // connection-refused, DNS and host-unreachable on every platform.
      throw const ApiException(_unreachableMessage);
    }
  }

  /// Decodes a JSON object body, or throws a readable [ApiException].
  ///
  /// The backend returns an HTML page on an unhandled 500, which would
  /// otherwise surface as a bare FormatException.
  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Fall through to the status-based message.
    }

    throw ApiException(
      response.statusCode >= 500
          ? 'The server ran into a problem (${response.statusCode}). Please try again.'
          : 'Unexpected response from the server (${response.statusCode}).',
    );
  }

  /// Reads FastAPI's `detail` field, falling back to [fallback].
  ///
  /// A 422 returns `detail` as a list of validation objects rather than a
  /// string, so anything that is not a non-empty string uses the fallback.
  static String _detail(Map<String, dynamic> data, String fallback) {
    final detail = data['detail'];
    return detail is String && detail.isNotEmpty ? detail : fallback;
  }

  // =========================================================
  // LOGIN
  // =========================================================

  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _post('/auth/login', {
      'identifier': identifier,
      'password': password,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    final retryAfter = response.headers['retry-after'];
    final failedAttempts = response.headers['x-login-attempts'];
    final remainingAttempts = response.headers['x-login-attempts-remaining'];
    throw LoginException(
      _detail(data, 'Login failed.'),
      retryAfterSeconds: retryAfter == null ? null : int.tryParse(retryAfter),
      failedAttempts:
          failedAttempts == null ? null : int.tryParse(failedAttempts),
      remainingAttempts: remainingAttempts == null
          ? null
          : int.tryParse(remainingAttempts),
    );
  }

  // =========================================================
  // SIGN UP - REQUEST OTP
  // =========================================================

  static Future<Map<String, dynamic>> requestSignupOtp({
    required String username,
    required String email,
  }) async {
    final response = await _post('/auth/signup/request-otp', {
      'username': username,
      'email': email,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(_detail(data, 'Failed to send verification code.'));
  }

  // =========================================================
  // SIGN UP - VERIFY OTP
  // =========================================================

  static Future<Map<String, dynamic>> verifySignupOtp({
    required String email,
    required int otp,
  }) async {
    final response = await _post('/auth/signup/verify-otp', {
      'email': email,
      'otp': otp,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(_detail(data, 'OTP verification failed.'));
  }

  // =========================================================
  // SIGN UP - SET PASSWORD
  // =========================================================

  static Future<Map<String, dynamic>> setSignupPassword({
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await _post('/auth/signup/set-password', {
      'email': email,
      'password': password,
      'confirm_password': confirmPassword,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(_detail(data, 'Failed to create account.'));
  }

  // =========================================================
  // FORGOT PASSWORD - REQUEST OTP
  // =========================================================

  static Future<Map<String, dynamic>> requestForgotPasswordOtp({
    required String identifier,
  }) async {
    final response = await _post('/auth/forgot-password/request-otp', {
      'identifier': identifier,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(_detail(data, 'Failed to send password reset code.'));
  }

  // =========================================================
  // FORGOT PASSWORD - VERIFY OTP
  // =========================================================

  static Future<Map<String, dynamic>> verifyForgotPasswordOtp({
    required String identifier,
    required int otp,
  }) async {
    final response = await _post('/auth/forgot-password/verify-otp', {
      'identifier': identifier,
      'otp': otp,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(_detail(data, 'OTP verification failed.'));
  }

  // =========================================================
  // FORGOT PASSWORD - RESET PASSWORD
  // =========================================================

  static Future<Map<String, dynamic>> resetForgotPassword({
    required String identifier,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await _post('/auth/forgot-password/reset-password', {
      'identifier': identifier,
      'password': password,
      'confirm_password': confirmPassword,
    });

    final data = _decode(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw ApiException(_detail(data, 'Failed to reset password.'));
  }
}
