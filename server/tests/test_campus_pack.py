import hashlib
import json
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routes import campus


class CatalogQuery:
    def __init__(self, rows):
        self.rows = rows
        self.columns = []

    def select(self, columns):
        self.columns = columns.split(",")
        return self

    def order(self, _column):
        return self

    def range(self, start, end):
        self.start, self.end = start, end
        return self

    def execute(self):
        page = self.rows[self.start:self.end + 1]
        return SimpleNamespace(data=[
            {column: row[column] for column in self.columns if column in row}
            for row in page
        ])


class CatalogDatabase:
    """Supabase-shaped fixture with the same columns written by Admin."""

    def __init__(self):
        self.rows = {
            "building": [{
                "building_id": 42,
                "building_code": "ENG",
                "building_name": "Engineering Hall",
                "classification": "Building",
                "description": "Teaching building beside the library.",
                "latitude": 16.7,
                "longitude": 121.6,
            }],
            "location": [{
                "location_id": 7,
                "building_id": 42,
                "type_id": 5,
                "location_code": "REST-7",
                "location_name": "Ground Restroom",
                "floor_id": 3,
                "description": "Restroom by the main entrance.",
                "keywords": "toilet, cr, palikuran",
            }],
            "floor": [{"floor_id": 3, "building_id": 42, "floor_number": 0}],
            "location_type": [{"type_id": 5, "type_name": "Restroom"}],
            "route_node": [],
            "pathway": [],
            "pathway_allowed_mode": [],
            "path_point": [],
        }

    def table(self, name):
        return CatalogQuery(self.rows[name])


def test_pack_manifest_and_download_match_admin_catalog_fields():
    app = FastAPI()
    app.include_router(campus.router)
    client = TestClient(app)

    with patch.object(campus, "supabase", CatalogDatabase()):
        manifest_response = client.get("/campus/pack/manifest")
        assert manifest_response.status_code == 200
        manifest = manifest_response.json()

        assert manifest["schemaVersion"] == 1
        assert manifest["minClientSchema"] <= 1 <= manifest["maxClientSchema"]
        assert manifest["capabilities"] == {
            "catalogSearch": True, "mapTiles": False, "routing": True,
        }
        assert len(manifest["files"]) == 1
        file = manifest["files"][0]
        assert file["path"] == "catalog.json"

        response = client.get(file["url"])
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("application/json")
        assert file["size"] == len(response.content)
        assert file["sha256"] == hashlib.sha256(response.content).hexdigest()
        assert manifest["catalogVersion"] == file["sha256"]

        catalog = json.loads(response.content)
        building = catalog["buildings"][0]
        assert building["description"] == "Teaching building beside the library."
        assert building["keywords"] == ""
        assert building["rooms"][0]["description"] == "Restroom by the main entrance."
        assert building["rooms"][0]["keywords"] == "toilet, cr, palikuran"


def test_pack_catalog_rejects_a_stale_version():
    app = FastAPI()
    app.include_router(campus.router)
    client = TestClient(app)
    catalog = {"buildings": [{"id": "7", "name": "Library"}], "skippedCount": 0}

    with patch.object(campus, "get_buildings", return_value=catalog), patch.object(
        campus, "routing_rows", return_value=[]
    ):
        manifest = client.get("/campus/pack/manifest").json()
        version = manifest["catalogVersion"]
        assert client.get(f"/campus/pack/catalog?version={version}").status_code == 200
        response = client.get("/campus/pack/catalog?version=old")
        assert response.status_code == 409
        assert response.json()["detail"] == "Catalog changed. Fetch a new manifest."
