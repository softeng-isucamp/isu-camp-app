import random
import re
import threading
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from pwdlib import PasswordHash

from app.database.supabase import supabase
from app.utils.email import send_otp_email
from app.utils.session import issue_session


router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

password_hash = PasswordHash.recommended()

MAX_LOGIN_ATTEMPTS = 6
LOGIN_LOCKOUT_DURATION = timedelta(minutes=5)
_login_attempts = {}
_login_attempts_lock = threading.Lock()


def _login_key(identifier: str) -> str:
    return identifier.strip().casefold()


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


def _clear_login_attempts(identifier: str) -> None:
    with _login_attempts_lock:
        _login_attempts.pop(_login_key(identifier), None)


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

class LoginRequest(BaseModel):
    identifier: str
    password: str


@router.post("/login")
def login(data: LoginRequest):

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
# FORGOT PASSWORD MODELS
# ============================================================

class ForgotPasswordRequest(BaseModel):
    identifier: str


class VerifyForgotPasswordOTP(BaseModel):
    identifier: str
    otp: int


class ResetPasswordRequest(BaseModel):
    identifier: str
    password: str
    confirm_password: str


# ============================================================
# HELPER: FIND USER USING USERNAME OR EMAIL
# ============================================================

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

@router.post("/forgot-password/request-otp")
def forgot_password_request_otp(
    data: ForgotPasswordRequest
):

    user = get_user_by_identifier(
        data.identifier
    )

    email = user["email"]
    username = user["username"]

    otp = random.randint(
        100000,
        999999
    )

    expires_at = (
        datetime.now(timezone.utc)
        + timedelta(minutes=5)
    )

    try:
        # ======================================
        # SAVE OTP TO pending_verification
        # ======================================

        supabase.table(
            "pending_verification"
        ).upsert(
            {
                "email": email,
                "username": username,
                "otp": otp,
                "otp_expires_at": expires_at.isoformat(),
                "otp_attempts": 0,
                "email_verified": False
            },
            on_conflict="email"
        ).execute()

        # ======================================
        # SEND EMAIL
        # ======================================

        send_otp_email(
            email,
            str(otp)
        )

    except Exception as e:

        # Remove OTP if email sending failed
        try:
            (
                supabase
                .table("pending_verification")
                .delete()
                .eq("email", email)
                .execute()
            )
        except Exception:
            pass

        raise HTTPException(
            status_code=500,
            detail=f"Failed to send OTP: {str(e)}"
        )

    return {
        "success": True,
        "message": "Password reset OTP sent successfully."
    }


# ============================================================
# FORGOT PASSWORD - VERIFY OTP
# ============================================================

@router.post("/forgot-password/verify-otp")
def forgot_password_verify_otp(
    data: VerifyForgotPasswordOTP
):

    user = get_user_by_identifier(
        data.identifier
    )

    email = user["email"]

    result = (
        supabase
        .table("pending_verification")
        .select("*")
        .eq("email", email)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=404,
            detail="No verification request found. Please request a new OTP."
        )

    verification = result.data[0]

    # ======================================
    # CHECK ATTEMPTS
    # ======================================

    attempts = (
        verification.get("otp_attempts")
        or 0
    )

    if attempts >= 5:

        (
            supabase
            .table("pending_verification")
            .delete()
            .eq("email", email)
            .execute()
        )

        raise HTTPException(
            status_code=400,
            detail="Too many incorrect attempts. Please request a new OTP."
        )

    # ======================================
    # CHECK OTP EXPIRATION
    # ======================================

    expiry_string = verification.get(
        "otp_expires_at"
    )

    if not expiry_string:
        raise HTTPException(
            status_code=400,
            detail="OTP expiration information is missing."
        )

    expiry = datetime.fromisoformat(
        expiry_string.replace(
            "Z",
            "+00:00"
        )
    )

    if datetime.now(timezone.utc) > expiry:

        (
            supabase
            .table("pending_verification")
            .delete()
            .eq("email", email)
            .execute()
        )

        raise HTTPException(
            status_code=400,
            detail="OTP expired. Please request a new OTP."
        )

    # ======================================
    # VERIFY OTP
    # ======================================

    if int(verification["otp"]) != data.otp:

        attempts += 1

        (
            supabase
            .table("pending_verification")
            .update(
                {
                    "otp_attempts": attempts
                }
            )
            .eq("email", email)
            .execute()
        )

        remaining = 5 - attempts

        raise HTTPException(
            status_code=400,
            detail=f"Invalid OTP. {remaining} attempt(s) remaining."
        )

    # ======================================
    # MARK OTP AS VERIFIED
    # ======================================

    (
        supabase
        .table("pending_verification")
        .update(
            {
                "email_verified": True
            }
        )
        .eq("email", email)
        .execute()
    )

    return {
        "success": True,
        "message": "OTP verified successfully."
    }


# ============================================================
# FORGOT PASSWORD - RESET PASSWORD
# ============================================================

@router.post("/forgot-password/reset-password")
def forgot_password_reset_password(
    data: ResetPasswordRequest
):

    user = get_user_by_identifier(
        data.identifier
    )

    email = user["email"]

    # ======================================
    # GET OTP VERIFICATION RECORD
    # ======================================

    result = (
        supabase
        .table("pending_verification")
        .select("*")
        .eq("email", email)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=404,
            detail="No verification request found."
        )

    verification = result.data[0]

    # ======================================
    # CHECK IF OTP WAS VERIFIED
    # ======================================

    if not verification.get(
        "email_verified",
        False
    ):
        raise HTTPException(
            status_code=400,
            detail="Please verify your OTP first."
        )

    # ======================================
    # CHECK OTP EXPIRATION AGAIN
    # ======================================

    expiry_string = verification.get(
        "otp_expires_at"
    )

    if expiry_string:

        expiry = datetime.fromisoformat(
            expiry_string.replace(
                "Z",
                "+00:00"
            )
        )

        if datetime.now(timezone.utc) > expiry:

            (
                supabase
                .table("pending_verification")
                .delete()
                .eq("email", email)
                .execute()
            )

            raise HTTPException(
                status_code=400,
                detail="Verification expired. Please request a new OTP."
            )

    # ======================================
    # PASSWORDS MUST MATCH
    # ======================================

    if data.password != data.confirm_password:
        raise HTTPException(
            status_code=400,
            detail="Passwords do not match."
        )

    # ======================================
    # PASSWORD VALIDATION
    # ======================================

    if len(data.password) < 8:
        raise HTTPException(
            status_code=400,
            detail="Password must be at least 8 characters."
        )

    if not re.search(
        r"[A-Z]",
        data.password
    ):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one uppercase letter."
        )

    if not re.search(
        r"[a-z]",
        data.password
    ):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one lowercase letter."
        )

    if not re.search(
        r"[0-9]",
        data.password
    ):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one number."
        )

    if not re.search(
        r'[^A-Za-z0-9]',
        data.password
    ):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one special character."
        )

    # ======================================
    # HASH NEW PASSWORD
    # ======================================

    hashed_password = password_hash.hash(
        data.password
    )

    # ======================================
    # UPDATE USER PASSWORD
    # ======================================

    update_result = (
        supabase
        .table("userInfo")
        .update(
            {
                "password": hashed_password
            }
        )
        .eq("email", email)
        .execute()
    )

    if not update_result.data:
        raise HTTPException(
            status_code=500,
            detail="Failed to update password."
        )

    # ======================================
    # DELETE TEMPORARY VERIFICATION
    # ======================================

    (
        supabase
        .table("pending_verification")
        .delete()
        .eq("email", email)
        .execute()
    )

    # ======================================
    # SUCCESS
    # ======================================

    return {
        "success": True,
        "message": "Password reset successfully."
    }
