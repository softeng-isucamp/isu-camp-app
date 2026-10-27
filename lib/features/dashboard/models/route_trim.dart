import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'navigation_camera.dart';
import 'navigation_progress.dart';

/// Farther than this from the route, a position no longer counts as progress
/// along it. Matches the off-route distance used for guidance.
const double routeTrimMaxOffsetMeters = 30;

/// Progress may land this far from the progress so far without the user
/// moving: about the GPS error navigation still accepts.
const double routeTrimAllowanceMeters = 25;

/// Distance travelled by GPS speed may undercount the distance along the
/// route, so the stretch ahead grows half as much again.
const double routeTrimTravelMargin = 1.5;

/// GPS wobble of someone standing still lands within this distance either way
/// of the progress so far. A match farther behind is not taken as the user:
/// it is more likely an earlier leg alongside while the user is ahead.
const double routeTrimWobbleMeters = 10;

/// The part of a route still ahead of the user during navigation.
///
/// When GPS is ambiguous, the line shows too much rather than erasing route
/// the user hasn't walked.
///
/// Progress only moves forward, so GPS wobble never brings walked route back.
/// It is only looked for in the stretch the user could have reached by
/// moving, so a nearby later leg (a hairpin) can't swallow the route between.
/// Travel is a [TravelOdometer] reading, so standing still opens nothing.
/// A new route (after a reroute) needs a new [RouteTrim].
class RouteTrim {
  /// The user was at the start of the route when the odometer read
  /// [startTravelled], such as when it was requested from their position.
  RouteTrim(this.points, double startTravelled)
      : _placedTravelled = startTravelled;

  final List<LatLng> points;
  double _walkedMeters = 0;
  double _placedTravelled;

  /// The route from [position], snapped onto it, to the destination, with the
  /// odometer at [travelled]. Without [advance] (for an untrusted fix), the
  /// line is drawn but doesn't move.
  List<LatLng> ahead(LatLng position,
      {required double travelled, bool advance = true}) {
    if (points.isEmpty) return const [];
    if (advance) _advance(position, travelled);
    if (_walkedMeters <= 0) return points;
    const distance = Distance();
    var covered = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final length = distance(a, b);
      if (covered + length > _walkedMeters) {
        final t = length == 0 ? 0.0 : (_walkedMeters - covered) / length;
        return [
          LatLng(a.latitude + (b.latitude - a.latitude) * t,
              a.longitude + (b.longitude - a.longitude) * t),
          ...points.sublist(i),
        ];
      }
      covered += length;
    }
    return [points.last];
  }

  void _advance(LatLng position, double travelled) {
    final moved = math.max(0.0, travelled - _placedTravelled);
    final projection = RouteProjection.locate(points, position,
        fromMeters: _walkedMeters - routeTrimAllowanceMeters,
        toMeters: _walkedMeters +
            routeTrimAllowanceMeters +
            routeTrimTravelMargin * moved);
    if (projection.awayMeters > routeTrimMaxOffsetMeters ||
        projection.alongMeters < _walkedMeters - routeTrimWobbleMeters) {
      return;
    }
    // On the route near the progress so far, even if not ahead of it, so the
    // stretch ahead is measured from here. Matches well behind it don't count,
    // so they can't hold the line back while the user is ahead.
    _placedTravelled = travelled;
    _walkedMeters = math.max(_walkedMeters, projection.alongMeters);
  }
}

/// How far the user has moved, by GPS speed alone: time passing while
/// standing still, or without fixes, is not movement. It undercounts rather
/// than overcounts, so the route line errs towards showing too much.
class TravelOdometer {
  double _meters = 0;
  DateTime? _at;
  double _speed = 0;

  /// Meters moved by [at]. The last speed carries on only as long as the
  /// position is predicted from it.
  double metersAt(DateTime at) {
    final since = _at;
    if (since == null) return _meters;
    final elapsed = at.difference(since);
    final carried = elapsed < Duration.zero
        ? Duration.zero
        : elapsed > maxPrediction
            ? maxPrediction
            : elapsed;
    return _meters + _speed * carried.inMilliseconds / 1000;
  }

  /// A fix moving at [speed] m/s at [at]; 0 for a fix not to be trusted. The
  /// time since the last fix counts only as [metersAt] carried it, so a gap
  /// in fixes isn't credited at the speed the next fix reports.
  void record(DateTime at, double speed) {
    final since = _at;
    if (since == null || at.isAfter(since)) {
      _meters = metersAt(at);
      _at = at;
    }
    _speed = speed.isFinite && speed > 0 ? speed : 0.0;
  }
}
