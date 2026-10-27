import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class CaptchaException implements Exception {
  const CaptchaException(this.message);
  final String message;
}

class CaptchaService {
  static Future<void> checkAvailability({String parentOrigin = ''}) async {
    final url = Uri.parse('${AuthService.baseUrl}/auth/captcha/config').replace(
      queryParameters:
          parentOrigin.isEmpty ? null : {'parent_origin': parentOrigin},
    );
    final http.Response response;
    try {
      response = await http.get(url).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const CaptchaException(
          'The verification service took too long to respond. Please try again.');
    } on http.ClientException {
      throw const CaptchaException(
          'Could not reach the verification service. Please try again later.');
    }

    if (response.statusCode == 404 || response.statusCode == 405) {
      throw const CaptchaException(
          'Human verification is not available on this server yet. Please contact support.');
    }

    dynamic data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      // A proxy may return an HTML error page instead of API JSON.
    }
    final detail = data is Map ? data['detail'] : null;
    final code = detail is Map ? detail['code'] : null;
    if (code == 'captcha_not_configured') {
      throw const CaptchaException(
          'Human verification has not been set up yet. Please contact support.');
    }
    if (code == 'captcha_origin_not_allowed') {
      throw const CaptchaException(
          'Human verification is not enabled for this app address. Please contact support.');
    }
    if (response.statusCode != 200 ||
        data is! Map ||
        data['provider'] != 'recaptcha-v2') {
      throw const CaptchaException(
          'The verification service is temporarily unavailable. Please try again later.');
    }
  }
}
