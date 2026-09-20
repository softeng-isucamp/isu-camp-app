import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/services/auth_service.dart';
import '../../auth/services/user_session.dart';
import '../models/navigation_history.dart';

class NavigationHistoryService {
  static Map<String, String> _headers([String? token]) {
    final session = token ?? UserSession.accessToken;
    if (session == null || session.isEmpty) {
      throw Exception('Please log in again to access your history.');
    }
    return {
      'Authorization': 'Bearer $session',
      'Content-Type': 'application/json'
    };
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] is String
          ? data['detail']
          : 'History request failed.');
    }
    return data;
  }

  static Future<List<NavigationHistoryEntry>> load() async {
    final headers = _headers();
    final entries = <NavigationHistoryEntry>[];
    while (true) {
      final response = await http
          .get(
            Uri.parse(
                '${AuthService.baseUrl}/history?offset=${entries.length}'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));
      final page = _decode(response)['entries'] as List;
      entries.addAll(page.map((row) => NavigationHistoryEntry.fromJson(
          Map<String, dynamic>.from(row as Map))));
      if (page.length < 100) return entries;
    }
  }

  static Future<void> record(
      {required String buildingId,
      String? roomId,
      required String token}) async {
    final response = await http
        .post(Uri.parse('${AuthService.baseUrl}/history'),
            headers: _headers(token),
            body: jsonEncode({
              'buildingId': int.parse(buildingId),
              'locationId': roomId == null ? null : int.parse(roomId),
            }))
        .timeout(const Duration(seconds: 20));
    _decode(response);
  }

  static Future<void> delete(String id) async {
    final response = await http
        .delete(
            Uri.parse(
                '${AuthService.baseUrl}/history/${Uri.encodeComponent(id)}'),
            headers: _headers())
        .timeout(const Duration(seconds: 20));
    _decode(response);
  }

  static Future<void> clear() async {
    final response = await http
        .delete(Uri.parse('${AuthService.baseUrl}/history'),
            headers: _headers())
        .timeout(const Duration(seconds: 20));
    _decode(response);
  }
}
