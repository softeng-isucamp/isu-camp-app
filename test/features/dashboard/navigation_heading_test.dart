import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:isu_camp_app/features/dashboard/models/navigation_heading.dart';

void main() {
  test('bearings follow north, east, south and west', () {
    const origin = LatLng(0, 0);
    expect(navigationBearing(origin, const LatLng(1, 0)), closeTo(0, .01));
    expect(navigationBearing(origin, const LatLng(0, 1)), closeTo(90, .01));
    expect(navigationBearing(origin, const LatLng(-1, 0)), closeTo(180, .01));
    expect(navigationBearing(origin, const LatLng(0, -1)), closeTo(270, .01));
    expect(navigationBearing(origin, origin), isNull);
  });

  test('preview turns at corners and retains incoming direction at arrival',
      () {
    const points = [LatLng(0, 0), LatLng(1, 0), LatLng(1, 1), LatLng(0, 1)];
    expect(routeHeading(points, points[0]), closeTo(0, .01));
    expect(routeHeading(points, points[1]), closeTo(90, .1));
    expect(routeHeading(points, points[2]), closeTo(180, .01));
    expect(routeHeading(points, points[3]), closeTo(180, .01));
  });

  test('empty and duplicate geometry does not produce invalid angles', () {
    const point = LatLng(0, 0);
    expect(routeHeading([], point), isNull);
    expect(routeHeading([point, point], point), isNull);
    expect(routeHeading([point, point, const LatLng(0, 1)], point),
        closeTo(90, .01));
  });
}
