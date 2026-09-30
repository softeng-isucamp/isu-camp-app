import unittest

from app.utils.campus_data import building_for_map


class CampusDataTests(unittest.TestCase):
    def test_existing_coordinates_and_schema(self):
        building = building_for_map({
            "building_id": 5, "building_name": "Infirmary",
            "building_code": "OSM-WAY-153312030",
            "latitude": "16.717874", "longitude": "121.688314",
        })
        self.assertEqual(building["id"], "5")
        self.assertEqual(building["name"], "Infirmary")
        self.assertEqual(building["latitude"], 16.717874)

    def test_search_keywords_are_exposed_and_default_to_empty(self):
        row = {
            "building_id": 5, "building_name": "Library",
            "latitude": "16.717874", "longitude": "121.688314",
        }
        self.assertEqual(building_for_map(row)["keywords"], "")
        self.assertEqual(
            building_for_map({**row, "keywords": "books, study"})["keywords"],
            "books, study",
        )

    def test_null_coordinates_use_polygon_without_duplicate_closing_point(self):
        building = building_for_map({
            "building_id": 1,
            "polygon_coordinates": [[16, 121], [18, 121], [18, 123], [16, 123], [16, 121]],
        })
        self.assertEqual((building["latitude"], building["longitude"]), (17, 122))
        self.assertEqual(len(building["polygonCoordinates"]), 5)

    def test_unusable_locations_are_skipped(self):
        for latitude in (None, "invalid", float("nan"), 100):
            self.assertIsNone(building_for_map({
                "building_id": 2, "latitude": latitude, "longitude": 121,
                "polygon_coordinates": [[None, 121], [16]],
            }))


if __name__ == "__main__":
    unittest.main()
