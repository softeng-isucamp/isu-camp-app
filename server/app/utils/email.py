# This block sends verification OTP emails through the configured SMTP server.
import os
import smtplib
from email.message import EmailMessage

from dotenv import load_dotenv

load_dotenv()


# This block reads SMTP settings, builds the email, and sends it after authenticating with the mail server.
def send_otp_email(recipient: str, otp: str):
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

    with smtplib.SMTP(smtp_host, smtp_port) as server:
        # When enabled, upgrades the SMTP connection with STARTTLS before logging in.
        if use_tls:
            server.starttls()
        server.login(username, password)
        server.send_message(message)
