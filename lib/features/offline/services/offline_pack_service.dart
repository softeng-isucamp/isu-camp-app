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
  })  : _store = store ?? OfflineFileStore(),
        _client = client,
        _baseUrl = baseUrl ?? (() => AuthService.baseUrl);

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

  OfflinePackStatus _status = const OfflinePackStatus();
  Map<String, dynamic>? _bundle;
  List<CampusBuilding>? _buildings;
  bool _pauseRequested = false;
  final Map<String, int> _receivedBytes = {};
  OfflinePackManifest? _manifest;
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
    OfflinePackManifest? manifest;
    try {
      if (meta?['manifest'] is Map) {
        manifest = OfflinePackManifest.fromJson(
            Map<String, dynamic>.from(meta!['manifest'] as Map));
      }
    } on FormatException {
      _update(const OfflinePackStatus());
      return;
    }
    final bundlePath = manifest == null
        ? _bundlePath
        : 'packs/${manifest.version}/$_bundlePath';
    final bundle = await _readJson(bundlePath);
    if (meta == null ||
        bundle == null ||
        (manifest != null && bundle['version'] != manifest.version)) {
      _update(const OfflinePackStatus());
      return;
    }
    _manifest = manifest;
    _adoptBundle(bundle);
    final present = manifest?.files
        .where((file) => _store.contains(manifest!.cachePath(file)))
        .toList();
    final complete = meta['complete'] == true &&
        (manifest == null || present!.length == manifest.files.length);
    final storedBytes = manifest == null
        ? await _store.bytesOnDisk()
        : present!.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    _update(OfflinePackStatus(
      state: complete ? OfflinePackState.ready : OfflinePackState.incomplete,
      installedVersion: meta['version'] as String?,
      updateVersion: meta['updateVersion'] as String?,
      completedFiles:
          present?.length ?? (meta['completedFiles'] as num?)?.toInt() ?? 0,
      totalFiles:
          manifest?.files.length ?? (meta['totalFiles'] as num?)?.toInt() ?? 0,
      bytesOnDisk: storedBytes,
      totalBytes: manifest?.totalBytes ?? (complete ? storedBytes : null),
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
      final manifest = await _publishedManifest();
      if (_status.isBusy) return false;
      final available = manifest.version;
      final checkedAt = DateTime.now();
      _update(_status.copyWith(
        updateVersion: available,
        lastCheckedAt: checkedAt,
        clearUpdateVersion: available == installed,
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
  Future<void> download({bool update = false}) {
    return _activeDownload ??= _runDownload(update: update).whenComplete(() {
      _activeDownload = null;
    });
  }

  /// Asks the running download to stop. Finished files stay on disk.
  void pause() {
    if (_status.isBusy) {
      _pauseRequested = true;
    }
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
    _manifest = null;
    _update(const OfflinePackStatus());
  }

  Future<OfflinePackManifest> _publishedManifest() async {
    final response = await _http
        .get(Uri.parse('${_baseUrl()}/campus/offline/manifest'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const _DownloadFailure(
          'The offline map pack is being prepared. Try again later.');
    }
    return OfflinePackManifest.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _runDownload({required bool update}) async {
    if (!_store.isSupported || !await _store.open()) {
      _update(_status.copyWith(state: OfflinePackState.unsupported));
      return;
    }
    _pauseRequested = false;
    final previousStatus = _status;
    final previousManifest = _manifest;
    _update(_status.copyWith(
        state: OfflinePackState.downloading,
        clearTotalBytes: true,
        clearMessage: true));
    final OfflinePackManifest manifest;
    try {
      // A paused pack stays pinned even if another version was published.
      manifest = !update &&
              previousStatus.state == OfflinePackState.incomplete &&
              _manifest != null
          ? _manifest!
          : await _publishedManifest();
    } catch (error) {
      _update(previousStatus.copyWith(
          message: error is _DownloadFailure
              ? error.message
              : error is FormatException
                  ? 'The server has not published a valid precomputed offline pack yet. Try again later.'
                  : 'Could not load the published offline map. Check your connection and try again.'));
      return;
    }
    // The denominator is available before any file request or disk validation.
    _update(_status.copyWith(
        totalBytes: manifest.totalBytes,
        totalFiles: manifest.files.length,
        completedFiles: 0,
        bytesOnDisk: 0,
        bytesInFlight: 0));
    final verified = <String>{};
    var savedBytes = 0;
    try {
      for (final file in manifest.files) {
        var matches = await _store.matches(
            manifest.cachePath(file), file.sizeBytes, file.checksum);
        final previousPath = previousManifest == null
            ? file.path
            : 'packs/${previousManifest.version}/${file.path}';
        if (!matches &&
            previousPath != manifest.cachePath(file) &&
            _store.contains(previousPath)) {
          final bytes = await _store.readBytes(previousPath);
          if (bytes != null &&
              bytes.length == file.sizeBytes &&
              sha256.convert(bytes).toString() == file.checksum) {
            await _store.write(manifest.cachePath(file), bytes);
            matches = true;
          }
        }
        if (!matches && _store.contains(manifest.cachePath(file))) {
          await _store.deletePrefix(manifest.cachePath(file));
        }
        if (matches) {
          verified.add(file.path);
          savedBytes += file.sizeBytes;
        }
      }
    } catch (_) {
      _update(previousStatus.copyWith(
          message:
              'Could not prepare offline storage. Check your free space and try again.'));
      return;
    }
    _update(_status.copyWith(
        bytesOnDisk: savedBytes, completedFiles: verified.length));
    final bundleFile =
        manifest.files.firstWhere((file) => file.path == _bundlePath);
    if (_pauseRequested && !verified.contains(_bundlePath)) {
      _update(previousStatus.copyWith(message: 'Paused before downloading.'));
      return;
    }
    try {
      if (!verified.contains(_bundlePath)) {
        if (!await _fetchInto(manifest, bundleFile)) {
          throw const _DownloadFailure(
              'Could not download the campus data. Check your connection and try again.');
        }
        verified.add(_bundlePath);
      }
      final bundle = await _readJson(manifest.cachePath(bundleFile));
      if (bundle == null || bundle['version'] != manifest.version) {
        throw const _DownloadFailure(
            'The published campus data is invalid. Try again later.');
      }
      _manifest = manifest;
      _adoptBundle(bundle);
    } catch (error) {
      _manifest = previousManifest;
      _update(previousStatus.copyWith(
          message: error is _DownloadFailure
              ? error.message
              : 'Could not read the offline map. Try again later.'));
      return;
    }
    _update(_status.copyWith(
        installedVersion: manifest.version,
        completedFiles: verified.length,
        clearUpdateVersion: true));
    await _writeMeta(complete: verified.length == manifest.files.length);
    var failures = 0;
    var checkpoint = verified.length;
    final pending =
        manifest.files.where((file) => !verified.contains(file.path)).toList();
    for (var start = 0;
        start < pending.length && !_pauseRequested && failures < _failureBudget;
        start += _parallelDownloads) {
      final batch = pending.skip(start).take(_parallelDownloads).toList();
      final results =
          await Future.wait(batch.map((file) => _fetchInto(manifest, file)));
      for (var i = 0; i < results.length; i++) {
        if (results[i]) {
          verified.add(batch[i].path);
          failures = 0;
        } else {
          failures++;
        }
      }
      _update(_status.copyWith(completedFiles: verified.length));
      if (verified.length - checkpoint >= _checkpointEvery) {
        checkpoint = verified.length;
        await _writeMeta(complete: false);
      }
    }
    final complete = verified.length == manifest.files.length;
    _update(_status.copyWith(
      state: complete ? OfflinePackState.ready : OfflinePackState.incomplete,
      bytesOnDisk: manifest.files
          .where((file) => verified.contains(file.path))
          .fold<int>(0, (sum, file) => sum + file.sizeBytes),
      bytesInFlight: 0,
      totalBytes: manifest.totalBytes,
      completedFiles: verified.length,
      installedAt: complete ? DateTime.now() : _status.installedAt,
      message: complete
          ? null
          : _pauseRequested
              ? 'Paused. Resume to finish downloading the offline map.'
              : 'Stopped after a connection or file verification problem. Resume to try again.',
      clearMessage: complete,
    ));
    _pauseRequested = false;
    await _writeMeta(complete: complete);
  }

  Future<Uint8List> _receive(String path, Uri url, int expectedBytes) async {
    final response = await _http
        .send(http.Request('GET', url)
          ..headers.addAll({
            'User-Agent': campusDownloadUserAgent,
            'Accept-Encoding': 'identity'
          }))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.timeout(const Duration(seconds: 30)).drain<void>();
      throw const _DownloadFailure('Offline pack file is unavailable.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > expectedBytes) {
        throw const _DownloadFailure(
            'Offline pack file exceeds its published size.');
      }
      bytes.add(chunk);
      _receivedBytes[path] = bytes.length;
      _publishTransferProgress();
    }
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

  Future<bool> _fetchInto(
      OfflinePackManifest manifest, OfflinePackFile file) async {
    var savedBytes = 0;
    try {
      final uri = Uri.parse(
          '${_baseUrl()}/campus/offline/packs/${manifest.version}/${file.path}');
      final bytes = await _receive(file.path, uri, file.sizeBytes);
      if (bytes.length != file.sizeBytes ||
          sha256.convert(bytes).toString() != file.checksum) {
        throw const _DownloadFailure('Offline pack checksum did not match.');
      }
      // Verify first, then atomically commit the original bytes. In particular,
      // re-encoding bundle JSON would invalidate its published size/checksum.
      await _store.write(manifest.cachePath(file), bytes);
      savedBytes = bytes.length;
      return true;
    } catch (_) {
      return false;
    } finally {
      _receivedBytes.remove(file.path);
      _publishTransferProgress(force: true, savedBytes: savedBytes);
    }
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
          'generatedAt': _manifest?.generatedAt ?? generatedAt,
          'complete': complete,
          'completedFiles': _status.completedFiles,
          'totalFiles': _status.totalFiles,
          'totalBytes': _status.totalBytes,
          'manifest': _manifest?.toJson(),
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
  ImageProvider? photoImage(String url) => _bundle == null
      ? null
      : _store.imageFor(_cacheKey(offlinePhotoPath(url)));

  /// A downloaded map tile, or null when it is not cached.
  ImageProvider? tileImage(int z, int x, int y) =>
      _store.imageFor(_cacheKey(OfflineTile(z, x, y).path));

  String _cacheKey(String path) =>
      _manifest == null ? path : 'packs/${_manifest!.version}/$path';
}

class _DownloadFailure implements Exception {
  final String message;
  const _DownloadFailure(this.message);
}
