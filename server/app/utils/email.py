"""OTP delivery over SMTP, configured per provider via the environment."""
import logging
import os
import smtplib
from email.message import EmailMessage
from functools import lru_cache

from dotenv import load_dotenv
from fastapi import HTTPException

load_dotenv()
logger = logging.getLogger(__name__)

TRUTHY = {"1", "true", "yes", "on"}


def _setting(name: str, *fallbacks: str, default: str = "") -> str:
    """First non-empty value among MAIL_* and the older EMAIL_* names."""
    for key in (name, *fallbacks):
        value = os.getenv(key, "").strip()
        if value:
            return value
    return default


@lru_cache(maxsize=1)
def mail_config():
    """Resolves SMTP settings, or raises if the service is not configured.

    Defaults target Gmail so existing EMAIL_USERNAME/EMAIL_PASSWORD setups keep
    working. Providers such as Resend authenticate with a fixed username and
    require From to be an address on a verified domain, which is why the sender
    is configured separately from the login.

    Cached: the environment does not change while the process runs. Failures
    are not cached, so fixing the environment does not need a restart.
    """
    host = _setting("MAIL_SERVER", default="smtp.gmail.com")
    port = _setting("MAIL_PORT", default="587")
    username = _setting("MAIL_USERNAME", "EMAIL_USERNAME")
    password = _setting("MAIL_PASSWORD", "EMAIL_PASSWORD")
    sender = _setting("MAIL_DEFAULT_SENDER", "EMAIL_USERNAME", default=username)
    use_tls = _setting("MAIL_USE_TLS", default="true").lower() in TRUTHY

    if not (username and password and sender):
        raise HTTPException(503, "Email service is not configured.")

    try:
        port = int(port)
    except ValueError:
        raise HTTPException(503, "Email service is not configured.") from None

    return host, port, username, password, sender, use_tls


def otp_message(sender: str, recipient: str, otp: str) -> EmailMessage:
    message = EmailMessage()
    message["Subject"] = "ISU-CAMP Email Verification"
    message["From"] = sender
    message["To"] = recipient

    message.set_content(
        f"""Hello,

Your ISU-CAMP verification code is:

{otp}

This code will expire in 5 minutes.

If you did not request this code, please ignore this email.

ISU-CAMP Team
"""
    )
    return message


def deliver(config, message):
    """Open SMTP and send. Blocks for the whole handshake, login and send."""
    host, port, username, password, _sender, use_tls = config
    try:
        with smtplib.SMTP(host, port, timeout=20) as server:
            if use_tls:
                server.starttls()
            server.login(username, password)
            server.send_message(message)
    except smtplib.SMTPAuthenticationError:
        raise HTTPException(
            503, "Email service rejected the credentials."
        ) from None
    except (smtplib.SMTPException, OSError):
        raise HTTPException(
            503, "Could not send the verification code. Please try again."
        ) from None


def send_otp_email(recipient: str, otp: str):
    """Send now, blocking the caller until the provider accepts the message."""
    config = mail_config()
    deliver(config, otp_message(config[4], recipient, otp))


def _deliver_in_background(config, message, recipient):
    """The response is already sent, so a failure can only be logged."""
    try:
        deliver(config, message)
    except HTTPException as error:
        logger.error("Could not deliver the OTP to %s: %s", recipient, error.detail)
    except Exception:
        logger.exception("Could not deliver the OTP to %s", recipient)


def queue_otp_email(background, recipient: str, otp: str):
    """Send after the response, so the user does not wait out the SMTP handshake.

    Configuration is still validated synchronously, so an unconfigured mail
    service is reported to the caller as before. Only the network round trip
    moves: if delivery then fails, the pending_verification row expires on its
    own in five minutes and the user's recovery is to ask for another code.
    """
    config = mail_config()
    background.add_task(
        _deliver_in_background, config, otp_message(config[4], recipient, otp), recipient)
