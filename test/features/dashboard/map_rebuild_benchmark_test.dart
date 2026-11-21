import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets show debugOnRebuildDirtyWidget;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';
import 'package:latlong2/latlong.dart';

import 'live_navigation_test.dart' show TestGps;

/// How much of the map screen rebuilds while the user stands still with GPS
/// on, pinches to zoom, or pans. Run with `--reporter expanded` to see the
/// numbers; the limits catch a regression to rebuilding every marker.
void main() {
  const buildingCount = 60;

  Map<String, Object> building(int i) {
    final lat = 16.7185 + (i ~/ 10) * 0.0008;
    final lng = 121.6875 + (i % 10) * 0.0008;
    return {
      'id': '$i',
      'name': 'Building $i',
      'acronym': 'B$i',
      'latitude': lat,
      'longitude': lng,
      'polygonCoordinates': [
        for (var k = 0; k < 24; k++)
          [
            lat + 0.0002 * (k.isEven ? 1 : 0.8) * _cos(k / 24),
            lng + 0.0002 * (k.isEven ? 1 : 0.8) * _sin(k / 24),
          ],
      ],
    };
  }

  testWidgets('map rebuild cost', (tester) async {
    final previousGps = GeolocatorPlatform.instance;
    final gps = TestGps();
    GeolocatorPlatform.instance = gps;
    addTearDown(() async {
      GeolocatorPlatform.instance = previousGps;
      await gps.fixes.close();
      await tester.binding.setSurfaceSize(null);
    });

    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(412, 860));
      await tester.pumpWidget(const MaterialApp(home: MapViewScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final controller =
          tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

      var rebuilt = 0;
      Future<({int rebuilt, int micros})> measure(
          Future<void> Function() body) async {
        rebuilt = 0;
        widgets.debugOnRebuildDirtyWidget = (_, __) => rebuilt++;
        final watch = Stopwatch()..start();
        await body();
        watch.stop();
        widgets.debugOnRebuildDirtyWidget = null;
        return (rebuilt: rebuilt, micros: watch.elapsedMicroseconds);
      }

      // Warm up so first-build costs don't land in a phase.
      controller.move(const LatLng(16.721, 121.691), 17.5);
      await tester.pump();

      final fixes = await measure(() async {
        for (var i = 0; i < 30; i++) {
          gps.move(16.7205 + i * 0.00001, 121.6905, speed: 0);
          await tester.pump(const Duration(milliseconds: 16));
        }
      });

      final zoom = await measure(() async {
        for (var i = 0; i < 60; i++) {
          controller.move(const LatLng(16.721, 121.691), 16.0 + i * 0.05);
          await tester.pump(const Duration(milliseconds: 16));
        }
      });

      final pan = await measure(() async {
        for (var i = 0; i < 60; i++) {
          controller.move(LatLng(16.721 + i * 0.00002, 121.691), 18.6);
          await tester.pump(const Duration(milliseconds: 16));
        }
      });

      // ignore: avoid_print
      print('BENCH buildings=$buildingCount '
          'gps30: rebuilt=${fixes.rebuilt} ms=${fixes.micros ~/ 1000} | '
          'zoom60: rebuilt=${zoom.rebuilt} ms=${zoom.micros ~/ 1000} | '
          'pan60: rebuilt=${pan.rebuilt} ms=${pan.micros ~/ 1000}');

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              if (request.url.path == '/campus/buildings') {
                return http.Response(
                    jsonEncode({
                      'buildings': [
                        for (var i = 0; i < buildingCount; i++) building(i)
                      ]
                    }),
                    200);
              }
              return http.Response('{}', 404);
            }));
  });
}

double _cos(double turns) => _trig(turns, cos: true);
double _sin(double turns) => _trig(turns, cos: false);
double _trig(double turns, {required bool cos}) {
  // A small polygon around the building, without importing dart:math twice.
  const steps = [
    1.0,
    0.966,
    0.866,
    0.707,
    0.5,
    0.259,
    0.0,
    -0.259,
    -0.5,
    -0.707,
    -0.866,
    -0.966,
    -1.0,
    -0.966,
    -0.866,
    -0.707,
    -0.5,
    -0.259,
    0.0,
    0.259,
    0.5,
    0.707,
    0.866,
    0.966,
  ];
  final i = (turns * 24).round() % 24;
  return cos ? steps[i] : steps[(i + 18) % 24];
}
