import logging
import hashlib
import os
from pathlib import Path as FilePath

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Path, Request, Response
from fastapi.responses import JSONResponse, FileResponse

from app.database.supabase import supabase
from app.utils.campus_data import (building_for_map, bundle_version, cover_photos_for_map,
                                   photo_content)
from app.utils.routing import campus_routes, RoutingError
from app.services.offline_pack import OfflinePackStore
from pydantic import BaseModel, Field
from typing import Literal

router = APIRouter(prefix="/campus", tags=["Campus"])
logger = logging.getLogger(__name__)

PHOTO_TABLES = {"building": "building_photo", "location": "location_photo"}
PHOTO_MIME_TYPES = {
    "image/jpeg", "image/png", "image/webp", "image/gif", "image/avif",
    "image/bmp", "image/x-icon", "image/vnd.microsoft.icon",
}


@router.get("/photos/{source}/{photo_id}", name="get_campus_photo")
def get_photo(request: Request, source: Literal["building", "location"],
              photo_id: int = Path(gt=0)):
    """Serve one photo under the same public access policy as the campus map."""
    try:
        rows = (supabase.table(PHOTO_TABLES[source])
                .select("content,mime_type").eq("photo_id", photo_id)
                .limit(1).execute().data or [])
        if not rows:
            raise HTTPException(404, "Campus photo not found.")
        content = photo_content(rows[0])
        mime = rows[0].get("mime_type")
        if not content or mime not in PHOTO_MIME_TYPES:
            raise HTTPException(404, "Campus photo is unavailable.")
        etag = '"' + hashlib.sha256(content).hexdigest() + '"'
        headers = {"Cache-Control": "public, max-age=300", "ETag": etag,
                   "X-Content-Type-Options": "nosniff"}
        validators = [tag.strip().removeprefix("W/")
                      for tag in request.headers.get("if-none-match", "").split(",")]
        if etag in validators or "*" in validators:
            return Response(status_code=304, headers=headers)
        return Response(content=content, media_type=mime, headers=headers)
    except HTTPException:
        raise
    except Exception:
        logger.exception("Could not load campus photo")
        raise HTTPException(503, "Campus photos are temporarily unavailable.") from None


class RouteOrigin(BaseModel):
    type: Literal["mainGate", "campusCenter", "campusLocation", "currentLocation"]
    buildingId: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: RouteOrigin
    destinationBuildingId: str
    mode: Literal["walking", "car", "motorcycle", "bicycle"] = "walking"


def routing_rows(table, columns, order):
    rows = []
    while True:
        page = supabase.table(table).select(columns).order(order).range(len(rows), len(rows) + 499).execute().data or []
        rows.extend(page)
        if len(page) < 500:
            return rows


def routing_dataset():
    """The whole transport graph; the offline pack routes from these same rows."""
    return {
        "nodes": routing_rows("route_node", "node_id,building_id,latitude,longitude,node_type,status,name", "node_id"),
        "pathways": routing_rows("pathway", "pathway_id,source_node_id,destination_node_id,status,direction,shade,name", "pathway_id"),
        "modes": routing_rows("pathway_allowed_mode", "pathway_id,mode", "pathway_id,mode"),
        "points": routing_rows("path_point", "point_id,pathway_id,sequence_no,latitude,longitude,status", "point_id"),
    }


@router.post("/routes")
def get_routes(request: RouteRequest):
    try:
        graph = routing_dataset()
        return campus_routes(graph["nodes"], graph["pathways"], graph["modes"],
                             graph["points"], request.model_dump())
    except RoutingError as error:
        raise HTTPException(status_code=404, detail=str(error)) from None
    except Exception:
        logger.exception("Could not compute campus routes")
        raise HTTPException(status_code=503, detail="Campus routes are temporarily unavailable.") from None


def campus_map_payload(request):
    """Buildings, rooms, and cover photo URLs exactly as the map consumes them."""
    building_rows = routing_rows(
        "building",
        "building_id,building_name,building_code,type_id,description,latitude,longitude,polygon_coordinates",
        "building_id",
    )
    location_rows = routing_rows(
        "location",
        "location_id,building_id,floor_id,type_id,location_name,location_code,description",
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
    building_type_rows = routing_rows(
        "building_type",
        "type_id,type_name",
        "type_id",
    )
    building_photos = cover_photos_for_map(routing_rows(
        "building_photo",
        "photo_id,building_id,position,is_cover",
        "photo_id",
    ), "building_id", lambda photo_id: str(request.url_for(
        "get_campus_photo", source="building", photo_id=str(photo_id))))
    location_photos = cover_photos_for_map(routing_rows(
        "location_photo",
        "photo_id,location_id,position,is_cover",
        "photo_id",
    ), "location_id", lambda photo_id: str(request.url_for(
        "get_campus_photo", source="location", photo_id=str(photo_id))))

    floors = {str(row["floor_id"]): row for row in floor_rows}
    types = {str(row["type_id"]): row["type_name"] for row in type_rows}
    building_types = {str(row["type_id"]): row["type_name"] for row in building_type_rows}

    category_by_type = {
        "room": "room",
        "laboratory": "laboratory",
        "office": "office",
        "facility": "facility",
        "restroom": "restroom",
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

    rooms_by_building = {}
    for row in location_rows:
        building_id = str(row["building_id"])
        floor = floors.get(str(row.get("floor_id")))

        # Iwasang ilagay ang room sa floor ng ibang building.
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
            "floor": floor_label(
                floor.get("floor_number") if floor else None
            ),
        })

    buildings = []
    skipped = 0
    for row in building_rows:
        building = building_for_map(row, building_types)
        if building is None:
            skipped += 1
            continue

        building["imageUrl"] = building_photos.get(str(row["building_id"])) or building["imageUrl"]

        building["rooms"] = rooms_by_building.get(
            str(row["building_id"]), []
        )
        buildings.append(building)

    return {"buildings": buildings, "skippedCount": skipped}


@router.get("/buildings")
def get_buildings(request: Request):
    try:
        return campus_map_payload(request)
    except Exception:
        logger.exception("Could not load campus buildings")
        raise HTTPException(
            status_code=503,
            detail="Campus locations are temporarily unavailable.",
        ) from None


def offline_bundle_payload(request):
    """Everything the app needs to search, draw, and route without a network."""
    map_payload = campus_map_payload(request)
    bundle = {
        "buildings": map_payload["buildings"],
        "skippedCount": map_payload["skippedCount"],
        "graph": routing_dataset(),
    }
    # The version covers the dataset only, so repeat downloads stay unnecessary.
    bundle["version"] = bundle_version(bundle)
    bundle["generatedAt"] = datetime.now(timezone.utc).isoformat()
    return bundle


def offline_pack_store():
    root = os.getenv("OFFLINE_PACK_ROOT", str(FilePath(__file__).resolve().parents[2] / "var/offline-packs"))
    return OfflinePackStore(root)


@router.get("/offline/manifest")
def get_offline_manifest(request: Request):
    """Read a previously published total; never generate a pack on request."""
    try:
        manifest = offline_pack_store().manifest()
        return JSONResponse(manifest, headers={"ETag": '"' + manifest["version"] + '"',
                                              "Cache-Control": "no-cache"})
    except (OSError, ValueError, KeyError):
        raise HTTPException(503, "The offline map pack is being prepared. Try again later.") from None


@router.get("/offline/packs/{version}/{asset_path:path}")
def get_offline_pack_asset(version: str, asset_path: str):
    try:
        file, entry = offline_pack_store().asset(version, asset_path)
    except (OSError, ValueError, KeyError):
        raise HTTPException(404, "Offline pack file not found.") from None
    return FileResponse(file, media_type="application/json" if asset_path == "bundle.json" else "application/octet-stream",
                        headers={"ETag": '"' + entry["sha256"] + '"',
                                 "Cache-Control": "public, max-age=31536000, immutable, no-transform",
                                 "Content-Encoding": "identity",
                                 "X-Content-Type-Options": "nosniff"})


@router.get("/offline/bundle")
def get_offline_bundle(request: Request):
    # Older installed clients receive the same published dataset/version.
    try:
        manifest = offline_pack_store().manifest()
        etag = '"' + manifest["version"] + '"'
        validators = [tag.strip().removeprefix("W/") for tag in
                      request.headers.get("if-none-match", "").split(",")]
        if etag in validators or "*" in validators:
            return Response(status_code=304, headers={"ETag": etag, "Cache-Control": "no-cache"})
        response = get_offline_pack_asset(manifest["version"], "bundle.json")
        response.headers["Cache-Control"] = "no-cache"
        response.headers["ETag"] = etag
        return response
    except (OSError, ValueError, KeyError):
        pass
    try:
        bundle = offline_bundle_payload(request)
    except Exception:
        logger.exception("Could not build the offline campus bundle")
        raise HTTPException(
            status_code=503,
            detail="The offline map download is temporarily unavailable.",
        ) from None
    etag = '"' + bundle["version"] + '"'
    headers = {"ETag": etag, "Cache-Control": "no-cache",
               "X-Content-Type-Options": "nosniff"}
    validators = [tag.strip().removeprefix("W/")
                  for tag in request.headers.get("if-none-match", "").split(",")]
    if etag in validators or "*" in validators:
        return Response(status_code=304, headers=headers)
    return JSONResponse(bundle, headers=headers)
