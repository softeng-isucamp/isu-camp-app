import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'navigation_heading.dart';
import 'navigation_progress.dart';

/// Above this speed (m/s, about 11 km/h) the GPS course is steadier than the
/// compass, which is disturbed inside vehicles.
const double courseHeadingSpeed = 3;

/// Positions are extrapolated at most this far past the last GPS fix.
const Duration maxPrediction = Duration(milliseconds: 1500);

/// flutter_map turns layers clockwise by the camera rotation, so a heading-up
/// view turns the map the opposite way.
double cameraRotationForHeading(double heading) => (360 - heading % 360) % 360;

/// The direction the map should face during navigation.
double? navigationFacing({
  double? compassHeading,
  double? gpsCourse,
  double speed = 0,
}) {
  if (gpsCourse != null && speed.isFinite && speed >= courseHeadingSpeed) {
    return gpsCourse;
  }
  return compassHeading ?? gpsCourse;
}

/// Where the user probably is [elapsed] after a fix at [fix], moving at
/// [speed] m/s along [course] degrees.
LatLng predictPosition(
  LatLng fix, {
  required double speed,
  required double? course,
  required Duration elapsed,
}) {
  if (course == null ||
      !course.isFinite ||
      !speed.isFinite ||
      speed < 0.5 ||
      elapsed <= Duration.zero) {
    return fix;
  }
  final seconds =
      (elapsed > maxPrediction ? maxPrediction : elapsed).inMicroseconds /
          Duration.microsecondsPerSecond;
  return const Distance().offset(fix, speed * seconds, course);
}

/// How far ahead on the route the navigation camera looks. Far enough that
/// GPS wobble and tiny route vertices don't twitch the map, near enough that
/// the map turns as the user rounds a corner.
const double routeLookAheadMeters = 25;

/// Beyond this distance from the route, the camera follows the walking
/// direction instead of the route.
const double offRouteCameraMeters = 25;

/// The point [meters] along [points], clamped to the route's ends.
LatLng pointAlongRoute(List<LatLng> points, double meters) {
  const distance = Distance();
  var remaining = meters;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final length = distance(a, b);
    if (length > 0 && remaining <= length) {
      final t = (remaining / length).clamp(0.0, 1.0);
      return LatLng(a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t);
    }
    remaining -= length;
  }
  return points.last;
}

/// The direction of the route a short way ahead of [position].
double? routeLookAheadBearing(List<LatLng> points, LatLng position,
    {double lookAhead = routeLookAheadMeters}) {
  if (points.length < 2) return null;
  final projection = RouteProjection.locate(points, position);
  // Near the destination, keep facing along the route's final stretch.
  final start = math.max(0.0,
      math.min(projection.alongMeters, projection.totalMeters - lookAhead));
  return navigationBearing(pointAlongRoute(points, start),
      pointAlongRoute(points, start + lookAhead));
}

/// The direction the map should face during navigation: the route ahead,
/// or the walking direction while the user is off the route.
double? navigationCameraHeading(List<LatLng> points, LatLng position,
    {double? gpsCourse}) {
  if (gpsCourse != null &&
      RouteProjection.locate(points, position).awayMeters >
          offRouteCameraMeters) {
    return gpsCourse;
  }
  return routeLookAheadBearing(points, position) ?? gpsCourse;
}
