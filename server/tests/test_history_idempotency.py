import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import history
from app.utils.session import issue_session


EVENT_ID = "b53a5f92-a8b2-4c5c-8cff-3e7d260e9c0a"


class FakeQuery:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters, self.action, self.payload = [], "select", None

    def select(self, *_args, **_kwargs): return self
    def eq(self, key, value): self.filters.append((key, value)); return self
    def insert(self, payload): self.action, self.payload = "insert", payload; return self

    def execute(self):
        if self.table == "building":
            return SimpleNamespace(data=[{"building_id": 8}])
        if self.table == "location":
            return SimpleNamespace(data=[{"location_id": 9, "building_id": 8}])
        matching = [row for row in self.db.rows if all(row.get(k) == v for k, v in self.filters)]
        if self.action == "insert":
            event_id = self.payload.get("client_event_id")
            if event_id and any(row["User_id"] == self.payload["User_id"]
                                and row.get("client_event_id") == event_id
                                for row in self.db.rows):
                raise RuntimeError("duplicate key")
            row = dict(self.payload, id=len(self.db.rows) + 1, created_at="2026-09-26T00:00:00Z")
            self.db.rows.append(row)
            return SimpleNamespace(data=[row])
        return SimpleNamespace(data=matching)


class FakeDatabase:
    def __init__(self): self.rows = []
    def table(self, name): return FakeQuery(self, name)


class HistoryIdempotencyTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"SESSION_SECRET": "idempotency-test-secret-" * 2})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.db = FakeDatabase()
        self.db_patch = patch.object(history, "supabase", self.db)
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)
        app = FastAPI()
        app.include_router(history.router)
        self.client = TestClient(app)
        self.headers = {"Authorization": "Bearer " + issue_session(11)}

    def _post(self, **payload):
        return self.client.post("/history", headers=self.headers,
                                json={"buildingId": 8, **payload})

    def test_retry_with_same_client_event_id_returns_original_record(self):
        first = self._post(clientEventId=EVENT_ID)
        retry = self._post(clientEventId=EVENT_ID)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(retry.status_code, 201)
        self.assertEqual(retry.json(), first.json())
        self.assertEqual(len(self.db.rows), 1)

    def test_reused_event_id_cannot_change_its_destination(self):
        self.assertEqual(self._post(clientEventId=EVENT_ID).status_code, 201)
        changed = self.client.post("/history", headers=self.headers,
                                   json={"buildingId": 8, "locationId": 9,
                                         "clientEventId": EVENT_ID})
        self.assertEqual(changed.status_code, 409)
        self.assertEqual(len(self.db.rows), 1)

    def test_event_identity_is_scoped_to_owner_and_optional_for_old_clients(self):
        self.assertEqual(self._post(clientEventId=EVENT_ID).status_code, 201)
        other_headers = {"Authorization": "Bearer " + issue_session(22)}
        other = self.client.post("/history", headers=other_headers,
                                 json={"buildingId": 8, "clientEventId": EVENT_ID})
        legacy_a = self._post()
        legacy_b = self._post()
        self.assertEqual(other.status_code, 201)
        self.assertNotEqual(other.json()["id"], "1")
        self.assertEqual(legacy_a.status_code, 201)
        self.assertEqual(legacy_b.status_code, 201)
        self.assertEqual(len(self.db.rows), 4)

    def test_invalid_event_id_is_rejected(self):
        result = self._post(clientEventId="not-a-uuid")
        self.assertEqual(result.status_code, 422)

    def test_history_entry_serializes_client_event_identity(self):
        row = {"id": 4, "Building_id": 8, "Location_id": None,
               "client_event_id": EVENT_ID, "created_at": "2026-09-26T00:00:00Z",
               "building": {"building_name": "CCSICT", "building_code": "CCS"},
               "location": None}
        self.assertEqual(history.history_entry(row)["clientEventId"], EVENT_ID)


if __name__ == "__main__":
    unittest.main()
