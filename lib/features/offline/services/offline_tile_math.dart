import 'dart:math' as math;

/// One Web Mercator tile in the slippy-map scheme used by the campus map.
class OfflineTile {
  final int z;
  final int x;
  final int y;

  const OfflineTile(this.z, this.x, this.y);

  /// Relative cache key inside the offline store.
  String get path => 'tiles/$z/$x/$y.png';

  @override
  bool operator ==(Object other) =>
      other is OfflineTile && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

int tileX(double longitude, int zoom) {
  final count = 1 << zoom;
  final x = ((longitude + 180) / 360 * count).floor();
  return x.clamp(0, count - 1);
}

int tileY(double latitude, int zoom) {
  final count = 1 << zoom;
  final radians = latitude * math.pi / 180;
  final y = ((1 -
              math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
          2 *
          count)
      .floor();
  return y.clamp(0, count - 1);
}

/// Every tile covering the given box, from [minZoom] to [maxZoom] inclusive.
///
/// Returned coarse zoom first so a paused download still leaves a usable,
/// if less detailed, map on disk.
List<OfflineTile> tilesForBounds({
  required double south,
  required double west,
  required double north,
  required double east,
  required int minZoom,
  required int maxZoom,
}) {
  final tiles = <OfflineTile>[];
  for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
    final left = tileX(math.min(west, east), zoom);
    final right = tileX(math.max(west, east), zoom);
    // Tile rows count downwards, so the northern edge is the smaller index.
    final top = tileY(math.max(south, north), zoom);
    final bottom = tileY(math.min(south, north), zoom);
    for (var x = left; x <= right; x++) {
      for (var y = top; y <= bottom; y++) {
        tiles.add(OfflineTile(zoom, x, y));
      }
    }
  }
  return tiles;
}
