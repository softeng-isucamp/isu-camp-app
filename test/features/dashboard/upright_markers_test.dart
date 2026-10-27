import 'dart:math' as math;
import 'dart:convert';
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
  final tile = File('assets/images/logo_isu_png.png').readAsBytesSync();
  const destinationYellow = Color(0xFFECC700);

  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    final previousGps = GeolocatorPlatform.instance;
    final gps = TestGps();
    GeolocatorPlatform.instance = gps;
    addTearDown(() async {
      GeolocatorPlatform.instance = previousGps;
      await gps.fixes.close();
      await tester.binding.setSurfaceSize(null);
    });
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpWidget(const MaterialApp(home: MapViewScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      await body();
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
                          'polygonCoordinates': [
                            [16.7209, 121.6909],
                            [16.7209, 121.6911],
                            [16.7211, 121.6911],
                            [16.7211, 121.6909],
                          ],
                        },
                        {
                          'id': '2',
                          'name': 'Other Hall',
                          'acronym': 'OTH',
                          'latitude': 16.722,
                          'longitude': 121.692,
                          'polygonCoordinates': [
                            [16.7219, 121.6919],
                            [16.7219, 121.6921],
                            [16.7221, 121.6921],
                            [16.7221, 121.6919],
                          ],
                        }
                      ]
                    }),
                    200);
              }
              if (request.url.path == '/campus/routes') {
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
                            'pathPoints': [
                              [16.72, 121.69],
                              [16.721, 121.69],
                              [16.721, 121.691]
                            ],
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

  MapController controller(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  /// How far [finder] is turned on screen, in degrees.
  double screenRotation(WidgetTester tester, Finder finder) {
    final transform =
        tester.renderObject<RenderBox>(finder).getTransformTo(null);
    return math.atan2(transform.entry(1, 0), transform.entry(0, 0)) *
        180 /
        math.pi;
  }

  testWidgets('building icons and names stay upright on a rotated map',
      (tester) async {
    await run(tester, () async {
      controller(tester).move(const LatLng(16.721, 121.691), 18.5);
      await tester.pump(const Duration(milliseconds: 300));
      for (final rotation in [90.0, 180.0, 235.0]) {
        controller(tester).rotate(rotation);
        await tester.pump(const Duration(milliseconds: 300));
        final icon = find.descendant(
            of: find.byKey(const ValueKey('building-icon-1')),
            matching: find.byType(Icon));
        final label = find.descendant(
            of: find.byKey(const ValueKey('building-label-1')),
            matching: find.byType(Text));
        expect(screenRotation(tester, icon), closeTo(0, 0.5),
            reason: 'icon at $rotation°');
        expect(screenRotation(tester, label), closeTo(0, 0.5),
            reason: 'label at $rotation°');
        final iconCircle = find.descendant(
            of: find.byKey(const ValueKey('building-icon-1')),
            matching: find.byType(AnimatedContainer));
        expect(tester.getTopLeft(label).dy,
            greaterThan(tester.getBottomLeft(iconCircle).dy),
            reason: 'label below icon at $rotation°');
        expect(
            (tester.getCenter(label).dx - tester.getCenter(iconCircle).dx)
                .abs(),
            lessThan(1));
      }
    });
  });

  Iterable<Polygon> highlighted(WidgetTester tester) => tester
      .widgetList<PolygonLayer>(find.byType(PolygonLayer))
      .expand((layer) => layer.polygons)
      .where((polygon) => polygon.borderColor == destinationYellow);

  /// Selects Test Building and opens its route details.
  Future<void> openRouteDetails(WidgetTester tester) async {
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
  }

  Future<void> openPreview(WidgetTester tester) async {
    // The square test font is wider than Montserrat, so at full size the
    // ETA wraps onto two lines and overflows its pill.
    tester.platformDispatcher.textScaleFactorTestValue = 0.75;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.ensureVisible(find.text('Preview'));
    await tester.tap(find.text('Preview'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  void expectDestinationShown(WidgetTester tester, String reason) {
    expect(highlighted(tester), hasLength(1), reason: reason);
    expect(highlighted(tester).single.points.first,
        const LatLng(16.7209, 121.6909));
    expect(find.byKey(const ValueKey('building-icon-1')), findsOneWidget,
        reason: reason);
    expect(find.byKey(const ValueKey('building-label-1')), findsOneWidget,
        reason: reason);
  }

  testWidgets('tapping a building icon on a rotated map selects it',
      (tester) async {
    await run(tester, () async {
      controller(tester)
          .moveAndRotate(const LatLng(16.7215, 121.6915), 18, 135);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('building-icon-2')));
      await tester.pump();
      expect(
          tester
              .widget<BuildingDetailsSheet>(find.byType(BuildingDetailsSheet))
              .building
              .id,
          '2');
    });
  });

  testWidgets('the destination building is highlighted while routing',
      (tester) async {
    await run(tester, () async {
      expect(highlighted(tester), isEmpty);
      await openRouteDetails(tester);
      expectDestinationShown(tester, 'route details');
      await openPreview(tester);
      expectDestinationShown(tester, 'route preview');
      await tester.tap(find.byTooltip('Back to route details'));
      await tester.pump();
      await tester.ensureVisible(find.text('Cancel Directions'));
      await tester.tap(find.text('Cancel Directions'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(highlighted(tester), isEmpty);
    });
  });

  testWidgets('category filters never hide the destination while routing',
      (tester) async {
    await run(tester, () async {
      await openRouteDetails(tester);
      // Test Building is not a parking, so this filter would hide it.
      await tester.tap(find.text('Parkings'));
      await tester.pump();
      expect(find.byKey(const ValueKey('building-icon-2')), findsNothing);
      expectDestinationShown(tester, 'route details');
      await openPreview(tester);
      expectDestinationShown(tester, 'route preview');
      await tester.tap(find.byTooltip('Back to route details'));
      await tester.pump();
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      for (var i = 0;
          i < 10 && find.byType(ActiveNavigationHud).evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ActiveNavigationHud), findsOneWidget);
      expectDestinationShown(tester, 'navigating');
    });
  });

  testWidgets('the route ETA stays upright above its route point',
      (tester) async {
    await run(tester, () async {
      await openRouteDetails(tester);
      await openPreview(tester);
      final time = tester
          .widget<RoutePreviewHud>(find.byType(RoutePreviewHud))
          .route
          .time;
      final pill = find.descendant(
          of: find.byType(MarkerLayer), matching: find.text(time));
      final pointer = find.descendant(
          of: find.byType(MarkerLayer),
          matching: find.byIcon(Icons.arrow_drop_down));
      for (final rotation in [90.0, 200.0]) {
        controller(tester).rotate(rotation);
        await tester.pump(const Duration(milliseconds: 300));
        expect(screenRotation(tester, pill), closeTo(0, 0.5),
            reason: 'ETA at $rotation°');
        final point = controller(tester)
            .camera
            .latLngToScreenPoint(const LatLng(16.721, 121.691));
        expect(tester.getCenter(pointer).dx, closeTo(point.x, 1),
            reason: 'ETA at $rotation°');
        expect(tester.getBottomLeft(pointer).dy,
            inInclusiveRange(point.y - 12, point.y + 1),
            reason: 'ETA just above its point at $rotation°');
        expect(tester.getBottomLeft(pill).dy, lessThan(point.y));
      }
    });
  });
}
