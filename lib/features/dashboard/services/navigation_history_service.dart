import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../auth/services/auth_service.dart';
import '../../auth/services/user_session.dart';
import '../models/navigation_history.dart';
import 'history_local_store.dart';

class NavigationHistoryService {
  static HistoryLocalStore store = const SecureHistoryLocalStore();
  static Completer<void>? _storageGate;
  static Future<void>? _syncInFlight;
  static String? _syncIdentity;

  static String get _account =>
      UserSession.currentUsername.trim().toLowerCase();

  static Future<T> _locked<T>(Future<T> Function() action) async {
    final previous = _storageGate?.future;
    final done = Completer<void>();
    _storageGate = done;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_storageGate, done)) _storageGate = null;
      done.complete();
    }
  }

  static Future<_HistoryData> _read(String account) async {
    final raw = await store.read(account);
    if (raw == null) return _HistoryData();
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return _HistoryData();
      return _HistoryData(
        pending: (value['pending'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        cached: (value['cached'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
      );
    } on FormatException {
      return _HistoryData();
    } on TypeError {
      return _HistoryData();
    }
  }

  static Future<void> _write(String account, _HistoryData data) => store.write(
      account,
      jsonEncode({
        'pending': data.pending,
        'cached': data.cached.take(500).toList(),
      }));

  static String _newEventId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Map<String, String> _headers(String? session) {
    if (session == null || session.isEmpty) {
      throw Exception('Please log in again to access your history.');
    }
    return {
      'Authorization': 'Bearer $session',
      'Content-Type': 'application/json'
    };
  }

  static Future<http.Response> _request(String method, Uri uri,
      {String? body, String? token, String? sessionIdentity}) async {
    if (sessionIdentity != null &&
        UserSession.sessionIdentity != sessionIdentity) {
      throw Exception('Your session has changed. Please try again.');
    }
    final initialToken = token ?? UserSession.accessToken;
    Future<http.Response> send(String? access) {
      final headers = _headers(access);
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'POST':
          return http.post(uri, headers: headers, body: body);
        case 'DELETE':
          return http.delete(uri, headers: headers);
        default:
          throw StateError('Unsupported History method.');
      }
    }

    var response =
        await send(initialToken).timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 && UserSession.refreshToken != null) {
      final renewed = UserSession.accessToken != initialToken
          ? UserSession.accessToken!
          : await UserSession.renewAccessToken();
      if (sessionIdentity != null &&
          UserSession.sessionIdentity != sessionIdentity) {
        throw Exception('Your session has changed. Please try again.');
      }
      response = await send(renewed).timeout(const Duration(seconds: 20));
    }
    return response;
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

  static List<NavigationHistoryEntry> _merge(
      _HistoryData data, List<NavigationHistoryEntry> remote) {
    final remoteEventIds = remote.map((entry) => entry.clientEventId).toSet();
    final pending = data.pending
        .map(NavigationHistoryEntry.fromJson)
        .where((entry) => !remoteEventIds.contains(entry.clientEventId));
    final result = [...pending, ...remote];
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  static Future<List<NavigationHistoryEntry>> load() async {
    try {
      await syncPending();
    } catch (_) {
      // History can still load remotely when device storage is unavailable.
    }
    final account = _account;
    final entries = <NavigationHistoryEntry>[];
    try {
      while (true) {
        final response = await _request(
            'GET',
            Uri.parse(
                '${AuthService.baseUrl}/history?offset=${entries.length}'));
        final page = _decode(response)['entries'] as List;
        entries.addAll(page.map((row) => NavigationHistoryEntry.fromJson(
            Map<String, dynamic>.from(row as Map))));
        if (page.length < 100) break;
      }
      try {
        return await _locked(() async {
          final data = await _read(account);
          final remoteIds = entries.map((entry) => entry.clientEventId).toSet();
          data.pending
              .removeWhere((row) => remoteIds.contains(row['clientEventId']));
          data.cached
            ..clear()
            ..addAll(entries.map((entry) => entry.toJson()));
          await _write(account, data);
          return _merge(data, entries);
        });
      } catch (_) {
        return entries;
      }
    } catch (_) {
      final data = await _locked(() => _read(account));
      if (data.pending.isNotEmpty || data.cached.isNotEmpty) {
        return _merge(
            data, data.cached.map(NavigationHistoryEntry.fromJson).toList());
      }
      rethrow;
    }
  }

  static Future<void> record({
    required String buildingId,
    String? roomId,
    String destinationName = 'Saved destination',
    String destinationAcronym = '',
    String? roomName,
    String? sessionIdentity,
  }) async {
    if (!UserSession.isLoggedIn ||
        (sessionIdentity != null &&
            UserSession.sessionIdentity != sessionIdentity)) {
      throw Exception('Please log in again to save your history.');
    }
    final account = _account;
    final eventId = _newEventId();
    final entry = NavigationHistoryEntry(
      id: 'local:$eventId',
      clientEventId: eventId,
      destinationId: int.parse(buildingId).toString(),
      destinationName: destinationName,
      destinationAcronym: destinationAcronym,
      roomId: roomId == null ? null : int.parse(roomId).toString(),
      roomName: roomName,
      createdAt: DateTime.now(),
    );
    await _locked(() async {
      final data = await _read(account);
      if (data.pending.length >= 1000) {
        throw Exception('Offline History is full. Reconnect to sync it.');
      }
      data.pending.add(entry.toJson());
      await _write(account, data);
    });
  }

  static Future<void> syncPending() async {
    if (!UserSession.isLoggedIn) return;
    final account = _account;
    final sessionIdentity = UserSession.sessionIdentity;
    if (_syncInFlight != null && _syncIdentity == sessionIdentity) {
      return _syncInFlight!;
    }
    final running = _sync(account, sessionIdentity);
    _syncInFlight = running;
    _syncIdentity = sessionIdentity;
    try {
      await running;
    } finally {
      if (identical(_syncInFlight, running)) {
        _syncInFlight = null;
        _syncIdentity = null;
      }
    }
  }

  static Future<void> _sync(String account, String? sessionIdentity) async {
    final events =
        await _locked(() async => (await _read(account)).pending.toList());
    for (final event in events) {
      if (_account != account ||
          UserSession.sessionIdentity != sessionIdentity) {
        return;
      }
      http.Response response;
      try {
        response =
            await _request('POST', Uri.parse('${AuthService.baseUrl}/history'),
                sessionIdentity: sessionIdentity,
                body: jsonEncode({
                  'buildingId': int.parse(event['destinationId'] as String),
                  'locationId': event['roomId'] == null
                      ? null
                      : int.parse(event['roomId'] as String),
                  'clientEventId': event['clientEventId'],
                }));
      } catch (_) {
        return; // Keep the durable event for the next reconnect.
      }
      if (response.statusCode == 400 || response.statusCode == 404) {
        continue; // Keep this event but allow later events to sync.
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final body = _decode(response);
      await _locked(() async {
        final data = await _read(account);
        data.pending.removeWhere(
            (row) => row['clientEventId'] == event['clientEventId']);
        final synced = Map<String, dynamic>.from(event);
        synced['id'] = body['id'].toString();
        data.cached.removeWhere(
            (row) => row['clientEventId'] == event['clientEventId']);
        data.cached.insert(0, synced);
        await _write(account, data);
      });
    }
  }

  static Future<void> delete(String id) async {
    final account = _account;
    if (id.startsWith('local:')) {
      await _locked(() async {
        final data = await _read(account);
        data.pending.removeWhere((row) => row['id'] == id);
        await _write(account, data);
      });
      return;
    }
    final response = await _request('DELETE',
        Uri.parse('${AuthService.baseUrl}/history/${Uri.encodeComponent(id)}'));
    _decode(response);
    await _locked(() async {
      final data = await _read(account);
      data.cached.removeWhere((row) => row['id'] == id);
      await _write(account, data);
    });
  }

  static Future<void> clear() async {
    final response =
        await _request('DELETE', Uri.parse('${AuthService.baseUrl}/history'));
    _decode(response);
    final account = _account;
    await _locked(() => _write(account, _HistoryData()));
  }
}

class _HistoryData {
  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> cached;

  _HistoryData(
      {List<Map<String, dynamic>>? pending, List<Map<String, dynamic>>? cached})
      : pending = pending ?? [],
        cached = cached ?? [];
}
