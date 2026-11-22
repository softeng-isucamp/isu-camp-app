import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/offline/services/offline_tile_provider.dart';

class _RecordingCache implements MapCachingProvider {
  final stored = <String, CachedMapTileMetadata>{};
  @override
  bool get isSupported => true;
  @override
  Future<CachedMapTile?> getTile(String url) async => null;
  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async =>
      stored[url] = metadata;
}

void main() {
  final now = DateTime.utc(2026, 11, 22, 12);
  late _RecordingCache inner;
  late FreshForAtLeast cache;

  setUp(() {
    inner = _RecordingCache();
    cache = FreshForAtLeast(inner, now: () => now);
  });

  test('a tile that arrives already stale stays fresh for a day', () async {
    await cache.putTile(
      url: 'a',
      bytes: Uint8List(1),
      metadata: CachedMapTileMetadata(
        staleAt: now.subtract(const Duration(days: 5)),
        lastModified: null,
        etag: '"abc"',
      ),
    );
    expect(inner.stored['a']!.staleAt, now.add(const Duration(days: 1)));
    expect(inner.stored['a']!.etag, '"abc"',
        reason: 'revalidation after a day still sends the etag');
  });

  test('a longer freshness from the server is kept', () async {
    final later = now.add(const Duration(days: 3));
    await cache.putTile(
      url: 'b',
      metadata:
          CachedMapTileMetadata(staleAt: later, lastModified: null, etag: null),
    );
    expect(inner.stored['b']!.staleAt, later);
  });
}
