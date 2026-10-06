import 'package:latlong2/latlong.dart';

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
  final seconds = (elapsed > maxPrediction ? maxPrediction : elapsed)
          .inMicroseconds /
      Duration.microsecondsPerSecond;
  return const Distance().offset(fix, speed * seconds, course);
}
