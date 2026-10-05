import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/models/navigation_progress.dart';

WalkingRoute route() => WalkingRoute.fromJson({
      'type': 'shortest',
      'distanceMeters': 220,
      'estimatedMinutes': 3,
      'startNodeName': 'Gate',
      'pathPoints': [
        [16.72, 121.69],
        [16.721, 121.69],
        [16.721, 121.691]
      ],
      'steps': [
        {
          'instruction': 'Follow North Path',
          'distanceMeters': 111,
          'coordinate': [16.72, 121.69]
        },
        {
          'instruction': 'Follow East Path',
          'distanceMeters': 106,
          'coordinate': [16.721, 121.69]
        },
      ],
    });

void main() {
  test('progress projects onto segment interiors and updates ETA', () {
    final start =
        NavigationProgress.calculate(route(), const LatLng(16.72, 121.69));
    final halfway =
        NavigationProgress.calculate(route(), const LatLng(16.7205, 121.69));
    expect(start.fraction, closeTo(0, .01));
    expect(halfway.fraction, inInclusiveRange(.24, .27));
    expect(halfway.remainingMeters, lessThan(start.remainingMeters));
    expect(halfway.remainingMinutes, lessThan(start.remainingMinutes));
    expect(halfway.offRouteMeters, lessThan(1));
    expect(halfway.arrived, isFalse);
  });
  test('approaching a junction announces turn and advances to next path', () {
    final turn =
        NavigationProgress.calculate(route(), const LatLng(16.7209, 121.69));
    expect(turn.instruction, contains('Turn right'));
    final after =
        NavigationProgress.calculate(route(), const LatLng(16.721, 121.6905));
    expect(after.instruction, 'Follow East Path');
  });
  test('arrival requires proximity to endpoint and accurate GPS', () {
    final end =
        NavigationProgress.calculate(route(), const LatLng(16.721, 121.691));
    expect(end.arrived, isTrue);
    expect(end.remainingMeters, 0);
    expect(end.fraction, 1);
    expect(
        NavigationProgress.calculate(route(), const LatLng(16.721, 121.691),
                accuracy: 60)
            .arrived,
        isFalse);
    expect(
        NavigationProgress.calculate(route(), const LatLng(16.721, 121.6905))
            .arrived,
        isFalse);
  });
  test('off-route GPS and starting connector are measured', () {
    final away =
        NavigationProgress.calculate(route(), const LatLng(16.7195, 121.69));
    expect(away.offRouteMeters, greaterThan(30));
    expect(away.arrived, isFalse);
    final connector =
        NavigationProgress.calculate(route(), const LatLng(16.7198, 121.69));
    expect(connector.instruction, contains('Join the highlighted path'));
  });
  test('empty and zero-length geometry are safe', () {
    final empty = RouteProjection.locate([], const LatLng(16.72, 121.69));
    expect(empty.awayMeters, double.infinity);
    final duplicate = RouteProjection.locate(
        [const LatLng(16.72, 121.69), const LatLng(16.72, 121.69)],
        const LatLng(16.72, 121.69));
    expect(duplicate.totalMeters, 0);
    expect(duplicate.alongMeters, 0);
  });
}
