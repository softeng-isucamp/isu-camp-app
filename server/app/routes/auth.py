# Signup flow: request an OTP, verify the email, and create an account with a hashed password.
import random
import re
from typing import Literal
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr
from pwdlib import PasswordHash

from app.database.supabase import supabase
from app.utils.email import send_otp_email
from app.utils.session import issue_session, session_secret


router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

password_hash = PasswordHash.recommended()


# ==========================================
# SIGN UP - REQUEST OTP
# ==========================================

# This block checks whether a username and a valid email address have been provided.
class SignupRequest(BaseModel):
    username: str
    email: EmailStr


# This block checks email/username availability, stores the OTP, and sends it by email.
@router.post("/signup/request-otp")
def request_otp(data: SignupRequest):

    existing_email = (
        supabase
        .table("userInfo")
        .select("id")
        .eq("email", data.email)
        .execute()
    )

    if existing_email.data:
        raise HTTPException(
            status_code=400,
            detail="Email is already registered."
        )

    existing_username = (
        supabase
        .table("user")
        .select("id")
        .eq("username", data.username)
        .execute()
    )

    if existing_username.data:
        raise HTTPException(
            status_code=400,
            detail="Username is already taken."
        )

    # This block generates a six-digit OTP with a five-minute validity period.
    otp = random.randint(100000, 999999)

    expires_at = (
        datetime.now(timezone.utc)
        + timedelta(minutes=5)
    )

    # This block replaces pending verification for the same email and resets the attempt counter.
    supabase.table("pending_verification").upsert(
        {
            "email": data.email,
            "username": data.username,
            "otp": otp,
            "otp_expires_at": expires_at.isoformat(),
            "otp_attempts": 0,
            "email_verified": False
        },
        on_conflict="email"
    ).execute()

    send_otp_email(
        data.email,
        str(otp)
    )

    return {
        "success": True,
        "message": "OTP sent successfully."
    }


# ==========================================
# SIGN UP - VERIFY OTP
# ==========================================

# This block checks whether a valid email address and a numeric verification code have been provided.
class VerifyOTPRequest(BaseModel):
    email: EmailStr
    otp: int


# This block checks the attempt limit, expiration, and OTP before marking the email as verified.
@router.post("/signup/verify-otp")
def verify_otp(data: VerifyOTPRequest):

    result = (
        supabase
        .table("pending_verification")
        .select("*")
        .eq("email", data.email)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=404,
            detail="No pending verification found."
        )

    verification = result.data[0]

    if verification["otp_attempts"] >= 5:
        raise HTTPException(
            status_code=400,
            detail="Too many OTP attempts. Please request a new OTP."
        )

    expires_at = datetime.fromisoformat(
        verification["otp_expires_at"].replace(
            "Z",
            "+00:00"
        )
    )

    if datetime.now(timezone.utc) > expires_at:
        raise HTTPException(
            status_code=400,
            detail="OTP has expired. Please request a new OTP."
        )

    if verification["otp"] != data.otp:

        supabase.table("pending_verification").update(
            {
                "otp_attempts": (
                    verification["otp_attempts"] + 1
                )
            }
        ).eq(
            "email",
            data.email
        ).execute()

        raise HTTPException(
            status_code=400,
            detail="Invalid OTP."
        )

    supabase.table("pending_verification").update(
        {
            "email_verified": True
        }
    ).eq(
        "email",
        data.email
    ).execute()

    return {
        "success": True,
        "message": "Email verified successfully."
    }


# ==========================================
# SIGN UP - SET PASSWORD
# ==========================================

# This block checks whether an email, password, confirmation, and supported account type have been provided.
class SetPasswordRequest(BaseModel):
    email: EmailStr
    password: str
    confirm_password: str
    user_type: Literal["Student", "Staff", "Visitor"]


# This block requires a verified signup, validates the password, and returns a session token.
@router.post("/signup/set-password")
def set_password(data: SetPasswordRequest):
    # This block checks session configuration before writing a new account.
    session_secret()

    # This block looks for the pending signup associated with the email address.
    result = (
        supabase
        .table("pending_verification")
        .select("*")
        .eq("email", data.email)
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=404,
            detail="No pending signup found."
        )

    verification = result.data[0]

    # This block validates whether the email address has been verified.
    if not verification["email_verified"]:
        raise HTTPException(
            status_code=400,
            detail="Email has not been verified."
        )

    # This block validates whether the password contains at least eight characters.
    if len(data.password) < 8:
        raise HTTPException(
            status_code=400,
            detail="Password must be at least 8 characters long."
        )

    # This block validates whether the password contains an uppercase letter.
    if not re.search(r"[A-Z]", data.password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain an uppercase letter."
        )

    # This block validates whether the password contains a lowercase letter.
    if not re.search(r"[a-z]", data.password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain a lowercase letter."
        )

    # This block validates whether the password contains a number.
    if not re.search(r"\d", data.password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain a number."
        )

    # This block validates whether the password contains a special character.
    if not re.search(r"[^A-Za-z0-9]", data.password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain a symbol."
        )

    # This block validates whether the password and confirmation match.
    if data.password != data.confirm_password:
        raise HTTPException(
            status_code=400,
            detail="Passwords do not match."
        )

    # This block hashes the password before saving it to the database.
    hashed_password = password_hash.hash(data.password)

    # This block saves the email address, hashed password, and account type.
    user_info = (
        supabase
        .table("userInfo")
        .insert(
            {
                "email": data.email,
                "password": hashed_password,
                "user_type": data.user_type
            }
        )
        .execute()
    )

    if not user_info.data:
        raise HTTPException(
            status_code=500,
            detail="Failed to create user information."
        )

    user_info_id = user_info.data[0]["id"]

    # This block creates the username record and links it to the saved account information.
    user = (
        supabase
        .table("user")
        .insert(
            {
                "username": verification["username"],
                "info_id": user_info_id
            }
        )
        .execute()
    )

    if not user.data:
        # This block removes the account information if creating the username record returned no result.
        supabase.table("userInfo").delete().eq(
            "id",
            user_info_id
        ).execute()

        raise HTTPException(
            status_code=500,
            detail="Failed to create user account."
        )

    # This block removes the temporary verification record after the account is created.
    supabase.table("pending_verification").delete().eq(
        "email",
        data.email
    ).execute()

    return {
        "success": True,
        "message": "Account created successfully.",
        "access_token": issue_session(user.data[0]["id"]),
    }
