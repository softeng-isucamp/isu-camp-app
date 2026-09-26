import hashlib
import os
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch

import jwt
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import history, sessions
from app.utils.session import REFRESH_LIFETIME


class FakeQuery:
    def __init__(self, db, table):
        self.db, self.table_name = db, table
        self.payload = None
        self.filters = []

    def select(self, *_args, **_kwargs): return self
    def order(self, *_args, **_kwargs): return self
    def range(self, *_args, **_kwargs): return self
    def eq(self, key, value): self.filters.append((key, value)); return self
    def is_(self, *_args, **_kwargs): return self
    def update(self, payload): self.payload = payload; return self

    def insert(self, payload):
        self.payload = payload
        return self

    def execute(self):
        if self.payload is None:
            return SimpleNamespace(data=[])
        if self.table_name == "HistoryRefreshSession" and "token_hash" not in self.payload:
            for key, value in self.filters:
                if key == "token_hash" and value in self.db.sessions:
                    self.db.sessions[value]["revoked_at"] = self.payload["revoked_at"]
            return SimpleNamespace(data=[])
        self.db.sessions[self.payload["token_hash"]] = dict(self.payload, revoked_at=None)
        return SimpleNamespace(data=[self.payload])


class FakeDatabase:
    def __init__(self):
        self.sessions = {}

    def table(self, name):
        return FakeQuery(self, name)

    def rpc(self, name, params):
        return FakeRpc(self, params)


class FakeRpc:
    def __init__(self, db, params):
        self.db, self.params = db, params

    def execute(self):
        params = self.params
        token = self.db.sessions.get(params["p_token_hash"])
        valid = token and token["revoked_at"] is None and datetime.fromisoformat(
            token["expires_at"].replace("Z", "+00:00")) > datetime.now(timezone.utc)
        if valid:
            token["revoked_at"] = datetime.now(timezone.utc).isoformat()
            self.db.sessions[params["p_new_token_hash"]] = {
                "user_id": token["user_id"], "expires_at": params["p_new_expires_at"],
                "revoked_at": None,
            }
            return SimpleNamespace(data=[{"user_id": token["user_id"]}])
        return SimpleNamespace(data=[])


class RefreshSessionTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"SESSION_SECRET": "refresh-test-secret-" * 3})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.db = FakeDatabase()
        self.db_patch = patch.object(sessions, "supabase", self.db)
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)
        self.history_patch = patch.object(history, "supabase", self.db)
        self.history_patch.start()
        self.addCleanup(self.history_patch.stop)
        app = FastAPI()
        app.include_router(sessions.router)
        app.include_router(history.router)
        self.client = TestClient(app)

    def _refresh(self, token):
        return self.client.post("/auth/refresh", json={"refresh_token": token})

    def test_expired_access_can_refresh_and_access_history(self):
        old_access = jwt.encode({"sub": "11", "iat": datetime.now(timezone.utc) - timedelta(days=2),
                                 "exp": datetime.now(timezone.utc) - timedelta(days=1),
                                 "aud": "isu-camp", "iss": "isu-camp-backend"},
                                os.environ["SESSION_SECRET"], algorithm="HS256")
        self.assertEqual(self.client.get("/history", headers={
            "Authorization": "Bearer " + old_access}).status_code, 401)

        raw_refresh = "opaque-initial-refresh-token"
        digest = hashlib.sha256(raw_refresh.encode()).hexdigest()
        self.db.sessions[digest] = {"user_id": 11,
                                    "expires_at": (datetime.now(timezone.utc) + REFRESH_LIFETIME).isoformat(),
                                    "revoked_at": None}
        result = self._refresh(raw_refresh)
        self.assertEqual(result.status_code, 200)
        body = result.json()
        self.assertNotEqual(body["refresh_token"], raw_refresh)
        self.assertNotIn(body["refresh_token"], self.db.sessions)
        self.assertIn(hashlib.sha256(body["refresh_token"].encode()).hexdigest(), self.db.sessions)
        history_result = self.client.get("/history", headers={
            "Authorization": "Bearer " + body["access_token"]})
        self.assertEqual(history_result.status_code, 200)

    def test_revoked_and_expired_refresh_tokens_are_rejected(self):
        for token, expires, revoked in [
                ("revoked-refresh", datetime.now(timezone.utc) + timedelta(days=1), True),
                ("expired-refresh", datetime.now(timezone.utc) - timedelta(seconds=1), False)]:
            digest = hashlib.sha256(token.encode()).hexdigest()
            self.db.sessions[digest] = {"user_id": 11, "expires_at": expires.isoformat(),
                                        "revoked_at": datetime.now(timezone.utc).isoformat() if revoked else None}
            self.assertEqual(self._refresh(token).status_code, 401)

    def test_refresh_token_rotation_makes_previous_token_unusable(self):
        raw = "rotate-me"
        digest = hashlib.sha256(raw.encode()).hexdigest()
        self.db.sessions[digest] = {"user_id": 11,
                                    "expires_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
                                    "revoked_at": None}
        first = self._refresh(raw)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(self._refresh(raw).status_code, 401)

    def test_revoke_endpoint_invalidates_refresh_token(self):
        raw = "log-out-token"
        digest = hashlib.sha256(raw.encode()).hexdigest()
        self.db.sessions[digest] = {"user_id": 11,
                                    "expires_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
                                    "revoked_at": None}
        result = self.client.post("/auth/logout", json={"refresh_token": raw})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(self._refresh(raw).status_code, 401)


if __name__ == "__main__":
    unittest.main()
