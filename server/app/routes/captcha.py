import json
import os
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse

from app.utils.captcha import captcha_settings

router = APIRouter(prefix='/auth/captcha', tags=['Authentication'])


def validate_parent_origin(parent_origin: str):
    if parent_origin:
        origins = {item.strip() for item in os.getenv('RECAPTCHA_PARENT_ORIGINS', '').split(',') if item.strip()}
        parsed = urlsplit(parent_origin)
        base_origin = f'{parsed.scheme}://{parsed.hostname}' if parsed.scheme and parsed.hostname else ''
        allows_local_port = parsed.hostname in ('localhost', '127.0.0.1') and base_origin in origins
        if (parent_origin not in origins and not allows_local_port) or parsed.scheme not in ('http', 'https') or not parsed.netloc:
            raise HTTPException(403, detail={
                'code': 'captcha_origin_not_allowed',
                'message': 'Human verification is not enabled for this app address. Please contact support.',
            })


@router.get('/config')
def config(parent_origin: str = Query(default='')):
    captcha_settings()
    validate_parent_origin(parent_origin)
    return {'provider': 'recaptcha-v2'}


@router.get('', response_class=HTMLResponse)
def captcha_page(parent_origin: str = Query(default='')):
    site_key, _, _ = captcha_settings()
    validate_parent_origin(parent_origin)
    # JSON encoding and escaping prevent settings from becoming executable HTML.
    settings = json.dumps({'siteKey': site_key, 'parentOrigin': parent_origin}).replace('<', '\\u003c')
    html = Path(__file__).with_name('captcha.html').read_text(encoding='utf-8')
    return HTMLResponse(html.replace('__CAPTCHA_SETTINGS__', settings), headers={'Cache-Control': 'no-store'})
