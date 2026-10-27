import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_pack_service.dart';

/// Serves campus tiles from the downloaded pack first and the network second.
///
/// With a pack installed the map draws with no requests at all; without one it
/// behaves exactly like the default network provider.
class OfflineAwareTileProvider extends TileProvider {
  OfflineAwareTileProvider({OfflinePackService? pack, super.headers})
      : _pack = pack ?? OfflinePackService.instance;

  final OfflinePackService _pack;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _pack.tileImage(coordinates.z, coordinates.x, coordinates.y) ??
      NetworkImage(getTileUrl(coordinates, options), headers: headers);
}
