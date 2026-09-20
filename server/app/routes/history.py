"""History using the existing UserHistory foreign keys; no schema changes."""
import logging
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field

from app.database.supabase import supabase
from app.utils.session import current_user_id

router = APIRouter(prefix="/history", tags=["History"])
logger = logging.getLogger(__name__)
HISTORY_SELECT = (
    "id,Building_id,Location_id,created_at,"
    "building:building!Building_id(building_name,building_code),"
    "location:location!Location_id(location_name)"
)


class HistoryRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    buildingId: int = Field(gt=0)
    locationId: int | None = Field(default=None, gt=0)


def history_entry(row):
    building = row.get("building") or {}
    location = row.get("location") or {}
    return {"id": str(row["id"]),
            "destinationId": str(row["Building_id"]) if row.get("Building_id") is not None else "",
            "destinationName": building.get("building_name") or "Unavailable building",
            "destinationAcronym": building.get("building_code") or "",
            "roomId": str(row["Location_id"]) if row.get("Location_id") is not None else None,
            "roomName": location.get("location_name"),
            "createdAt": row["created_at"]}


@router.get("")
def list_history(offset: int = Query(0, ge=0), user_id: int = Depends(current_user_id)):
    try:
        rows = (supabase.table("UserHistory").select(HISTORY_SELECT)
                .eq("User_id", user_id).order("created_at", desc=True)
                .order("id", desc=True).range(offset, offset + 99).execute().data or [])
        return {"entries": [history_entry(row) for row in rows]}
    except Exception:
        logger.exception("Could not load history")
        raise HTTPException(503, "Could not load history. Please try again.") from None


@router.post("", status_code=201)
def create_history(data: HistoryRequest, user_id: int = Depends(current_user_id)):
    try:
        building = (supabase.table("building").select("building_id")
                    .eq("building_id", data.buildingId).execute().data)
        if not building:
            raise HTTPException(404, "This building is no longer available.")
        if data.locationId is not None:
            location = (supabase.table("location").select("location_id")
                        .eq("location_id", data.locationId)
                        .eq("building_id", data.buildingId).execute().data)
            if not location:
                raise HTTPException(400, "This room does not belong to the selected building.")
        rows = supabase.table("UserHistory").insert({
            "User_id": user_id, "Building_id": data.buildingId,
            "Location_id": data.locationId,
        }).execute().data
        if not rows:
            raise HTTPException(503, "History was not saved. Please try again.")
        return {"id": str(rows[0]["id"])}
    except HTTPException:
        raise
    except Exception:
        logger.exception("Could not save history")
        raise HTTPException(503, "Could not save history. Please try again.") from None


@router.delete("")
def clear_history(user_id: int = Depends(current_user_id)):
    try:
        supabase.table("UserHistory").delete().eq("User_id", user_id).execute()
        return {"success": True}
    except Exception:
        logger.exception("Could not clear history")
        raise HTTPException(503, "Could not clear history. Please try again.") from None


@router.delete("/{entry_id}")
def delete_history(entry_id: int, user_id: int = Depends(current_user_id)):
    try:
        supabase.table("UserHistory").delete().eq("User_id", user_id).eq("id", entry_id).execute()
        return {"success": True}
    except Exception:
        logger.exception("Could not delete history")
        raise HTTPException(503, "Could not delete history. Please try again.") from None
