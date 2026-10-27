import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';
import 'package:latlong2/latlong.dart';

import 'live_navigation_test.dart' show TestGps;

void main() {
  const distance = Distance();
  late TestGps gps;
  // The line only follows plausible progress, so tests move the clock along
  // with the user.
  var elapsed = Duration.zero;
  List<LatLng> drawnRoute(WidgetTester tester) => tester
      .widget<PolylineLayer>(find.byType(PolylineLayer))
      .polylines
      .single
      .points;

  // Drives from [from] to [to] in one-second fixes, at the speed and heading
  // that cover the way: travel is only believed from GPS speed.
  Future<void> drive(WidgetTester tester, LatLng from, LatLng to, int seconds,
      {double heading = 0}) async {
    final speed = distance(from, to) / seconds;
    for (var second = 1; second <= seconds; second++) {
      final t = second / seconds;
      elapsed += const Duration(seconds: 1);
      gps.move(from.latitude + (to.latitude - from.latitude) * t,
          from.longitude + (to.longitude - from.longitude) * t,
          speed: speed, heading: heading);
      await tester.pump();
    }
  }

  Future<void> navigate(WidgetTester tester, Future<void> Function() walk,
      {List<List<double>> path = const [
        [16.72, 121.69],
        [16.721, 121.69],
        [16.721, 121.691]
      ],
      Duration rerouteDelay = Duration.zero}) async {
    final previousGps = GeolocatorPlatform.instance;
    gps = TestGps()..current = TestGps.fix(16.72, 121.69, speed: 0);
    GeolocatorPlatform.instance = gps;
    elapsed = Duration.zero;
    addTearDown(() async {
      GeolocatorPlatform.instance = previousGps;
      await gps.fixes.close();
      await tester.binding.setSurfaceSize(null);
    });
    final tile = File('assets/images/logo_isu_png.png').readAsBytesSync();
    var routeRequests = 0;

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
      await tester.tap(find.byKey(const ValueKey('route-origin-field')));
      await tester.pump();
      await tester.tap(find.text('Use My Current Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('View Route'));
      await tester.tap(find.text('View Route'));
      await tester.pump();
      // Route details still show the whole route.
      expect(drawnRoute(tester), hasLength(path.length));
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      for (var i = 0;
          i < 10 && find.byType(ActiveNavigationHud).evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ActiveNavigationHud), findsOneWidget);
      await walk();
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
                // Later requests are reroutes, which may answer slowly.
                if (routeRequests++ > 0) await Future.delayed(rerouteDelay);
                return http.Response(
                    jsonEncode({
                      'routes': [
                        for (final type in ['shortest', 'comfortableShaded'])
                          {
                            'type': type,
                            'mode': 'walking',
                            'distanceMeters': 220,
                            'estimatedMinutes': 3,
                            'startNodeName': 'Gate',
                            'pathPoints': path,
                            'steps': [],
                          }
                      ]
                    }),
                    200);
              }
              return http.Response.bytes(tile, 200,
                  headers: {'content-type': 'image/png'});
            }));
  }

  testWidgets('the route line shrinks behind the user while navigating',
      (tester) async {
    await navigate(tester, () async {
      await drive(tester, const LatLng(16.72, 121.69),
          const LatLng(16.7205, 121.69), 5);
      expect(distance(drawnRoute(tester).first, const LatLng(16.7205, 121.69)),
          lessThan(1));
      expect(drawnRoute(tester), hasLength(3));

      // A fix slightly behind does not bring the walked route back.
      gps.move(16.7203, 121.69, speed: 0);
      await tester.pump();
      expect(distance(drawnRoute(tester).first, const LatLng(16.7205, 121.69)),
          lessThan(1));

      // Round the corner: the first leg is gone.
      await drive(tester, const LatLng(16.7205, 121.69),
          const LatLng(16.721, 121.69), 4);
      await drive(tester, const LatLng(16.721, 121.69),
          const LatLng(16.721, 121.6905), 4,
          heading: 90);
      expect(drawnRoute(tester), hasLength(2));
      expect(distance(drawnRoute(tester).first, const LatLng(16.721, 121.6905)),
          lessThan(1));
    });
  });

  testWidgets('an inaccurate fix does not trim the route line', (tester) async {
    await navigate(tester, () async {
      await drive(tester, const LatLng(16.72, 121.69),
          const LatLng(16.7205, 121.69), 5);
      // Round the corner, but too inaccurate to count as progress.
      elapsed += const Duration(seconds: 1);
      gps.move(16.721, 121.6905, accuracy: 80, speed: 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(drawnRoute(tester), hasLength(3));

      elapsed += const Duration(seconds: 1);
      gps.move(16.7207, 121.69, speed: 0);
      await tester.pump();
      await tester.pump();
      expect(drawnRoute(tester), hasLength(3));
      expect(distance(drawnRoute(tester).first, const LatLng(16.7207, 121.69)),
          lessThan(1));
    });
  });

  testWidgets('a slow reroute starts the line where the user is by then',
      (tester) async {
    // A hairpin: about 111 m north, 11 m east, then back south alongside.
    LatLng alongHairpin(double meters) => meters <= 111.2
        ? LatLng(16.72 + meters / 111.2 * 0.001, 121.69)
        : meters <= 122.2
            ? LatLng(16.721, 121.69 + (meters - 111.2) / 11 * 0.0001032)
            : LatLng(16.721 - (meters - 122.2) / 111.2 * 0.001, 121.6901032);
    await navigate(tester, () async {
      // The route from the start takes 10 s to arrive; meanwhile the user
      // drives round the hairpin to beside the first leg, then stops.
      for (var second = 1; second <= 11; second++) {
        final meters = 18.8 * math.min(second, 10);
        elapsed += const Duration(seconds: 1);
        gps.move(alongHairpin(meters).latitude, alongHairpin(meters).longitude,
            speed: second > 10 ? 0 : 18.8,
            heading: meters <= 111.2
                ? 0
                : meters <= 122.2
                    ? 90
                    : 180);
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(drawnRoute(tester), hasLength(2));
      expect(
          distance(drawnRoute(tester).first, alongHairpin(188)), lessThan(1));
    }, path: const [
      [16.72, 121.69],
      [16.721, 121.69],
      [16.721, 121.6901032],
      [16.72, 121.6901032]
    ], rerouteDelay: const Duration(seconds: 10));
  });
}
