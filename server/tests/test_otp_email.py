import os
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.routes import auth, login
from app.utils import email as email_util

MAIL_ENV = {
    "MAIL_SERVER": "smtp.resend.com", "MAIL_PORT": "587", "MAIL_USE_TLS": "True",
    "MAIL_USERNAME": "resend", "MAIL_PASSWORD": "re_test",
    "MAIL_DEFAULT_SENDER": "no-reply@example.com",
}


class OtpEmailTests(unittest.TestCase):
    def setUp(self):
        email_util.mail_config.cache_clear()
        self.addCleanup(email_util.mail_config.cache_clear)
        app = FastAPI()
        app.include_router(auth.router)
        app.include_router(login.router)
        self.client = TestClient(app)

        self.db = MagicMock()
        # No existing email/username, so signup proceeds to the OTP step.
        self.db.table.return_value.select.return_value.eq.return_value.execute.return_value = \
            SimpleNamespace(data=[])
        for module in (auth, login):
            patcher = patch.object(module, "supabase", self.db)
            patcher.start()
            self.addCleanup(patcher.stop)

    def request_otp(self):
        return self.client.post("/auth/signup/request-otp",
                                json={"username": "student", "email": "student@example.com"})

    def test_otp_is_delivered_after_the_response(self):
        order = []
        with patch.dict(os.environ, MAIL_ENV), \
                patch.object(email_util, "deliver",
                             side_effect=lambda *a: order.append("delivered")) as deliver:
            result = self.request_otp()
            # TestClient runs background tasks before returning, so by here the
            # send has happened - but it happened *after* the handler returned.
            self.assertEqual(result.status_code, 200)
            self.assertTrue(result.json()["success"])
        deliver.assert_called_once()
        self.assertEqual(order, ["delivered"])

    def test_the_handler_itself_never_opens_smtp(self):
        """The OTP send must be queued, not called inline."""
        with patch.dict(os.environ, MAIL_ENV), \
                patch.object(email_util, "deliver") as deliver:
            background = None
            original = email_util.queue_otp_email

            def spy(bg, recipient, otp):
                nonlocal background
                original(bg, recipient, otp)
                background = bg
                # Nothing may have been delivered at the point the handler runs.
                deliver.assert_not_called()

            with patch.object(auth, "queue_otp_email", spy):
                self.assertEqual(self.request_otp().status_code, 200)
        self.assertIsNotNone(background)
        deliver.assert_called_once()

    def test_unconfigured_mail_is_still_reported_to_the_caller(self):
        with patch.dict(os.environ, {k: "" for k in MAIL_ENV}, clear=False), \
                patch.dict(os.environ, {"EMAIL_USERNAME": "", "EMAIL_PASSWORD": ""}), \
                patch.object(email_util, "deliver") as deliver:
            result = self.request_otp()
        self.assertEqual(result.status_code, 503)
        self.assertIn("not configured", result.json()["detail"])
        deliver.assert_not_called()

    def test_delivery_failure_is_logged_not_raised(self):
        with patch.dict(os.environ, MAIL_ENV), \
                patch.object(email_util, "deliver",
                             side_effect=HTTPException(503, "Could not send the verification code.")):
            with self.assertLogs("app.utils.email", "ERROR"):
                result = self.request_otp()
        self.assertEqual(result.status_code, 200,
                         "a provider outage must not fail a request that already succeeded")

    def test_forgot_password_also_queues(self):
        self.db.table.return_value.select.return_value.eq.return_value.execute.return_value =             SimpleNamespace(data=[{"id": 5, "email": "student@example.com",
                                   "user": {"id": 11, "username": "student"}}])
        with patch.dict(os.environ, MAIL_ENV), patch.object(email_util, "deliver") as deliver:
            result = self.client.post("/auth/forgot-password/request-otp",
                                      json={"identifier": "student@example.com"})
        self.assertEqual(result.status_code, 200)
        deliver.assert_called_once()


if __name__ == "__main__":
    unittest.main()
