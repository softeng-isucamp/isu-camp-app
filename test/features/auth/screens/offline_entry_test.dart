import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/screens/get_started_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('saved catalog exposes a search entry after app restart',
      (tester) async {
    final content = utf8.encode(jsonEncode({
      'buildings': [
        {'id': '1', 'name': 'Library', 'latitude': 16.72, 'longitude': 121.69}
      ]
    }));
    final hash = sha256.convert(content).toString();
    SharedPreferences.setMockInitialValues({
      'campus_pack_v1': jsonEncode({
        'schemaVersion': 1,
        'size': content.length,
        'sha256': hash,
        'content': base64Encode(content),
      }),
    });
    await tester.pumpWidget(const MaterialApp(home: GetStartedScreen()));
    await tester.pump();
    expect(find.text('Open offline campus map'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
