import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.services.offline_pack import OfflinePackStore, campus_tile_paths, photo_path
from app.routes import campus


class OfflinePackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = OfflinePackStore(self.temp.name)
        self.bundle = {'buildings': [{'id': '1', 'name': 'Admin',
            'imageUrl': 'https://api.test/campus/photos/building/1', 'rooms': []}],
            'graph': {'nodes': [], 'pathways': [], 'points': [], 'modes': []},
            'version': 'legacy', 'generatedAt': 'changes-per-request'}
        self.tile = 'tiles/15/27459/14838.png'
        self.assets = {self.tile: b'tile bytes',
                       photo_path(self.bundle['buildings'][0]['imageUrl']): b'photo bytes'}
        self.required = [self.tile]

    def publish(self, bundle=None, assets=None):
        return self.store.publish(bundle or self.bundle,
            assets if assets is not None else self.assets, required_tiles=self.required)

    def test_manifest_measures_the_same_immutable_bytes_that_are_served(self):
        manifest = self.publish()
        total = 0
        for entry in manifest['files']:
            file, _ = self.store.asset(manifest['version'], entry['path'])
            content = file.read_bytes()
            total += len(content)
            self.assertEqual(entry['bytes'], len(content))
            self.assertEqual(entry['sha256'], hashlib.sha256(content).hexdigest())
        self.assertEqual(manifest['totalBytes'], total)
        bundle = json.loads(self.store.asset(manifest['version'], 'bundle.json')[0].read_bytes())
        self.assertEqual(bundle['version'], manifest['version'])

    def test_repeat_build_does_not_change_published_bytes_or_time(self):
        first = self.publish()
        self.bundle['generatedAt'] = 'new clock value'
        self.assertEqual(first, self.publish())

    @unittest.skipUnless(os.name == 'posix', 'Separate container users use POSIX permissions')
    def test_published_pack_is_readable_by_a_separate_api_user_with_private_builder_umask(self):
        previous = os.umask(0o077)
        try:
            manifest = self.publish()
        finally:
            os.umask(previous)
        snapshot = self.store.root / manifest['version']
        # Check every traversal/read permission, including the atomic pointer
        # and TemporaryDirectory root that otherwise default to private modes.
        for path in [self.store.root / 'current', snapshot, *snapshot.rglob('*')]:
            mode = path.stat().st_mode
            self.assertTrue(mode & 0o004, str(path))
            if path.is_dir():
                self.assertTrue(mode & 0o001, str(path))

    def test_each_source_content_change_changes_version_and_retains_old_files(self):
        first = self.publish()
        for kind in ['data', 'photo', 'tile']:
            bundle, assets = copy.deepcopy(self.bundle), dict(self.assets)
            if kind == 'data':
                bundle['buildings'][0]['name'] = 'Changed'
            else:
                path = self.tile if kind == 'tile' else photo_path(bundle['buildings'][0]['imageUrl'])
                assets[path] += b'changed'
            changed = self.publish(bundle, assets)
            self.assertNotEqual(changed['version'], first['version'])
            self.assertEqual(self.store.asset(first['version'], self.tile)[0].read_bytes(), b'tile bytes')

    def test_missing_or_empty_sources_never_replace_the_current_pack(self):
        first = self.publish()
        for assets in [{}, {**self.assets, self.tile: b''}]:
            with self.assertRaises(ValueError):
                self.publish(assets=assets)
            self.assertEqual(self.store.manifest(), first)

    def test_production_builder_requires_the_entire_campus_coverage(self):
        with self.assertRaises(ValueError):
            self.store.publish(self.bundle, self.assets)

    def test_failed_write_does_not_publish_partial_version(self):
        first = self.publish()
        self.bundle['buildings'][0]['name'] = 'New dataset'
        with patch('app.services.offline_pack._write_payload', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                self.publish()
        self.assertEqual(self.store.manifest(), first)
        self.assertFalse(list(Path(self.temp.name).glob('.build-*')))

    def test_only_allowlisted_pack_files_can_be_served(self):
        version = self.publish()['version']
        for path in ['../manifest.json', 'meta.json', 'tiles/1/2/3.png', 'photos/no.img']:
            with self.assertRaises(FileNotFoundError):
                self.store.asset(version, path)
        with self.assertRaises(ValueError):
            self.store.manifest('../anything')

    def test_tile_coverage_matches_the_flutter_pack(self):
        paths = list(campus_tile_paths())
        self.assertEqual(len(paths), 1126)
        self.assertIn('tiles/15/27459/14838.png', paths)
        self.assertIn('tiles/19/439357/237452.png', paths)

    def test_endpoints_read_the_snapshot_without_querying_live_sources(self):
        published = self.publish()
        app = FastAPI()
        app.include_router(campus.router)
        with patch.object(campus, 'offline_pack_store', return_value=self.store), \
             patch.object(campus, 'offline_bundle_payload', side_effect=AssertionError('request-time build')):
            client = TestClient(app)
            response = client.get('/campus/offline/manifest')
            self.assertEqual(response.json(), published)
            for entry in published['files']:
                response = client.get(f"/campus/offline/packs/{published['version']}/{entry['path']}")
                self.assertEqual(response.status_code, 200)
                self.assertEqual(len(response.content), entry['bytes'])
                self.assertEqual(response.headers['content-length'], str(entry['bytes']))
                self.assertIn('immutable', response.headers['cache-control'])
            bundle_response = client.get('/campus/offline/bundle')
            self.assertEqual(bundle_response.json()['version'], published['version'])
            self.assertEqual(bundle_response.headers['cache-control'], 'no-cache')
            self.assertEqual(client.get('/campus/offline/bundle', headers={
                'If-None-Match': bundle_response.headers['etag']}).status_code, 304)
            self.assertEqual(client.get(f"/campus/offline/packs/{published['version']}/manifest.json").status_code, 404)

    def test_builder_command_publishes_all_sources_from_configured_inputs(self):
        from contextlib import redirect_stdout
        from io import BytesIO, StringIO
        from PIL import Image
        from scripts.build_offline_pack import main
        from test_offline_endpoints import FakeDatabase
        import app.database.supabase as database_module
        tile_root = Path(self.temp.name) / 'rendered-tiles'
        output_root = Path(self.temp.name) / 'published'
        image = BytesIO()
        Image.new('RGB', (1, 1), color='white').save(image, format='PNG')
        for path in campus_tile_paths():
            file = tile_root / path.removeprefix('tiles/')
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(image.getvalue())
        database = FakeDatabase()
        args = ['build_offline_pack.py', '--tiles', str(tile_root),
                '--root', str(output_root), '--api-base-url', 'https://api.test']
        with patch('sys.argv', args), patch.object(campus, 'supabase', database), \
             patch.object(database_module, 'supabase', database), redirect_stdout(StringIO()):
            main()
        manifest = OfflinePackStore(output_root).manifest()
        self.assertEqual(len(manifest['files']), 1126 + 2 + 1)
        self.assertEqual(manifest['totalBytes'], sum(entry['bytes'] for entry in manifest['files']))

    def test_no_published_pack_is_explicitly_unavailable(self):
        app = FastAPI()
        app.include_router(campus.router)
        with patch.object(campus, 'offline_pack_store', return_value=self.store):
            response = TestClient(app).get('/campus/offline/manifest')
            self.assertEqual(response.status_code, 503)
            self.assertIn('being prepared', response.json()['detail'])


if __name__ == '__main__':
    unittest.main()
