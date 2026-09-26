"""Refresh and revoke opaque history sessions."""
from fastapi import APIRouter
from pydantic import BaseModel

from app.database.supabase import supabase
from app.utils.session import issue_session, refresh_session, revoke_refresh_session

router = APIRouter(prefix="/auth", tags=["Authentication"])


class RefreshRequest(BaseModel):
    refresh_token: str


class RevokeRequest(BaseModel):
    refresh_token: str


@router.post("/refresh")
def refresh(data: RefreshRequest):
    user_id, replacement = refresh_session(data.refresh_token, supabase)
    return {"access_token": issue_session(user_id), "refresh_token": replacement,
            "token_type": "bearer"}


@router.post("/logout")
def revoke(data: RevokeRequest):
    revoke_refresh_session(data.refresh_token, supabase)
    return {"success": True}
