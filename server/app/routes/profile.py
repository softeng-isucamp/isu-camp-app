import re
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, EmailStr
from postgrest.exceptions import APIError

from app.database.supabase import supabase
from app.utils import otp_limits
from app.utils.email import mask_email, send_email_changed_notice
from app.utils.passwords import ensure_different_password, password_hash, validate_new_password
from app.utils.pending_otp import delete_pending, issue_code, require_verified, verify_code
from app.utils.session import current_user_id

router = APIRouter(prefix='/profile', tags=['Profile'])


UserType = Literal['Student', 'Staff', 'Visitor']


class UpdateProfileRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    username: Optional[str] = None
    # Self-declared at signup and not verified, so the owner may change it freely.
    user_type: Optional[UserType] = None


def read_profile(user_id: int):
    user = supabase.table('user').select('id, username, info_id').eq('id', user_id).execute()
    if not user.data:
        raise HTTPException(404, 'User account not found.')
    row = user.data[0]
    info = supabase.table('userInfo').select('email, user_type').eq('id', row['info_id']).execute()
    if not info.data:
        raise HTTPException(404, 'User information not found.')
    # Older accounts may have no type saved; the app shows that as "Not set".
    return {'username': row['username'], 'email': info.data[0]['email'],
            'user_type': info.data[0].get('user_type'), 'info_id': row['info_id']}


def _public(profile: dict):
    return {key: profile[key] for key in ('username', 'email', 'user_type')}


@router.get('')
def get_profile(user_id: int = Depends(current_user_id)):
    try:
        return _public(read_profile(user_id))
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, 'Could not load your profile. Please try again.') from None


@router.patch('')
def update_profile(data: UpdateProfileRequest, user_id: int = Depends(current_user_id)):
    if data.username is None and data.user_type is None:
        raise HTTPException(400, 'Nothing to update.')
    username = None if data.username is None else data.username.strip()
    if username is not None and not re.fullmatch(r'[A-Za-z0-9_]{3,30}', username):
        raise HTTPException(400, 'Use 3–30 letters, numbers, or underscores for your username.')
    try:
        current = read_profile(user_id)
        if username is not None and current['username'] != username:
            current = _update_username(current, username, user_id)
        if data.user_type is not None and current['user_type'] != data.user_type:
            updated = supabase.table('userInfo').update(
                {'user_type': data.user_type}).eq('id', current['info_id']).execute()
            if not updated.data:
                raise HTTPException(503, 'Could not save your account type. Please try again.')
            current = dict(current, user_type=updated.data[0]['user_type'])
        return _public(current)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, 'Could not save your profile. Please try again.') from None


def _update_username(current: dict, username: str, user_id: int):
    # Case-insensitive duplicate checks; escaped underscore is literal in LIKE.
    matches = supabase.table('user').select('id').ilike('username', username.replace('_', r'\_')).execute()
    if any(row['id'] != user_id for row in matches.data):
        raise HTTPException(409, 'Username is already taken.')
    try:
        updated = supabase.table('user').update({'username': username}).eq('id', user_id).execute()
    except APIError as error:
        if error.code == '23505':
            raise HTTPException(409, 'Username is already taken.') from None
        raise HTTPException(503, 'Could not save your username. Please try again.') from None
    if not updated.data:
        raise HTTPException(503, 'Could not save your username. Please try again.')
    return dict(current, username=updated.data[0]['username'])


# ============================================================
# ACCOUNT CHANGES (password and email) — codes are emailed, user comes from the session
# ============================================================

class VerifyCodeRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    otp: int


class ChangePasswordRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    current_password: str
    password: str
    confirm_password: str


class EmailChangeRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    email: EmailStr


class VerifyEmailChangeRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    email: EmailStr
    otp: int


def _account(user_id: int):
    user = supabase.table('user').select('id, username, info_id').eq('id', user_id).execute()
    if not user.data:
        raise HTTPException(404, 'User account not found.')
    row = user.data[0]
    info = supabase.table('userInfo').select('id, email, password').eq('id', row['info_id']).execute()
    if not info.data:
        raise HTTPException(404, 'User information not found.')
    return {'username': row['username'], 'info_id': row['info_id'],
            'email': info.data[0]['email'], 'password': info.data[0].get('password')}


def _ilike_literal(value: str) -> str:
    return value.replace('\\', '\\\\').replace('%', r'\%').replace('_', r'\_')


# This block checks that an address is not used by another account (case-insensitive).
def _ensure_email_available(email: str, info_id):
    matches = supabase.table('userInfo').select('id').ilike('email', _ilike_literal(email)).execute()
    if any(row['id'] != info_id for row in matches.data):
        raise HTTPException(409, 'That email is already in use.')


@router.post('/password/request-otp')
def request_password_change_code(user_id: int = Depends(current_user_id)):
    account = _account(user_id)
    issue_code(account['email'], account['username'], 'password_change', user_id)
    return {'success': True, 'sent_to': mask_email(account['email'])}


@router.post('/password/verify-otp')
def verify_password_change_code(data: VerifyCodeRequest, user_id: int = Depends(current_user_id)):
    account = _account(user_id)
    verify_code(account['email'], account['username'], data.otp, 'password_change', user_id)
    return {'success': True}


@router.post('/password')
def change_password(data: ChangePasswordRequest, user_id: int = Depends(current_user_id)):
    account = _account(user_id)
    require_verified(account['email'], account['username'])
    limit_purpose = 'password_change_current_password'
    otp_limits.ensure_can_guess(limit_purpose, user_id)
    try:
        current_matches = bool(account['password']) and password_hash.verify(
            data.current_password, account['password'])
    except Exception:
        current_matches = False
    if not current_matches:
        remaining = otp_limits.record_wrong_guess(limit_purpose, user_id)
        if remaining == 0:
            otp_limits.ensure_can_guess(limit_purpose, user_id)
        raise HTTPException(400, 'Current password is incorrect.')
    validate_new_password(data.password, data.confirm_password)
    ensure_different_password(data.password, account['password'])
    updated = supabase.table('userInfo').update(
        {'password': password_hash.hash(data.password)}).eq('id', account['info_id']).execute()
    if not updated.data:
        raise HTTPException(503, 'Could not update your password. Please try again.')
    delete_pending(account['email'])
    otp_limits.clear_guesses(limit_purpose, user_id)
    return {'success': True}


@router.post('/email/request-otp')
def request_email_change_code(data: EmailChangeRequest, user_id: int = Depends(current_user_id)):
    account = _account(user_id)
    email = data.email.strip()
    if email.casefold() == account['email'].casefold():
        raise HTTPException(400, 'That is already your email.')
    _ensure_email_available(email, account['info_id'])
    issue_code(email, account['username'], 'email_change', user_id)
    return {'success': True, 'sent_to': email}


# This block confirms the code sent to the new address, then applies the change.
@router.post('/email/verify-otp')
def confirm_email_change(data: VerifyEmailChangeRequest, user_id: int = Depends(current_user_id)):
    account = _account(user_id)
    email = data.email.strip()
    verify_code(email, account['username'], data.otp, 'email_change', user_id)
    _ensure_email_available(email, account['info_id'])
    try:
        updated = supabase.table('userInfo').update({'email': email}).eq('id', account['info_id']).execute()
    except APIError as error:
        if error.code == '23505':
            raise HTTPException(409, 'That email is already in use.') from None
        raise HTTPException(503, 'Could not update your email. Please try again.') from None
    if not updated.data:
        raise HTTPException(503, 'Could not update your email. Please try again.')
    delete_pending(email)
    try:
        send_email_changed_notice(account['email'], email)
    except Exception:
        pass  # The change is done; the notice is best effort.
    return {'username': account['username'], 'email': email}
