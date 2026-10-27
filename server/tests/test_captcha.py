import os
import unittest
from unittest.mock import patch, Mock

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from app.routes import captcha, login
from app.utils.captcha import verify_captcha


class CaptchaTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {
            'RECAPTCHA_SITE_KEY': 'public-key', 'RECAPTCHA_SECRET_KEY': 'secret-key',
            'RECAPTCHA_ALLOWED_HOSTNAMES': 'api.example.com,localhost',
            'RECAPTCHA_PARENT_ORIGINS': 'https://app.example.com',
        })
        env.start()
        self.addCleanup(env.stop)
        app = FastAPI()
        app.include_router(captcha.router)
        app.include_router(login.router)
        self.client = TestClient(app)

    def test_missing_configuration_and_missing_token_cannot_pass(self):
        with patch.dict(os.environ, {'RECAPTCHA_SECRET_KEY': ''}):
            response = self.client.get('/auth/captcha/config')
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json()['detail']['code'], 'captcha_not_configured')
            self.assertNotIn('secret-key', response.text)
        result = self.client.post('/auth/login', json={'identifier': 'Karl', 'password': 'password'})
        self.assertEqual(result.status_code, 400)

    def test_success_requires_google_verification_and_allowed_hostname(self):
        response = Mock()
        response.json.return_value = {'success': True, 'hostname': 'api.example.com'}
        with patch('app.utils.captcha.httpx.post', return_value=response) as post:
            verify_captcha('real-token')
        self.assertEqual(post.call_args.kwargs['data'], {'secret': 'secret-key', 'response': 'real-token'})
        self.assertEqual(post.call_args.kwargs['timeout'], 10)
        for result in [{'success': False, 'error-codes': ['timeout-or-duplicate']},
                       {'success': True, 'hostname': 'attacker.example.com'},
                       {'success': True}]:
            response.json.return_value = result
            with patch('app.utils.captcha.httpx.post', return_value=response), self.assertRaises(HTTPException) as error:
                verify_captcha('bad-token')
            self.assertEqual(error.exception.status_code, 400)

    def test_provider_failure_is_unavailable_and_never_bypassed(self):
        with patch('app.utils.captcha.httpx.post', side_effect=httpx.ConnectError('offline')), self.assertRaises(HTTPException) as error:
            verify_captcha('token')
        self.assertEqual(error.exception.status_code, 503)

    def test_page_exposes_only_public_key_and_limits_parent_origin(self):
        response = self.client.get('/auth/captcha?parent_origin=https://app.example.com')
        self.assertEqual(response.status_code, 200)
        self.assertIn('public-key', response.text)
        self.assertNotIn('secret-key', response.text)
        self.assertIn('Cache-Control', response.headers)
        self.assertEqual(self.client.get('/auth/captcha?parent_origin=https://evil.example.com').status_code, 403)
        self.assertEqual(self.client.get('/auth/captcha').status_code, 200)

    def test_config_checks_browser_origin_before_opening_challenge(self):
        self.assertEqual(self.client.get('/auth/captcha/config', params={
            'parent_origin': 'https://app.example.com',
        }).status_code, 200)
        response = self.client.get('/auth/captcha/config', params={
            'parent_origin': 'http://localhost:9999',
        })
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()['detail']['code'], 'captcha_origin_not_allowed')

    def test_invalid_captcha_stops_login_before_credentials_lookup(self):
        response = Mock()
        response.json.return_value = {'success': False}
        with patch('app.utils.captcha.httpx.post', return_value=response), patch.object(login, 'supabase') as database:
            self.assertEqual(self.client.post('/auth/login', json={
                'identifier': 'Karl', 'password': 'test', 'captcha_token': 'bad-token',
            }).status_code, 400)
            database.table.assert_not_called()


if __name__ == '__main__':
    unittest.main()
