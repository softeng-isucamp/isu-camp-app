"""Build a small, redistributable campus tile fixture for the offline test APK.

Requires Pillow, rasterio, pyproj and requests. This deliberately renders OSM
data locally; it never downloads tiles from tile.openstreetmap.org.
"""

from __future__ import annotations

import hashlib
import io
import json
import math
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import numpy as np
import rasterio
import requests
from PIL import Image, ImageDraw
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject

BOUNDS = (121.683, 16.712, 121.701, 16.731)  # west, south, east, north
OSM_BBOX = (121.678, 16.708, 121.706, 16.735)
OSM_URL = "https://api.openstreetmap.org/api/0.6/map?bbox=" + ",".join(
    map(str, OSM_BBOX)
)
SENTINEL_SCENE = "S2B_51QUU_20251112_0_L2A"
SENTINEL_URL = (
    "https://sentinel-cogs.s3.us-west-2.amazonaws.com/"
    "sentinel-s2-l2a-cogs/51/Q/UU/2025/11/"
    + SENTINEL_SCENE
    + "/TCI.tif"
)
OUTPUT = Path(__file__).resolve().parents[1] / "assets/offline_tiles/campus_tiles.zip"
OSM_INPUT = Path("/tmp/kumpas-campus-osm.xml")


def tile_point(lon: float, lat: float, z: int) -> tuple[float, float]:
    scale = 2**z
    lat_rad = math.radians(lat)
    return (
        (lon + 180) / 360 * scale,
        (1 - math.asinh(math.tan(lat_rad)) / math.pi) / 2 * scale,
    )


def tile_range(z: int) -> tuple[range, range]:
    west, south, east, north = BOUNDS
    x0, y0 = tile_point(west, north, z)
    x1, y1 = tile_point(east, south, z)
    return range(math.floor(x0), math.floor(x1) + 1), range(
        math.floor(y0), math.floor(y1) + 1
    )


def tile_mercator_bounds(z: int, x: int, y: int) -> tuple[float, ...]:
    extent = 20037508.342789244
    side = 2 * extent / 2**z
    left = -extent + x * side
    top = extent - y * side
    return left, top - side, left + side, top


def download_osm() -> bytes:
    if OSM_INPUT.exists():
        return OSM_INPUT.read_bytes()
    response = requests.get(
        OSM_URL,
        headers={"User-Agent": "ISU-CAMP-offline-test/0.1 (https://kumpas.live)"},
        timeout=90,
    )
    response.raise_for_status()
    OSM_INPUT.write_bytes(response.content)
    return response.content


def parse_osm(raw: bytes):
    root = ET.fromstring(raw)
    nodes = {
        node.get("id"): (float(node.get("lon")), float(node.get("lat")))
        for node in root.findall("node")
    }
    ways = []
    for way in root.findall("way"):
        tags = {tag.get("k"): tag.get("v") for tag in way.findall("tag")}
        coords = [
            nodes[ref.get("ref")]
            for ref in way.findall("nd")
            if ref.get("ref") in nodes
        ]
        if len(coords) >= 2:
            ways.append((tags, coords))
    return ways


def draw_osm_tile(ways, z: int, tx: int, ty: int) -> bytes:
    scale = 2
    image = Image.new("RGB", (256 * scale, 256 * scale), "#f3f1e8")
    draw = ImageDraw.Draw(image)

    def points(coords):
        return [
            ((tile_point(lon, lat, z)[0] - tx) * 256 * scale,
             (tile_point(lon, lat, z)[1] - ty) * 256 * scale)
            for lon, lat in coords
        ]

    def intersects(coords):
        ps = points(coords)
        return (max(p[0] for p in ps) >= 0 and min(p[0] for p in ps) <= 512
                and max(p[1] for p in ps) >= 0 and min(p[1] for p in ps) <= 512)

    for tags, coords in ways:
        if not intersects(coords) or coords[0] != coords[-1]:
            continue
        kind = tags.get("landuse") or tags.get("leisure") or tags.get("natural")
        color = {
            "farmland": "#e5e6c8", "grass": "#dce9cc", "park": "#cbe5bd",
            "wood": "#bad5ac", "water": "#b8dce8", "wetland": "#d1e3d8",
            "residential": "#eeece3", "industrial": "#e7e2da",
        }.get(kind)
        if color:
            draw.polygon(points(coords), fill=color)

    widths = {"trunk": 11, "primary": 9, "secondary": 8,
              "tertiary": 7, "unclassified": 6, "residential": 5,
              "service": 4, "track": 3, "footway": 2, "path": 2}
    for tags, coords in ways:
        highway = tags.get("highway")
        if highway not in widths or not intersects(coords):
            continue
        width = widths[highway] * scale
        ps = points(coords)
        draw.line(ps, fill="#c6c2b8", width=width + 3 * scale, joint="curve")
        draw.line(ps, fill="#fffdfa" if width >= 4 * scale else "#ede8d8",
                  width=width, joint="curve")

    for tags, coords in ways:
        if "building" not in tags or coords[0] != coords[-1] or not intersects(coords):
            continue
        ps = points(coords)
        draw.polygon(ps, fill="#ddd8ca")
        draw.line(ps, fill="#c3bdad", width=scale, joint="curve")

    image = image.resize((256, 256), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def read_sentinel_crop():
    from rasterio.warp import transform_bounds
    from rasterio.windows import from_bounds as window_from_bounds

    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"):
        with rasterio.open(SENTINEL_URL) as dataset:
            window = window_from_bounds(
                *transform_bounds("EPSG:4326", dataset.crs, *OSM_BBOX),
                transform=dataset.transform,
            ).round_offsets().round_lengths()
            return dataset.read(window=window), dataset.window_transform(window), dataset.crs


def draw_satellite_tile(source, source_transform, source_crs, z, x, y) -> bytes:
    result = np.zeros((3, 256, 256), dtype=np.uint8)
    destination_transform = from_bounds(*tile_mercator_bounds(z, x, y), 256, 256)
    for band in range(3):
        reproject(
            source=source[band], destination=result[band],
            src_transform=source_transform, src_crs=source_crs,
            dst_transform=destination_transform, dst_crs="EPSG:3857",
            resampling=Resampling.bilinear,
        )
    image = Image.fromarray(result.transpose(1, 2, 0))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def main():
    raw_osm = download_osm()
    ways = parse_osm(raw_osm)
    sentinel, sentinel_transform, sentinel_crs = read_sentinel_crop()
    manifest = {
        "schemaVersion": 1,
        "bounds": list(BOUNDS),
        "layers": {
            "osm": {
                "minZoom": 15, "maxZoom": 18, "bounds": list(BOUNDS),
                "attribution": "© OpenStreetMap contributors (ODbL)",
                "source": OSM_URL,
                "sourceSha256": hashlib.sha256(raw_osm).hexdigest(),
                "license": "https://www.openstreetmap.org/copyright",
            },
            "satellite": {
                "minZoom": 15, "maxZoom": 17, "bounds": list(BOUNDS),
                "attribution": "Contains modified Copernicus Sentinel data 2025",
                "source": SENTINEL_URL,
                "scene": SENTINEL_SCENE,
                "license": "https://sentinels.copernicus.eu/documents/247904/690755/Sentinel_Data_Legal_Notice",
            },
        },
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest, indent=2))
        for layer, max_zoom in (("osm", 18), ("satellite", 17)):
            count = 0
            for z in range(15, max_zoom + 1):
                xs, ys = tile_range(z)
                for x in xs:
                    for y in ys:
                        content = (
                            draw_osm_tile(ways, z, x, y)
                            if layer == "osm" else
                            draw_satellite_tile(
                                sentinel, sentinel_transform, sentinel_crs, z, x, y
                            )
                        )
                        archive.writestr(f"{layer}/{z}/{x}/{y}.png", content)
                        count += 1
            print(layer, count)
    print(OUTPUT, OUTPUT.stat().st_size, hashlib.sha256(OUTPUT.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
