import unittest
from app.utils.routing import walking_routes, RoutingError
from app.utils.routing import meters


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.nodes = [dict(node_id=i, latitude=16.72 + i*.0001, longitude=121.69,
                           node_type='entrance', status='active', name='Gate' if i == 1 else str(i),
                           building_id=10 if i == 3 else None) for i in (1, 2, 3)]
        self.paths = [self.edge(1, 1, 3, 100, 'Unshaded'),
                      self.edge(2, 1, 2, 75, 'Fully Shaded'),
                      self.edge(3, 2, 3, 75, 'Fully Shaded')]
        self.modes = [dict(pathway_id=i, mode='Walking') for i in (1, 2, 3)]
        self.request = dict(mode='walking', destinationBuildingId='10',
                            origin=dict(type='mainGate'))

    def edge(self, i, a, b, length, shade):
        return dict(pathway_id=i, source_node_id=a, destination_node_id=b,
                    distance_m=length, shade=shade, status='active', direction='One-way')

    def solve(self, points=None):
        return walking_routes(self.nodes, self.paths, self.modes, points or [], self.request)['routes']

    def test_current_location_snaps_to_path_interior(self):
        self.paths = [self.paths[0]]
        self.request['origin'] = dict(type='currentLocation', latitude=16.7202, longitude=121.69)
        route = self.solve()[0]
        self.assertAlmostEqual(route['pathPoints'][0][0], 16.7202)
        self.assertAlmostEqual(route['distanceMeters'], meters((16.7202, 121.69), (16.7203, 121.69)))

    def test_current_location_respects_one_way_path(self):
        self.paths = [self.paths[0]]
        self.nodes[0]['building_id'] = 20
        self.request.update(destinationBuildingId='20', origin=dict(type='currentLocation', latitude=16.7202, longitude=121.69))
        with self.assertRaises(RoutingError):
            self.solve()
        self.paths[0]['direction'] = 'Two-way'
        route = self.solve()[0]
        self.assertEqual(route['endNodeId'], '1')
        self.assertAlmostEqual(route['distanceMeters'], meters((16.7202, 121.69), (16.7201, 121.69)))

    def test_shortest_and_shaded_use_different_weights(self):
        shortest, shaded = self.solve()
        self.assertEqual(shortest['pathwayIds'], ['1'])
        self.assertEqual(shaded['pathwayIds'], ['2', '3'])
        expected = meters((16.7201, 121.69), (16.7202, 121.69)) * 2
        self.assertAlmostEqual(shaded['distanceMeters'], expected)
        self.assertAlmostEqual(shaded['weightedCost'], expected)
        self.assertAlmostEqual(shaded['estimatedMinutes'], expected / 80)

    def test_disallowed_and_inactive_paths_are_excluded(self):
        self.modes = [dict(pathway_id=1, mode='Vehicle')]
        with self.assertRaises(RoutingError): self.solve()
        self.modes = [dict(pathway_id=1, mode='Walking')]
        self.paths[0]['status'] = 'inactive'
        with self.assertRaises(RoutingError): self.solve()

    def test_one_way_and_reversed_geometry(self):
        self.nodes[0]['building_id'] = 20
        self.request.update(destinationBuildingId='20', origin=dict(type='campusLocation', buildingId='10'))
        with self.assertRaises(RoutingError): self.solve()
        self.paths[0]['direction'] = 'Two-way'
        route = self.solve()[0]
        self.assertEqual(route['startNodeId'], '3')
        self.assertEqual(route['endNodeId'], '1')
        self.assertGreater(route['pathPoints'][0][0], route['pathPoints'][-1][0])

    def test_direction_labels_from_pathway_table(self):
        self.nodes[0]['building_id'] = 20
        self.request.update(destinationBuildingId='20', origin=dict(type='campusLocation', buildingId='10'))
        self.paths = [self.paths[0]]
        for direction in ('One-way', 'One Way', 'one_way'):
            with self.subTest(direction=direction):
                self.paths[0]['direction'] = direction
                with self.assertRaises(RoutingError):
                    self.solve()
        for direction in ('Two-way', 'Two Way', 'two_way', ' TWO-WAY '):
            with self.subTest(direction=direction):
                self.paths[0]['direction'] = direction
                route = self.solve()[0]
                self.assertEqual(route['pathwayIds'], ['1'])
                self.assertEqual((route['startNodeId'], route['endNodeId']), ('3', '1'))
                self.assertEqual(len(route['pathPoints']), 2)
                self.assertAlmostEqual(route['pathPoints'][0][0], 16.7203)
                self.assertAlmostEqual(route['pathPoints'][-1][0], 16.7201)

    def test_database_metrics_are_ignored_and_ordered_geometry_is_used(self):
        self.paths = [self.paths[0]]
        self.paths[0]['distance_m'] = 9999
        self.paths[0]['estimated_minutes'] = 999
        points = [dict(pathway_id=1, sequence_no=i, latitude=16.7201+i*.00005,
                       longitude=121.6901, status='active') for i in (2, 1)]
        route = self.solve(points)[0]
        expected = sum(meters(a, b) for a, b in zip(route['pathPoints'], route['pathPoints'][1:]))
        self.assertAlmostEqual(route['distanceMeters'], expected)
        self.assertAlmostEqual(route['estimatedMinutes'], expected / 80)
        self.assertEqual(route['pathPoints'][1][0], 16.72015)

    def test_missing_entrance_and_far_origin(self):
        self.request['destinationBuildingId'] = 'missing'
        with self.assertRaises(RoutingError): self.solve()
        self.request.update(destinationBuildingId='10', origin=dict(type='currentLocation', latitude=0, longitude=0))
        with self.assertRaises(RoutingError): self.solve()

    def test_unknown_shade_gets_full_penalty(self):
        self.paths = [self.paths[0]]
        self.paths[0]['shade'] = None
        route = self.solve()[1]
        self.assertAlmostEqual(route['weightedCost'], route['distanceMeters'] * 2)

    def test_unsupported_mode_is_rejected(self):
        self.request['mode'] = 'train'
        with self.assertRaises(RoutingError): self.solve()

    def test_vehicle_modes_use_vehicle_paths_and_mode_specific_eta(self):
        self.paths = [self.paths[0]]
        self.modes = [dict(pathway_id=1, mode='Vehicle')]
        for mode, speed in [('car', 350), ('motorcycle', 450), ('bicycle', 220)]:
            with self.subTest(mode=mode):
                self.request['mode'] = mode
                shortest, shaded = self.solve()
                self.assertEqual(shortest['mode'], mode)
                self.assertEqual(shortest['pathwayIds'], ['1'])
                self.assertAlmostEqual(shortest['estimatedMinutes'], shortest['distanceMeters'] / speed)
                self.assertEqual(shaded['mode'], mode)
                self.request['origin'] = dict(type='currentLocation', latitude=16.7202, longitude=121.69)
                partial = self.solve()[0]
                self.assertAlmostEqual(partial['estimatedMinutes'], partial['distanceMeters'] / speed)
                self.request['origin'] = dict(type='mainGate')
        self.request['mode'] = 'walking'
        with self.assertRaises(RoutingError): self.solve()

    def test_vehicle_modes_cannot_use_walking_only_paths(self):
        for mode in ('car', 'motorcycle', 'bicycle'):
            self.request['mode'] = mode
            with self.subTest(mode=mode), self.assertRaises(RoutingError): self.solve()

    def test_specific_mode_permissions_are_not_shared(self):
        self.paths = [self.paths[0]]
        self.modes = [dict(pathway_id=1, mode='Bicycle')]
        self.request['mode'] = 'bicycle'
        self.assertEqual(self.solve()[0]['pathwayIds'], ['1'])
        for mode in ('car', 'motorcycle', 'walking'):
            self.request['mode'] = mode
            with self.subTest(mode=mode), self.assertRaises(RoutingError): self.solve()

    def test_vehicle_modes_respect_one_way(self):
        self.paths = [self.paths[0]]
        self.modes = [dict(pathway_id=1, mode='Vehicle')]
        self.nodes[0]['building_id'] = 20
        for mode in ('car', 'motorcycle', 'bicycle'):
            self.request.update(mode=mode, destinationBuildingId='20',
                origin=dict(type='currentLocation', latitude=16.7202, longitude=121.69))
            self.paths[0]['direction'] = 'One-way'
            with self.subTest(mode=mode), self.assertRaises(RoutingError): self.solve()
            self.paths[0]['direction'] = 'Two-way'
            self.assertEqual(self.solve()[0]['endNodeId'], '1')


if __name__ == '__main__': unittest.main()
