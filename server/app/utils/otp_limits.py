# In-memory limits for emailed verification codes (per server process, reset on restart).
import math
import threading
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

RESEND_COOLDOWN = timedelta(seconds=60)
REQUEST_WINDOW = timedelta(minutes=30)
MAX_REQUESTS_PER_WINDOW = 5
MAX_WRONG_GUESSES = 5
GUESS_LOCKOUT = timedelta(minutes=5)

_state = {}
_lock = threading.Lock()


def _now():
    return datetime.now(timezone.utc)


def _key(purpose: str, subject) -> tuple[str, str]:
    return purpose, str(subject).strip().casefold()


def _too_many(detail: str, until: datetime, now: datetime):
    seconds = max(1, math.ceil((until - now).total_seconds()))
    raise HTTPException(429, detail, headers={"Retry-After": str(seconds)})


def _entry(key, now):
    entry = _state.get(key)
    if entry is None or now - entry["window_start"] >= REQUEST_WINDOW:
        entry = {"window_start": now, "requests": 0, "last_request": None,
                 "wrong_guesses": 0, "locked_until": None}
        _state[key] = entry
    return entry


# This block allows a new code at most once per minute and five times per 30 minutes.
def record_code_request(purpose: str, subject):
    now = _now()
    with _lock:
        entry = _entry(_key(purpose, subject), now)
        if entry["locked_until"] and now < entry["locked_until"]:
            _too_many("Too many incorrect attempts. Please try again later.", entry["locked_until"], now)
        if entry["last_request"] and now - entry["last_request"] < RESEND_COOLDOWN:
            _too_many("Please wait before requesting another code.", entry["last_request"] + RESEND_COOLDOWN, now)
        if entry["requests"] >= MAX_REQUESTS_PER_WINDOW:
            _too_many("Too many code requests. Please try again later.", entry["window_start"] + REQUEST_WINDOW, now)
        entry["requests"] += 1
        entry["last_request"] = now


# This block rejects guesses while the subject is locked out.
def ensure_can_guess(purpose: str, subject):
    now = _now()
    with _lock:
        entry = _state.get(_key(purpose, subject))
        if entry and entry["locked_until"]:
            if now < entry["locked_until"]:
                _too_many("Too many incorrect attempts. Please try again later.", entry["locked_until"], now)
            entry["locked_until"] = None
            entry["wrong_guesses"] = 0


# This block counts wrong guesses across new codes and returns the guesses left before lockout.
def record_wrong_guess(purpose: str, subject) -> int:
    now = _now()
    with _lock:
        entry = _entry(_key(purpose, subject), now)
        entry["wrong_guesses"] += 1
        remaining = MAX_WRONG_GUESSES - entry["wrong_guesses"]
        if remaining <= 0:
            entry["locked_until"] = now + GUESS_LOCKOUT
            return 0
        return remaining


def clear_guesses(purpose: str, subject):
    with _lock:
        entry = _state.get(_key(purpose, subject))
        if entry:
            entry["wrong_guesses"] = 0
            entry["locked_until"] = None


def reset_all():
    """Test helper."""
    with _lock:
        _state.clear()
