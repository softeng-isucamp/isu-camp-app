import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../auth/services/auth_service.dart';
import '../../dashboard/data/campus_dataset.dart';
import '../../dashboard/models/campus_models.dart';
import '../models/offline_pack.dart';
import 'offline_file_store.dart';
import 'offline_routing_engine.dart';
import 'offline_tile_math.dart';

/// Relative cache key for one campus photo.
///
/// Keyed on the URL path, not the whole URL, so switching between the local
/// and deployed API does not re-download every photo.
String offlinePhotoPath(String url) {
  final uri = Uri.tryParse(url);
  final key = uri == null || !uri.hasScheme
      ? url
      : [uri.path, uri.query].where((part) => part.isNotEmpty).join('?');
  return 'photos/${sha1.convert(utf8.encode(key))}.img';
}

/// Owns the downloaded campus pack: the dataset, its photos, and its map tiles.
///
/// Downloads only ever start from an explicit user action. When the backend
/// publishes a newer dataset the service records it and notifies listeners;
/// it never replaces what is on disk on its own.
class OfflinePackService extends ChangeNotifier {
  OfflinePackService({
    OfflineFileStore? store,
    http.Client? client,
    String Function()? baseUrl,
    int maxTileZoom = offlineTileMaxZoom,
  })  : _store = store ?? OfflineFileStore(),
        _client = client,
        _baseUrl = baseUrl ?? (() => AuthService.baseUrl),
        _maxTileZoom = maxTileZoom;

  static OfflinePackService _instance = OfflinePackService();

  static OfflinePackService get instance => _instance;

  /// Lets a test drive the widgets and `CampusService` from a temporary cache.
  @visibleForTesting
  static set instance(OfflinePackService service) => _instance = service;

  static const String _bundlePath = 'bundle.json';
  static const String _metaPath = 'meta.json';
  static const int _parallelDownloads = 4;

  /// How many finished files to collect before saving resume progress.
  static const int _checkpointEvery = 40;

  /// Stop after this many consecutive failures; the tile host is rate limiting
  /// or the connection dropped, and retrying every remaining tile is pointless.
  static const int _failureBudget = 8;

  final OfflineFileStore _store;
  final http.Client? _client;
  final String Function() _baseUrl;

  /// Deepest zoom to cache. Lowered in tests to keep them quick.
  final int _maxTileZoom;

  OfflinePackStatus _status = const OfflinePackStatus();
  Map<String, dynamic>? _bundle;
  List<CampusBuilding>? _buildings;
  bool _pauseRequested = false;
  final Map<String, int> _receivedBytes = {};
  final Stopwatch _progressClock = Stopwatch()..start();
  int _lastProgressAt = -100;
  Timer? _progressTimer;
  Future<void>? _activeDownload;
  Future<void>? _activeDelete;

  OfflinePackStatus get status => _status;

  /// Campus buildings from the downloaded dataset, or null when none is stored.
  List<CampusBuilding>? get buildings => _buildings;

  http.Client? _fallbackClient;

  /// One client for the service, so a download reuses its connections
  /// instead of opening a fresh pool for every tile.
  http.Client get _http => _client ?? (_fallbackClient ??= http.Client());

  /// Reads whatever is already on disk. Safe to call more than once.
  Future<void> load() async {
    // A running download already owns the status; re-reading would undo it.
    if (_status.isBusy) return;
    if (!_store.isSupported || !await _store.open()) {
      _update(_status.copyWith(state: OfflinePackState.unsupported));
      return;
    }
    final meta = await _readJson(_metaPath);
    final bundle = await _readJson(_bundlePath);
    if (meta == null || bundle == null) {
      _update(const OfflinePackStatus());
      return;
    }
    _adoptBundle(bundle);
    final complete = meta['complete'] == true;
    _update(OfflinePackStatus(
      state: complete ? OfflinePackState.ready : OfflinePackState.incomplete,
      installedVersion: meta['version'] as String?,
      updateVersion: meta['updateVersion'] as String?,
      completedFiles: (meta['completedFiles'] as num?)?.toInt() ?? 0,
      totalFiles: (meta['totalFiles'] as num?)?.toInt() ?? 0,
      bytesOnDisk: await _store.bytesOnDisk(),
      installedAt: DateTime.tryParse(meta['installedAt'] as String? ?? ''),
      lastCheckedAt: DateTime.tryParse(meta['lastCheckedAt'] as String? ?? ''),
      message: complete
          ? null
          : 'Download stopped before it finished. Resume to complete it.',
    ));
  }

  /// Asks the backend whether a newer dataset exists. Never downloads it.
  ///
  /// Returns true only when an update is waiting for the user to accept.
  Future<bool> checkForUpdate() async {
    final installed = _status.installedVersion;
    if (installed == null || _status.isBusy) return false;
    try {
      final response = await _http
          .get(Uri.parse('${_baseUrl()}/campus/offline/manifest'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final available = manifest['version'] as String?;
      final checkedAt = DateTime.now();
      _update(_status.copyWith(
        updateVersion: available,
        lastCheckedAt: checkedAt,
        clearUpdateVersion: available == null || available == installed,
      ));
      await _writeMeta(complete: _status.isReady);
      return _status.hasUpdate;
    } catch (_) {
      // No connection, or the backend is older than this app. Keep using what
      // is already downloaded and say nothing.
      return false;
    }
  }

  /// Downloads, resumes, or updates the pack. Started only by the user.
  Future<void> download() {
    return _activeDownload ??= _runDownload().whenComplete(() {
      _activeDownload = null;
    });
  }

  /// Asks the running download to stop. Finished files stay on disk.
  void pause() {
    if (_status.isBusy) _pauseRequested = true;
  }

  /// Removes every downloaded file and returns the app to online-only.
  ///
  /// Calling this again while it runs joins the first delete rather than
  /// racing it over the same directory tree.
  Future<void> delete() {
    return _activeDelete ??= _runDelete().whenComplete(() {
      _activeDelete = null;
    });
  }

  Future<void> _runDelete() async {
    _pauseRequested = true;
    await _activeDownload;
    if (!_store.isSupported) return;
    await _store.deleteAll();
    _bundle = null;
    _buildings = null;
    _update(const OfflinePackStatus());
  }

  Future<void> _runDownload() async {
    if (!_store.isSupported || !await _store.open()) {
      _update(_status.copyWith(state: OfflinePackState.unsupported));
      return;
    }
    _pauseRequested = false;
    final resumeState = _status.state;
    _update(_status.copyWith(
        state: OfflinePackState.downloading, clearMessage: true));

    final Map<String, dynamic> bundle;
    try {
      final bytes = await _receive(
        _bundlePath,
        Uri.parse('${_baseUrl()}/campus/offline/bundle'),
        const Duration(seconds: 60),
      );
      bundle = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (error) {
      _receivedBytes.remove(_bundlePath);
      _progressTimer?.cancel();
      _progressTimer = null;
      _update(_status.copyWith(
        bytesInFlight: 0,
        // Keep whatever was stored: a half-finished pack must not be
        // reported as ready just because the update attempt failed.
        state: resumeState,
        message: error is _DownloadFailure
            ? error.message
            : 'Could not reach the campus server. Check your connection and try again.',
      ));
      return;
    }

    final version = bundle['version'] as String?;
    // A new dataset can reuse photo ids for different images, so the stored
    // photos go with the dataset they came from. Map tiles do not.
    if (version != null && version != _status.installedVersion) {
      await _store.deletePrefix('photos/');
    }
    await _store.writeText(_bundlePath, jsonEncode(bundle));
    _adoptBundle(bundle);
    _receivedBytes.remove(_bundlePath);
    _update(_status.copyWith(
      bytesOnDisk: await _store.bytesOnDisk(),
      bytesInFlight: 0,
    ));

    final photoPaths = <String, String>{
      for (final url in _photoUrls(bundle)) offlinePhotoPath(url): url,
    };
    final tiles = tilesForBounds(
      south: isuCampusSouth,
      west: isuCampusWest,
      north: isuCampusNorth,
      east: isuCampusEast,
      minZoom: offlineTileMinZoom,
      maxZoom: _maxTileZoom,
    );

    final work = <String, Uri>{
      for (final entry in photoPaths.entries)
        if (!_store.contains(entry.key)) entry.key: Uri.parse(entry.value),
      for (final tile in tiles)
        if (!_store.contains(tile.path)) tile.path: Uri.parse(_tileUrl(tile)),
    };
    final total = 1 + photoPaths.length + tiles.length;
    var completed = total - work.length;

    _update(_status.copyWith(
      installedVersion: version,
      completedFiles: completed,
      totalFiles: total,
      clearUpdateVersion: true,
    ));
    await _writeMeta(
        complete: work.isEmpty, generatedAt: bundle['generatedAt']);

    var failures = 0;
    var checkpoint = completed;
    final pending = work.entries.toList();
    for (var start = 0;
        start < pending.length && !_pauseRequested && failures < _failureBudget;
        start += _parallelDownloads) {
      final batch = pending.skip(start).take(_parallelDownloads);
      final results = await Future.wait(
          batch.map((entry) => _fetchInto(entry.key, entry.value)));
      for (final saved in results) {
        if (saved) {
          completed++;
          failures = 0;
        } else {
          failures++;
        }
      }
      _update(_status.copyWith(completedFiles: completed));
      // Survive being killed mid-download: resuming skips what is on disk.
      // Checkpointing in groups keeps the write cost off the per-tile path.
      if (completed - checkpoint >= _checkpointEvery) {
        checkpoint = completed;
        await _writeMeta(complete: false, generatedAt: bundle['generatedAt']);
      }
    }

    final missing = work.keys.where((path) => !_store.contains(path)).length;
    final complete = missing == 0;
    _update(_status.copyWith(
      state: complete ? OfflinePackState.ready : OfflinePackState.incomplete,
      completedFiles: total - missing,
      totalFiles: total,
      bytesOnDisk: await _store.bytesOnDisk(),
      installedAt: complete ? DateTime.now() : _status.installedAt,
      message: complete
          ? null
          : _pauseRequested
              ? 'Paused. Resume to finish downloading the offline map.'
              : 'Stopped after a connection problem. Resume to finish downloading the offline map.',
      clearMessage: complete,
    ));
    _pauseRequested = false;
    await _writeMeta(complete: complete, generatedAt: bundle['generatedAt']);
  }

  /// Keeps concurrent transfers separate so chunks are counted exactly once.
  Future<Uint8List> _receive(String path, Uri url, Duration timeout) async {
    final response = await _http
        .send(http.Request('GET', url)
          ..headers['User-Agent'] = campusDownloadUserAgent)
        .timeout(timeout);
    if (response.statusCode != 200) {
      await response.stream.drain<void>().timeout(timeout);
      throw const _DownloadFailure(
          'The offline map is not available right now. Try again later.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(timeout)) {
      bytes.add(chunk);
      _receivedBytes[path] = bytes.length;
      _publishTransferProgress();
    }
    if (bytes.isEmpty) throw const _DownloadFailure('Empty download.');
    return bytes.takeBytes();
  }

  void _publishTransferProgress({bool force = false, int savedBytes = 0}) {
    final now = _progressClock.elapsedMilliseconds;
    if (!force && now - _lastProgressAt < 100) {
      _progressTimer ??= Timer(
        Duration(milliseconds: 100 - (now - _lastProgressAt)),
        () => _publishTransferProgress(force: true),
      );
      return;
    }
    _progressTimer?.cancel();
    _progressTimer = null;
    _lastProgressAt = now;
    _update(_status.copyWith(
      bytesOnDisk: _status.bytesOnDisk + savedBytes,
      bytesInFlight:
          _receivedBytes.values.fold<int>(0, (sum, bytes) => sum + bytes),
    ));
  }

  Future<bool> _fetchInto(String path, Uri url) async {
    var savedBytes = 0;
    try {
      final bytes = await _receive(path, url, const Duration(seconds: 30));
      await _store.write(path, bytes);
      savedBytes = bytes.length;
      return true;
    } catch (_) {
      return false;
    } finally {
      // Failed partial responses are discarded; only committed files survive
      // pause/restart. Moving bytes to disk must not double-count them.
      _receivedBytes.remove(path);
      _publishTransferProgress(force: true, savedBytes: savedBytes);
    }
  }

  String _tileUrl(OfflineTile tile) => campusTileUrlTemplate
      .replaceAll('{z}', '${tile.z}')
      .replaceAll('{x}', '${tile.x}')
      .replaceAll('{y}', '${tile.y}');

  static List<String> _photoUrls(Map<String, dynamic> bundle) {
    final urls = <String>{};
    for (final building in (bundle['buildings'] as List<dynamic>? ?? [])) {
      final row = building as Map<String, dynamic>;
      for (final url in [
        row['imageUrl'],
        ...((row['rooms'] as List<dynamic>? ?? [])
            .map((room) => (room as Map<String, dynamic>)['imageUrl']))
      ]) {
        if (url is String && url.startsWith('http')) urls.add(url);
      }
    }
    return urls.toList(growable: false);
  }

  void _adoptBundle(Map<String, dynamic> bundle) {
    _bundle = bundle;
    _buildings = (bundle['buildings'] as List<dynamic>? ?? [])
        .map((row) => CampusBuilding.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _readJson(String path) async {
    final contents = await _store.readText(path);
    if (contents == null || contents.isEmpty) return null;
    try {
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMeta({required bool complete, Object? generatedAt}) async {
    await _store.writeText(
        _metaPath,
        jsonEncode({
          'version': _status.installedVersion,
          'generatedAt': generatedAt,
          'complete': complete,
          'completedFiles': _status.completedFiles,
          'totalFiles': _status.totalFiles,
          'installedAt': _status.installedAt?.toIso8601String(),
          'updateVersion': _status.updateVersion,
          'lastCheckedAt': _status.lastCheckedAt?.toIso8601String(),
        }));
  }

  void _update(OfflinePackStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ---- Offline reads used by the map while the network is unavailable ----

  /// Routes computed on this device from the downloaded transport graph.
  List<WalkingRoute> offlineRoutes({
    required NavigationOrigin origin,
    required CampusBuilding destination,
    required TransportMode mode,
  }) {
    final graph = _bundle?['graph'];
    if (graph == null) {
      throw Exception(
          'Download the offline map to get directions without a connection.');
    }
    final result =
        OfflineRoutingEngine(Map<String, dynamic>.from(graph as Map)).routes({
      'mode': mode.name,
      'destinationBuildingId': destination.id,
      'origin': {
        'type': origin.type.name,
        'buildingId': origin.type == NavigationOriginType.campusLocation
            ? origin.id
            : null,
        'latitude': origin.coordinate.latitude,
        'longitude': origin.coordinate.longitude,
      },
    });
    return (result['routes'] as List)
        .map((row) =>
            WalkingRoute.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// A downloaded campus photo, or null when it is not cached.
  ImageProvider? photoImage(String url) =>
      _bundle == null ? null : _store.imageFor(offlinePhotoPath(url));

  /// A downloaded map tile, or null when it is not cached.
  ImageProvider? tileImage(int z, int x, int y) =>
      _store.imageFor(OfflineTile(z, x, y).path);
}

class _DownloadFailure implements Exception {
  final String message;
  const _DownloadFailure(this.message);
}
