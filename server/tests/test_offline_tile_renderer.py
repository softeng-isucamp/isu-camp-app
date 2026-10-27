import importlib.util
from pathlib import Path
import unittest

from PIL import ImageFont

spec = importlib.util.spec_from_file_location('renderer', Path(__file__).resolve().parents[1] / 'scripts/render_offline_tiles.py')
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


def coordinate(x, y, zoom=19):
    import math
    size = 256 * 2**zoom
    return {'lon': x / size * 360 - 180,
            'lat': math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / size))))}


class OfflineTileRendererTests(unittest.TestCase):
    def test_osm_xml_resolves_way_nodes_and_skips_incomplete_parent_relations(self):
        raw = b'''<osm copyright="OpenStreetMap and contributors">
          <node id="1" lat="16.72" lon="121.69"/>
          <node id="2" lat="16.721" lon="121.691"/>
          <way id="3"><nd ref="1"/><nd ref="2"/><tag k="highway" v="service"/></way>
          <relation id="4"><member type="way" ref="999" role="outer"/>
            <tag k="type" v="multipolygon"/><tag k="natural" v="water"/></relation>
        </osm>'''
        source = renderer.load_source(raw)
        renderer.validate_source(source)
        self.assertEqual(len(source['elements']), 1)
        self.assertEqual(source['elements'][0]['geometry'][1], {'lat': 16.721, 'lon': 121.691})
        self.assertEqual(source['osm3s']['copyright'], 'OpenStreetMap and contributors')

    def test_xml_with_missing_road_nodes_is_rejected(self):
        with self.assertRaises(KeyError):
            renderer.load_source(b'<osm><way id="1"><nd ref="missing"/></way></osm>')

    def test_source_bounds_cover_all_full_tiles_and_padding(self):
        south, west, north, east = renderer.source_bounds()
        for zoom, x, y in renderer.tile_coordinates():
            top = coordinate(x * 256, y * 256, zoom)
            bottom = coordinate((x+1) * 256, (y+1) * 256, zoom)
            self.assertLess(south, bottom['lat'])
            self.assertGreater(north, top['lat'])
            self.assertLess(west, top['lon'])
            self.assertGreater(east, bottom['lon'])

    def test_missing_and_partial_extracts_are_rejected(self):
        for payload in ({}, {'elements': [{'tags': {}}]}, {'remark': 'runtime error', 'elements': [{'tags': {'highway': 'service'}, 'geometry': [1, 2]}]}):
            with self.assertRaises(ValueError):
                renderer.validate_source(payload)

    def test_real_geometry_renders_connected_road_across_tile_edges(self):
        x, y = 439357, 237452
        geometry = [coordinate(x*256 + 30, y*256 + 128), coordinate(x*256 + 450, y*256 + 128)]
        payload = {'elements': [{'type': 'way', 'tags': {'highway': 'residential'}, 'geometry': geometry}]}
        prepared = renderer.features(payload, 19)
        font = ImageFont.load_default(size=22)
        left = renderer.render_tile(19, x, y, prepared, font)
        right = renderer.render_tile(19, x+1, y, prepared, font)
        self.assertEqual(left.size, (256, 256))
        self.assertEqual(left.getpixel((255, 128)), right.getpixel((0, 128)))
        self.assertEqual(left.getpixel((255, 128)), (255, 255, 255))
        self.assertNotEqual(left.getpixel((255, 128)), left.getpixel((255, 0)))

    def test_multipolygon_holes_preserve_underlying_map(self):
        x, y = 439357, 237452
        def box(a, b):
            return [coordinate(x*256+i, y*256+j) for i,j in [(a,a),(b,a),(b,b),(a,b),(a,a)]]
        outer, inner = box(20, 235), box(90, 165)
        members = [{'role': 'outer', 'geometry': outer[:3]},
                   {'role': 'outer', 'geometry': list(reversed(outer[2:]))},
                   {'role': 'inner', 'geometry': inner}]
        payload = {'elements': [{'type': 'relation', 'tags': {'natural': 'water'}, 'members': members}]}
        image = renderer.render_tile(19, x, y, renderer.features(payload, 19), ImageFont.load_default(size=22))
        self.assertEqual(image.getpixel((50, 50)), (168, 214, 229))
        self.assertEqual(image.getpixel((128, 128)), (243, 241, 234))


if __name__ == '__main__':
    unittest.main()
