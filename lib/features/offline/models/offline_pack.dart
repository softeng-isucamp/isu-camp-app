/// Where the downloaded campus pack currently stands.
enum OfflinePackState {
  /// Nothing downloaded yet.
  absent,

  /// A download is running now.
  downloading,

  /// A download stopped part way; what finished is kept on disk.
  incomplete,

  /// The whole pack is on disk and offline navigation works.
  ready,

  /// This platform has no writable cache (the web build).
  unsupported,
}

/// Immutable snapshot of the offline pack, rebuilt on every progress step.
class OfflinePackStatus {
  final OfflinePackState state;

  /// Dataset version currently on disk, or null when nothing is stored.
  final String? installedVersion;

  /// Newer dataset version the backend reported. Downloading it is always the
  /// user's choice; finding one never starts a download.
  final String? updateVersion;

  final int completedFiles;
  final int totalFiles;
  final int bytesOnDisk;

  /// Precomputed size of the published pack, including already saved files.
  /// Null only before its manifest loads or for a legacy local pack.
  final int? totalBytes;

  /// Received bytes in files that have not yet been committed to disk.
  final int bytesInFlight;
  final DateTime? installedAt;
  final DateTime? lastCheckedAt;

  /// Why the last download or update check stopped, for display.
  final String? message;

  const OfflinePackStatus({
    this.state = OfflinePackState.absent,
    this.installedVersion,
    this.updateVersion,
    this.completedFiles = 0,
    this.totalFiles = 0,
    this.bytesOnDisk = 0,
    this.totalBytes,
    this.bytesInFlight = 0,
    this.installedAt,
    this.lastCheckedAt,
    this.message,
  });

  bool get isReady => state == OfflinePackState.ready;
  bool get isBusy => state == OfflinePackState.downloading;
  bool get isSupported => state != OfflinePackState.unsupported;

  /// True only while a stored pack is older than what the backend offers.
  bool get hasUpdate =>
      installedVersion != null &&
      updateVersion != null &&
      updateVersion != installedVersion;

  double get progress => totalBytes == null || totalBytes! <= 0
      ? 0
      : (downloadedBytes / totalBytes!).clamp(0.0, 1.0);

  int get downloadedBytes => bytesOnDisk + bytesInFlight;

  String get downloadSizeLabel => _formatBytes(downloadedBytes);
  String get sizeLabel => _formatBytes(bytesOnDisk);
  String get downloadProgressLabel => totalBytes == null
      ? '$downloadSizeLabel downloaded'
      : '$downloadSizeLabel / ${_formatBytes(totalBytes!)}';

  static String _formatBytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  OfflinePackStatus copyWith({
    OfflinePackState? state,
    String? installedVersion,
    String? updateVersion,
    int? completedFiles,
    int? totalFiles,
    int? bytesOnDisk,
    int? totalBytes,
    int? bytesInFlight,
    DateTime? installedAt,
    DateTime? lastCheckedAt,
    String? message,
    bool clearInstalledVersion = false,
    bool clearUpdateVersion = false,
    bool clearMessage = false,
    bool clearTotalBytes = false,
  }) =>
      OfflinePackStatus(
        state: state ?? this.state,
        installedVersion: clearInstalledVersion
            ? null
            : installedVersion ?? this.installedVersion,
        updateVersion:
            clearUpdateVersion ? null : updateVersion ?? this.updateVersion,
        completedFiles: completedFiles ?? this.completedFiles,
        totalFiles: totalFiles ?? this.totalFiles,
        bytesOnDisk: bytesOnDisk ?? this.bytesOnDisk,
        totalBytes: clearTotalBytes ? null : totalBytes ?? this.totalBytes,
        bytesInFlight: bytesInFlight ?? this.bytesInFlight,
        installedAt: installedAt ?? this.installedAt,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        message: clearMessage ? null : message ?? this.message,
      );
}

/// One immutable payload in a published pack. Paths are cache keys, never
/// arbitrary URLs: downloads are pinned to the configured backend and version.
class OfflinePackFile {
  final String path;
  final int sizeBytes;
  final String checksum;

  const OfflinePackFile(this.path, this.sizeBytes, this.checksum);

  factory OfflinePackFile.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    final size = json['bytes'];
    final checksum = json['sha256'];
    if (path is! String ||
        !RegExp(r'^(bundle\.json|photos/[0-9a-f]{40}\.img|tiles/\d+/\d+/\d+\.png)$')
            .hasMatch(path) ||
        size is! int ||
        size <= 0 ||
        checksum is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException('Invalid offline pack file');
    }
    return OfflinePackFile(path, size, checksum);
  }

  Map<String, dynamic> toJson() =>
      {'path': path, 'bytes': sizeBytes, 'sha256': checksum};
}

class OfflinePackManifest {
  final String version;
  final String? generatedAt;
  final List<OfflinePackFile> files;
  final int totalBytes;

  const OfflinePackManifest._(
      this.version, this.generatedAt, this.files, this.totalBytes);

  factory OfflinePackManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final rawFiles = json['files'];
    if (json['schemaVersion'] != 1 ||
        version is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(version) ||
        rawFiles is! List ||
        rawFiles.isEmpty) {
      throw const FormatException(
          'The server has not published a precomputed offline pack');
    }
    if (rawFiles.any((row) => row is! Map) ||
        (json['generatedAt'] != null && json['generatedAt'] is! String)) {
      throw const FormatException('Invalid offline pack metadata');
    }
    final files = rawFiles
        .map((row) =>
            OfflinePackFile.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    final paths = files.map((file) => file.path).toSet();
    final total = files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    if (paths.length != files.length ||
        !paths.contains('bundle.json') ||
        json['totalBytes'] is! int ||
        json['totalBytes'] != total) {
      throw const FormatException(
          'Offline pack total does not match its files');
    }
    return OfflinePackManifest._(version, json['generatedAt'] as String?,
        List.unmodifiable(files), total);
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'version': version,
        'generatedAt': generatedAt,
        'totalBytes': totalBytes,
        'files': files.map((file) => file.toJson()).toList(),
      };

  String cachePath(OfflinePackFile file) => 'packs/$version/${file.path}';
}
