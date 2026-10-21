import base64
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import campus


PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j9n8AAAAASUVORK5CYII=')
JPEG = b'\xff\xd8\xff\xe0test-jpeg\xff\xd9'


class PhotoDatabase:
    def __init__(self):
        self.rows = {
            'building': [{'building_id': index, 'building_name': f'Building {index}',
                          'building_code': f'B{index}', 'type_id': 1,
                          'description': '', 'latitude': 16.7, 'longitude': 121.6,
                          'polygon_coordinates': []} for index in range(1, 53)],
            'location': [{'location_id': index, 'building_id': (index - 1) % 52 + 1,
                          'floor_id': None, 'type_id': 1, 'location_name': f'Room {index}',
                          'location_code': f'R{index}', 'description': ''}
                         for index in range(1, 84)],
            'building_type': [{'type_id': 1, 'type_name': 'College'}],
            'floor': [], 'location_type': [{'type_id': 1, 'type_name': 'Room'}],
            'building_photo': [{'photo_id': index, 'building_id': index, 'position': 0,
                                'is_cover': True, 'content': PNG, 'mime_type': 'image/png'}
                               for index in range(1, 14)],
            'location_photo': [{'photo_id': index, 'location_id': index, 'position': 0,
                                'is_cover': True, 'content': JPEG, 'mime_type': 'image/jpeg'}
                               for index in range(1, 59)],
        }
        self.queries = []
        self.reject_content_reads = False
        self.fail_table = None

    def table(self, name):
        return PhotoQuery(self, name)


class PhotoQuery:
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
        self.database.queries.append((self.table, self.columns, self.filters,
                                      self.bounds, self.row_limit))
        if self.database.fail_table == self.table:
            raise RuntimeError('database unavailable')
        columns = self.columns.split(',')
        if self.database.reject_content_reads and ('content' in columns or '*' in columns):
            raise RuntimeError('The buildings list must not fetch image bytes or wildcard rows')
        rows = [row for row in self.database.rows[self.table]
                if all(row.get(key) == value for key, value in self.filters)]
        if self.order_key:
            rows = sorted(rows, key=lambda row: row[self.order_key])
        if self.bounds:
            rows = rows[self.bounds[0]:self.bounds[1] + 1]
        if self.row_limit is not None:
            rows = rows[:self.row_limit]
        return SimpleNamespace(data=[{key: row.get(key) for key in columns} for row in rows])


class CampusPhotoTests(unittest.TestCase):
    def setUp(self):
        self.database = PhotoDatabase()
        database_patch = patch.object(campus, 'supabase', self.database)
        database_patch.start()
        self.addCleanup(database_patch.stop)
        app = FastAPI()
        app.include_router(campus.router)
        self.client = TestClient(app, base_url='https://api.example.test')

    def test_list_reads_metadata_only_and_stays_small_with_large_stored_photos(self):
        # Shared by rows in this fixture; never selected or serialized by the list.
        large_photo = r'\x' + 'aa' * 2_700_000
        for table in ('building_photo', 'location_photo'):
            for row in self.database.rows[table]:
                row['content'] = large_photo
        self.database.reject_content_reads = True
        response = self.client.get('/campus/buildings')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(len(data['buildings']), 52)
        self.assertEqual(sum(len(row['rooms']) for row in data['buildings']), 83)
        self.assertLess(len(response.content), 1_000_000)
        self.assertNotIn('data:', response.text)
        self.assertNotIn('base64', response.text)
        self.assertEqual(data['buildings'][0]['imageUrl'],
                         'https://api.example.test/campus/photos/building/1')
        self.assertEqual(data['buildings'][0]['rooms'][0]['imageUrl'],
                         'https://api.example.test/campus/photos/location/1')
        self.assertIsNone(data['buildings'][51]['imageUrl'])
        missing_photo_room = next(room for building in data['buildings']
                                  for room in building['rooms'] if room['id'] == '83')
        self.assertIsNone(missing_photo_room['imageUrl'])
        self.assertEqual(len(self.database.queries), 7)

    def test_returned_urls_fetch_only_the_requested_photo_from_the_correct_table(self):
        building = self.client.get('/campus/buildings').json()['buildings'][0]
        urls = [(building['imageUrl'], 'building_photo', PNG, 'image/png'),
                (building['rooms'][0]['imageUrl'], 'location_photo', JPEG, 'image/jpeg')]
        self.database.queries.clear()
        for url, table, content, mime in urls:
            with self.subTest(table=table):
                response = self.client.get(url)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.content, content)
                self.assertEqual(response.headers['content-type'], mime)
                self.assertEqual(response.headers['cache-control'], 'public, max-age=300')
                self.assertEqual(response.headers['x-content-type-options'], 'nosniff')
                query = self.database.queries[-1]
                self.assertEqual(query, (table, 'content,mime_type', [('photo_id', 1)], None, 1))
        self.assertEqual(len(self.database.queries), 2)

    def test_photo_cache_revalidation_returns_no_image_body(self):
        url = '/campus/photos/building/1'
        original = self.client.get(url)
        etag = original.headers['etag']
        for validator in (etag, 'W/' + etag, '"another", ' + etag, '*'):
            response = self.client.get(url, headers={'If-None-Match': validator})
            self.assertEqual(response.status_code, 304)
            self.assertEqual(response.content, b'')
            self.assertEqual(response.headers['etag'], etag)
        self.assertEqual(self.client.get(url, headers={'If-None-Match': '"different"'}).status_code, 200)

    def test_cover_priority_position_and_id_are_preserved(self):
        self.database.rows['building_photo'] = [
            {'photo_id': 1, 'building_id': 1, 'position': 0, 'is_cover': False},
            {'photo_id': 3, 'building_id': 1, 'position': 1, 'is_cover': True},
            {'photo_id': 2, 'building_id': 1, 'position': 1, 'is_cover': True},
            {'photo_id': 4, 'building_id': 2, 'position': None, 'is_cover': False},
            {'photo_id': 5, 'building_id': 2, 'position': 0, 'is_cover': False},
        ]
        buildings = self.client.get('/campus/buildings').json()['buildings']
        self.assertTrue(buildings[0]['imageUrl'].endswith('/building/2'))
        self.assertTrue(buildings[1]['imageUrl'].endswith('/building/5'))
        self.assertIsNone(buildings[2]['imageUrl'])

    def test_invalid_photo_ids_and_sources_never_query_arbitrary_tables(self):
        for url in ('/campus/photos/user/1', '/campus/photos/building/0',
                    '/campus/photos/location/-1', '/campus/photos/building/not-an-id'):
            self.assertEqual(self.client.get(url).status_code, 422)
        self.assertEqual(self.database.queries, [])
        self.assertEqual(self.client.get('/campus/photos/building/999').status_code, 404)

    def test_missing_invalid_or_unsafe_photo_content_does_not_break_the_list(self):
        photo = self.database.rows['building_photo'][0]
        for content, mime in ((None, 'image/png'), (b'', 'image/png'),
                              (r'\xinvalid', 'image/png'), ('invalid', 'image/png'),
                              (PNG, 'text/html'), (PNG, 'image/svg+xml')):
            with self.subTest(content_type=type(content).__name__, mime=mime):
                photo.update(content=content, mime_type=mime)
                self.assertEqual(self.client.get('/campus/buildings').status_code, 200)
                self.assertEqual(self.client.get('/campus/photos/building/1').status_code, 404)

    def test_metadata_pagination_does_not_drop_cover_rows_after_first_page(self):
        self.database.rows['building_photo'] = [
            {'photo_id': index, 'building_id': 1, 'position': index, 'is_cover': index == 501}
            for index in range(1, 502)
        ]
        self.database.reject_content_reads = True
        buildings = self.client.get('/campus/buildings').json()['buildings']
        self.assertTrue(buildings[0]['imageUrl'].endswith('/building/501'))
        photo_queries = [query for query in self.database.queries if query[0] == 'building_photo']
        self.assertEqual([query[3] for query in photo_queries], [(0, 499), (500, 999)])

    def test_photo_urls_include_the_api_mount_prefix_and_https_origin(self):
        app = FastAPI(root_path='/api')
        app.include_router(campus.router)
        client = TestClient(app, base_url='https://campus.example.test')
        url = client.get('/campus/buildings').json()['buildings'][0]['imageUrl']
        self.assertEqual(url, 'https://campus.example.test/api/campus/photos/building/1')
        self.assertEqual(client.get(url).content, PNG)

    def test_database_failures_return_service_unavailable(self):
        self.database.fail_table = 'building_photo'
        with self.assertLogs(campus.logger, level='ERROR'):
            self.assertEqual(self.client.get('/campus/photos/building/1').status_code, 503)
        self.database.fail_table = 'building'
        with self.assertLogs(campus.logger, level='ERROR'):
            self.assertEqual(self.client.get('/campus/buildings').status_code, 503)


if __name__ == '__main__':
    unittest.main()
