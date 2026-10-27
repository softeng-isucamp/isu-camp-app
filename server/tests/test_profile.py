import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.routes import profile
from app.utils.session import issue_session


class FakeDatabase:
    def __init__(self):
        self.users = [{'id': 11, 'username': 'Karl', 'info_id': 5},
                      {'id': 22, 'username': 'Another_User', 'info_id': 6}]

    def table(self, name):
        return FakeQuery(self, name)


class FakeQuery:
    def __init__(self, db, table):
        self.db, self.table, self.filters, self.payload = db, table, [], None

    def select(self, fields): return self
    def eq(self, key, value):
        self.filters.append(lambda row: row[key] == value)
        return self
    def ilike(self, key, value):
        self.filters.append(lambda row: row[key].lower() == value.replace(r'\_', '_').lower())
        return self
    def update(self, payload):
        self.payload = payload
        return self
    def execute(self):
        rows = self.db.users if self.table == 'user' else [{'id': 5, 'email': 'karl@example.com'}, {'id': 6, 'email': 'other@example.com'}]
        matches = [row for row in rows if all(test(row) for test in self.filters)]
        if self.payload:
            for row in matches: row.update(self.payload)
        return SimpleNamespace(data=matches)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {'SESSION_SECRET': 'test-secret-' * 5})
        env.start()
        self.addCleanup(env.stop)
        self.database = FakeDatabase()
        mock = patch.object(profile, 'supabase', self.database)
        mock.start()
        self.addCleanup(mock.stop)
        app = FastAPI()
        app.include_router(profile.router)
        self.client = TestClient(app)
        self.headers = {'Authorization': 'Bearer ' + issue_session(11)}

    def test_authentication_required_and_owner_comes_from_session(self):
        self.assertEqual(self.client.get('/profile').status_code, 401)
        self.assertEqual(self.client.patch('/profile', json={'username': 'NewName'}).status_code, 401)
        self.assertEqual(self.client.patch('/profile', headers=self.headers, json={'username': 'NewName', 'id': 22}).status_code, 422)
        self.assertEqual(self.client.patch('/profile', headers=self.headers, json={'username': 'NewName', 'email': 'evil@example.com'}).status_code, 422)

    def test_loads_real_email_and_updates_only_owner(self):
        self.assertEqual(self.client.get('/profile', headers=self.headers).json(), {'username': 'Karl', 'email': 'karl@example.com'})
        response = self.client.patch('/profile', headers=self.headers, json={'username': ' Karl_New '})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'username': 'Karl_New', 'email': 'karl@example.com'})
        self.assertEqual(self.database.users[1]['username'], 'Another_User')

    def test_invalid_and_duplicate_username_do_not_change_database(self):
        for value, status in [('ab', 400), ('Bad Name', 400), ('A' * 31, 400), ('another_user', 409)]:
            self.assertEqual(self.client.patch('/profile', headers=self.headers, json={'username': value}).status_code, status)
        self.assertEqual(self.database.users[0]['username'], 'Karl')

    def test_database_unavailable_and_missing_profile(self):
        with patch.object(self.database, 'table', side_effect=RuntimeError('internal secret')):
            response = self.client.get('/profile', headers=self.headers)
            self.assertEqual(response.status_code, 503)
            self.assertNotIn('internal secret', response.text)
        self.database.users.clear()
        self.assertEqual(self.client.get('/profile', headers=self.headers).status_code, 404)


if __name__ == '__main__':
    unittest.main()
