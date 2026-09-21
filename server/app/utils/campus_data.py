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
        "latitude": position[0],
        "longitude": position[1],
        "polygonCoordinates": polygon,
        "isParking": "parking" in classification.lower(),
    }


def floor_label(number):
    if number is None:
        return "Floor unknown"
    number = int(number)
    if number == 0:
        return "Ground Floor"
    suffix = (
        "th" if 11 <= number % 100 <= 13
        else {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
    )
    return f"{number}{suffix} Floor"


CATEGORY_BY_TYPE = {
    "room": "room",
    "laboratory": "laboratory",
    "office": "office",
    "facility": "facility",
    "restroom": "restroom",
}


def buildings_payload(building_rows, location_rows, floor_rows, type_rows):
    """The /campus/buildings body, joined in Python from four whole tables.

    A pure function of the rows, so the result can be built once per cache
    refresh instead of once per request.
    """
    floors = {str(row["floor_id"]): row for row in floor_rows}
    types = {str(row["type_id"]): row["type_name"] for row in type_rows}

    rooms_by_building = {}
    for row in location_rows:
        building_id = str(row["building_id"])
        floor = floors.get(str(row.get("floor_id")))

        # Iwasang ilagay ang room sa floor ng ibang building.
        if floor and str(floor["building_id"]) != building_id:
            continue

        type_name = types.get(str(row.get("type_id")), "Room")
        category = CATEGORY_BY_TYPE.get(type_name.strip().lower(), "room")

        rooms_by_building.setdefault(building_id, []).append({
            "id": str(row["location_id"]),
            "title": row.get("location_name")
                     or row.get("location_code")
                     or "Unnamed location",
            "category": category,
            "floor": floor_label(floor.get("floor_number") if floor else None),
        })

    buildings = []
    skipped = 0
    for row in building_rows:
        building = building_for_map(row)
        if building is None:
            skipped += 1
            continue

        building["rooms"] = rooms_by_building.get(str(row["building_id"]), [])
        buildings.append(building)

    return {"buildings": buildings, "skippedCount": skipped}
