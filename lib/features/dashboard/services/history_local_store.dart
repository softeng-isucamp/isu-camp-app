import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class HistoryLocalStore {
  Future<String?> read(String account);
  Future<void> write(String account, String value);
}

class SecureHistoryLocalStore implements HistoryLocalStore {
  const SecureHistoryLocalStore();

  static const _storage = FlutterSecureStorage();

  String _key(String account) =>
      'navigation_history_v1_${sha256.convert(utf8.encode(account))}';

  @override
  Future<String?> read(String account) => _storage.read(key: _key(account));

  @override
  Future<void> write(String account, String value) =>
      _storage.write(key: _key(account), value: value);
}
