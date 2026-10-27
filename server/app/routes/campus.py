# Campus API: retrieves buildings, rooms, photos, and computes routes from database records.
import logging
from concurrent.futures import ThreadPoolExecutor, wait
from time import monotonic

from fastapi import APIRouter, HTTPException

from app.database.supabase import supabase
from app.utils.campus_data import building_for_map, cover_photos_for_map
from app.utils.routing import campus_routes, RoutingError
from pydantic import BaseModel, Field
from typing import Literal

router = APIRouter(prefix="/campus", tags=["Campus"])
logger = logging.getLogger(__name__)


# This block validates the starting-point type and checks whether the coordinates are within valid ranges.
class RouteOrigin(BaseModel):
    type: Literal["mainGate", "campusCenter", "campusLocation", "currentLocation"]
    buildingId: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


# This block checks whether a starting point, destination building, and supported travel mode have been provided.
class RouteRequest(BaseModel):
    origin: RouteOrigin
    destinationBuildingId: str
    mode: Literal["walking", "car", "motorcycle", "bicycle"] = "walking"


# This block fetches ordered pages of 500 rows until all table results have been retrieved.
def routing_rows(table, columns, order):
    rows = []
    while True:
        page = supabase.table(table).select(columns).order(order).range(len(rows), len(rows) + 499).execute().data or []
        rows.extend(page)
        if len(page) < 500:
            return rows


def map_cover_photos(table, owner_key, deadline=None):
    """Read lightweight metadata first; fetch only candidate covers in small batches."""
    photos = {}
    deadline = deadline if deadline is not None else monotonic() + 12
    try:
        if monotonic() >= deadline:
            return photos
        metadata = routing_rows(
            table, f"photo_id,{owner_key},position,is_cover", "photo_id"
        )
        metadata.sort(key=lambda row: (
            not bool(row.get("is_cover")),
            row.get("position") if row.get("position") is not None else float("inf"),
            row["photo_id"],
        ))
        pending = {}
        for row in metadata:
            if row.get(owner_key) is not None:
                pending.setdefault(str(row[owner_key]), []).append(row)
        while pending:
            if monotonic() >= deadline:
                break
            candidates = [rows.pop(0) for rows in pending.values()]
            def fetch_batch(batch):
                try:
                    rows = (supabase.table(table)
                            .select(f"photo_id,{owner_key},position,mime_type,content,is_cover")
                            .in_("photo_id", [row["photo_id"] for row in batch])
                            .execute().data or [])
                    return cover_photos_for_map(rows, owner_key)
                except Exception:
                    logger.warning("Could not load a batch of optional %s photos", table)
                    return {}
            batches = [candidates[start:start + 5]
                       for start in range(0, len(candidates), 5)]
            pool = ThreadPoolExecutor(max_workers=4)
            try:
                futures = [pool.submit(fetch_batch, batch) for batch in batches]
                done, unfinished = wait(futures, timeout=max(0, deadline - monotonic()))
                for future in done:
                    photos.update(future.result())
                if unfinished:
                    logger.warning("Optional %s photo loading reached its time budget", table)
                    break
            finally:
                # In-flight reads may finish in the background; don't hold up map data.
                pool.shutdown(wait=False, cancel_futures=True)
            pending = {owner: rows for owner, rows in pending.items()
                       if owner not in photos and rows}
    except Exception:
        # Photos are optional; campus names, keywords and coordinates remain usable.
        logger.warning("Could not load optional %s covers", table, exc_info=True)
    return photos


# This block reads the route network and passes it to the routing engine without writing to the database.
@router.post("/routes")
def get_routes(request: RouteRequest):
    try:
        nodes = routing_rows("route_node", "node_id,building_id,latitude,longitude,node_type,status,name", "node_id")
        paths = routing_rows("pathway", "pathway_id,source_node_id,destination_node_id,status,direction,shade,name", "pathway_id")
        modes = routing_rows("pathway_allowed_mode", "pathway_id,mode", "pathway_id,mode")
        points = routing_rows("path_point", "point_id,pathway_id,sequence_no,latitude,longitude,status", "point_id")
        return campus_routes(nodes, paths, modes, points, request.model_dump())
    except RoutingError as error:
        raise HTTPException(status_code=404, detail=str(error)) from None
    except Exception:
        logger.exception("Could not compute campus routes")
        raise HTTPException(status_code=503, detail="Campus routes are temporarily unavailable.") from None


# This block combines buildings, room locations, floors, types, and cover photos for the map.
@router.get("/buildings")
def get_buildings():
    try:
        building_rows = routing_rows(
            "building",
            "*",
            "building_id",
        )
        location_rows = routing_rows(
            "location",
            "*",
            "location_id",
        )
        floor_rows = routing_rows(
            "floor",
            "floor_id,building_id,floor_number",
            "floor_id",
        )
        type_rows = routing_rows(
            "location_type",
            "type_id,type_name",
            "type_id",
        )
        photo_deadline = monotonic() + 12
        building_photos = map_cover_photos("building_photo", "building_id", photo_deadline)
        location_photos = map_cover_photos("location_photo", "location_id", photo_deadline)

        floors = {str(row["floor_id"]): row for row in floor_rows}
        types = {str(row["type_id"]): row["type_name"] for row in type_rows}

        category_by_type = {
            "room": "room",
            "laboratory": "laboratory",
            "office": "office",
            "facility": "facility",
            "restroom": "restroom",
        }

        # This block converts a floor number into a readable label with the appropriate ordinal suffix.
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

        rooms_by_building = {}
        for row in location_rows:
            if row.get("status") == "inactive":
                continue
            building_id = str(row["building_id"])
            floor = floors.get(str(row.get("floor_id")))

            # This block skips a room if its linked floor belongs to a different building.
            if floor and str(floor["building_id"]) != building_id:
                continue

            type_name = types.get(str(row.get("type_id")), "Room")
            category = category_by_type.get(
                type_name.strip().lower(), "room"
            )

            rooms_by_building.setdefault(building_id, []).append({
                "id": str(row["location_id"]),
                "title": row.get("location_name")
                         or row.get("location_code")
                         or "Unnamed location",
                "category": category,
                "imageUrl": location_photos.get(str(row["location_id"])),
                "description": row.get("description") or "",
                "keywords": row.get("keywords") or "",
                "code": row.get("location_code") or "",
                "latitude": row.get("latitude"),
                "longitude": row.get("longitude"),
                "floor": floor_label(
                    floor.get("floor_number") if floor else None
                ),
            })

        buildings = []
        skipped = 0
        for row in building_rows:
            if row.get("status") == "inactive":
                continue
            building = building_for_map(row)
            if building is None:
                skipped += 1
                continue

            building["imageUrl"] = building_photos.get(str(row["building_id"])) or building["imageUrl"]

            building["rooms"] = rooms_by_building.get(
                str(row["building_id"]), []
            )
            buildings.append(building)

        return {"buildings": buildings, "skippedCount": skipped}

    except Exception:
        logger.exception("Could not load campus buildings")
        raise HTTPException(
            status_code=503,
            detail="Campus locations are temporarily unavailable.",
        ) from None
