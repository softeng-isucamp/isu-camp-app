"""Translate the existing Supabase building schema for the mobile map."""

import math


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
        "latitude": position[0],
        "longitude": position[1],
        "polygonCoordinates": polygon,
        "isParking": "parking" in classification.lower(),
    }
