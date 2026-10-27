"""Publish a pack before app downloads; run again after source content changes.

Usage: python scripts/build_offline_pack.py --tiles /srv/campus-xyz \
       --api-base-url https://api.kumpas.live
Tiles must be pre-rendered XYZ PNGs from a source that permits offline use.
This command never downloads tiles from the public OpenStreetMap tile host.
"""
import argparse
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def main():
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tiles", default=os.getenv("OFFLINE_TILE_DIRECTORY"))
    parser.add_argument("--root", default=os.getenv("OFFLINE_PACK_ROOT", str(Path(__file__).resolve().parents[1] / "var/offline-packs")))
    parser.add_argument("--api-base-url", default=os.getenv("PUBLIC_API_BASE_URL"))
    args = parser.parse_args()
    if not args.tiles or not args.api_base_url:
        parser.error("Set --tiles/OFFLINE_TILE_DIRECTORY and --api-base-url/PUBLIC_API_BASE_URL")
    origin = urlsplit(args.api_base_url)
    if origin.scheme not in ("http", "https") or not origin.netloc or origin.path not in ("", "/"):
        parser.error("API base URL must be an HTTP(S) origin")
    from starlette.requests import Request
    from app.routes.campus import offline_bundle_payload, PHOTO_TABLES, PHOTO_MIME_TYPES
    from app.database.supabase import supabase
    from app.services.offline_pack import OfflinePackStore, campus_tile_paths, photo_path
    from app.utils.campus_data import bundle_photo_urls, photo_content

    tile_root = Path(args.tiles).resolve()
    assets = {}
    # Fail before any database work if the tile source is incomplete.
    for path in campus_tile_paths():
        source = tile_root / path.removeprefix("tiles/")
        if not source.resolve().is_relative_to(tile_root):
            raise ValueError("Tile source escapes its configured directory")
        content = source.read_bytes()
        # Catch missing, truncated, or non-PNG renderer output before publication.
        from io import BytesIO
        from PIL import Image
        with Image.open(BytesIO(content)) as image:
            if image.format != "PNG":
                raise ValueError("Offline tiles must be PNG files")
            image.verify()
        assets[path] = content
    request = Request({"type": "http", "method": "GET", "scheme": origin.scheme,
                       "server": (origin.hostname, origin.port or (443 if origin.scheme == "https" else 80)),
                       "path": "/", "root_path": "", "query_string": b"",
                       "headers": [(b"host", origin.netloc.encode())], "router": None})
    # url_for requires the campus router's named photo route.
    from fastapi import FastAPI
    from app.routes.campus import router
    app = FastAPI()
    app.include_router(router)
    request.scope["router"] = app.router
    bundle = offline_bundle_payload(request)
    for url in bundle_photo_urls(bundle["buildings"]):
        parsed = urlsplit(url)
        match = re.fullmatch(r"/campus/photos/(building|location)/(\d+)", parsed.path)
        if parsed.netloc != origin.netloc or not match:
            raise ValueError("External photos must be imported into campus photo storage before publishing")
        source, photo_id = match.groups()
        rows = supabase.table(PHOTO_TABLES[source]).select("content,mime_type").eq("photo_id", int(photo_id)).limit(1).execute().data or []
        content = photo_content(rows[0]) if rows else None
        if not content or rows[0].get("mime_type") not in PHOTO_MIME_TYPES:
            raise ValueError("A required campus photo is unavailable")
        assets[photo_path(url)] = content
    manifest = OfflinePackStore(args.root).publish(bundle, assets)
    print(f"Published {manifest['version']}: {manifest['totalBytes']} bytes, {len(manifest['files'])} files")


if __name__ == "__main__":
    main()
