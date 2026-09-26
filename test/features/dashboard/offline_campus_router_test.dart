import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/services/offline_campus_router.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('offline routing handles a pathway with no intermediate shape points', () {
    final graph = <String, dynamic>{
      'nodes': [
        {
          'node_id': 'gate',
          'name': 'Main Gate',
          'status': 'active',
          'node_type': 'gate',
          'latitude': 16.7200,
          'longitude': 121.6900,
        },
        {
          'node_id': 'library-entrance',
          'building_id': 'library',
          'status': 'active',
          'node_type': 'entrance',
          'latitude': 16.7202,
          'longitude': 121.6902,
        },
      ],
      'pathways': [
        {
          'pathway_id': 'walk-1',
          'source_node_id': 'gate',
          'destination_node_id': 'library-entrance',
          'status': 'active',
          'direction': 'one way',
          'shade': 'partial shade',
          'name': 'Main walk',
        },
      ],
      'modes': [
        {'pathway_id': 'walk-1', 'mode': 'walking'},
      ],
      'points': [],
    };
    const destination = CampusBuilding(
      id: 'library',
      name: 'Library',
      acronym: 'LIB',
      category: 'Facility',
      description: '',
      coordinate: LatLng(16.7202, 121.6902),
    );
    const origin = NavigationOrigin(
      id: 'main_gate',
      label: 'ISU Main Gate',
      coordinate: LatLng(16.7200, 121.6900),
      type: NavigationOriginType.mainGate,
    );

    final routes = OfflineCampusRouter.routes(
      graph: graph,
      origin: origin,
      destination: destination,
    );

    expect(routes, hasLength(2));
    expect(routes.first.points, hasLength(2));
    expect(routes.first.steps.single.instruction, 'Follow Main walk');
    expect(routes.first.distanceMeters, greaterThan(0));
    expect(OfflineCampusRouter.mapPathways(graph).single, hasLength(2));
  });
}
