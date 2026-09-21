"""Process-local snapshot of the campus tables, refreshed on a TTL.

The campus network is about 220 rows that change maybe monthly, but every
request used to re-read all of it over four sequential Supabase round trips -
roughly 0.3-0.8 s of waiting before any routing work began. Holding the rows,
the built graph and the finished /campus/buildings body in the process turns
both campus endpoints into pure CPU.

The snapshot is per-process. Under `uvicorn --workers N` each worker keeps its
own copy, which only means N times the refresh traffic.
"""
import hashlib
import json
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from app.database.supabase import supabase
from app.utils.campus_data import buildings_payload
from app.utils.routing import build_graph

logger = logging.getLogger(__name__)

TTL_SECONDS = float(os.getenv("CAMPUS_CACHE_TTL", "300"))

# A failed refresh is not retried until this many seconds have passed, so a
# Supabase outage costs one round trip per interval rather than one per request.
RETRY_SECONDS = 15.0

PAGE = 500

# name -> (table, columns, order)
TABLES = {
    "nodes": ("route_node",
              "node_id,building_id,latitude,longitude,node_type,status,name",
              "node_id"),
    "pathways": ("pathway",
                 "pathway_id,source_node_id,destination_node_id,status,direction,shade,name",
                 "pathway_id"),
    "modes": ("pathway_allowed_mode", "pathway_id,mode", "pathway_id,mode"),
    "points": ("path_point",
               "point_id,pathway_id,sequence_no,latitude,longitude,status",
               "point_id"),
    "buildings": ("building",
                  "building_id,building_code,building_name,description,"
                  "latitude,longitude,polygon_coordinates,classification",
                  "building_id"),
    "locations": ("location",
                  "location_id,building_id,type_id,location_code,location_name,floor_id",
                  "location_id"),
    "floors": ("floor", "floor_id,building_id,floor_number", "floor_id"),
    "types": ("location_type", "type_id,type_name", "type_id"),
}


def rows(table, columns, order):
    """Every row of a table, paged the way PostgREST requires."""
    out = []
    while True:
        page = (supabase.table(table).select(columns).order(order)
                .range(len(out), len(out) + PAGE - 1).execute().data) or []
        out.extend(page)
        if len(page) < PAGE:
            return out


class Snapshot:
    """One consistent read of the campus tables. Treat as immutable."""

    __slots__ = ("nodes", "graph", "buildings_body", "etag", "loaded_at")

    def __init__(self, data):
        self.nodes, self.graph = build_graph(
            data["nodes"], data["pathways"], data["modes"], data["points"])
        payload = buildings_payload(
            data["buildings"], data["locations"], data["floors"], data["types"])
        # Serialised once per refresh: the body is identical for every caller
        # until the snapshot expires, so there is no reason to re-encode 42
        # polygons per request.
        self.buildings_body = json.dumps(payload, separators=(",", ":")).encode()
        self.etag = '"%s"' % hashlib.sha256(self.buildings_body).hexdigest()[:16]
        self.loaded_at = time.monotonic()


def _load():
    """Read all eight tables at once, so a refresh costs one round trip of time."""
    with ThreadPoolExecutor(max_workers=len(TABLES)) as pool:
        pending = {name: pool.submit(rows, *spec) for name, spec in TABLES.items()}
        return Snapshot({name: future.result() for name, future in pending.items()})


_lock = threading.Lock()
_snapshot = None
_retry_after = 0.0


def _fresh(snapshot):
    return snapshot is not None and time.monotonic() - snapshot.loaded_at < TTL_SECONDS


def current():
    """The campus snapshot, refreshing it if the TTL has passed.

    Serves the previous snapshot if a refresh fails, so a Supabase blip degrades
    to stale data rather than a 503. Only raises when there is nothing cached.
    """
    global _snapshot, _retry_after

    snapshot = _snapshot
    if _fresh(snapshot):
        return snapshot
    if snapshot is not None and time.monotonic() < _retry_after:
        return snapshot

    with _lock:
        # Another thread may have refreshed it while this one waited.
        if _fresh(_snapshot):
            return _snapshot
        if _snapshot is not None and time.monotonic() < _retry_after:
            return _snapshot
        try:
            _snapshot = _load()
            _retry_after = 0.0
        except Exception:
            if _snapshot is None:
                raise
            _retry_after = time.monotonic() + RETRY_SECONDS
            logger.exception(
                "Campus cache refresh failed; serving data from %.0fs ago",
                time.monotonic() - _snapshot.loaded_at)
        return _snapshot


def invalidate():
    """Drop the snapshot so the next request reloads it."""
    global _snapshot, _retry_after
    with _lock:
        _snapshot = None
        _retry_after = 0.0


def warm():
    """Prime the cache at startup. Never raises: the first request can retry."""
    try:
        current()
    except Exception:
        logger.exception("Could not prime the campus cache at startup")
