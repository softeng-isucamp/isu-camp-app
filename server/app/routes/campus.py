import logging
import os
import secrets

from fastapi import APIRouter, Header, HTTPException, Response

from app.utils import campus_cache
from app.utils.routing import routes_for, RoutingError
from pydantic import BaseModel, Field
from typing import Literal

router = APIRouter(prefix="/campus", tags=["Campus"])
logger = logging.getLogger(__name__)

CACHE_CONTROL = "public, max-age=%d" % int(campus_cache.TTL_SECONDS)


class RouteOrigin(BaseModel):
    type: Literal["mainGate", "campusCenter", "campusLocation", "currentLocation"]
    buildingId: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: RouteOrigin
    destinationBuildingId: str
    mode: Literal["walking"] = "walking"


@router.post("/routes")
def get_routes(request: RouteRequest):
    try:
        snapshot = campus_cache.current()
        return routes_for(snapshot.nodes, snapshot.graph, request.model_dump())
    except RoutingError as error:
        raise HTTPException(status_code=404, detail=str(error)) from None
    except Exception:
        logger.exception("Could not compute walking routes")
        raise HTTPException(status_code=503, detail="Walking routes are temporarily unavailable.") from None


@router.get("/buildings")
def get_buildings(if_none_match: str | None = Header(default=None)):
    try:
        snapshot = campus_cache.current()
    except Exception:
        logger.exception("Could not load campus buildings")
        raise HTTPException(
            status_code=503,
            detail="Campus locations are temporarily unavailable.",
        ) from None

    headers = {"ETag": snapshot.etag, "Cache-Control": CACHE_CONTROL}
    # The map screen reloads buildings on every open; a 304 saves ~70 kB.
    if if_none_match and snapshot.etag in (tag.strip() for tag in if_none_match.split(",")):
        return Response(status_code=304, headers=headers)
    return Response(content=snapshot.buildings_body,
                    media_type="application/json", headers=headers)


@router.post("/refresh-cache", status_code=204)
def refresh_cache(authorization: str | None = Header(default=None)):
    """Publish admin edits without waiting out the TTL."""
    expected = os.getenv("ADMIN_REFRESH_TOKEN", "")
    if len(expected) < 16:
        raise HTTPException(503, "Cache refresh is not configured.")
    if not authorization or not secrets.compare_digest(authorization, "Bearer " + expected):
        raise HTTPException(401, "Not authorised to refresh the campus cache.")
    campus_cache.invalidate()
    return Response(status_code=204)
