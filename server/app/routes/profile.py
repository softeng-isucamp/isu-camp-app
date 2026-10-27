import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from postgrest.exceptions import APIError

from app.database.supabase import supabase
from app.utils.session import current_user_id

router = APIRouter(prefix='/profile', tags=['Profile'])


class UpdateProfileRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    username: str


def read_profile(user_id: int):
    user = supabase.table('user').select('id, username, info_id').eq('id', user_id).execute()
    if not user.data:
        raise HTTPException(404, 'User account not found.')
    row = user.data[0]
    info = supabase.table('userInfo').select('email').eq('id', row['info_id']).execute()
    if not info.data:
        raise HTTPException(404, 'User information not found.')
    return {'username': row['username'], 'email': info.data[0]['email']}


@router.get('')
def get_profile(user_id: int = Depends(current_user_id)):
    try:
        return read_profile(user_id)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, 'Could not load your profile. Please try again.') from None


@router.patch('')
def update_profile(data: UpdateProfileRequest, user_id: int = Depends(current_user_id)):
    username = data.username.strip()
    if not re.fullmatch(r'[A-Za-z0-9_]{3,30}', username):
        raise HTTPException(400, 'Use 3–30 letters, numbers, or underscores for your username.')
    try:
        current = read_profile(user_id)
        if current['username'] == username:
            return current
        # Case-insensitive duplicate checks; escaped underscore is literal in LIKE.
        matches = supabase.table('user').select('id').ilike('username', username.replace('_', r'\_')).execute()
        if any(row['id'] != user_id for row in matches.data):
            raise HTTPException(409, 'Username is already taken.')
        updated = supabase.table('user').update({'username': username}).eq('id', user_id).execute()
        if not updated.data:
            raise HTTPException(503, 'Could not save your username. Please try again.')
        return dict(current, username=updated.data[0]['username'])
    except HTTPException:
        raise
    except APIError as error:
        if error.code == '23505':
            raise HTTPException(409, 'Username is already taken.') from None
        raise HTTPException(503, 'Could not save your username. Please try again.') from None
    except Exception:
        raise HTTPException(503, 'Could not save your username. Please try again.') from None
