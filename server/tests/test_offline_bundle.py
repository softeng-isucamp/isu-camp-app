import unittest

from app.utils.campus_data import bundle_photo_urls, bundle_version, offline_manifest


def bundle(photo_host="http://localhost:8000"):
    return {
        "buildings": [
            {
                "id": "1",
                "name": "Admin",
                "imageUrl": f"{photo_host}/campus/photos/building/4",
                "rooms": [
                    {"id": "7", "imageUrl": f"{photo_host}/campus/photos/location/9"},
                    {"id": "8", "imageUrl": None},
                ],
            },
            {"id": "2", "name": "Library", "imageUrl": None, "rooms": []},
        ],
        "skippedCount": 0,
        "graph": {"nodes": [{"node_id": 1}], "pathways": [{"pathway_id": 3}],
                  "modes": [], "points": []},
    }


class OfflineBundleTests(unittest.TestCase):
    def test_same_dataset_keeps_one_version_across_api_hosts(self):
        local = bundle("http://10.0.2.2:8000")
        live = bundle("https://api.kumpas.live")
        self.assertEqual(bundle_version(local), bundle_version(live))

    def test_version_changes_when_campus_data_changes(self):
        changed = bundle()
        changed["buildings"][1]["name"] = "New Library"
        self.assertNotEqual(bundle_version(bundle()), bundle_version(changed))

    def test_version_ignores_key_order(self):
        reordered = {key: bundle()[key] for key in ("graph", "skippedCount", "buildings")}
        self.assertEqual(bundle_version(bundle()), bundle_version(reordered))

    def test_photo_urls_cover_buildings_and_rooms_without_duplicates(self):
        payload = bundle()
        payload["buildings"][1]["imageUrl"] = payload["buildings"][0]["imageUrl"]
        self.assertEqual(bundle_photo_urls(payload["buildings"]), [
            "http://localhost:8000/campus/photos/building/4",
            "http://localhost:8000/campus/photos/location/9",
        ])

    def test_manifest_reports_download_cost_without_the_payload(self):
        payload = bundle()
        payload["version"] = bundle_version(payload)
        payload["generatedAt"] = "2026-10-14T00:00:00+00:00"
        manifest = offline_manifest(payload)
        self.assertEqual(manifest["version"], payload["version"])
        self.assertEqual(manifest["generatedAt"], "2026-10-14T00:00:00+00:00")
        self.assertEqual(manifest["buildingCount"], 2)
        self.assertEqual(manifest["roomCount"], 2)
        self.assertEqual(manifest["photoCount"], 2)
        self.assertEqual(manifest["pathwayCount"], 1)
        self.assertGreater(manifest["dataBytes"], 0)
        self.assertNotIn("buildings", manifest)


if __name__ == "__main__":
    unittest.main()
