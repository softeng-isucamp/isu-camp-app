"""Signed sessions for the application's existing custom user table."""
import os
import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from dotenv import load_dotenv
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

load_dotenv()
bearer = HTTPBearer(auto_error=False)


def session_secret():
    secret = os.getenv("SESSION_SECRET", "")
    if len(secret) < 32:
        raise HTTPException(503, "Session service is not configured.")
    return secret


def issue_session(user_id):
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": str(user_id), "iat": now,
                       "exp": now + timedelta(hours=24),
                       "aud": "isu-camp", "iss": "isu-camp-backend"},
                      session_secret(), algorithm="HS256")


REFRESH_LIFETIME = timedelta(days=90)


def _refresh_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def issue_refresh_session(user_id, database):
    """Persist only a digest of a new opaque refresh credential."""
    token = secrets.token_urlsafe(48)
    database.table("HistoryRefreshSession").insert({
        "token_hash": _refresh_hash(token),
        "user_id": int(user_id),
        "expires_at": (datetime.now(timezone.utc) + REFRESH_LIFETIME).isoformat(),
    }).execute()
    return token


def refresh_session(token: str, database):
    """Atomically consume a refresh credential and issue its replacement."""
    if not token or len(token) > 256:
        raise HTTPException(401, "Your session has expired. Please log in again.")
    replacement = secrets.token_urlsafe(48)
    result = database.rpc("refresh_history_session", {
        "p_token_hash": _refresh_hash(token),
        "p_new_token_hash": _refresh_hash(replacement),
        "p_new_expires_at": (datetime.now(timezone.utc) + REFRESH_LIFETIME).isoformat(),
    }).execute()
    rows = getattr(result, "data", None)
    if not rows:
        raise HTTPException(401, "Your session has expired. Please log in again.")
    row = rows[0] if isinstance(rows, list) else rows
    return int(row["user_id"]), replacement


def revoke_refresh_session(token: str, database):
    if token and len(token) <= 256:
        database.table("HistoryRefreshSession").update({
            "revoked_at": datetime.now(timezone.utc).isoformat(),
        }).eq("token_hash", _refresh_hash(token)).is_("revoked_at", "null").execute()


def current_user_id(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if credentials is None:
        raise HTTPException(401, "Please log in to access your history.")
    try:
        claims = jwt.decode(credentials.credentials, session_secret(),
                            algorithms=["HS256"], audience="isu-camp",
                            issuer="isu-camp-backend",
                            options={"require": ["sub", "exp", "iat"]})
        user_id = int(claims["sub"])
        if user_id <= 0:
            raise ValueError()
        return user_id
    except (jwt.InvalidTokenError, ValueError, TypeError):
        raise HTTPException(401, "Your session has expired. Please log in again.") from None
