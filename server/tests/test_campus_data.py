import unittest

from app.utils.campus_data import building_for_map, photo_for_map, photo_content, cover_photos_for_map


class CampusDataTests(unittest.TestCase):
    def test_photo_tables_choose_cover_then_position_per_owner(self):
        rows = [
            {"photo_id": 1, "building_id": 1, "position": 0, "content": r"\x01"},
            {"photo_id": 2, "building_id": 1, "position": 1, "content": r"\x02", "is_cover": True},
            {"photo_id": 3, "building_id": 2, "position": 3, "content": r"\x03"},
            {"photo_id": 4, "building_id": 2, "position": 0, "content": r"\x04"},
        ]
        self.assertEqual(cover_photos_for_map(rows, "building_id", lambda identifier: f"/photos/building/{identifier}"), {
            "1": "/photos/building/2",
            "2": "/photos/building/4",
        })

    def test_location_cover_selection_does_not_inspect_image_content(self):
        rows = [
            {"photo_id": 1, "location_id": 9, "is_cover": True, "content": r"\xinvalid"},
            {"photo_id": 2, "location_id": 9, "position": 0, "content": r"\x89504e47", "mime_type": "image/png"},
        ]
        self.assertEqual(cover_photos_for_map(rows, "location_id", lambda identifier: f"/photos/location/{identifier}"), {
            "9": "/photos/location/1",
        })

    def test_supabase_bytea_photo(self):
        self.assertEqual(photo_content({"content": r"\xffd8ffe0"}), b"\xff\xd8\xff\xe0")

    def test_binary_photo_and_missing_or_invalid_photo(self):
        self.assertEqual(photo_content({"content": b"\x89PNG"}), b"\x89PNG")
        for photo in (None, "", r"\xinvalid"):
            self.assertIsNone(photo_content({"content": photo}))

    def test_map_never_embeds_legacy_photo_bytes_or_data_urls(self):
        self.assertIsNone(photo_for_map({"content": b"large photo", "photo": b"large photo"}))
        self.assertIsNone(photo_for_map({"image_url": "data:image/png;base64,iVBORw=="}))

    def test_building_photo_is_returned_to_mobile(self):
        building = building_for_map({
            "building_id": 5, "latitude": 16.7, "longitude": 121.6,
            "image_url": "https://example.com/building.jpg",
        })
        self.assertEqual(building["imageUrl"], "https://example.com/building.jpg")

    def test_existing_coordinates_and_schema(self):
        building = building_for_map({
            "building_id": 5, "building_name": "Infirmary",
            "building_code": "OSM-WAY-153312030",
            "latitude": "16.717874", "longitude": "121.688314",
        })
        self.assertEqual(building["id"], "5")
        self.assertEqual(building["name"], "Infirmary")
        self.assertEqual(building["latitude"], 16.717874)

    def test_category_and_parking_come_from_building_type(self):
        types = {"2": "Campus Services", "3": "Parking"}
        row = {"building_id": 5, "latitude": 16.7, "longitude": 121.6}
        services = building_for_map({**row, "type_id": 2}, types)
        self.assertEqual(services["category"], "Campus Services")
        self.assertFalse(services["isParking"])
        parking = building_for_map({**row, "type_id": 3}, types)
        self.assertEqual(parking["category"], "Parking")
        self.assertTrue(parking["isParking"])

    def test_unknown_or_missing_type_falls_back_to_building(self):
        types = {"2": "Campus Services"}
        row = {"building_id": 5, "latitude": 16.7, "longitude": 121.6}
        for type_id in (99, None):
            building = building_for_map({**row, "type_id": type_id}, types)
            self.assertEqual(building["category"], "Building")
            self.assertFalse(building["isParking"])
        self.assertEqual(building_for_map(row)["category"], "Building")

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
