import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_pack_service.dart';

/// Serves campus tiles from the downloaded pack first and the network second.
///
/// With a pack installed the map draws with no requests at all. Without one,
/// tiles come from flutter_map's network provider, which keeps a disk cache
/// on Android and iOS (so a relaunch draws the campus without downloading it
/// again) and drops requests for tiles that scrolled away before they arrived.
class OfflineAwareTileProvider extends NetworkTileProvider {
  OfflineAwareTileProvider({OfflinePackService? pack, super.headers})
      : _pack = pack ?? OfflinePackService.instance,
        super(cachingProvider: _liveTileCache);

  final OfflinePackService _pack;

  /// The whole campus at zooms 15-19 is about 20 MB, so 100 MB holds it with
  /// room to spare. The default would let the cache grow to 1 GB.
  static final _liveTileCache = FreshForAtLeast(
    BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: 100000000),
  );

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) =>
      _pack.tileImage(coordinates.z, coordinates.x, coordinates.y) ??
      super.getImageWithCancelLoadingSupport(
          coordinates, options, cancelLoading);
}

/// Keeps each cached tile fresh for at least [minimum].
///
/// flutter_map dates a tile's freshness as `max-age` minus the CDN's `Age`.
/// OpenStreetMap's CDN often serves tiles that are days old against a
/// `max-age` of a few hours, so they arrive already stale and every relaunch
/// asks the server for each tile again. OpenStreetMap's own headers allow a
/// stale tile for 7 days (`stale-while-revalidate=604800`); a day is well
/// inside that, and a campus map rarely changes faster.
class FreshForAtLeast implements MapCachingProvider {
  FreshForAtLeast(this._inner,
      {this.minimum = const Duration(days: 1), DateTime Function()? now})
      : _now = now ?? DateTime.timestamp;

  final MapCachingProvider _inner;
  final Duration minimum;
  final DateTime Function() _now;

  @override
  bool get isSupported => _inner.isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) => _inner.getTile(url);

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) {
    final floor = _now().add(minimum);
    return _inner.putTile(
      url: url,
      bytes: bytes,
      metadata: metadata.staleAt.isAfter(floor)
          ? metadata
          : CachedMapTileMetadata(
              staleAt: floor,
              lastModified: metadata.lastModified,
              etag: metadata.etag,
            ),
    );
  }
}
