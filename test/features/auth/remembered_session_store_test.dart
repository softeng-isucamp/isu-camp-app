import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/services/remembered_session_store.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';

String tokenExpiringAt(DateTime time) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({
        'exp': time.millisecondsSinceEpoch ~/ 1000,
      })))
      .replaceAll('=', '');
  return 'header.$payload.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.logout();
  });

  test('restores a remembered, unexpired session', () async {
    final token = tokenExpiringAt(DateTime.now().add(const Duration(hours: 1)));
    await RememberedSessionStore.save(
      username: 'student1',
      token: token,
      keepSignedIn: true,
    );

    expect(await RememberedSessionStore.restore(), isTrue);
    expect(UserSession.currentUsername, 'student1');
    expect(UserSession.accessToken, token);
  });

  test('does not restore when keep signed in is unchecked', () async {
    final token = tokenExpiringAt(DateTime.now().add(const Duration(hours: 1)));
    await RememberedSessionStore.save(
      username: 'student1',
      token: token,
      keepSignedIn: true,
    );
    await RememberedSessionStore.save(
      username: 'student1',
      token: token,
      keepSignedIn: false,
    );

    expect(await RememberedSessionStore.restore(), isFalse);
    expect(UserSession.accessToken, isNull);
  });

  test('rejects and removes an expired session', () async {
    await RememberedSessionStore.save(
      username: 'student1',
      token: tokenExpiringAt(DateTime.now().subtract(const Duration(hours: 1))),
      keepSignedIn: true,
    );

    expect(await RememberedSessionStore.restore(), isFalse);
    expect(
        await const FlutterSecureStorage().read(key: 'remembered_access_token'),
        isNull);
  });
}
