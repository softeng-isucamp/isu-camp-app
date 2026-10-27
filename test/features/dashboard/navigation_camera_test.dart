import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/navigation_camera.dart';
import 'package:latlong2/latlong.dart';

/// Matches a compass heading within 2°, treating 0° and 360° as equal.
Matcher isHeading(double expected) => predicate<double?>(
    (actual) =>
        actual != null && ((actual - expected + 540) % 360 - 180).abs() < 2,
    'a heading of about $expected°');

void main() {
  test('heading-up turns the map against the heading', () {
    expect(cameraRotationForHeading(0), 0);
    expect(cameraRotationForHeading(90), 270);
    expect(cameraRotationForHeading(270), 90);
    expect(cameraRotationForHeading(450), 270);
  });

  test('uses the compass when slow and the GPS course when fast', () {
    expect(navigationFacing(compassHeading: 10, gpsCourse: 200, speed: 1), 10);
    expect(navigationFacing(compassHeading: 10, gpsCourse: 200, speed: 8), 200);
    expect(navigationFacing(gpsCourse: 200, speed: 0), 200);
    expect(navigationFacing(compassHeading: 10, speed: 8), 10);
    expect(navigationFacing(), isNull);
  });

  test('predicts movement along the course, capped after the last fix', () {
    const fix = LatLng(16.72, 121.69);
    const distance = Distance();
    final ahead = predictPosition(fix,
        speed: 10, course: 0, elapsed: const Duration(milliseconds: 500));
    expect(distance(fix, ahead), closeTo(5, 0.1));
    expect(ahead.latitude, greaterThan(fix.latitude));

    final capped = predictPosition(fix,
        speed: 10, course: 90, elapsed: const Duration(seconds: 10));
    expect(distance(fix, capped), closeTo(15, 0.1));
    expect(capped.longitude, greaterThan(fix.longitude));
  });

  test('does not predict while still or without a course', () {
    const fix = LatLng(16.72, 121.69);
    const elapsed = Duration(seconds: 1);
    expect(predictPosition(fix, speed: 0.2, course: 0, elapsed: elapsed), fix);
    expect(predictPosition(fix, speed: 5, course: null, elapsed: elapsed), fix);
  });

  group('route-up camera', () {
    // 100 m north, then 100 m east.
    const start = LatLng(16.72, 121.69);
    const distance = Distance();
    final corner = distance.offset(start, 100, 0);
    final end = distance.offset(corner, 100, 90);
    final route = [start, corner, end];

    test('faces along the route on a straight stretch', () {
      final onRoute = distance.offset(start, 30, 0);
      expect(navigationCameraHeading(route, onRoute, gpsCourse: 200),
          isHeading(0));
    });

    test('ignores the walking direction while on the route', () {
      final nearRoute = distance.offset(distance.offset(start, 30, 0), 5, 90);
      expect(navigationCameraHeading(route, nearRoute, gpsCourse: 270),
          isHeading(0));
    });

    test('turns gradually while rounding a corner', () {
      final beforeCorner = distance.offset(start, 90, 0);
      final heading = navigationCameraHeading(route, beforeCorner)!;
      expect(heading, greaterThan(10));
      expect(heading, lessThan(80));

      final afterCorner = distance.offset(corner, 30, 90);
      expect(navigationCameraHeading(route, afterCorner), isHeading(90));
    });

    test('keeps facing the final stretch at the destination', () {
      expect(navigationCameraHeading(route, end), isHeading(90));
    });

    test('follows the walking direction when off the route', () {
      final offRoute = distance.offset(distance.offset(start, 30, 0), 60, 270);
      expect(navigationCameraHeading(route, offRoute, gpsCourse: 180), 180);
      expect(navigationCameraHeading(route, offRoute), isHeading(0));
    });

    test('measures points along the route', () {
      expect(
          distance(
              pointAlongRoute(route, 150), distance.offset(corner, 50, 90)),
          lessThan(0.5));
      expect(pointAlongRoute(route, 1000), end);
    });
  });
}
