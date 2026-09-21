import os
import unittest
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import campus
from app.utils import campus_cache
from tests.test_campus_cache import FakeSupabase


class CampusRouteTests(unittest.TestCase):
    def setUp(self):
        self.db = FakeSupabase()
        patcher = patch.object(campus_cache, "supabase", self.db)
        patcher.start()
        self.addCleanup(patcher.stop)
        campus_cache.invalidate()
        self.addCleanup(campus_cache.invalidate)
        app = FastAPI()
        app.include_router(campus.router)
        self.client = TestClient(app)

    def test_buildings_returns_json_with_an_etag(self):
        result = self.client.get("/campus/buildings")
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["buildings"][0]["name"], "CCSICT")
        self.assertTrue(result.headers["etag"])
        self.assertIn("max-age", result.headers["cache-control"])

    def test_matching_if_none_match_returns_304_without_a_body(self):
        first = self.client.get("/campus/buildings")
        again = self.client.get("/campus/buildings",
                                headers={"If-None-Match": first.headers["etag"]})
        self.assertEqual(again.status_code, 304)
        self.assertEqual(again.content, b"")
        self.assertEqual(again.headers["etag"], first.headers["etag"])

    def test_stale_if_none_match_returns_the_new_body(self):
        result = self.client.get("/campus/buildings", headers={"If-None-Match": '"outdated"'})
        self.assertEqual(result.status_code, 200)

    def test_repeated_requests_do_not_re_read_the_database(self):
        self.client.get("/campus/buildings")
        calls = self.db.calls
        for _ in range(5):
            self.client.get("/campus/buildings")
            self.client.post("/campus/routes", json={
                "mode": "walking", "destinationBuildingId": "10",
                "origin": {"type": "mainGate", "latitude": 16.7172, "longitude": 121.6855}})
        self.assertEqual(self.db.calls, calls)

    def test_routes_are_computed_from_the_cached_graph(self):
        result = self.client.post("/campus/routes", json={
            "mode": "walking", "destinationBuildingId": "10",
            "origin": {"type": "mainGate", "latitude": 16.7172, "longitude": 121.6855}})
        self.assertEqual(result.status_code, 200)
        types = [r["type"] for r in result.json()["routes"]]
        self.assertEqual(types, ["shortest", "comfortableShaded"])
        self.assertEqual(result.json()["routes"][0]["pathwayIds"], ["1"])

    def test_unreachable_building_is_a_404(self):
        result = self.client.post("/campus/routes", json={
            "mode": "walking", "destinationBuildingId": "999",
            "origin": {"type": "mainGate", "latitude": 16.7172, "longitude": 121.6855}})
        self.assertEqual(result.status_code, 404)
        self.assertIn("entrance", result.json()["detail"])

    def test_cold_database_failure_is_a_503(self):
        self.db.fail = True
        self.assertEqual(self.client.get("/campus/buildings").status_code, 503)

    def test_refresh_requires_the_admin_token(self):
        with patch.dict(os.environ, {"ADMIN_REFRESH_TOKEN": "s" * 32}):
            self.client.get("/campus/buildings")
            self.assertEqual(self.client.post("/campus/refresh-cache").status_code, 401)
            self.assertEqual(self.client.post("/campus/refresh-cache", headers={
                "Authorization": "Bearer wrong"}).status_code, 401)
            calls = self.db.calls
            accepted = self.client.post("/campus/refresh-cache", headers={
                "Authorization": "Bearer " + "s" * 32})
            self.assertEqual(accepted.status_code, 204)
            self.client.get("/campus/buildings")
            self.assertGreater(self.db.calls, calls, "refresh must drop the snapshot")

    def test_refresh_is_disabled_when_unconfigured(self):
        with patch.dict(os.environ, {"ADMIN_REFRESH_TOKEN": ""}):
            self.assertEqual(self.client.post("/campus/refresh-cache", headers={
                "Authorization": "Bearer anything"}).status_code, 503)


if __name__ == "__main__":
    unittest.main()
