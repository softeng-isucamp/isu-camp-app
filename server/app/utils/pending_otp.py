# Emailed one-time codes stored in pending_verification, shared by reset and account-change flows.
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from app.database.supabase import supabase
from app.utils import otp_limits
from app.utils.email import send_otp_email

CODE_LIFETIME = timedelta(minutes=5)


def _table():
    return supabase.table("pending_verification")


def delete_pending(email: str):
    _table().delete().eq("email", email).execute()


def _expired(row) -> bool:
    value = row.get("otp_expires_at")
    if not value:
        return True
    expiry = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return datetime.now(timezone.utc) > expiry


# This block rate-limits, stores, and emails a new code; the row is removed if sending fails.
def issue_code(email: str, username: str, purpose: str, limit_subject):
    otp_limits.record_code_request(purpose, limit_subject)
    otp = 100000 + secrets.randbelow(900000)
    expires_at = datetime.now(timezone.utc) + CODE_LIFETIME
    try:
        _table().upsert({
            "email": email,
            "username": username,
            "otp": otp,
            "otp_expires_at": expires_at.isoformat(),
            "otp_attempts": 0,
            "email_verified": False,
        }, on_conflict="email").execute()
        send_otp_email(email, str(otp), purpose)
    except Exception:
        try:
            delete_pending(email)
        except Exception:
            pass
        raise HTTPException(500, "Failed to send verification code. Please try again.") from None


def _load(email: str, username: str):
    result = _table().select("*").eq("email", email).execute()
    # A row created for another account or flow (for example a signup) is not this user's code.
    if not result.data or result.data[0].get("username") != username:
        raise HTTPException(404, "No verification request found. Please request a new code.")
    return result.data[0]


# This block checks a code; wrong guesses count across resends until the lockout.
def verify_code(email: str, username: str, otp: int, purpose: str, limit_subject):
    otp_limits.ensure_can_guess(purpose, limit_subject)
    row = _load(email, username)
    if _expired(row):
        delete_pending(email)
        raise HTTPException(400, "OTP expired. Please request a new OTP.")
    if int(row["otp"]) != otp:
        remaining = otp_limits.record_wrong_guess(purpose, limit_subject)
        if remaining == 0:
            delete_pending(email)
            raise HTTPException(
                400, "Too many incorrect attempts. Please request a new OTP.",
                headers={"Retry-After": str(int(otp_limits.GUESS_LOCKOUT.total_seconds()))})
        raise HTTPException(400, f"Invalid OTP. {remaining} attempt(s) remaining.")
    otp_limits.clear_guesses(purpose, limit_subject)
    _table().update({"email_verified": True}).eq("email", email).execute()
    return row


# This block requires a verified, unexpired code before a password is replaced.
def require_verified(email: str, username: str):
    row = _load(email, username)
    if not row.get("email_verified"):
        raise HTTPException(400, "Please verify your OTP first.")
    if _expired(row):
        delete_pending(email)
        raise HTTPException(400, "Verification expired. Please request a new OTP.")
    return row
