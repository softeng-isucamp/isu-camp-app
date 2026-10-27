import os

import httpx
from fastapi import HTTPException


def captcha_settings():
    site_key = os.getenv('RECAPTCHA_SITE_KEY', '').strip()
    secret = os.getenv('RECAPTCHA_SECRET_KEY', '').strip()
    hosts = {host.strip().lower() for host in os.getenv('RECAPTCHA_ALLOWED_HOSTNAMES', '').split(',') if host.strip()}
    if not site_key or not secret or not hosts:
        raise HTTPException(503, detail={
            'code': 'captcha_not_configured',
            'message': 'Human verification is not configured on the server. Please contact support.',
        })
    return site_key, secret, hosts


def verify_captcha(token: str):
    _, secret, hosts = captcha_settings()
    if not token or len(token) > 8192:
        raise HTTPException(400, 'Please complete human verification.')
    try:
        response = httpx.post('https://www.google.com/recaptcha/api/siteverify',
                              data={'secret': secret, 'response': token}, timeout=10)
        response.raise_for_status()
        result = response.json()
        if not isinstance(result, dict):
            raise ValueError()
    except (httpx.HTTPError, ValueError):
        raise HTTPException(503, 'Could not verify the CAPTCHA. Please try again.') from None
    hostname = result.get('hostname')
    if result.get('success') is not True or not isinstance(hostname, str) or hostname.lower() not in hosts:
        raise HTTPException(400, 'Human verification expired or failed. Please try again.')
