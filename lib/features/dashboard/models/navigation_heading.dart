import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

double? navigationBearing(LatLng from, LatLng to) {
  if (from == to) return null;
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final delta = (to.longitude - from.longitude) * math.pi / 180;
  return (math.atan2(
                  math.sin(delta) * math.cos(lat2),
                  math.cos(lat1) * math.sin(lat2) -
                      math.sin(lat1) * math.cos(lat2) * math.cos(delta)) *
              180 /
              math.pi +
          360) %
      360;
}

double? routeHeading(List<LatLng> points, LatLng position) {
  if (points.length < 2) return null;
  const distance = Distance();
  var nearest = 0;
  for (var i = 1; i < points.length; i++) {
    if (distance(position, points[i]) < distance(position, points[nearest])) {
      nearest = i;
    }
  }
  for (var i = nearest + 1; i < points.length; i++) {
    final bearing = navigationBearing(points[nearest], points[i]);
    if (bearing != null) return bearing;
  }
  for (var i = nearest - 1; i >= 0; i--) {
    final bearing = navigationBearing(points[i], points[nearest]);
    if (bearing != null) return bearing;
  }
  return null;
}
