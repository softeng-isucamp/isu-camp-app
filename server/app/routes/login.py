# Login and password recovery endpoints, including failed-login lockout.
import threading
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from pwdlib import PasswordHash

from app.database.supabase import supabase
from app.utils.email import mask_email
from app.utils.passwords import ensure_different_password, validate_new_password
from app.utils.pending_otp import delete_pending, issue_code, require_verified, verify_code
from app.utils.session import issue_session
from app.utils.captcha import verify_captcha


router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

password_hash = PasswordHash.recommended()

MAX_LOGIN_ATTEMPTS = 6
LOGIN_LOCKOUT_DURATION = timedelta(minutes=5)
# Attempt counters are stored in memory, separately per server process, and reset on restart.
_login_attempts = {}
# This block protects counter updates against concurrent requests within this process.
_login_attempts_lock = threading.Lock()


# This block normalizes case and surrounding whitespace for a consistent lockout key.
def _login_key(identifier: str) -> str:
    return identifier.strip().casefold()


# This block reads the remaining lockout time and removes the state when the lockout expires.
def _remaining_lockout(identifier: str) -> int:
    """Return remaining lockout seconds for an identifier, or 0 if unlocked."""
    key = _login_key(identifier)
    now = datetime.now(timezone.utc)
    with _login_attempts_lock:
        state = _login_attempts.get(key)
        if not state or not state.get("locked_until"):
            return 0
        remaining = int((state["locked_until"] - now).total_seconds())
        if remaining <= 0:
            _login_attempts.pop(key, None)
            return 0
        return remaining + 1


# This block increments failed attempts and starts a five-minute lockout on the sixth failure.
def _record_failed_login(identifier: str) -> tuple[int, int]:
    """Record a failed attempt and return (attempt count, lockout seconds)."""
    key = _login_key(identifier)
    now = datetime.now(timezone.utc)
    with _login_attempts_lock:
        state = _login_attempts.setdefault(key, {"attempts": 0})
        state["attempts"] += 1
        if state["attempts"] >= MAX_LOGIN_ATTEMPTS:
            state["locked_until"] = now + LOGIN_LOCKOUT_DURATION
            return state["attempts"], int(LOGIN_LOCKOUT_DURATION.total_seconds())
        return state["attempts"], 0


# This block resets failed attempts for the identifier after a successful login.
def _clear_login_attempts(identifier: str) -> None:
    with _login_attempts_lock:
        _login_attempts.pop(_login_key(identifier), None)


# This block raises 401 or 429 with attempt counts and, during lockout, a retry time in the headers.
def _invalid_login(identifier: str):
    attempts, lockout_seconds = _record_failed_login(identifier)
    headers = {
        "X-Login-Attempts": str(attempts),
        "X-Login-Attempts-Remaining": str(max(MAX_LOGIN_ATTEMPTS - attempts, 0)),
    }
    if lockout_seconds:
        headers["Retry-After"] = str(lockout_seconds)
        raise HTTPException(
            status_code=429,
            detail="Too many failed login attempts. Please try again in 5 minutes.",
            headers=headers,
        )
    raise HTTPException(
        status_code=401,
        detail="Invalid username/email or password.",
        headers=headers,
    )


# ==========================================
# LOGIN
# ==========================================

# This block checks whether a username or email and a password have been provided.
class LoginRequest(BaseModel):
    identifier: str
    password: str
    captcha_token: str = ''


# This block finds the account by email or username and verifies the password against its stored hash.
@router.post("/login")
def login(data: LoginRequest):
    verify_captcha(data.captcha_token)
    identifier = data.identifier.strip()

    remaining_lockout = _remaining_lockout(identifier)
    if remaining_lockout:
        raise HTTPException(
            status_code=429,
            detail="Too many failed login attempts. Please try again in 5 minutes.",
            headers={
                "Retry-After": str(remaining_lockout),
                "X-Login-Attempts": str(MAX_LOGIN_ATTEMPTS),
                "X-Login-Attempts-Remaining": "0",
            },
        )

    # ======================================
    # LOGIN USING EMAIL
    # ======================================

    if "@" in identifier:

        result = (
            supabase
            .table("userInfo")
            .select("id, email, password")
            .eq("email", identifier)
            .execute()
        )

        if not result.data:
            _invalid_login(identifier)

        user_info = result.data[0]

    # ======================================
    # LOGIN USING USERNAME
    # ======================================

    else:

        user_result = (
            supabase
            .table("user")
            .select("id, username, info_id")
            .eq("username", identifier)
            .execute()
        )

        if not user_result.data:
            _invalid_login(identifier)

        user = user_result.data[0]

        user_info_result = (
            supabase
            .table("userInfo")
            .select("id, email, password")
            .eq("id", user["info_id"])
            .execute()
        )

        if not user_info_result.data:
            _invalid_login(identifier)

        user_info = user_info_result.data[0]

    # ======================================
    # VERIFY PASSWORD
    # ======================================

    try:
        password_valid = password_hash.verify(
            data.password,
            user_info["password"]
        )
    except Exception:
        password_valid = False

    if not password_valid:
        _invalid_login(identifier)

    # ======================================
    # GET USER
    # ======================================

    user_result = (
        supabase
        .table("user")
        .select("id, username, info_id")
        .eq("info_id", user_info["id"])
        .execute()
    )

    if not user_result.data:
        raise HTTPException(
            status_code=404,
            detail="User account not found."
        )

    _clear_login_attempts(identifier)

    user = user_result.data[0]

    # ======================================
    # SUCCESS
    # ======================================

    return {
        "success": True,
        "message": "Login successful.",
        "access_token": issue_session(user["id"]),
        "user": {
            "id": user["id"],
            "username": user["username"],
            "email": user_info["email"]
        }
    }


# ============================================================
# FORGOT PASSWORD INPUT CHECKS
# ============================================================

# This block checks whether a username or email has been provided for account recovery.
class ForgotPasswordRequest(BaseModel):
    identifier: str


# This block checks whether an account identifier and a numeric recovery code have been provided.
class VerifyForgotPasswordOTP(BaseModel):
    identifier: str
    otp: int


# This block checks whether an account identifier, new password, and confirmation have been provided.
class ResetPasswordRequest(BaseModel):
    identifier: str
    password: str
    confirm_password: str


# ============================================================
# HELPER: FIND USER USING USERNAME OR EMAIL
# ============================================================

# This block finds linked user/userInfo records and returns the email used for account recovery.
def get_user_by_identifier(identifier: str):

    identifier = identifier.strip()

    # ======================================
    # IDENTIFIER IS EMAIL
    # ======================================

    if "@" in identifier:

        info_result = (
            supabase
            .table("userInfo")
            .select("id, email")
            .eq("email", identifier)
            .execute()
        )

        if not info_result.data:
            raise HTTPException(
                status_code=404,
                detail="Account not found."
            )

        user_info = info_result.data[0]

        user_result = (
            supabase
            .table("user")
            .select("id, username, info_id")
            .eq("info_id", user_info["id"])
            .execute()
        )

        if not user_result.data:
            raise HTTPException(
                status_code=404,
                detail="User account not found."
            )

        user = user_result.data[0]

        return {
            "email": user_info["email"],
            "username": user["username"],
            "info_id": user_info["id"]
        }

    # ======================================
    # IDENTIFIER IS USERNAME
    # ======================================

    user_result = (
        supabase
        .table("user")
        .select("id, username, info_id")
        .eq("username", identifier)
        .execute()
    )

    if not user_result.data:
        raise HTTPException(
            status_code=404,
            detail="Account not found."
        )

    user = user_result.data[0]

    info_result = (
        supabase
        .table("userInfo")
        .select("id, email")
        .eq("id", user["info_id"])
        .execute()
    )

    if not info_result.data:
        raise HTTPException(
            status_code=404,
            detail="User information not found."
        )

    user_info = info_result.data[0]

    return {
        "email": user_info["email"],
        "username": user["username"],
        "info_id": user_info["id"]
    }


# ============================================================
# FORGOT PASSWORD - REQUEST OTP
# ============================================================

# This block emails a rate-limited recovery code to the account's registered address.
@router.post("/forgot-password/request-otp")
def forgot_password_request_otp(
    data: ForgotPasswordRequest
):
    user = get_user_by_identifier(data.identifier)
    issue_code(user["email"], user["username"], "password_reset", user["email"])
    return {
        "success": True,
        "message": "Password reset OTP sent successfully.",
        "sent_to": mask_email(user["email"]),
    }


# ============================================================
# FORGOT PASSWORD - VERIFY OTP
# ============================================================

# This block validates the recovery OTP and marks the pending record as verified.
@router.post("/forgot-password/verify-otp")
def forgot_password_verify_otp(
    data: VerifyForgotPasswordOTP
):
    user = get_user_by_identifier(data.identifier)
    verify_code(user["email"], user["username"], data.otp, "password_reset", user["email"])
    return {
        "success": True,
        "message": "OTP verified successfully."
    }


# ============================================================
# FORGOT PASSWORD - RESET PASSWORD
# ============================================================

# This block requires a verified, unexpired OTP before replacing the password hash.
@router.post("/forgot-password/reset-password")
def forgot_password_reset_password(
    data: ResetPasswordRequest
):
    user = get_user_by_identifier(data.identifier)
    email = user["email"]
    require_verified(email, user["username"])
    validate_new_password(data.password, data.confirm_password)

    current = (
        supabase
        .table("userInfo")
        .select("password")
        .eq("id", user["info_id"])
        .execute()
    )
    ensure_different_password(data.password, current.data[0].get("password") if current.data else None)

    update_result = (
        supabase
        .table("userInfo")
        .update({"password": password_hash.hash(data.password)})
        .eq("id", user["info_id"])
        .execute()
    )
    if not update_result.data:
        raise HTTPException(
            status_code=500,
            detail="Failed to update password."
        )

    delete_pending(email)
    return {
        "success": True,
        "message": "Password reset successfully."
    }
