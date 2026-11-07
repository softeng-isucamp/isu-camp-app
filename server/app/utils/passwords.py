# Shared password rules for password reset and password change.
import re

from fastapi import HTTPException
from pwdlib import PasswordHash

password_hash = PasswordHash.recommended()


# This block enforces matching confirmation, length, and character-class rules.
def validate_new_password(password: str, confirm_password: str):
    if password != confirm_password:
        raise HTTPException(400, "Passwords do not match.")
    if len(password) < 8:
        raise HTTPException(400, "Password must be at least 8 characters.")
    if not re.search(r"[A-Z]", password):
        raise HTTPException(400, "Password must contain at least one uppercase letter.")
    if not re.search(r"[a-z]", password):
        raise HTTPException(400, "Password must contain at least one lowercase letter.")
    if not re.search(r"[0-9]", password):
        raise HTTPException(400, "Password must contain at least one number.")
    if not re.search(r"[^A-Za-z0-9]", password):
        raise HTTPException(400, "Password must contain at least one special character.")


# This block rejects a new password that matches the stored hash.
def ensure_different_password(password: str, current_hash):
    if not current_hash:
        return
    try:
        same = password_hash.verify(password, current_hash)
    except Exception:
        same = False
    if same:
        raise HTTPException(400, "New password must be different from your current password.")
