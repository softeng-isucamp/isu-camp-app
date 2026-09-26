import logging
import hashlib
import json

from fastapi import APIRouter, HTTPException, Response

from app.database.supabase import supabase
from app.utils.campus_data import building_for_map
from app.utils.routing import walking_routes, RoutingError
from pydantic import BaseModel, Field
from typing import Literal

router = APIRouter(prefix="/campus", tags=["Campus"])
logger = logging.getLogger(__name__)


class RouteOrigin(BaseModel):
    type: Literal["mainGate", "campusCenter", "campusLocation", "currentLocation"]
    buildingId: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: RouteOrigin
    destinationBuildingId: str
    mode: Literal["walking"] = "walking"


def routing_rows(table, columns, order):
    rows = []
    while True:
        page = supabase.table(table).select(columns).order(order).range(len(rows), len(rows) + 499).execute().data or []
        rows.extend(page)
        if len(page) < 500:
            return rows


@router.post("/routes")
def get_routes(request: RouteRequest):
    try:
        nodes = routing_rows("route_node", "node_id,building_id,latitude,longitude,node_type,status,name", "node_id")
        paths = routing_rows("pathway", "pathway_id,source_node_id,destination_node_id,status,direction,shade,name", "pathway_id")
        modes = routing_rows("pathway_allowed_mode", "pathway_id,mode", "pathway_id,mode")
        points = routing_rows("path_point", "point_id,pathway_id,sequence_no,latitude,longitude,status", "point_id")
        return walking_routes(nodes, paths, modes, points, request.model_dump())
    except RoutingError as error:
        raise HTTPException(status_code=404, detail=str(error)) from None
    except Exception:
        logger.exception("Could not compute walking routes")
        raise HTTPException(status_code=503, detail="Walking routes are temporarily unavailable.") from None


@router.get("/buildings")
def get_buildings():
    try:
        building_rows = routing_rows(
            "building",
            "building_id,building_code,building_name,description,"
            "latitude,longitude,polygon_coordinates,classification",
            "building_id",
        )
        location_rows = routing_rows(
            "location",
            "location_id,building_id,type_id,location_code,"
            "location_name,floor_id,description,keywords",
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

        floors = {str(row["floor_id"]): row for row in floor_rows}
        types = {str(row["type_id"]): row["type_name"] for row in type_rows}

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
                "description": row.get("description") or "",
                "keywords": row.get("keywords") or "",
                "floor": floor_label(
                    floor.get("floor_number") if floor else None
                ),
            })

        buildings = []
        skipped = 0
        for row in building_rows:
            building = building_for_map(row)
            if building is None:
                skipped += 1
                continue

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


def catalog_bytes():
    catalog = get_buildings()
    # The offline pack carries the same active routing source used by /routes.
    # The app can then route locally when the API or network is unavailable.
    catalog["routingGraph"] = {
        "nodes": routing_rows("route_node", "node_id,building_id,latitude,longitude,node_type,status,name", "node_id"),
        "pathways": routing_rows("pathway", "pathway_id,source_node_id,destination_node_id,status,direction,shade,name", "pathway_id"),
        "modes": routing_rows("pathway_allowed_mode", "pathway_id,mode", "pathway_id,mode"),
        "points": routing_rows("path_point", "point_id,pathway_id,sequence_no,latitude,longitude,status", "point_id"),
    }
    return json.dumps(catalog, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


@router.get("/pack/manifest")
def get_pack_manifest():
    content = catalog_bytes()
    version = hashlib.sha256(content).hexdigest()
    return {
        "schemaVersion": 1,
        "catalogVersion": version,
        "minClientSchema": 1,
        "maxClientSchema": 1,
        "capabilities": {"catalogSearch": True, "mapTiles": False, "routing": True},
        "files": [{
            "path": "catalog.json",
            "url": f"/campus/pack/catalog?version={version}",
            "size": len(content),
            "sha256": version,
        }],
    }


@router.get("/pack/catalog")
def get_pack_catalog(version: str):
    content = catalog_bytes()
    if hashlib.sha256(content).hexdigest() != version:
        raise HTTPException(status_code=409, detail="Catalog changed. Fetch a new manifest.")
    return Response(content=content, media_type="application/json", headers={"Cache-Control": "no-store"})
