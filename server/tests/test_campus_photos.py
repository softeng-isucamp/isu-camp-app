import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.routes import campus


class CampusPhotoTests(unittest.TestCase):
    def test_metadata_timeout_does_not_break_buildings(self):
        def rows(table, columns, order):
            if table.endswith("_photo"):
                raise RuntimeError("statement timeout")
            if table == "building":
                return [{"building_id": 1, "building_name": "Test",
                         "latitude": 16.72, "longitude": 121.69,
                         "keywords": "search keyword"}]
            return []
        with patch.object(campus, "routing_rows", side_effect=rows), patch.object(campus, "logger"):
            result = campus.get_buildings()
        self.assertEqual(result["buildings"][0]["keywords"], "search keyword")

    def test_only_selected_covers_are_fetched_in_small_batches(self):
        metadata = [{"photo_id": i, "location_id": i, "is_cover": True}
                    for i in range(12)]
        metadata.append({"photo_id": 999, "location_id": 0, "is_cover": False})
        fetched = []
        def table(_):
            query = MagicMock()
            def ids(column, values):
                fetched.extend(values)
                self.assertLessEqual(len(values), 5)
                query.execute.return_value = SimpleNamespace(data=[
                    {"photo_id": value, "location_id": value, "content": r"\x01"}
                    for value in values])
                return query
            query.select.return_value = query
            query.in_.side_effect = ids
            return query
        with patch.object(campus, "routing_rows", return_value=metadata), patch.object(campus.supabase, "table", side_effect=table):
            result = campus.map_cover_photos("location_photo", "location_id")
        self.assertEqual(len(result), 12)
        self.assertNotIn(999, fetched)


if __name__ == "__main__":
    unittest.main()
