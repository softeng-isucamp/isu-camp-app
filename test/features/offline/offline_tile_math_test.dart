import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/data/campus_dataset.dart';
import 'package:isu_camp_app/features/offline/services/offline_tile_math.dart';

void main() {
  test('campus tile indices follow the slippy map scheme', () {
    // Matching the numbers tile.openstreetmap.org serves for this campus.
    expect(tileX(isuCampusWest, 15), 27459);
    expect(tileX(isuCampusEast, 15), 27461);
    expect(tileY(isuCampusNorth, 15), 14838);
    expect(tileY(isuCampusSouth, 15), 14840);
    expect(tileX(isuCampusWest, 19), 439357);
    expect(tileY(isuCampusSouth, 19), 237452);
  });

  test('the campus box is fully covered at every zoom the map allows', () {
    final tiles = tilesForBounds(
      south: isuCampusSouth,
      west: isuCampusWest,
      north: isuCampusNorth,
      east: isuCampusEast,
      minZoom: offlineTileMinZoom,
      maxZoom: offlineTileMaxZoom,
    );

    expect(tiles.toSet().length, tiles.length, reason: 'no tile downloads twice');
    expect(tiles.length, 1126);
    for (var zoom = offlineTileMinZoom; zoom <= offlineTileMaxZoom; zoom++) {
      final atZoom = tiles.where((tile) => tile.z == zoom);
      expect(atZoom, isNotEmpty);
      // Every corner of the camera bounds has a tile on disk.
      for (final corner in [
        (isuCampusSouth, isuCampusWest),
        (isuCampusSouth, isuCampusEast),
        (isuCampusNorth, isuCampusWest),
        (isuCampusNorth, isuCampusEast),
      ]) {
        expect(
          atZoom.contains(OfflineTile(
              zoom, tileX(corner.$2, zoom), tileY(corner.$1, zoom))),
          isTrue,
          reason: 'zoom $zoom is missing the tile at $corner',
        );
      }
    }
  });

  test('coarse zooms download first so a paused map is still usable', () {
    final tiles = tilesForBounds(
      south: isuCampusSouth,
      west: isuCampusWest,
      north: isuCampusNorth,
      east: isuCampusEast,
      minZoom: 15,
      maxZoom: 17,
    );
    expect(tiles.first.z, 15);
    expect(tiles.last.z, 17);
    expect(tiles.map((tile) => tile.z).toList(),
        orderedEquals(tiles.map((tile) => tile.z).toList()..sort()));
  });

  test('cache keys are stable and path-shaped', () {
    expect(const OfflineTile(17, 109839, 59355).path,
        'tiles/17/109839/59355.png');
  });

  test('swapped corners describe the same box', () {
    final straight = tilesForBounds(
        south: 16.71, west: 121.68, north: 16.73, east: 121.70,
        minZoom: 16, maxZoom: 16);
    final swapped = tilesForBounds(
        south: 16.73, west: 121.70, north: 16.71, east: 121.68,
        minZoom: 16, maxZoom: 16);
    expect(swapped, straight);
  });
}
