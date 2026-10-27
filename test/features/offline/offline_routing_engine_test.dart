import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/offline/services/offline_routing_engine.dart';

/// The expected values come from running `app.utils.routing.campus_routes` on
/// this same fixture, so a drift between the backend router and this port
/// fails here rather than on a student's phone.
void main() {
  final graph = {
    'nodes': [
      {
        'node_id': 1,
        'building_id': null,
        'latitude': 16.7200,
        'longitude': 121.6900,
        'node_type': 'junction',
        'status': 'Active',
        'name': 'Main Gate',
      },
      {
        'node_id': 2,
        'building_id': null,
        'latitude': 16.7210,
        'longitude': 121.6900,
        'node_type': 'junction',
        'status': 'active',
        'name': 'Quad junction',
      },
      {
        'node_id': 3,
        'building_id': 5,
        'latitude': 16.7220,
        'longitude': 121.6900,
        'node_type': 'Entrance',
        'status': 'active',
        'name': 'CCSICT entrance',
      },
      {
        'node_id': 4,
        'building_id': 9,
        'latitude': 16.7230,
        'longitude': 121.6900,
        'node_type': 'entrance',
        'status': 'inactive',
        'name': 'Closed entrance',
      },
    ],
    'pathways': [
      {
        'pathway_id': 10,
        'source_node_id': 1,
        'destination_node_id': 2,
        'status': 'active',
        'direction': 'Two Way',
        'shade': 'unshaded',
        'name': 'Front walkway',
      },
      {
        'pathway_id': 11,
        'source_node_id': 2,
        'destination_node_id': 3,
        'status': 'active',
        'direction': 'two-way',
        'shade': 'unshaded',
        'name': 'Quad walkway',
      },
      {
        'pathway_id': 12,
        'source_node_id': 1,
        'destination_node_id': 3,
        'status': 'active',
        'direction': 'twoway',
        'shade': 'fully shaded',
        'name': 'Acacia lane',
      },
    ],
    'modes': [
      {'pathway_id': 10, 'mode': 'Walking'},
      {'pathway_id': 11, 'mode': 'walk'},
      {'pathway_id': 12, 'mode': 'Pedestrian'},
      {'pathway_id': 10, 'mode': 'Vehicle'},
    ],
    'points': [
      {
        'point_id': 1,
        'pathway_id': 12,
        'sequence_no': 1,
        'latitude': 16.7210,
        'longitude': 121.6908,
        'status': 'active',
      },
    ],
  };

  Map<String, dynamic> routesFor(Map<String, dynamic> request) =>
      OfflineRoutingEngine(graph).routes(request);

  Map<String, dynamic> fromMainGate({String mode = 'walking'}) =>
      routesFor({
        'mode': mode,
        'destinationBuildingId': '5',
        'origin': {
          'type': 'mainGate',
          'latitude': 16.72,
          'longitude': 121.69,
        },
      });

  test('shortest and shaded routes match the backend router', () {
    final routes = fromMainGate()['routes'] as List;
    final shortest = routes[0] as Map<String, dynamic>;
    final shaded = routes[1] as Map<String, dynamic>;

    expect(shortest['type'], 'shortest');
    expect(shortest['pathwayIds'], ['10', '11']);
    expect(shortest['distanceMeters'], closeTo(222.3898532892451, 1e-6));
    expect(shortest['estimatedMinutes'], closeTo(2.779873166115564, 1e-9));
    expect(shortest['startNodeName'], 'Main Gate');
    expect(shortest['endNodeId'], '3');
    expect(shortest['pathPoints'], [
      [16.72, 121.69],
      [16.721, 121.69],
      [16.722, 121.69],
    ]);
    expect(shortest['steps'], [
      {
        'instruction': 'Follow Front walkway',
        'distanceMeters': closeTo(111.19492664462256, 1e-6),
        'coordinate': [16.72, 121.69],
      },
      {
        'instruction': 'Follow Quad walkway',
        'distanceMeters': closeTo(111.19492664462256, 1e-6),
        'coordinate': [16.721, 121.69],
      },
    ]);

    // The shaded preference takes the longer fully shaded lane on purpose.
    expect(shaded['type'], 'comfortableShaded');
    expect(shaded['pathwayIds'], ['12']);
    expect(shaded['distanceMeters'], closeTo(280.1602123535505, 1e-6));
    expect(shaded['weightedCost'], closeTo(280.1602123535505, 1e-6));
  });

  test('current location snaps onto the nearest permitted pathway', () {
    final routes = routesFor({
      'mode': 'walking',
      'destinationBuildingId': '5',
      'origin': {
        'type': 'currentLocation',
        'latitude': 16.72105,
        'longitude': 121.69005,
      },
    })['routes'] as List;
    final shortest = routes.first as Map<String, dynamic>;

    expect(shortest['startNodeId'], '__current_location__');
    expect(shortest['startNodeName'], 'Quad walkway');
    expect(shortest['pathwayIds'], ['11']);
    expect(shortest['distanceMeters'], closeTo(105.63518031233838, 1e-6));
    expect(shortest['pathPoints'], [
      [16.72105, 121.69],
      [16.722, 121.69],
    ]);
    // Shading only changes the weighting, never the reported distance.
    expect((routes[1] as Map<String, dynamic>)['weightedCost'],
        closeTo(211.27036062467675, 1e-6));
  });

  test('a mode with no permitted pathway is reported, not guessed', () {
    expect(
      () => fromMainGate(mode: 'bicycle'),
      throwsA(isA<OfflineRoutingException>().having((error) => error.message,
          'message', contains('No connected bicycle route'))),
    );
  });

  test('Vehicle pathways serve every wheeled mode but never walking', () {
    expect(pathwayAllowsMode('Vehicle', 'car'), isTrue);
    expect(pathwayAllowsMode('Vehicle', 'motorcycle'), isTrue);
    expect(pathwayAllowsMode('Vehicle', 'bicycle'), isTrue);
    expect(pathwayAllowsMode('Vehicle', 'walking'), isFalse);
    expect(pathwayAllowsMode('Motorbike', 'motorcycle'), isTrue);
    expect(pathwayAllowsMode('Motorbike', 'car'), isFalse);
    expect(pathwayAllowsMode(null, 'walking'), isFalse);
  });

  test('inactive entrances are not treated as destinations', () {
    expect(
      () => routesFor({
        'mode': 'walking',
        'destinationBuildingId': '9',
        'origin': {
          'type': 'mainGate',
          'latitude': 16.72,
          'longitude': 121.69,
        },
      }),
      throwsA(isA<OfflineRoutingException>().having((error) => error.message,
          'message', contains('no active entrance'))),
    );
  });

  test('an unsupported transport mode is rejected before routing', () {
    expect(() => fromMainGate(mode: 'helicopter'),
        throwsA(isA<OfflineRoutingException>()));
  });
}
