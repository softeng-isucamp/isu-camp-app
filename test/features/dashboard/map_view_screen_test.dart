import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';

void main() {
  testWidgets('controls remain after buildings finish loading', (tester) async {
    final response = Completer<http.Response>();
    final tileBytes = File('assets/images/logo_isu_png.png').readAsBytesSync();
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: MapViewScreen()));
      expect(find.byType(TextField), findsOneWidget);
      final searchElement = tester.element(find.byType(TextField));
      // Chrome grows when docked DevTools closes, before the request finishes.
      await tester.binding.setSurfaceSize(const Size(2560, 1440));
      await tester.pump();
      response.complete(http.Response(
          jsonEncode({
            'buildings': [
              {
                'id': '1',
                'name': 'Test Building',
                'acronym': 'TEST',
                'latitude': 16.7216,
                'longitude': 121.6917
              }
            ]
          }),
          200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Loading campus locations...'), findsNothing);
      final buildingLabel = find.byKey(const ValueKey('building-label-1'));
      final buildingIcon = find.byKey(const ValueKey('building-icon-1'));
      expect(tester.widget<AnimatedOpacity>(buildingLabel).opacity, 0);
      expect(tester.widget<AnimatedOpacity>(buildingIcon).opacity, 1);
      expect(find.byKey(const ValueKey('building-marker-1')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(buildingLabel).opacity,
          greaterThan(0));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(buildingLabel).opacity, 1);
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
          tester.widget<AnimatedOpacity>(buildingLabel).opacity, lessThan(1));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(buildingLabel).opacity, 0);
      expect(tester.widget<AnimatedOpacity>(buildingIcon).opacity, 1);
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(buildingIcon).opacity,
          inExclusiveRange(0, 1));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(buildingIcon).opacity, 0);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.element(find.byType(TextField)), same(searchElement));
      expect(find.text('All'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) {
              if (request.url.path == '/campus/buildings')
                return response.future;
              return Future.value(http.Response.bytes(tileBytes, 200,
                  headers: {'content-type': 'image/png'}));
            }));
  });

  testWidgets('map retains search, filters and profile controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: MapViewScreen()));
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
