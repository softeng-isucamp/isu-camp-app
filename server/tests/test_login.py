import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi.security import HTTPAuthorizationCredentials

from app.routes import login
from app.utils.session import current_user_id

INFO = {"id": 5, "email": "student@example.com", "password": "hash"}
USER = {"id": 11, "username": "student", "info_id": 5}


class LoginTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {"SESSION_SECRET": "test-secret-" * 5})
        env.start()
        self.addCleanup(env.stop)
        login._login_attempts.clear()
        self.addCleanup(login._login_attempts.clear)

    def run_login(self, rows, identifier="student@example.com", valid=True):
        """Returns (result-or-exception, number of database round trips)."""
        with patch.object(login, "supabase") as database, \
                patch.object(login.password_hash, "verify", return_value=valid):
            chain = database.table.return_value.select.return_value.eq.return_value
            chain.execute.return_value = SimpleNamespace(data=rows)
            try:
                return login.login(login.LoginRequest(identifier=identifier, password="pw")), \
                    chain.execute.call_count
            except Exception as error:
                return error, chain.execute.call_count

    # PostgREST returns an object for a to-one embed and a list for to-many.
    # Which one applies depends on whether the FK column is unique, so the
    # handler must cope with either shape.
    def test_email_login_accepts_either_embed_shape(self):
        for embedded in (USER, [USER]):
            with self.subTest(shape=type(embedded).__name__):
                result, calls = self.run_login([dict(INFO, user=embedded)])
                self.assertEqual(calls, 1, "email login must be one round trip")
                self.assertEqual(result["user"], {
                    "id": 11, "username": "student", "email": "student@example.com"})
                credentials = HTTPAuthorizationCredentials(
                    scheme="Bearer", credentials=result["access_token"])
                self.assertEqual(current_user_id(credentials), 11)

    def test_username_login_accepts_either_embed_shape(self):
        for embedded in (INFO, [INFO]):
            with self.subTest(shape=type(embedded).__name__):
                result, calls = self.run_login([dict(USER, userInfo=embedded)],
                                               identifier="student")
                self.assertEqual(calls, 1, "username login must be one round trip")
                self.assertEqual(result["user"]["id"], 11)
                self.assertEqual(result["user"]["email"], "student@example.com")

    def test_unknown_identifier_is_a_401(self):
        result, _ = self.run_login([])
        self.assertEqual(result.status_code, 401)
        self.assertEqual(result.headers["X-Login-Attempts"], "1")

    def test_wrong_password_is_a_401_and_counts_the_attempt(self):
        result, _ = self.run_login([dict(INFO, user=USER)], valid=False)
        self.assertEqual(result.status_code, 401)

    def test_orphaned_info_row_is_reported_only_after_the_password_check(self):
        """A missing user row must not reveal that the email exists."""
        wrong_password, _ = self.run_login([dict(INFO, user=None)], valid=False)
        self.assertEqual(wrong_password.status_code, 401)
        right_password, _ = self.run_login([dict(INFO, user=None)], valid=True)
        self.assertEqual(right_password.status_code, 404)

    def test_database_failure_is_a_503_not_a_bare_500(self):
        with patch.object(login, "supabase") as database:
            database.table.side_effect = RuntimeError("supabase is down")
            with self.assertLogs("app.routes.login", "ERROR"):
                with self.assertRaises(Exception) as caught:
                    login.login(login.LoginRequest(identifier="a@b.com", password="pw"))
        self.assertEqual(caught.exception.status_code, 503)
        self.assertIn("try again", caught.exception.detail)

    def test_database_failure_on_password_reset_is_also_a_503(self):
        with patch.object(login, "supabase") as database:
            database.table.side_effect = RuntimeError("supabase is down")
            with self.assertLogs("app.routes.login", "ERROR"):
                with self.assertRaises(Exception) as caught:
                    login.get_user_by_identifier("a@b.com")
        self.assertEqual(caught.exception.status_code, 503)

    def test_lockout_after_six_failures(self):
        for _ in range(login.MAX_LOGIN_ATTEMPTS - 1):
            self.assertEqual(self.run_login([])[0].status_code, 401)
        locked = self.run_login([])[0]
        self.assertEqual(locked.status_code, 429)
        self.assertEqual(locked.headers["Retry-After"], "300")
        # Already locked: rejected before the database is touched at all.
        again, calls = self.run_login([])
        self.assertEqual(again.status_code, 429)
        self.assertEqual(calls, 0)

    def test_attempt_map_is_bounded(self):
        with patch.object(login, "MAX_TRACKED_IDENTIFIERS", 20):
            for i in range(200):
                self.run_login([], identifier="user%d@example.com" % i)
            self.assertLessEqual(len(login._login_attempts), 20)

    def test_lapsed_lockouts_are_evicted(self):
        from datetime import datetime, timedelta, timezone
        login._login_attempts["stale@example.com"] = {
            "attempts": 6,
            "locked_until": datetime.now(timezone.utc) - timedelta(hours=1)}
        self.run_login([], identifier="fresh@example.com")
        self.assertNotIn("stale@example.com", login._login_attempts)


class GetUserByIdentifierTests(unittest.TestCase):
    def resolve(self, rows, identifier="student@example.com"):
        with patch.object(login, "supabase") as database:
            chain = database.table.return_value.select.return_value.eq.return_value
            chain.execute.return_value = SimpleNamespace(data=rows)
            try:
                return login.get_user_by_identifier(identifier), chain.execute.call_count
            except Exception as error:
                return error, chain.execute.call_count

    def test_resolves_in_one_round_trip(self):
        result, calls = self.resolve([dict(INFO, user=USER)])
        self.assertEqual(calls, 1)
        self.assertEqual(result, {"email": "student@example.com",
                                  "username": "student", "info_id": 5})

    def test_the_four_not_found_cases_keep_their_messages(self):
        self.assertEqual(self.resolve([])[0].detail, "Account not found.")
        self.assertEqual(self.resolve([dict(INFO, user=None)])[0].detail,
                         "User account not found.")
        self.assertEqual(self.resolve([], identifier="student")[0].detail,
                         "Account not found.")
        self.assertEqual(self.resolve([dict(USER, userInfo=None)], identifier="student")[0].detail,
                         "User information not found.")


if __name__ == "__main__":
    unittest.main()
