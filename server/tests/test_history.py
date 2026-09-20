import os
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch

import jwt
from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.routes import history
from app.utils.session import issue_session


class FakeDatabase:
    def __init__(self):
        self.rows = [dict(id=1, User_id=11, Building_id=8, Location_id=None,
                         created_at="2026-09-20T01:00:00Z"),
                     dict(id=2, User_id=22, Building_id=8, Location_id=None,
                          created_at="2026-09-20T01:00:00Z")]

    def table(self, name):
        return FakeQuery(self, name)


class FakeQuery:
    def __init__(self, db, name):
        self.db, self.name, self.filters = db, name, []
        self.action, self.payload = "select", None
        self.start, self.end = 0, 99

    def select(self, _): return self
    def order(self, *args, **kwargs): return self
    def range(self, start, end):
        self.start, self.end = start, end
        return self
    def eq(self, key, value):
        self.filters.append((key, value))
        return self
    def delete(self):
        self.action = "delete"
        return self
    def insert(self, payload):
        self.action, self.payload = "insert", payload
        return self

    def execute(self):
        if self.name == "building":
            source = [{"building_id": 8}]
        elif self.name == "location":
            source = [{"location_id": 9, "building_id": 8},
                      {"location_id": 10, "building_id": 99}]
        else:
            source = self.db.rows
        matching = [r for r in source if all(r.get(k) == v for k, v in self.filters)]
        if self.action == "insert":
            row = dict(self.payload, id=3, created_at="2026-09-20T02:00:00Z")
            self.db.rows.append(row)
            return SimpleNamespace(data=[row])
        if self.action == "delete":
            self.db.rows[:] = [r for r in self.db.rows if r not in matching]
        if self.name == "UserHistory" and self.action == "select":
            matching = [dict(r, building={"building_name": "CCSICT", "building_code": "CCS"},
                             location=None) for r in matching[self.start:self.end + 1]]
        return SimpleNamespace(data=matching)


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"SESSION_SECRET": "test-secret-" * 5})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.db = FakeDatabase()
        db_patch = patch.object(history, "supabase", self.db)
        db_patch.start()
        self.addCleanup(db_patch.stop)
        app = FastAPI()
        app.include_router(history.router)
        self.client = TestClient(app)
        self.headers = {"Authorization": "Bearer " + issue_session(11)}

    def test_no_session_and_tampered_session_are_rejected(self):
        self.assertEqual(self.client.get('/history').status_code, 401)
        self.assertEqual(self.client.get('/history', headers={
            'Authorization': self.headers['Authorization'] + 'broken'}).status_code, 401)

    def test_expired_session_is_rejected(self):
        token = jwt.encode({'sub': '11', 'iat': datetime.now(timezone.utc) - timedelta(days=2),
                            'exp': datetime.now(timezone.utc) - timedelta(days=1),
                            'aud': 'isu-camp', 'iss': 'isu-camp-backend'},
                           os.environ['SESSION_SECRET'], algorithm='HS256')
        self.assertEqual(self.client.get('/history', headers={
            'Authorization': 'Bearer ' + token}).status_code, 401)

    def test_reads_only_current_users_joined_history(self):
        result = self.client.get('/history', headers=self.headers)
        self.assertEqual(result.status_code, 200)
        self.assertEqual([r['id'] for r in result.json()['entries']], ['1'])
        self.assertEqual(result.json()['entries'][0]['destinationName'], 'CCSICT')

    def test_create_derives_owner_and_allows_building_only(self):
        result = self.client.post('/history', headers=self.headers, json={'buildingId': 8})
        self.assertEqual(result.status_code, 201)
        self.assertEqual(self.db.rows[-1]['User_id'], 11)
        self.assertIsNone(self.db.rows[-1]['Location_id'])

    def test_room_must_belong_to_building_and_owner_cannot_be_supplied(self):
        for payload, status in [({'buildingId': 8, 'locationId': 10}, 400),
                                ({'buildingId': 99}, 404),
                                ({'buildingId': 8, 'User_id': 22}, 422)]:
            self.assertEqual(self.client.post('/history', headers=self.headers,
                                             json=payload).status_code, status)
        self.assertEqual(self.client.post('/history', headers=self.headers,
                         json={'buildingId': 8, 'locationId': 9}).status_code, 201)

    def test_delete_and_clear_cannot_remove_another_users_history(self):
        self.client.delete('/history/2', headers=self.headers)
        self.assertEqual(len(self.db.rows), 2)
        self.client.delete('/history/1', headers=self.headers)
        self.assertEqual([r['id'] for r in self.db.rows], [2])
        self.client.delete('/history', headers=self.headers)
        self.assertEqual([r['id'] for r in self.db.rows], [2])

    def test_database_failure_returns_error(self):
        with patch.object(self.db, 'table', side_effect=RuntimeError('offline')):
            self.assertEqual(self.client.get('/history', headers=self.headers).status_code, 503)

    def test_successful_login_issues_session_for_database_user(self):
        from app.routes import login
        from app.utils.session import current_user_id
        from fastapi.security import HTTPAuthorizationCredentials
        with patch.object(login, 'supabase') as database, \
                patch.object(login.password_hash, 'verify', return_value=True):
            database.table.return_value.select.return_value.eq.return_value.execute.side_effect = [
                SimpleNamespace(data=[{'id': 5, 'email': 'student@example.com', 'password': 'hash'}]),
                SimpleNamespace(data=[{'id': 11, 'username': 'student', 'info_id': 5}]),
            ]
            result = login.login(login.LoginRequest(identifier='student@example.com', password='test'))
        credentials = HTTPAuthorizationCredentials(scheme='Bearer', credentials=result['access_token'])
        self.assertEqual(current_user_id(credentials), 11)


if __name__ == '__main__':
    unittest.main()
