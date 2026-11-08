import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import login, profile
from app.utils import email as email_utils, otp_limits, passwords, pending_otp
from app.utils.session import issue_session

OLD_PASSWORD = 'OldPass1!'
NEW_PASSWORD = 'NewPass2@'


class FakeDatabase:
    def __init__(self):
        self.tables = {
            'user': [{'id': 11, 'username': 'Karl', 'info_id': 5},
                     {'id': 22, 'username': 'Other', 'info_id': 6}],
            'userInfo': [{'id': 5, 'email': 'karl@example.com', 'password': passwords.password_hash.hash(OLD_PASSWORD)},
                         {'id': 6, 'email': 'Taken@Example.com', 'password': 'x'}],
            'pending_verification': [],
        }

    def table(self, name):
        return FakeQuery(self, name)

    def pending(self, email):
        return next((row for row in self.tables['pending_verification'] if row['email'] == email), None)


class FakeQuery:
    def __init__(self, db, name):
        self.db, self.name, self.filters = db, name, []
        self.action, self.payload = 'select', None

    def select(self, _fields): return self

    def eq(self, key, value):
        self.filters.append(lambda row: row.get(key) == value)
        return self

    def ilike(self, key, pattern):
        literal = pattern.replace(r'\_', '_').replace(r'\%', '%').replace('\\\\', '\\')
        self.filters.append(lambda row: str(row.get(key, '')).lower() == literal.lower())
        return self

    def update(self, payload):
        self.action, self.payload = 'update', payload
        return self

    def upsert(self, payload, on_conflict):
        self.action, self.payload, self.conflict = 'upsert', payload, on_conflict
        return self

    def delete(self):
        self.action = 'delete'
        return self

    def execute(self):
        rows = self.db.tables[self.name]
        if self.action == 'upsert':
            existing = [row for row in rows if row[self.conflict] == self.payload[self.conflict]]
            for row in existing:
                rows.remove(row)
            rows.append(dict(self.payload))
            return SimpleNamespace(data=[self.payload])
        matches = [row for row in rows if all(test(row) for test in self.filters)]
        if self.action == 'update':
            for row in matches:
                row.update(self.payload)
        if self.action == 'delete':
            for row in matches:
                rows.remove(row)
        return SimpleNamespace(data=[dict(row) for row in matches])


class AccountChangeTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {'SESSION_SECRET': 'test-secret-' * 5})
        env.start()
        self.addCleanup(env.stop)
        otp_limits.reset_all()
        self.addCleanup(otp_limits.reset_all)
        self.db = FakeDatabase()
        self.sent = []
        self.notices = []
        for target in (profile, login, pending_otp):
            mock = patch.object(target, 'supabase', self.db)
            mock.start()
            self.addCleanup(mock.stop)
        for mock in (
            patch.object(pending_otp, 'send_otp_email', lambda to, otp, purpose: self.sent.append((to, otp, purpose))),
            patch.object(profile, 'send_email_changed_notice', lambda old, new: self.notices.append((old, new))),
        ):
            mock.start()
            self.addCleanup(mock.stop)
        app = FastAPI()
        app.include_router(profile.router)
        app.include_router(login.router)
        self.client = TestClient(app)
        self.headers = {'Authorization': 'Bearer ' + issue_session(11)}

    def post(self, path, body=None):
        return self.client.post(path, headers=self.headers, json=body)

    def last_code(self):
        return int(self.sent[-1][1])

    def advance(self, seconds):
        """Move the rate limiter's clock forward from its current time."""
        base = otp_limits._now()
        later = base.__class__.fromtimestamp(base.timestamp() + seconds, base.tzinfo)
        mock = patch.object(otp_limits, '_now', return_value=later)
        mock.start()
        self.addCleanup(mock.stop)

    def password_matches(self, password):
        return passwords.password_hash.verify(password, self.db.tables['userInfo'][0]['password'])

    # ---------------- password change ----------------

    def test_endpoints_require_login(self):
        for path in ('/profile/password/request-otp', '/profile/password/verify-otp', '/profile/password',
                     '/profile/email/request-otp', '/profile/email/verify-otp'):
            self.assertEqual(self.client.post(path, json={}).status_code, 401, path)

    def test_password_change_full_flow(self):
        response = self.post('/profile/password/request-otp')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['sent_to'], 'k***@example.com')
        self.assertEqual(self.sent[-1][0], 'karl@example.com')
        self.assertEqual(self.sent[-1][2], 'password_change')

        self.assertEqual(self.post('/profile/password', {'current_password': OLD_PASSWORD, 'password': NEW_PASSWORD, 'confirm_password': NEW_PASSWORD}).status_code, 400)
        self.assertEqual(self.post('/profile/password/verify-otp', {'otp': self.last_code()}).status_code, 200)
        response = self.post('/profile/password', {'current_password': OLD_PASSWORD, 'password': NEW_PASSWORD, 'confirm_password': NEW_PASSWORD})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(self.password_matches(NEW_PASSWORD))
        self.assertIsNone(self.db.pending('karl@example.com'))

    def test_password_change_requires_the_current_password_even_after_email_verification(self):
        self.post('/profile/password/request-otp')
        self.post('/profile/password/verify-otp', {'otp': self.last_code()})
        body = {'password': NEW_PASSWORD, 'confirm_password': NEW_PASSWORD}
        self.assertEqual(self.post('/profile/password', body).status_code, 422)
        for current in ('', 'WrongPass1!', OLD_PASSWORD + ' '):
            response = self.post('/profile/password', dict(body, current_password=current))
            self.assertEqual(response.status_code, 400, response.text)
            self.assertEqual(response.json()['detail'], 'Current password is incorrect.')
            self.assertTrue(self.password_matches(OLD_PASSWORD))
            self.assertIsNotNone(self.db.pending('karl@example.com'))
        response = self.post('/profile/password', dict(body, current_password=OLD_PASSWORD))
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(self.password_matches(NEW_PASSWORD))

    def test_incorrect_current_password_is_rate_limited(self):
        self.post('/profile/password/request-otp')
        self.post('/profile/password/verify-otp', {'otp': self.last_code()})
        body = {'current_password': 'WrongPass1!', 'password': NEW_PASSWORD,
                'confirm_password': NEW_PASSWORD}
        for _ in range(4):
            self.assertEqual(self.post('/profile/password', body).status_code, 400)
        locked = self.post('/profile/password', body)
        self.assertEqual(locked.status_code, 429)
        self.assertIn('Retry-After', locked.headers)
        body['current_password'] = OLD_PASSWORD
        self.assertEqual(self.post('/profile/password', body).status_code, 429)
        self.assertTrue(self.password_matches(OLD_PASSWORD))

    def test_password_change_rejects_same_and_weak_passwords(self):
        self.post('/profile/password/request-otp')
        self.post('/profile/password/verify-otp', {'otp': self.last_code()})
        same = self.post('/profile/password', {'current_password': OLD_PASSWORD, 'password': OLD_PASSWORD, 'confirm_password': OLD_PASSWORD})
        self.assertEqual(same.status_code, 400)
        self.assertIn('different', same.json()['detail'])
        for password, confirm in [('short1!A', 'short1!B'), ('alllower1!', 'alllower1!'), ('NoSpecial12', 'NoSpecial12')]:
            self.assertEqual(self.post('/profile/password', {'current_password': OLD_PASSWORD, 'password': password, 'confirm_password': confirm}).status_code, 400)
        self.assertTrue(self.password_matches(OLD_PASSWORD))

    def test_code_from_another_flow_is_not_accepted(self):
        # A signup row for the same address belongs to a different username.
        self.db.tables['pending_verification'].append({
            'email': 'karl@example.com', 'username': 'someone', 'otp': 123456,
            'otp_expires_at': '2999-01-01T00:00:00+00:00', 'otp_attempts': 0, 'email_verified': True})
        self.assertEqual(self.post('/profile/password', {'current_password': OLD_PASSWORD, 'password': NEW_PASSWORD, 'confirm_password': NEW_PASSWORD}).status_code, 404)

    # ---------------- rate limits ----------------

    def test_resend_cooldown_and_request_cap(self):
        self.assertEqual(self.post('/profile/password/request-otp').status_code, 200)
        early = self.post('/profile/password/request-otp')
        self.assertEqual(early.status_code, 429)
        self.assertIn('Retry-After', early.headers)
        for _ in range(4):
            self.advance(61)
            self.assertEqual(self.post('/profile/password/request-otp').status_code, 200)
        self.advance(61)
        self.assertEqual(self.post('/profile/password/request-otp').status_code, 429)
        self.advance(31 * 60)
        self.assertEqual(self.post('/profile/password/request-otp').status_code, 200)

    def test_new_code_does_not_reset_wrong_guesses(self):
        self.post('/profile/password/request-otp')
        wrong = (self.last_code() % 999999) + 1
        for remaining in (4, 3, 2):
            response = self.post('/profile/password/verify-otp', {'otp': wrong})
            self.assertEqual(response.json()['detail'], f'Invalid OTP. {remaining} attempt(s) remaining.')
        self.advance(61)
        self.post('/profile/password/request-otp')
        wrong = (self.last_code() % 999999) + 1
        self.assertIn('1 attempt(s)', self.post('/profile/password/verify-otp', {'otp': wrong}).json()['detail'])
        locked = self.post('/profile/password/verify-otp', {'otp': wrong})
        self.assertIn('Too many', locked.json()['detail'])
        self.assertEqual(self.post('/profile/password/verify-otp', {'otp': self.last_code()}).status_code, 429)

    # ---------------- email change ----------------

    def test_email_change_full_flow(self):
        response = self.post('/profile/email/request-otp', {'email': 'new@example.com'})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.sent[-1][0], 'new@example.com')
        self.assertEqual(self.sent[-1][2], 'email_change')
        self.assertEqual(self.db.tables['userInfo'][0]['email'], 'karl@example.com')
        response = self.post('/profile/email/verify-otp', {'email': 'new@example.com', 'otp': self.last_code()})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), {'username': 'Karl', 'email': 'new@example.com'})
        self.assertEqual(self.db.tables['userInfo'][0]['email'], 'new@example.com')
        self.assertEqual(self.notices, [('karl@example.com', 'new@example.com')])
        self.assertIsNone(self.db.pending('new@example.com'))

    def test_email_change_rejects_invalid_same_and_taken(self):
        self.assertEqual(self.post('/profile/email/request-otp', {'email': 'not-an-email'}).status_code, 422)
        self.assertEqual(self.post('/profile/email/request-otp', {'email': 'KARL@example.com'}).status_code, 400)
        taken = self.post('/profile/email/request-otp', {'email': 'taken@example.com'})
        self.assertEqual(taken.status_code, 409)
        self.assertEqual(self.sent, [])

    def test_email_taken_between_request_and_confirm(self):
        self.post('/profile/email/request-otp', {'email': 'new@example.com'})
        self.db.tables['userInfo'][1]['email'] = 'new@example.com'
        response = self.post('/profile/email/verify-otp', {'email': 'new@example.com', 'otp': self.last_code()})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.db.tables['userInfo'][0]['email'], 'karl@example.com')

    def test_wrong_email_change_code_keeps_old_email(self):
        self.post('/profile/email/request-otp', {'email': 'new@example.com'})
        wrong = (self.last_code() % 999999) + 1
        self.assertEqual(self.post('/profile/email/verify-otp', {'email': 'new@example.com', 'otp': wrong}).status_code, 400)
        self.assertEqual(self.db.tables['userInfo'][0]['email'], 'karl@example.com')
        self.assertEqual(self.notices, [])

    # ---------------- forgot password ----------------

    def test_forgot_password_flow_uses_reset_subject_and_rejects_same_password(self):
        response = self.client.post('/auth/forgot-password/request-otp', json={'identifier': 'Karl'})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.sent[-1][2], 'password_reset')
        self.client.post('/auth/forgot-password/verify-otp', json={'identifier': 'Karl', 'otp': self.last_code()})
        same = self.client.post('/auth/forgot-password/reset-password',
                                json={'identifier': 'Karl', 'password': OLD_PASSWORD, 'confirm_password': OLD_PASSWORD})
        self.assertEqual(same.status_code, 400)
        ok = self.client.post('/auth/forgot-password/reset-password',
                              json={'identifier': 'karl@example.com', 'password': NEW_PASSWORD, 'confirm_password': NEW_PASSWORD})
        self.assertEqual(ok.status_code, 200, ok.text)
        self.assertTrue(self.password_matches(NEW_PASSWORD))

    def test_forgot_password_is_rate_limited_per_email(self):
        self.assertEqual(self.client.post('/auth/forgot-password/request-otp', json={'identifier': 'Karl'}).status_code, 200)
        # Same account through its email address shares the limit.
        self.assertEqual(self.client.post('/auth/forgot-password/request-otp', json={'identifier': 'karl@example.com'}).status_code, 429)


class EmailSubjectTests(unittest.TestCase):
    def test_each_purpose_has_its_own_subject(self):
        subjects = {subject for subject, _ in email_utils.OTP_PURPOSES.values()}
        self.assertEqual(len(subjects), len(email_utils.OTP_PURPOSES))

    def test_mask_email(self):
        self.assertEqual(email_utils.mask_email('jade@gmail.com'), 'j***@gmail.com')


if __name__ == '__main__':
    unittest.main()
