import unittest
from unittest.mock import Mock, patch
from pydantic import ValidationError
from fastapi import HTTPException
from app.routes import auth


class SignupUserTypeTests(unittest.TestCase):
    def request(self, user_type):
        return auth.SetPasswordRequest(email='signup@example.com', password='Testing9!',
            confirm_password='Testing9!', user_type=user_type)

    def test_each_type_is_saved_to_user_info(self):
        for user_type in ('Student', 'Staff', 'Visitor'):
            with self.subTest(user_type=user_type):
                pending, info, user = Mock(), Mock(), Mock()
                pending.select.return_value.eq.return_value.execute.return_value.data = [
                    {'email_verified': True, 'username': 'signup'}]
                info.insert.return_value.execute.return_value.data = [{'id': 11}]
                user.insert.return_value.execute.return_value.data = [{'id': 22}]
                database = Mock()
                database.table.side_effect = lambda table: {'pending_verification': pending,
                    'userInfo': info, 'user': user}[table]
                with patch.object(auth, 'supabase', database), \
                     patch.object(auth, 'session_secret'), \
                     patch.object(auth, 'password_hash') as hasher, \
                     patch.object(auth, 'issue_session', return_value='test-token'):
                    hasher.hash.return_value = 'hashed-password'
                    result = auth.set_password(self.request(user_type))
                self.assertTrue(result['success'])
                info.insert.assert_called_once_with({'email': 'signup@example.com',
                    'password': 'hashed-password', 'user_type': user_type})
                user.insert.assert_called_once_with({'username': 'signup', 'info_id': 11})

    def test_unknown_or_missing_type_is_rejected(self):
        for user_type in ('Teacher', 'Admin', '', None):
            with self.subTest(user_type=user_type), self.assertRaises(ValidationError):
                self.request(user_type)
        with self.assertRaises(ValidationError):
            auth.SetPasswordRequest(email='signup@example.com', password='Testing9!', confirm_password='Testing9!')

    def test_unverified_email_does_not_write_user_type(self):
        database = Mock()
        database.table.return_value.select.return_value.eq.return_value.execute.return_value.data = [
            {'email_verified': False, 'username': 'signup'}]
        with patch.object(auth, 'supabase', database), patch.object(auth, 'session_secret'):
            with self.assertRaises(HTTPException):
                auth.set_password(self.request('Staff'))
        database.table.return_value.insert.assert_not_called()


if __name__ == '__main__':
    unittest.main()
