"""Translate the existing Supabase building schema for the mobile map."""

import hashlib
import json
import math
from urllib.parse import urlsplit, urlunsplit


def photo_for_map(row):
    """Preserve legacy network URLs without ever embedding image bytes."""
    for key in ("image_url", "imageUrl", "photo_url"):
        url = row.get(key)
        if isinstance(url, str) and url.lower().startswith(("http://", "https://")):
            return url
    return None


def photo_content(row):
    """Decode one stored PostgREST bytea value for the image endpoint."""
    content = row.get("content")
    try:
        if isinstance(content, str) and content.startswith("\\x"):
            return bytes.fromhex(content[2:]) or None
        if isinstance(content, (bytes, bytearray, memoryview)):
            return bytes(content) or None
    except ValueError:
        pass
    return None


def cover_photos_for_map(rows, owner_key, url_for_photo):
    """Choose cover metadata per owner without reading or encoding content."""
    photos = {}
    ordered = sorted((row for row in rows if row.get("photo_id") is not None), key=lambda row: (
        not bool(row.get("is_cover")),
        row.get("position") if row.get("position") is not None else float("inf"),
        row["photo_id"],
    ))
    for row in ordered:
        owner = row.get(owner_key)
        if owner is None or str(owner) in photos:
            continue
        photos[str(owner)] = url_for_photo(row["photo_id"])
    return photos


def coordinate(latitude, longitude):
    try:
        lat, lng = float(latitude), float(longitude)
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(lat) and math.isfinite(lng)):
        return None
    return [lat, lng] if -90 <= lat <= 90 and -180 <= lng <= 180 else None


def building_for_map(row):
    # The admin table stores polygon points as [latitude, longitude].
    polygon = []
    for point in row.get("polygon_coordinates") or []:
        if isinstance(point, (list, tuple)) and len(point) == 2:
            parsed = coordinate(*point)
            if parsed is not None:
                polygon.append(parsed)
    position = coordinate(row.get("latitude"), row.get("longitude"))
    if position is None and polygon:
        vertices = polygon[:-1] if len(polygon) > 1 and polygon[0] == polygon[-1] else polygon
        position = [sum(p[i] for p in vertices) / len(vertices) for i in (0, 1)]
    if position is None:
        return None
    classification = row.get("classification") or "Building"
    return {
        "id": str(row["building_id"]),
        "name": row.get("building_name") or "Unnamed building",
        "acronym": row.get("building_code") or "",
        "category": classification,
        "description": row.get("description") or "",
        "keywords": row.get("keywords") or "",
        "imageUrl": photo_for_map(row),
        "latitude": position[0],
        "longitude": position[1],
        "polygonCoordinates": polygon,
        "isParking": "parking" in classification.lower(),
    }


def normalize_for_version(value):
    """Strip request-dependent photo hosts so one dataset yields one version."""
    if isinstance(value, dict):
        return {str(key): normalize_for_version(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize_for_version(item) for item in value]
    if isinstance(value, str) and value.lower().startswith(("http://", "https://")):
        parsed = urlsplit(value)
        return urlunsplit(("", "", parsed.path, parsed.query, ""))
    return value


def bundle_version(payload):
    """Content hash of the offline dataset; equal payloads always hash equally."""
    canonical = json.dumps(normalize_for_version(payload), sort_keys=True,
                           separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]


def bundle_photo_urls(buildings):
    """Every cover photo the offline pack has to store, buildings and rooms."""
    urls = []
    for building in buildings:
        for url in [building.get("imageUrl"),
                    *(room.get("imageUrl") for room in building.get("rooms") or [])]:
            if isinstance(url, str) and url and url not in urls:
                urls.append(url)
    return urls


def offline_manifest(bundle):
    """Legacy dataset-only counts; dataBytes excludes photos and tiles.

    Published complete-pack manifests come from OfflinePackStore instead.
    """
    buildings = bundle.get("buildings") or []
    graph = bundle.get("graph") or {}
    return {
        "version": bundle["version"],
        "generatedAt": bundle.get("generatedAt"),
        "buildingCount": len(buildings),
        "roomCount": sum(len(b.get("rooms") or []) for b in buildings),
        "photoCount": len(bundle_photo_urls(buildings)),
        "pathwayCount": len(graph.get("pathways") or []),
        "dataBytes": len(json.dumps(bundle, default=str).encode("utf-8")),
    }
