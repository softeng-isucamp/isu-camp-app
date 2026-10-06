import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:latlong2/latlong.dart';

class TestGps extends GeolocatorPlatform {
  final fixes = StreamController<Position>.broadcast();
  Position current = fix(16.72, 121.69);
  static Position fix(double latitude, double longitude,
          {double accuracy = 5, double speed = 1, double heading = 0}) =>
      Position(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now(),
          accuracy: accuracy,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: heading,
          headingAccuracy: 0,
          speed: speed,
          speedAccuracy: 0);
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      current;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      fixes.stream;
  void move(double latitude, double longitude,
      {double accuracy = 5, double speed = 1, double heading = 0}) {
    current = fix(latitude, longitude,
        accuracy: accuracy, speed: speed, heading: heading);
    fixes.add(current);
  }
}

void main() {
  for (final mode in TransportMode.values) {
    testWidgets(
        '${mode.name}: live GPS advances guidance, reroutes, and arrives without a simulator',
        (tester) async {
      final previousGps = GeolocatorPlatform.instance;
      final gps = TestGps();
      GeolocatorPlatform.instance = gps;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() async {
        GeolocatorPlatform.instance = previousGps;
        debugDefaultTargetPlatformOverride = null;
        await gps.fixes.close();
        await tester.binding.setSurfaceSize(null);
      });
      var requests = 0;
      var elapsed = Duration.zero;
      final tile = File('assets/images/logo_isu_png.png').readAsBytesSync();
      await http.runWithClient(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        await tester.pumpWidget(MaterialApp(
            home: MapViewScreen(
                navigationClock: () => DateTime.now().add(elapsed))));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byKey(const ValueKey('building-icon-1')));
        await tester.pump();
        await tester.tap(find.text('DIRECTIONS'));
        await tester.pump();
        if (mode != TransportMode.walking) {
          await tester.tap(find.byIcon(routeModeIcon(mode)));
          await tester.pump();
        }
        await tester.tap(find.byKey(const ValueKey('route-origin-field')));
        await tester.pump();
        await tester.tap(find.text('Use My Current Location'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.ensureVisible(find.text('View Route'));
        await tester.tap(find.text('View Route'));
        await tester.pump();
        await tester.ensureVisible(find.text('Start'));
        await tester.tap(find.text('Start'));
        for (var i = 0;
            i < 10 && find.byType(ActiveNavigationHud).evaluate().isEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(ActiveNavigationHud), findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((text) => text.data)
                .join(' | '));
        final initial = tester
            .widget<ActiveNavigationHud>(find.byType(ActiveNavigationHud))
            .progress!;
        expect(
            tester
                .widget<ActiveNavigationHud>(find.byType(ActiveNavigationHud))
                .selectedTransportMode,
            mode);
        expect(
            tester
                .widget<ActiveNavigationHud>(find.byType(ActiveNavigationHud))
                .route
                .mode,
            mode);
        // Moving fast to the east: the map turns heading-up (east at the
        // top) and the camera keeps moving between one-second GPS fixes.
        final camera = () => tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera;
        gps.move(16.7202, 121.69, speed: 10, heading: 90);
        await tester.pump();
        elapsed = const Duration(seconds: 1);
        await tester.pump(const Duration(seconds: 1));
        expect(camera().rotation, closeTo(270, 1));
        // At least one second ahead at 10 m/s, at most the 1.5 s cap.
        expect(const Distance()(const LatLng(16.7202, 121.69), camera().center),
            inInclusiveRange(10, 15));
        expect(camera().center.longitude, greaterThan(121.69));
        elapsed = Duration.zero;

        gps.move(16.7209, 121.69);
        await tester.pump();
        // After the follow ticks above, the fix can rebuild one frame later.
        await tester.pump();
        expect(find.textContaining('Turn right'), findsOneWidget);
        final advanced = tester
            .widget<ActiveNavigationHud>(find.byType(ActiveNavigationHud))
            .progress!;
        expect(advanced.remainingMeters, lessThan(initial.remainingMeters));
        final beforeReroute = requests;
        gps.move(16.7205, 121.6895);
        await tester.pump();
        gps.move(16.7205, 121.6895);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        // Initial route refresh is rate-limited; sustained deviation retries after cooldown.
        await tester.pump(const Duration(seconds: 16));
        elapsed = const Duration(seconds: 16);
        gps.move(16.7205, 121.6895);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(requests, greaterThan(beforeReroute));
        expect(find.text('Retry route'), findsOneWidget);
        gps.move(16.7205, 121.6895);
        await tester.pump();
        expect(find.textContaining('Route update failed'), findsOneWidget);
        await tester.tap(find.text('Retry route'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.textContaining('Route update failed'), findsNothing);
        elapsed = const Duration(seconds: 40);
        await tester.pump(const Duration(seconds: 5));
        expect(find.textContaining('GPS signal lost'), findsOneWidget);
        elapsed = const Duration(seconds: 16);
        gps.move(16.721, 121.691, accuracy: 80);
        await tester.pump();
        expect(find.byType(ArrivalHud), findsNothing);
        gps.move(16.721, 121.691);
        await tester.pump();
        expect(find.byType(ArrivalHud), findsNothing);
        gps.move(16.721, 121.691);
        await tester.pump();
        expect(find.byType(ArrivalHud), findsOneWidget);
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
                          }
                        ]
                      }),
                      200);
                }
                if (request.url.path == '/campus/routes') {
                  requests++;
                  expect(jsonDecode(request.body)['mode'], mode.name);
                  if (requests == 3)
                    return http.Response(
                        '{"detail":"Temporarily unavailable"}', 503);
                  return http.Response(
                      jsonEncode({
                        'routes': [
                          for (final type in ['shortest', 'comfortableShaded'])
                            {
                              'type': type,
                              'mode': mode.name,
                              'distanceMeters': 220,
                              'estimatedMinutes': 220 /
                                  (mode == TransportMode.car
                                      ? 350
                                      : mode == TransportMode.motorcycle
                                          ? 450
                                          : mode == TransportMode.bicycle
                                              ? 220
                                              : 80),
                              'startNodeName': 'Gate',
                              'pathPoints': [
                                [16.72, 121.69],
                                [16.721, 121.69],
                                [16.721, 121.691]
                              ],
                              'steps': [
                                {
                                  'instruction': 'Follow North Path',
                                  'distanceMeters': 111,
                                  'coordinate': [16.72, 121.69]
                                },
                                {
                                  'instruction': 'Follow East Path',
                                  'distanceMeters': 106,
                                  'coordinate': [16.721, 121.69]
                                },
                              ],
                            }
                        ]
                      }),
                      200);
                }
                return http.Response.bytes(tile, 200,
                    headers: {'content-type': 'image/png'});
              }));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
