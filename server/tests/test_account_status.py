import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import login, profile
from app.utils import otp_limits, passwords, pending_otp, session
from app.utils.session import issue_session

PASSWORD = 'Correct1!'
DEACTIVATED = 'This account has been deactivated. Please contact the ISU CAMP administrator.'


class FakeDatabase:
    def __init__(self):
        self.fail_status_lookup = False
        self.tables = {
            'user': [{'id': 11, 'username': 'Karl', 'info_id': 5, 'status': 'active'}],
            'userInfo': [{'id': 5, 'email': 'karl@example.com', 'user_type': 'Student',
                          'password': passwords.password_hash.hash(PASSWORD)}],
            'pending_verification': [],
        }

    def table(self, name):
        return FakeQuery(self, name)

    @property
    def user(self):
        return self.tables['user'][0]


class FakeQuery:
    def __init__(self, db, name):
        self.db, self.name, self.filters = db, name, []
        self.action, self.payload, self.fields = 'select', None, ''

    def select(self, fields):
        self.fields = fields
        return self

    def eq(self, key, value):
        self.filters.append(lambda row: row.get(key) == value)
        return self

    def ilike(self, key, pattern):
        literal = pattern.replace(r'\_', '_')
        self.filters.append(lambda row: str(row.get(key, '')).lower() == literal.lower())
        return self

    def upsert(self, payload, on_conflict):
        self.action, self.payload = 'upsert', payload
        return self

    def delete(self):
        self.action = 'delete'
        return self

    def execute(self):
        if self.db.fail_status_lookup and self.name == 'user' and 'status' in self.fields:
            raise RuntimeError('supabase is down: internal detail')
        rows = self.db.tables[self.name]
        if self.action == 'upsert':
            rows.append(dict(self.payload))
            return SimpleNamespace(data=[self.payload])
        matches = [row for row in rows if all(test(row) for test in self.filters)]
        if self.action == 'delete':
            for row in matches:
                rows.remove(row)
        return SimpleNamespace(data=[dict(row) for row in matches])


class AccountStatusTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {'SESSION_SECRET': 'test-secret-' * 5})
        env.start()
        self.addCleanup(env.stop)
        otp_limits.reset_all()
        self.addCleanup(otp_limits.reset_all)
        login._login_attempts.clear()
        self.addCleanup(login._login_attempts.clear)
        self.db = FakeDatabase()
        self.sent = []
        mocks = [patch.object(target, 'supabase', self.db) for target in (login, profile, pending_otp, session)]
        mocks += [patch.object(login, 'verify_captcha'),
                  patch.object(pending_otp, 'send_otp_email',
                               lambda to, otp, purpose: self.sent.append((to, otp, purpose)))]
        for mock in mocks:
            mock.start()
            self.addCleanup(mock.stop)
        app = FastAPI()
        app.include_router(login.router)
        app.include_router(profile.router)
        self.client = TestClient(app)

    def login(self, identifier='Karl', password=PASSWORD):
        return self.client.post('/auth/login', json={'identifier': identifier, 'password': password})

    def assert_deactivated(self, response):
        self.assertEqual(response.status_code, 403, response.text)
        self.assertEqual(response.json()['detail'], DEACTIVATED)
        self.assertEqual(response.headers.get('x-account-status'), 'inactive')

    # ---------------- login ----------------

    def test_inactive_user_is_refused_only_after_the_correct_password(self):
        self.db.user['status'] = 'inactive'
        for identifier in ('Karl', 'karl@example.com'):
            response = self.login(identifier)
            self.assert_deactivated(response)
            self.assertNotIn('access_token', response.text)

    def test_wrong_password_for_inactive_user_keeps_generic_error(self):
        self.db.user['status'] = 'inactive'
        response = self.login(password='Wrong1!')
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()['detail'], 'Invalid username/email or password.')
        self.assertNotIn('x-account-status', response.headers)
        self.assertNotIn('deactivated', response.text)

    def test_deactivated_login_does_not_count_toward_lockout(self):
        self.db.user['status'] = 'inactive'
        for _ in range(login.MAX_LOGIN_ATTEMPTS + 2):
            self.assert_deactivated(self.login())
        self.assertEqual(login._remaining_lockout('Karl'), 0)
        response = self.login(password='Wrong1!')
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers['x-login-attempts'], '1')

    def test_missing_or_empty_status_counts_as_active(self):
        for status in (None, '', 'active', 'ACTIVE'):
            self.db.user['status'] = status
            self.assertEqual(self.login().status_code, 200, status)
        self.db.user.pop('status')
        response = self.login()
        self.assertEqual(response.status_code, 200)
        headers = {'Authorization': 'Bearer ' + response.json()['access_token']}
        self.assertEqual(self.client.get('/profile', headers=headers).status_code, 200)

    def test_login_status_lookup_failure_returns_503(self):
        self.db.fail_status_lookup = True
        response = self.login()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('internal detail', response.text)
        self.assertNotIn('access_token', response.text)

    # ---------------- existing sessions ----------------

    def test_existing_token_for_deactivated_user_is_refused(self):
        headers = {'Authorization': 'Bearer ' + issue_session(11)}
        self.assertEqual(self.client.get('/profile', headers=headers).status_code, 200)
        self.db.user['status'] = 'inactive'
        self.assert_deactivated(self.client.get('/profile', headers=headers))
        self.assert_deactivated(self.client.patch('/profile', headers=headers, json={'username': 'Karl2'}))
        self.assert_deactivated(self.client.post('/profile/password/request-otp', headers=headers))
        self.assertEqual(self.db.user['username'], 'Karl')
        self.assertEqual(self.sent, [])

    def test_session_status_lookup_failure_returns_503(self):
        headers = {'Authorization': 'Bearer ' + issue_session(11)}
        self.db.fail_status_lookup = True
        response = self.client.get('/profile', headers=headers)
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('internal detail', response.text)

    # ---------------- forgot password ----------------

    def test_forgot_password_treats_inactive_account_as_unknown(self):
        unknown = {path: self.client.post(path, json=body) for path, body in self.recovery_requests('Nobody')}
        unknown_email = self.client.post('/auth/forgot-password/request-otp', json={'identifier': 'nobody@example.com'})
        self.db.user['status'] = 'inactive'
        for identifier in ('Karl', 'karl@example.com'):
            for path, body in self.recovery_requests(identifier):
                response = self.client.post(path, json=body)
                self.assertEqual(response.status_code, unknown[path].status_code, path)
                self.assertEqual(response.json(), unknown[path].json(), path)
        self.assertEqual(unknown_email.json(), unknown['/auth/forgot-password/request-otp'].json())
        self.assertEqual(self.sent, [])
        self.assertEqual(self.db.tables['pending_verification'], [])

    def test_forgot_password_still_works_for_active_account(self):
        response = self.client.post('/auth/forgot-password/request-otp', json={'identifier': 'Karl'})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.sent[-1][0], 'karl@example.com')

    def test_web_app_can_read_the_deactivation_header(self):
        from app.main import app
        response = TestClient(app).get('/no-such-route', headers={'Origin': 'http://localhost:5000'})
        exposed = response.headers.get('access-control-expose-headers', '').lower()
        self.assertIn('x-account-status', exposed)

    @staticmethod
    def recovery_requests(identifier):
        return [
            ('/auth/forgot-password/request-otp', {'identifier': identifier}),
            ('/auth/forgot-password/verify-otp', {'identifier': identifier, 'otp': 123456}),
            ('/auth/forgot-password/reset-password',
             {'identifier': identifier, 'password': 'NewPass2@', 'confirm_password': 'NewPass2@'}),
        ]


if __name__ == '__main__':
    unittest.main()
