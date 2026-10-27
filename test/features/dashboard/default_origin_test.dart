import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';

import 'live_navigation_test.dart' show TestGps;

/// Holds the first fix back until the test releases it. Assign a new
/// completer to hold back the next one.
class DelayedGps extends TestGps {
  var firstFix = Completer<Position>();
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      firstFix.isCompleted ? Future.value(current) : firstFix.future;
}

void main() {
  final tile = File('assets/images/logo_isu_png.png').readAsBytesSync();

  Future<void> run(
      WidgetTester tester,
      TestGps gps,
      Future<void> Function(List<Map<String, dynamic>> routeRequests)
          body) async {
    final previousGps = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = gps;
    addTearDown(() async {
      GeolocatorPlatform.instance = previousGps;
      await gps.fixes.close();
      await tester.binding.setSurfaceSize(null);
    });
    final routeRequests = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      await tester.pumpWidget(const MaterialApp(home: MapViewScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      await body(routeRequests);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              if (request.url.path == '/campus/buildings') {
                return http.Response(
                    jsonEncode({
                      'buildings': [
                        {
                          'id': '1',
                          'name': 'Test Building',
                          'acronym': 'TEST',
                          'latitude': 16.721,
                          'longitude': 121.691,
                        },
                        {
                          'id': '2',
                          'name': 'Other Hall',
                          'acronym': 'OTH',
                          'latitude': 16.722,
                          'longitude': 121.692,
                        }
                      ]
                    }),
                    200);
              }
              if (request.url.path == '/campus/routes') {
                routeRequests.add(jsonDecode(request.body));
                return http.Response(jsonEncode({'routes': []}), 200);
              }
              return http.Response.bytes(tile, 200,
                  headers: {'content-type': 'image/png'});
            }));
  }

  Future<void> openDirections(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('building-icon-1')));
    await tester.pump();
    await tester.tap(find.text('DIRECTIONS'));
    await tester.pump();
  }

  String originText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('route-origin-field')))
      .controller!
      .text;

  testWidgets('directions start from the current location inside campus',
      (tester) async {
    await run(tester, TestGps(), (routeRequests) async {
      await openDirections(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'My Current Location');
      expect(routeRequests, isNotEmpty);
      expect(routeRequests.last['origin']['type'], 'currentLocation');
    });
  });

  testWidgets('directions start with no origin outside campus', (tester) async {
    final gps = TestGps()..current = TestGps.fix(16.0, 121.0);
    await run(tester, gps, (routeRequests) async {
      await openDirections(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), isEmpty);
      expect(routeRequests, isEmpty);
    });
  });

  testWidgets('a fix arriving after directions open becomes the origin',
      (tester) async {
    final gps = DelayedGps();
    await run(tester, gps, (routeRequests) async {
      await openDirections(tester);
      expect(originText(tester), isEmpty);
      gps.firstFix.complete(gps.current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'My Current Location');
      expect(routeRequests, isNotEmpty);
    });
  });

  testWidgets('a later fix never replaces a starting point the user chose',
      (tester) async {
    final gps = DelayedGps();
    await run(tester, gps, (routeRequests) async {
      await openDirections(tester);
      final field = find.byKey(const ValueKey('route-origin-field'));
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'other');
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byType(ChooseRouteSheet),
          matching: find.text('Other Hall')));
      await tester.pump();
      expect(originText(tester), 'Other Hall');
      gps.firstFix.complete(gps.current);
      await tester.pump();
      gps.move(16.7201, 121.69);
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'Other Hall');
      expect(routeRequests.last['origin']['type'], isNot('currentLocation'));
    });
  });
  testWidgets('a fix lost to a GPS error is not preselected', (tester) async {
    final gps = DelayedGps();
    await run(tester, gps, (routeRequests) async {
      gps.firstFix.complete(gps.current);
      await tester.pump();
      gps.fixes.addError(Exception('Location services were turned off'));
      await tester.pump();
      gps.firstFix = Completer<Position>();
      await openDirections(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), isEmpty);
      expect(routeRequests, isEmpty);
      // The background request restarts location and its fix is used.
      gps.firstFix.complete(gps.current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'My Current Location');
    });
  });

  testWidgets('a stale fix is not preselected', (tester) async {
    final stale = TestGps.fix(16.72, 121.69);
    final gps = TestGps()
      ..current = Position(
          latitude: stale.latitude,
          longitude: stale.longitude,
          timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
          accuracy: stale.accuracy,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0);
    await run(tester, gps, (routeRequests) async {
      await openDirections(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), isEmpty);
      expect(routeRequests, isEmpty);
    });
  });

  testWidgets('a fix arriving mid-search keeps the query and picker',
      (tester) async {
    final gps = DelayedGps();
    await run(tester, gps, (routeRequests) async {
      await openDirections(tester);
      final field = find.byKey(const ValueKey('route-origin-field'));
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'other');
      await tester.pump();
      gps.firstFix.complete(gps.current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'other');
      final otherHall = find.descendant(
          of: find.byType(ChooseRouteSheet), matching: find.text('Other Hall'));
      expect(otherHall, findsOneWidget);
      await tester.tap(otherHall);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'Other Hall');
      expect(routeRequests.last['origin']['buildingId'], '2');
      gps.move(16.7201, 121.69);
      await tester.pump(const Duration(milliseconds: 100));
      expect(originText(tester), 'Other Hall');
      expect(routeRequests.last['origin']['buildingId'], '2');
    });
  });
}
