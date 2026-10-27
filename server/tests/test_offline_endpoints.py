import unittest
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import campus

PNG = b'\x89PNG\r\n\x1a\n'


class FakeDatabase:
    """Minimal PostgREST stand-in covering the map and routing tables."""

    def __init__(self):
        self.rows = {
            'building': [
                {'building_id': 1, 'building_name': 'Admin Building',
                 'building_code': 'ADM', 'classification': 'Administrative',
                 'description': 'Registrar', 'latitude': 16.7220,
                 'longitude': 121.6900, 'polygon_coordinates': []},
            ],
            'location': [
                {'location_id': 7, 'building_id': 1, 'floor_id': None, 'type_id': 1,
                 'location_name': 'Registrar', 'location_code': 'R1',
                 'description': 'Records'},
            ],
            'floor': [],
            'location_type': [{'type_id': 1, 'type_name': 'Office'}],
            'building_photo': [{'photo_id': 4, 'building_id': 1, 'position': 0,
                                'is_cover': True, 'content': PNG,
                                'mime_type': 'image/png'}],
            'location_photo': [{'photo_id': 9, 'location_id': 7, 'position': 0,
                                'is_cover': True, 'content': PNG,
                                'mime_type': 'image/png'}],
            'route_node': [
                {'node_id': 1, 'building_id': None, 'latitude': 16.7200,
                 'longitude': 121.6900, 'node_type': 'junction', 'status': 'active',
                 'name': 'Main Gate'},
                {'node_id': 2, 'building_id': 1, 'latitude': 16.7220,
                 'longitude': 121.6900, 'node_type': 'entrance', 'status': 'active',
                 'name': 'Admin entrance'},
            ],
            'pathway': [
                {'pathway_id': 10, 'source_node_id': 1, 'destination_node_id': 2,
                 'status': 'active', 'direction': 'twoway', 'shade': 'mostly shaded',
                 'name': 'Front walkway'},
            ],
            'pathway_allowed_mode': [{'pathway_id': 10, 'mode': 'Walking'}],
            'path_point': [],
        }

    def table(self, name):
        return FakeQuery(self, name)


class FakeQuery:
    def __init__(self, database, table):
        self.database, self.table = database, table
        self.columns, self.order_key, self.filters = '', None, []
        self.bounds, self.row_limit = None, None

    def select(self, columns):
        self.columns = columns
        return self

    def order(self, key):
        self.order_key = key
        return self

    def range(self, start, end):
        self.bounds = (start, end)
        return self

    def eq(self, key, value):
        self.filters.append((key, value))
        return self

    def limit(self, count):
        self.row_limit = count
        return self

    def execute(self):
        rows = [row for row in self.database.rows[self.table]
                if all(row.get(key) == value for key, value in self.filters)]
        if self.order_key:
            rows = sorted(rows, key=lambda row: row[self.order_key.split(',')[0]])
        if self.bounds:
            rows = rows[self.bounds[0]:self.bounds[1] + 1]
        if self.row_limit is not None:
            rows = rows[:self.row_limit]
        columns = self.columns.split(',')
        return SimpleNamespace(data=[{key: row.get(key) for key in columns}
                                     for row in rows])


class OfflineEndpointTests(unittest.TestCase):
    def setUp(self):
        self.database = FakeDatabase()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        from app.services.offline_pack import OfflinePackStore
        pack_patch = patch.object(campus, 'offline_pack_store', return_value=OfflinePackStore(directory.name))
        pack_patch.start()
        self.addCleanup(pack_patch.stop)
        database_patch = patch.object(campus, 'supabase', self.database)
        database_patch.start()
        self.addCleanup(database_patch.stop)
        app = FastAPI()
        app.include_router(campus.router)
        self.client = TestClient(app, base_url='https://api.example.test')

    def test_bundle_carries_the_map_and_the_whole_routing_graph(self):
        response = self.client.get('/campus/offline/bundle')
        self.assertEqual(response.status_code, 200)
        bundle = response.json()

        self.assertEqual(len(bundle['version']), 32)
        self.assertIn('generatedAt', bundle)
        self.assertEqual(bundle['skippedCount'], 0)

        building = bundle['buildings'][0]
        self.assertEqual(building['name'], 'Admin Building')
        self.assertEqual(building['imageUrl'],
                         'https://api.example.test/campus/photos/building/4')
        self.assertEqual(building['rooms'][0]['imageUrl'],
                         'https://api.example.test/campus/photos/location/9')

        # The app routes from these rows itself, so all four tables must ship.
        self.assertEqual({'nodes', 'pathways', 'modes', 'points'},
                         set(bundle['graph']))
        self.assertEqual(len(bundle['graph']['nodes']), 2)
        self.assertEqual(bundle['graph']['pathways'][0]['name'], 'Front walkway')
        self.assertEqual(bundle['graph']['modes'][0]['mode'], 'Walking')

        # Image bytes are served by the photo routes, never embedded here.
        self.assertNotIn('base64', response.text)
        self.assertNotIn('data:image', response.text)

    def test_bundle_matches_the_live_buildings_response(self):
        bundle = self.client.get('/campus/offline/bundle').json()
        live = self.client.get('/campus/buildings').json()
        self.assertEqual(bundle['buildings'], live['buildings'])
        self.assertEqual(bundle['skippedCount'], live['skippedCount'])

    def test_repeated_requests_report_the_same_version(self):
        first = self.client.get('/campus/offline/bundle').json()['version']
        second = self.client.get('/campus/offline/bundle').json()['version']
        self.assertEqual(first, second)

    def test_edited_campus_data_publishes_a_new_version(self):
        before = self.client.get('/campus/offline/bundle').json()['version']
        self.database.rows['building'][0]['building_name'] = 'Administration Hall'
        after = self.client.get('/campus/offline/bundle').json()['version']
        self.assertNotEqual(before, after)

    def test_manifest_requires_a_previously_published_pack(self):
        # No database query or per-file size discovery in the request path.
        with patch.object(campus, 'offline_bundle_payload', side_effect=AssertionError('must not build here')):
            response = self.client.get('/campus/offline/manifest')
        self.assertEqual(response.status_code, 503)
        self.assertIn('being prepared', response.json()['detail'])

    def test_an_unchanged_bundle_revalidates_instead_of_downloading_again(self):
        first = self.client.get('/campus/offline/bundle')
        etag = first.headers['etag']
        self.assertEqual(etag, '"' + first.json()['version'] + '"')

        repeat = self.client.get('/campus/offline/bundle',
                                 headers={'If-None-Match': etag})
        self.assertEqual(repeat.status_code, 304)
        self.assertEqual(repeat.content, b'')

        self.database.rows['building'][0]['building_name'] = 'Administration Hall'
        changed = self.client.get('/campus/offline/bundle',
                                  headers={'If-None-Match': etag})
        self.assertEqual(changed.status_code, 200)
        self.assertNotEqual(changed.headers['etag'], etag)

    def test_a_database_failure_is_reported_as_unavailable(self):
        with patch.object(campus, 'routing_rows',
                          side_effect=RuntimeError('database unavailable')):
            for path in ('/campus/offline/bundle', '/campus/offline/manifest'):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 503)
                self.assertNotIn('database unavailable', response.text)


if __name__ == '__main__':
    unittest.main()
