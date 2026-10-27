"""Render a cached OpenStreetMap extract into the offline builder's XYZ PNGs.

python scripts/render_offline_tiles.py --source /srv/campus.osm.json \
    --output /srv/campus-xyz --download-source

Downloads one small raw OSM extract, never hosted map tiles. Keep the source
extract and source.json alongside the tiles for ODbL provenance. The app displays
OpenStreetMap contributor attribution. Re-run with --download-source to refresh.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.offline_pack import campus_tile_paths

BACKGROUND = '#f3f1ea'
SCALE = 2


def tile_coordinates():
    return [tuple(map(int, path.removeprefix('tiles/').removesuffix('.png').split('/')))
            for path in campus_tile_paths()]


def source_bounds():
    tiles = tile_coordinates()
    latitude = lambda y, z: math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / 2**z))))
    return (min(latitude(y + 1, z) for z, x, y in tiles) - .002,
            min(x / 2**z * 360 - 180 for z, x, y in tiles) - .002,
            max(latitude(y, z) for z, x, y in tiles) + .002,
            max((x + 1) / 2**z * 360 - 180 for z, x, y in tiles) + .002)


def load_source(raw):
    if not raw.lstrip().startswith(b'<'):
        return json.loads(raw)
    root = ET.fromstring(raw)
    if root.tag != 'osm':
        raise ValueError('Expected an OSM data extract')
    nodes = {node.attrib['id']: {'lat': float(node.attrib['lat']), 'lon': float(node.attrib['lon'])}
             for node in root.findall('node')}
    ways = {}
    elements = []
    for way in root.findall('way'):
        geometry = [nodes[node.attrib['ref']] for node in way.findall('nd')]
        ways[way.attrib['id']] = geometry
        elements.append({'type': 'way', 'geometry': geometry,
                         'tags': {tag.attrib['k']: tag.attrib['v'] for tag in way.findall('tag')}})
    for relation in root.findall('relation'):
        tags = {tag.attrib['k']: tag.attrib['v'] for tag in relation.findall('tag')}
        members = relation.findall('member')
        # The map API can include parent relations extending beyond the extract.
        # Skip incomplete relations rather than inventing missing geometry.
        if tags.get('type') == 'multipolygon' and all(m.attrib['type'] == 'way' and m.attrib['ref'] in ways for m in members):
            elements.append({'type': 'relation', 'tags': tags, 'members': [
                {'role': m.attrib.get('role', ''), 'geometry': ways[m.attrib['ref']]} for m in members]})
    for node in root.findall('node'):
        tags = {tag.attrib['k']: tag.attrib['v'] for tag in node.findall('tag')}
        if tags.get('place'):
            elements.append({'type': 'node', **nodes[node.attrib['id']], 'tags': tags})
    return {'elements': elements, 'osm3s': {key: root.attrib.get(key) for key in
            ('generator', 'copyright', 'attribution', 'license')},
            'bounds': root.find('bounds').attrib if root.find('bounds') is not None else None}


def download_source(path, endpoint='https://api.openstreetmap.org/api/0.6/map'):
    south, west, north, east = source_bounds()
    bbox = ','.join(map(str, (south, west, north, east)))
    query = (f'[out:json][timeout:90];(way({bbox});'
             f'relation["type"="multipolygon"]({bbox});node["place"]({bbox}););out geom;')
    if urllib.parse.urlsplit(endpoint).path.rstrip('/').endswith('/map'):
        endpoint += '?' + urllib.parse.urlencode({'bbox': f'{west},{south},{east},{north}'})
        data = None
    else:
        data = urllib.parse.urlencode({'data': query}).encode()
    request = urllib.request.Request(endpoint, data=data, headers={
            'User-Agent': 'KumpasOfflineBuilder/1.0 (https://github.com/softeng-isucamp/isu-camp-app)'})
    with urllib.request.urlopen(request, timeout=120) as response:
        content = response.read()
    payload = load_source(content)
    validate_source(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_suffix('.tmp')
    staging.write_bytes(content)
    staging.replace(path)


def validate_source(payload):
    if payload.get('remark') or not payload.get('elements'):
        raise ValueError('OSM extract is empty or incomplete: ' + payload.get('remark', 'no elements'))
    if not any(e.get('tags', {}).get('highway') and e.get('geometry') for e in payload['elements']):
        raise ValueError('OSM extract has no mapped roads')


def project(point, zoom):
    size = 256 * 2**zoom
    lat = math.radians(point['lat'])
    return ((point['lon'] + 180) / 360 * size,
            (1 - math.asinh(math.tan(lat)) / math.pi) / 2 * size)


def area_color(tags):
    if tags.get('natural') == 'water' or tags.get('waterway') == 'riverbank' or tags.get('landuse') == 'reservoir':
        return '#a8d6e5'
    if tags.get('building') and tags['building'] != 'no':
        return '#d9d3c9'
    if tags.get('leisure') in ('pitch', 'track', 'stadium'):
        return '#c2ddbc'
    if tags.get('landuse') in ('forest', 'orchard') or tags.get('natural') in ('wood', 'scrub'):
        return '#c4d8b5'
    if tags.get('landuse') in ('grass', 'farmland', 'meadow', 'plant_nursery') or tags.get('leisure') in ('park', 'garden') or tags.get('natural') == 'grassland':
        return '#dce7c7'
    if tags.get('amenity') in ('school', 'university', 'college'):
        return '#ecebdc'
    if tags.get('landuse') == 'residential':
        return '#e8e5df'
    if tags.get('amenity') == 'parking':
        return '#e1e1dc'
    return None


def rings(members):
    """Join fragmented multipolygon members, including reversed OSM ways."""
    pending = [list(m['geometry']) for m in members if len(m.get('geometry', [])) > 1]
    while pending:
        ring = pending.pop()
        while ring[0] != ring[-1]:
            for i, part in enumerate(pending):
                if ring[-1] == part[0]:
                    ring.extend(part[1:])
                elif ring[-1] == part[-1]:
                    ring.extend(reversed(part[:-1]))
                elif ring[0] == part[-1]:
                    ring = part[:-1] + ring
                elif ring[0] == part[0]:
                    ring = list(reversed(part[1:])) + ring
                else:
                    continue
                pending.pop(i)
                break
            else:
                break
        if len(ring) >= 4 and ring[0] == ring[-1]:
            yield ring


def features(payload, zoom):
    areas, roads, waterways, labels = [], [], [], []
    for element in payload['elements']:
        tags = element.get('tags', {})
        geometry = element.get('geometry', [])
        color = area_color(tags)
        if color:
            if element['type'] == 'relation':
                members = element.get('members', [])
                outer = list(rings([m for m in members if m.get('role', '') in ('', 'outer')]))
                inner = list(rings([m for m in members if m.get('role') == 'inner']))
            else:
                outer = [geometry] if len(geometry) >= 4 and geometry[0] == geometry[-1] else []
                inner = []
            if outer:
                outlines = [[project(p, zoom) for p in ring] for ring in outer]
                holes = [[project(p, zoom) for p in ring] for ring in inner]
                # Broad land uses below parks/campuses, then water, then buildings.
                order = 4 if tags.get('building') else 3 if color == '#a8d6e5' else 2 if tags.get('leisure') else 1 if tags.get('amenity') else 0
                areas.append((order, outlines, holes, color))
                if zoom >= 18 and tags.get('name') and tags.get('building'):
                    points = outlines[0][:-1]
                    labels.append((sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points), tags['name']))
        if len(geometry) > 1:
            points = [project(p, zoom) for p in geometry]
            if tags.get('highway') and tags.get('area') != 'yes':
                kind = tags['highway']
                meters = {'motorway': 12, 'trunk': 11, 'primary': 10, 'secondary': 9, 'tertiary': 8,
                          'residential': 6, 'unclassified': 6, 'service': 4, 'track': 3}.get(kind, 1.5)
                width = max(1, meters / (156543.03392 * math.cos(math.radians(16.72)) / 2**zoom))
                color = '#f7d899' if kind in ('motorway', 'trunk', 'primary', 'secondary') else '#ffffff'
                if kind in ('footway', 'path', 'steps', 'pedestrian', 'cycleway', 'track'):
                    color = '#d5bca4'
                roads.append((width, points, color))
            elif tags.get('waterway'):
                waterways.append((points, max(1, 3 * 2**(zoom - 17))))
        if element['type'] == 'node' and tags.get('place') and tags.get('name'):
            x, y = project(element, zoom)
            labels.append((x, y, tags['name']))
    return sorted(areas, key=lambda a: a[0]), roads, waterways, labels


def render_tile(zoom, column, row, prepared, font):
    areas, roads, waterways, labels = prepared
    origin_x, origin_y = column * 256, row * 256
    image = Image.new('RGB', (256 * SCALE, 256 * SCALE), BACKGROUND)
    draw = ImageDraw.Draw(image)
    def local(points):
        return [((x - origin_x) * SCALE, (y - origin_y) * SCALE) for x, y in points]
    def visible(points, padding=32):
        return (max(x for x, y in points) >= origin_x - padding and min(x for x, y in points) <= origin_x + 256 + padding
                and max(y for x, y in points) >= origin_y - padding and min(y for x, y in points) <= origin_y + 256 + padding)
    for order, outlines, holes, color in areas:
        if not any(visible(points) for points in outlines):
            continue
        mask = Image.new('L', image.size)
        painter = ImageDraw.Draw(mask)
        for points in outlines:
            painter.polygon(local(points), fill=255)
        for points in holes:
            painter.polygon(local(points), fill=0)
        image.paste(color, mask=mask)
        if order == 4:
            for points in outlines + holes:
                draw.line(local(points), fill='#beb8af', width=SCALE, joint='curve')
    for points, width in waterways:
        if visible(points):
            draw.line(local(points), fill='#a8d6e5', width=max(1, round(width * SCALE)), joint='curve')
    # Draw all road casings first, so intersections remain connected.
    for casing in (True, False):
        for width, points, color in roads:
            if visible(points, width + 4):
                line_width = max(1, round((width + (1.8 if casing else 0)) * SCALE))
                draw.line(local(points), fill='#c8c3b9' if casing else color, width=line_width, joint='curve')
                radius = line_width / 2
                for x, y in (local(points)[0], local(points)[-1]):
                    draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill='#c8c3b9' if casing else color)
    for x, y, name in labels:
        if origin_x - 180 <= x <= origin_x + 436 and origin_y - 20 <= y <= origin_y + 276:
            # World-space anchors keep text continuous across tile boundaries.
            if draw.textlength(name, font=font) <= 300 * SCALE:
                draw.text(((x-origin_x)*SCALE, (y-origin_y)*SCALE), name, font=font,
                          fill='#55594f', anchor='mm', stroke_width=2, stroke_fill='#f9f8f1')
    return image.resize((256, 256), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--download-source', action='store_true')
    parser.add_argument('--endpoint', default='https://api.openstreetmap.org/api/0.6/map')
    args = parser.parse_args()
    if args.download_source:
        download_source(args.source, args.endpoint)
    raw = args.source.read_bytes()
    payload = load_source(raw)
    validate_source(payload)
    font = ImageFont.load_default(size=11 * SCALE)
    prepared = {}
    for zoom, column, row in tile_coordinates():
        if zoom not in prepared:
            prepared[zoom] = features(payload, zoom)
        target = args.output / str(zoom) / str(column) / f'{row}.png'
        target.parent.mkdir(parents=True, exist_ok=True)
        render_tile(zoom, column, row, prepared[zoom], font).save(target)
    metadata = {'source': 'https://www.openstreetmap.org', 'license': 'ODbL-1.0',
                'attribution': '© OpenStreetMap contributors',
                'sourceSha256': hashlib.sha256(raw).hexdigest(),
                'rendererSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                'osm': payload.get('osm3s'), 'bounds': source_bounds(), 'tileCount': len(tile_coordinates())}
    (args.output / 'source.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Rendered {metadata["tileCount"]} tiles from {len(payload["elements"])} OSM elements')


if __name__ == '__main__':
    main()
