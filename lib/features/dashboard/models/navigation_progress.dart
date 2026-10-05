import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'campus_models.dart';
import 'navigation_heading.dart';

/// Projects GPS onto route segments, rather than jumping between map vertices.
class RouteProjection {
  final double alongMeters;
  final double awayMeters;
  final double totalMeters;
  const RouteProjection(this.alongMeters, this.awayMeters, this.totalMeters);

  static RouteProjection locate(List<LatLng> points, LatLng position) {
    if (points.isEmpty) return const RouteProjection(0, double.infinity, 0);
    const distance = Distance();
    var total = 0.0;
    var along = 0.0;
    var away = distance(position, points.first);
    final scale = math.cos(position.latitude * math.pi / 180);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final dx = (b.longitude - a.longitude) * scale;
      final dy = b.latitude - a.latitude;
      final px = (position.longitude - a.longitude) * scale;
      final py = position.latitude - a.latitude;
      final square = dx * dx + dy * dy;
      final t =
          square == 0 ? 0.0 : ((px * dx + py * dy) / square).clamp(0.0, 1.0);
      final projected = LatLng(
          a.latitude + dy * t, a.longitude + (b.longitude - a.longitude) * t);
      final separation = distance(position, projected);
      final length = distance(a, b);
      if (separation < away) {
        away = separation;
        along = total + length * t;
      }
      total += length;
    }
    return RouteProjection(along, away, total);
  }
}

class NavigationProgress {
  final double remainingMeters;
  final double remainingMinutes;
  final double fraction;
  final double offRouteMeters;
  final String instruction;
  final double instructionMeters;
  final bool arrived;

  const NavigationProgress(
      {required this.remainingMeters,
      required this.remainingMinutes,
      required this.fraction,
      required this.offRouteMeters,
      required this.instruction,
      required this.instructionMeters,
      required this.arrived});

  factory NavigationProgress.calculate(WalkingRoute route, LatLng position,
      {double accuracy = 10}) {
    final projection = RouteProjection.locate(route.points, position);
    final remaining =
        math.max(0.0, projection.totalMeters - projection.alongMeters);
    final accurate = accuracy.isFinite && accuracy >= 0 && accuracy <= 25;
    final arrived = accurate &&
        route.points.isNotEmpty &&
        const Distance()(position, route.points.last) <= 15 &&
        remaining <= 20;
    final offRoute = projection.awayMeters > 30;
    var instruction = 'Continue to the building entrance';
    var instructionDistance = remaining;
    if (route.points.isNotEmpty &&
        projection.awayMeters > 15 &&
        projection.alongMeters < 5) {
      instruction = 'Join the highlighted path at ${route.startNodeName}';
      instructionDistance = const Distance()(position, route.points.first);
    } else {
      for (var i = 0; i < route.steps.length; i++) {
        final step = route.steps[i];
        final next = i + 1 < route.steps.length ? route.steps[i + 1] : null;
        final end = next?.coordinate == null
            ? projection.totalMeters
            : RouteProjection.locate(route.points, next!.coordinate!)
                .alongMeters;
        if (projection.alongMeters < end - 3 || i == route.steps.length - 1) {
          instruction = step.instruction;
          instructionDistance = math.max(0.0, end - projection.alongMeters);
          if (next != null &&
              instructionDistance <= 25 &&
              next.coordinate != null &&
              step.coordinate != null) {
            final following = i + 2 < route.steps.length
                ? route.steps[i + 2].coordinate
                : route.points.last;
            final incoming =
                navigationBearing(step.coordinate!, next.coordinate!);
            final outgoing = following == null
                ? null
                : navigationBearing(next.coordinate!, following);
            if (incoming != null && outgoing != null) {
              final turn = (outgoing - incoming + 540) % 360 - 180;
              instruction =
                  '${turn.abs() < 30 ? 'Continue straight' : turn.abs() > 150 ? 'Turn around' : turn > 0 ? 'Turn right' : 'Turn left'}. ${next.instruction}';
            }
          }
          break;
        }
      }
    }
    final minutesPerMeter =
        projection.totalMeters > 0 && route.estimatedMinutes > 0
            ? route.estimatedMinutes / projection.totalMeters
            : 1 /
                (route.mode == TransportMode.car
                    ? 350
                    : route.mode == TransportMode.motorcycle
                        ? 450
                        : route.mode == TransportMode.bicycle
                            ? 220
                            : 80);
    return NavigationProgress(
      remainingMeters: arrived ? 0 : remaining + projection.awayMeters,
      remainingMinutes:
          arrived ? 0 : (remaining + projection.awayMeters) * minutesPerMeter,
      fraction: arrived
          ? 1
          : projection.totalMeters == 0
              ? 0
              : (projection.alongMeters / projection.totalMeters)
                  .clamp(0.0, 1.0),
      offRouteMeters: projection.awayMeters,
      instruction: offRoute ? 'You are away from the mapped path' : instruction,
      instructionMeters: instructionDistance,
      arrived: arrived,
    );
  }
}
