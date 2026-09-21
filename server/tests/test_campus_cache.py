import copy
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from app.utils import campus_cache


ROWS = {
    "route_node": [
        dict(node_id=1, building_id=None, latitude=16.7172, longitude=121.6855,
             node_type="entrance", status="active", name="Main Gate"),
        dict(node_id=2, building_id=10, latitude=16.7180, longitude=121.6860,
             node_type="entrance", status="active", name="CCSICT"),
    ],
    "pathway": [dict(pathway_id=1, source_node_id=1, destination_node_id=2,
                     status="active", direction="Two-way", shade="Unshaded", name="Main Walk")],
    "pathway_allowed_mode": [dict(pathway_id=1, mode="Walking")],
    "path_point": [],
    "building": [dict(building_id=10, building_code="CCS", building_name="CCSICT",
                      description=None, latitude=16.7180, longitude=121.6860,
                      polygon_coordinates=None, classification="Building")],
    "location": [], "floor": [], "location_type": [],
}


class FakeSupabase:
    """Counts round trips and can be told to fail."""

    def __init__(self):
        self.calls = 0
        self.fail = False
        self.rows = copy.deepcopy(ROWS)
        self.lock = threading.Lock()

    def table(self, name):
        with self.lock:
            self.calls += 1
            if self.fail:
                raise RuntimeError("supabase is down")
        return FakeQuery(self.rows[name])


class FakeQuery:
    def __init__(self, rows):
        self.rows = rows

    def select(self, _): return self
    def order(self, *_a, **_k): return self

    def range(self, start, end):
        self.rows = self.rows[start:end + 1]
        return self

    def execute(self):
        return SimpleNamespace(data=self.rows)


class CampusCacheTests(unittest.TestCase):
    def setUp(self):
        self.db = FakeSupabase()
        patcher = patch.object(campus_cache, "supabase", self.db)
        patcher.start()
        self.addCleanup(patcher.stop)
        campus_cache.invalidate()
        self.addCleanup(campus_cache.invalidate)

    def test_within_ttl_the_database_is_read_once(self):
        first = campus_cache.current()
        after_load = self.db.calls
        self.assertEqual(after_load, len(campus_cache.TABLES))
        for _ in range(25):
            self.assertIs(campus_cache.current(), first)
        self.assertEqual(self.db.calls, after_load, "cache hit must not touch the database")

    def test_expired_ttl_reloads_and_invalidate_forces_a_reload(self):
        first = campus_cache.current()
        with patch.object(campus_cache, "TTL_SECONDS", -1):
            self.assertIsNot(campus_cache.current(), first)
        reloaded = self.db.calls
        campus_cache.invalidate()
        campus_cache.current()
        self.assertEqual(self.db.calls, reloaded + len(campus_cache.TABLES))

    def test_snapshot_exposes_graph_and_prebuilt_body(self):
        snapshot = campus_cache.current()
        self.assertEqual(set(snapshot.nodes), {"1", "2"})
        self.assertEqual(len(snapshot.graph["1"]), 1)
        self.assertIn(b"CCSICT", snapshot.buildings_body)
        self.assertTrue(snapshot.etag.startswith('"') and snapshot.etag.endswith('"'))

    def test_etag_tracks_the_data(self):
        before = campus_cache.current().etag
        campus_cache.invalidate()
        self.db.rows["building"][0]["building_name"] = "Renamed Hall"
        after = campus_cache.current().etag
        self.assertNotEqual(before, after)

    def test_failed_refresh_serves_stale_data_instead_of_raising(self):
        good = campus_cache.current()
        self.db.fail = True
        with patch.object(campus_cache, "TTL_SECONDS", -1):
            with self.assertLogs("app.utils.campus_cache", "ERROR"):
                stale = campus_cache.current()
        self.assertIs(stale, good, "a Supabase outage must degrade to stale, not 503")

    def test_a_failed_refresh_is_not_retried_on_every_request(self):
        campus_cache.current()
        self.db.fail = True
        with patch.object(campus_cache, "TTL_SECONDS", -1):
            with self.assertLogs("app.utils.campus_cache", "ERROR"):
                campus_cache.current()
            attempted = self.db.calls
            for _ in range(10):
                campus_cache.current()
            self.assertEqual(self.db.calls, attempted, "backoff must throttle a sick backend")

    def test_first_load_failure_propagates(self):
        self.db.fail = True
        with self.assertRaises(RuntimeError):
            campus_cache.current()

    def test_concurrent_cold_start_loads_once(self):
        start = threading.Barrier(8)
        seen = []

        def worker():
            start.wait()
            seen.append(campus_cache.current())

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for t in threads: t.start()
        for t in threads: t.join()
        self.assertEqual(len(seen), 8)
        self.assertEqual(len(set(id(s) for s in seen)), 1, "all callers share one snapshot")
        self.assertEqual(self.db.calls, len(campus_cache.TABLES), "no stampede on a cold cache")

    def test_warm_swallows_startup_failure(self):
        self.db.fail = True
        with self.assertLogs("app.utils.campus_cache", "ERROR"):
            campus_cache.warm()


if __name__ == "__main__":
    unittest.main()
