import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/route_trim.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // About 111 m north, then about 107 m east.
  const route = [
    LatLng(16.72, 121.69),
    LatLng(16.721, 121.69),
    LatLng(16.721, 121.691),
  ];
  // A hairpin: about 111 m north, 11 m east, then back south alongside.
  const hairpin = [
    LatLng(16.72, 121.69),
    LatLng(16.721, 121.69),
    LatLng(16.721, 121.6901032),
    LatLng(16.72, 121.6901032),
  ];
  const distance = Distance();
  double lengthOf(List<LatLng> points) => [
        for (var i = 1; i < points.length; i++)
          distance(points[i - 1], points[i])
      ].fold(0.0, (sum, length) => sum + length);
  // [meters] up the first leg of either route.
  LatLng up(double meters) => LatLng(16.72 + meters / 111.2 * 0.001, 121.69);
  final start = DateTime(2026);
  DateTime after(int seconds) => start.add(Duration(seconds: seconds));
  late TravelOdometer odometer;
  setUp(() => odometer = TravelOdometer()..record(start, 0));
  // A fix [seconds] in, moving at [speed] m/s, fed to the trim as the map does.
  List<LatLng> fix(RouteTrim trim, LatLng position, int seconds,
      {double speed = 0, bool advance = true}) {
    odometer.record(after(seconds), speed);
    return trim.ahead(position,
        travelled: odometer.metersAt(after(seconds)), advance: advance);
  }

  // As if the user had travelled far since the route began, so anywhere on
  // it is a plausible place for them to be.
  RouteTrim travelledFar(List<LatLng> points) => RouteTrim(points, -1000);

  test('the line starts where the user is on the route', () {
    final ahead = fix(travelledFar(route), const LatLng(16.7205, 121.69), 1);
    expect(distance(ahead.first, const LatLng(16.7205, 121.69)), lessThan(1));
    expect(ahead.sublist(1), route.sublist(1));
  });

  test('a position off to the side snaps onto the route', () {
    final ahead = fix(travelledFar(route), const LatLng(16.7205, 121.69005), 1);
    expect(distance(ahead.first, const LatLng(16.7205, 121.69)), lessThan(1));
  });

  test('past a corner, the walked leg is gone', () {
    final ahead = fix(travelledFar(route), const LatLng(16.721, 121.6905), 1);
    expect(ahead, hasLength(2));
    expect(ahead.last, route.last);
    expect(distance(ahead.first, const LatLng(16.721, 121.6905)), lessThan(1));
  });

  test('the full route shows before the user reaches it', () {
    expect(fix(RouteTrim(route, 0), const LatLng(16.7198, 121.69), 10), route);
  });

  test('walked route never grows back', () {
    final trim = travelledFar(route);
    fix(trim, const LatLng(16.7208, 121.69), 1);
    final ahead = fix(trim, const LatLng(16.7203, 121.69), 2);
    expect(distance(ahead.first, const LatLng(16.7208, 121.69)), lessThan(1));
  });

  test('positions far from the route do not move the trim', () {
    final trim = travelledFar(route);
    fix(trim, const LatLng(16.7202, 121.69), 1);
    // Well east of the route: a wrong GPS fix, not progress.
    final ahead = fix(trim, const LatLng(16.7205, 121.693), 2);
    expect(distance(ahead.first, const LatLng(16.7202, 121.69)), lessThan(1));
  });

  test('at the destination, only the end point is left', () {
    final ahead = fix(travelledFar(route), route.last, 1);
    expect(ahead, hasLength(1));
    expect(distance(ahead.single, route.last), lessThan(1));
  });

  test('an empty route stays empty', () {
    expect(fix(RouteTrim(const [], 0), route.first, 1), isEmpty);
  });

  test('walking along, the line keeps starting at the user', () {
    final trim = RouteTrim(route, 0);
    // About 1.4 m/s, one fix a second.
    for (var second = 1; second <= 60; second++) {
      final ahead = fix(trim, up(1.4 * second), second, speed: 1.4);
      expect(distance(ahead.first, up(1.4 * second)), lessThan(1));
    }
  });

  test('a vehicle at speed is not left behind', () {
    final trim = RouteTrim(route, 0);
    // About 18 m/s up the first leg.
    for (var second = 1; second <= 5; second++) {
      final ahead = fix(trim, up(18.0 * second), second, speed: 18);
      expect(distance(ahead.first, up(18.0 * second)), lessThan(1));
    }
  });

  test('after a long GPS gap, the line catches up gradually, never ahead', () {
    final trim = RouteTrim(route, 0);
    for (var second = 1; second <= 8; second++) {
      fix(trim, up(1.4 * second), second, speed: 1.4);
    }
    // No fixes for a minute, in which the user went on to 80 m; they keep
    // walking. The gap is not taken on trust, so the line holds back...
    late List<LatLng> ahead;
    for (var second = 68; second <= 88; second++) {
      final at = 80 + 1.4 * (second - 68);
      ahead = fix(trim, up(at), second, speed: 1.4);
      expect(lengthOf(route) - lengthOf(ahead), lessThanOrEqualTo(at + 2));
    }
    // ...and has caught up with them within 20 s.
    expect(distance(ahead.first, up(80 + 1.4 * 20)), lessThan(1));
  });

  test('a position too far ahead is caught up with gradually, never passed',
      () {
    final trim = RouteTrim(route, 0);
    for (var second = 1; second <= 8; second++) {
      fix(trim, up(1.4 * second), second, speed: 1.4);
    }
    // 69 m on a second later is implausible, so the line stays put...
    var ahead = fix(trim, up(80), 9, speed: 1.4);
    expect(distance(ahead.first, up(11.2)), lessThan(1));
    // ...and as the user walks on from there, it catches up within 20 s.
    for (var second = 10; second <= 29; second++) {
      final at = 80 + 1.4 * (second - 9);
      ahead = fix(trim, up(at), second, speed: 1.4);
      expect(lengthOf(route) - lengthOf(ahead), lessThanOrEqualTo(at + 2));
    }
    expect(distance(ahead.first, up(80 + 1.4 * 20)), lessThan(1));
  });

  test('a later leg close by does not swallow the route still ahead', () {
    final trim = RouteTrim(hairpin, 0);
    // Walk about 44 m up the first leg.
    for (var second = 1; second <= 32; second++) {
      fix(trim, up(1.4 * second), second, speed: 1.4);
    }
    // 8 m sideways error: nearer the returning leg than the one walked.
    var ahead = fix(trim, const LatLng(16.720405, 121.690075), 33, speed: 1.4);
    expect(ahead, hasLength(4));
    for (var second = 34; second <= 37; second++) {
      ahead = fix(trim, up(1.4 * second), second, speed: 1.4);
      expect(ahead, hasLength(4));
      expect(distance(ahead.first, up(1.4 * second)), lessThan(1));
    }
  });

  test('wobble while standing still does not let a later leg swallow the route',
      () {
    final trim = RouteTrim(hairpin, 0);
    for (var second = 1; second <= 32; second++) {
      fix(trim, up(1.4 * second), second, speed: 1.4);
    }
    // Standing about 45 m up the first leg, fixes a few meters either way.
    for (var second = 33; second <= 62; second++) {
      fix(trim, up(second.isEven ? 48 : 42), second);
    }
    // 8 m sideways error: nearer the returning leg than the one walked.
    expect(fix(trim, const LatLng(16.720405, 121.690075), 63), hasLength(4));
  });

  test('a corrected fix while standing still does not open the way ahead', () {
    final trim = RouteTrim(hairpin, 0);
    for (var second = 1; second <= 32; second++) {
      fix(trim, up(1.4 * second), second, speed: 1.4);
    }
    // Standing about 45 m up the first leg. One fix 13 m ahead, then
    // corrected fixes back where the user stands.
    fix(trim, up(58), 33);
    for (var second = 34; second <= 42; second++) {
      fix(trim, up(44.8), second);
    }
    // 8 m sideways error: nearer the returning leg than the one walked.
    final ahead = fix(trim, const LatLng(16.720403, 121.690075), 43);
    expect(ahead, hasLength(4));
  });

  test('a fix after a gap in GPS does not let a later leg swallow the route',
      () {
    final trim = RouteTrim(hairpin, 0);
    // Walk about 45 m up the first leg, then stand there.
    for (var second = 1; second <= 32; second++) {
      fix(trim, up(1.4 * second), second, speed: 1.4);
    }
    for (var second = 33; second <= 35; second++) {
      fix(trim, up(44.8), second);
    }
    // No fixes for 20 s, then one moving 1.4 m on with 8 m sideways error.
    final ahead =
        fix(trim, const LatLng(16.720416, 121.690075), 55, speed: 1.4);
    expect(ahead, hasLength(4));
  });

  test('a line that starts late on a hairpin never erases route ahead', () {
    // The route arrives while the user is already on the returning leg,
    // beside about 45 m of the first leg, and they walk on to the end.
    final trim = RouteTrim(hairpin, odometer.metersAt(start));
    for (var second = 0; second <= 30; second++) {
      final position = LatLng(16.720405 - 0.0000126 * second, 121.6901032);
      final ahead = fix(trim, position, second, speed: 1.4);
      // Ambiguous, so the line shows too much: at least all that is left.
      expect(lengthOf(ahead),
          greaterThanOrEqualTo(distance(position, hairpin.last) - 2));
    }
  });

  test('a position that may not advance the line still draws it', () {
    final trim = travelledFar(route);
    fix(trim, const LatLng(16.7202, 121.69), 1);
    final ahead = fix(trim, const LatLng(16.721, 121.6905), 2, advance: false);
    expect(ahead, hasLength(3));
    expect(distance(ahead.first, const LatLng(16.7202, 121.69)), lessThan(1));
  });

  group('travel', () {
    test('standing still, or a speed GPS cannot give, is no travel', () {
      for (var second = 1; second <= 60; second++) {
        odometer.record(after(second), second.isEven ? 0 : double.nan);
      }
      expect(odometer.metersAt(after(60)), 0);
    });

    test('moving adds up, carried past the last fix only while predicted', () {
      for (var second = 1; second <= 10; second++) {
        odometer.record(after(second), 2);
      }
      expect(odometer.metersAt(after(10)), closeTo(18, 0.01));
      expect(odometer.metersAt(start.add(const Duration(milliseconds: 10500))),
          closeTo(19, 0.01));
      // Without fixes, it stops growing.
      expect(odometer.metersAt(after(60)), closeTo(21, 0.01));
    });

    test('a gap in fixes is not credited at the next fix\'s speed', () {
      odometer.record(after(1), 2);
      odometer.record(after(60), 2.5);
      // Only what the last speed carried past its fix.
      expect(odometer.metersAt(after(60)), closeTo(3, 0.01));
    });
  });
}
