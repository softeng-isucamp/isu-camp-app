import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/navigation_camera.dart';
import 'package:latlong2/latlong.dart';

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
}
