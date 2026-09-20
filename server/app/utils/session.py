"""Signed sessions for the application's existing custom user table."""
import os
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
