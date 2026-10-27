# This block converts database coordinates, building records, and photos into the Flutter map format.
"""Translate the existing Supabase building schema for the mobile map."""

import math
import base64


# This block converts a binary/hex photo to a base64 data URL, falling back to an existing image URL.
def photo_for_map(row):
    """Convert PostgREST bytea hex photos to an image the app can display."""
    photo = row.get("content") or row.get("photo")
    if photo:
        try:
            if isinstance(photo, str) and photo.startswith("\\x"):
                photo = bytes.fromhex(photo[2:])
            elif isinstance(photo, (bytes, bytearray, memoryview)):
                photo = bytes(photo)
            else:
                photo = None
            if photo:
                mime = row.get("mime_type") or row.get("photo_mime_type") or "image/jpeg"
                return f"data:{mime};base64,{base64.b64encode(photo).decode('ascii')}"
        except ValueError:
            pass
    return row.get("image_url") or row.get("imageUrl") or row.get("photo_url")


# This block prioritizes a valid cover photo, then position and photo ID, for each building or location.
def cover_photos_for_map(rows, owner_key):
    """Choose a valid cover per building/location, then the earliest position."""
    photos = {}
    ordered = sorted(rows, key=lambda row: (
        not bool(row.get("is_cover")),
        row.get("position") if row.get("position") is not None else float("inf"),
        row["photo_id"],
    ))
    for row in ordered:
        owner = row.get(owner_key)
        if owner is None or str(owner) in photos:
            continue
        image = photo_for_map(row)
        if image:
            photos[str(owner)] = image
    return photos


# This block accepts only finite numeric latitude/longitude values within valid geographic ranges.
def coordinate(latitude, longitude):
    try:
        lat, lng = float(latitude), float(longitude)
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(lat) and math.isfinite(lng)):
        return None
    return [lat, lng] if -90 <= lat <= 90 and -180 <= lng <= 180 else None


# This block validates polygon and marker coordinates and builds the application's building object.
def building_for_map(row):
    # The admin table stores polygon points as [latitude, longitude].
    polygon = []
    for point in row.get("polygon_coordinates") or []:
        if isinstance(point, (list, tuple)) and len(point) == 2:
            parsed = coordinate(*point)
            if parsed is not None:
                polygon.append(parsed)
    position = coordinate(row.get("latitude"), row.get("longitude"))
    # Fallback marker: averages polygon vertices without counting a repeated closing vertex twice.
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
