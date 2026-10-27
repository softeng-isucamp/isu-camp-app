"""Build once, publish atomically, and serve the same measured offline bytes."""
import copy
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import tempfile
from functools import lru_cache
from datetime import datetime, timezone
from urllib.parse import urlsplit

from app.utils.campus_data import bundle_photo_urls

VERSION = re.compile(r"^[0-9a-f]{64}$")
ASSET = re.compile(r"^(bundle\.json|photos/[0-9a-f]{40}\.img|tiles/\d+/\d+/\d+\.png)$")


def encode_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def photo_path(url):
    parsed = urlsplit(url)
    key = parsed.path + ("?" + parsed.query if parsed.query else "")
    return "photos/" + hashlib.sha1(key.encode()).hexdigest() + ".img"


def campus_tile_paths(min_zoom=15, max_zoom=19):
    """XYZ coverage shared with the app's Echague camera bounds."""
    south, west, north, east = 16.7120, 121.6830, 16.7310, 121.7010
    def x(lon, zoom):
        return math.floor((lon + 180) / 360 * (1 << zoom))
    def y(lat, zoom):
        radians = math.radians(lat)
        return math.floor((1 - math.asinh(math.tan(radians)) / math.pi) / 2 * (1 << zoom))
    for zoom in range(min_zoom, max_zoom + 1):
        for column in range(x(west, zoom), x(east, zoom) + 1):
            for row in range(y(north, zoom), y(south, zoom) + 1):
                yield f"tiles/{zoom}/{column}/{row}.png"


def _write_payload(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('wb') as stream:
        # Pack assets are public downloads, shared with a separate API user.
        os.fchmod(stream.fileno(), 0o644)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def _sync_directory(path):
    if os.name == 'posix':
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


@lru_cache(maxsize=16)
def _published_snapshot(directory):
    directory = Path(directory)
    manifest = json.loads((directory / 'manifest.json').read_bytes())
    if manifest.get('version') != directory.name or manifest.get('schemaVersion') != 1:
        raise ValueError('Invalid published manifest')
    return manifest, {entry['path']: entry for entry in manifest['files']}


class OfflinePackStore:
    def __init__(self, root):
        self.root = Path(root).resolve()

    @staticmethod
    def entry(path, content):
        return {"path": path, "bytes": len(content),
                "sha256": hashlib.sha256(content).hexdigest()}

    def manifest(self, version=None):
        if version is None:
            version = (self.root / "current").read_text().strip()
        if not VERSION.fullmatch(version):
            raise ValueError("Invalid pack version")
        return _published_snapshot(str(self.root / version))[0]

    def asset(self, version, path):
        if not ASSET.fullmatch(path):
            raise FileNotFoundError(path)
        self.manifest(version)
        entry = _published_snapshot(str(self.root / version))[1].get(path)
        if entry is None:
            raise FileNotFoundError(path)
        file = self.root / version / "files" / PurePosixPath(path)
        if not file.is_file() or not file.resolve().is_relative_to(self.root / version / "files"):
            raise FileNotFoundError(path)
        return file, entry

    def publish(self, bundle, assets, *, required_tiles=None):
        """No source requests occur here or in the serving endpoints.

        assets are exact photo/tile bytes from the builder's permitted sources.
        A failed build leaves the previous current pointer untouched.
        """
        assets = dict(assets)
        payload = copy.deepcopy(bundle)
        payload.pop("version", None)
        payload.pop("generatedAt", None)
        required = set(required_tiles if required_tiles is not None else campus_tile_paths())
        required.update(photo_path(url) for url in bundle_photo_urls(payload.get("buildings", [])))
        if set(assets) != required:
            raise ValueError("Pack must contain every required photo and tile, with no extra files")
        entries = []
        for path in sorted(assets):
            content = assets[path]
            if not ASSET.fullmatch(path) or path == "bundle.json" or not isinstance(content, bytes) or not content:
                raise ValueError("Invalid or empty pack asset")
            entries.append(self.entry(path, content))
        version = hashlib.sha256(encode_json({"schemaVersion": 1, "dataset": payload, "assets": entries})).hexdigest()
        self.root.mkdir(parents=True, exist_ok=True)
        destination = self.root / version
        if not destination.exists():
            with tempfile.TemporaryDirectory(prefix=".build-", dir=self.root) as staging:
                staging = Path(staging)
                generated_at = datetime.now(timezone.utc).isoformat()
                payload.update(version=version, generatedAt=generated_at)
                bundle_bytes = encode_json(payload)
                files = [self.entry("bundle.json", bundle_bytes), *entries]
                manifest = {
                    "schemaVersion": 1, "version": version, "generatedAt": generated_at,
                    "totalBytes": sum(entry["bytes"] for entry in files), "files": files,
                    "buildingCount": len(payload.get("buildings", [])),
                    "roomCount": sum(len(building.get("rooms") or []) for building in payload.get("buildings", [])),
                    "pathwayCount": len((payload.get("graph") or {}).get("pathways") or []),
                    "photoCount": sum(path.startswith("photos/") for path in assets),
                    "dataBytes": len(bundle_bytes),
                }
                for path, content in [("bundle.json", bundle_bytes), *assets.items()]:
                    target = staging / "files" / path
                    _write_payload(target, content)
                _write_payload(staging / "manifest.json", encode_json(manifest))
                for directory in sorted((p for p in staging.rglob('*') if p.is_dir()),
                                        key=lambda p: len(p.parts), reverse=True):
                    directory.chmod(0o755)
                    _sync_directory(directory)
                staging.chmod(0o755)
                _sync_directory(staging)
                # Concurrent identical builds may already have published it.
                try:
                    staging.rename(destination)
                except OSError:
                    if not destination.exists():
                        raise
        # Never replace an existing version's bytes or discard retained versions.
        manifest = self.manifest(version)
        fd, pointer = tempfile.mkstemp(prefix=".current-", dir=self.root)
        try:
            with os.fdopen(fd, "w") as stream:
                os.fchmod(stream.fileno(), 0o644)
                stream.write(version)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(pointer, self.root / "current")
            _sync_directory(self.root)
        finally:
            Path(pointer).unlink(missing_ok=True)
        return manifest
