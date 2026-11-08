# This block sends verification OTP emails through the configured SMTP server.
import os
import smtplib
from email.message import EmailMessage

from dotenv import load_dotenv

load_dotenv()

# Subject line and opening sentence for each kind of emailed code.
OTP_PURPOSES = {
    "signup": ("ISU-CAMP Email Verification",
               "Your ISU-CAMP verification code is:"),
    "password_reset": ("ISU-CAMP Password Reset Code",
                       "Use this code to reset your ISU-CAMP password:"),
    "password_change": ("ISU-CAMP Password Change Code",
                        "Use this code to change your ISU-CAMP password:"),
    "email_change": ("ISU-CAMP Email Change Code",
                     "Use this code to confirm your new ISU-CAMP email address:"),
}


def mask_email(email: str) -> str:
    local, _, domain = email.partition("@")
    return f"{local[:1]}***@{domain}" if domain else "***"


# This block reads SMTP settings and sends a plain-text message after authenticating.
def _send(recipient: str, subject: str, body: str):
    smtp_host = os.getenv("MAIL_SERVER", "smtp.gmail.com")
    smtp_port = int(os.getenv("MAIL_PORT", "587"))
    use_tls = os.getenv("MAIL_USE_TLS", "True").strip().lower() in {
        "1", "true", "yes", "on"
    }
    username = os.getenv("MAIL_USERNAME") or os.getenv("EMAIL_USERNAME")
    password = os.getenv("MAIL_PASSWORD") or os.getenv("EMAIL_PASSWORD")
    sender = os.getenv("MAIL_DEFAULT_SENDER") or username

    if not username or not password or not sender:
        raise RuntimeError("SMTP email settings are not configured")

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = sender
    message["To"] = recipient
    message.set_content(body)

    with smtplib.SMTP(smtp_host, smtp_port) as server:
        # When enabled, upgrades the SMTP connection with STARTTLS before logging in.
        if use_tls:
            server.starttls()
        server.login(username, password)
        server.send_message(message)


def send_otp_email(recipient: str, otp: str, purpose: str = "signup"):
    subject, intro = OTP_PURPOSES[purpose]
    _send(recipient, subject, f"""Hello,

{intro}

{otp}

This code will expire in 5 minutes.

If you did not request this code, please ignore this email.

ISU-CAMP Team
""")


# This block tells the previous address that the account email was changed.
def send_email_changed_notice(old_email: str, new_email: str):
    _send(old_email, "Your ISU-CAMP email was changed", f"""Hello,

The email address on your ISU-CAMP account was changed to {mask_email(new_email)}.

If you did not make this change, please contact the ISU-CAMP team.

ISU-CAMP Team
""")
