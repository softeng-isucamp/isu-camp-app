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

  double get progress =>
      totalFiles == 0 ? 0 : (completedFiles / totalFiles).clamp(0.0, 1.0);

  int get downloadedBytes => bytesOnDisk + bytesInFlight;

  String get downloadSizeLabel => _formatBytes(downloadedBytes);
  String get sizeLabel => _formatBytes(bytesOnDisk);

  static String _formatBytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  OfflinePackStatus copyWith({
    OfflinePackState? state,
    String? installedVersion,
    String? updateVersion,
    int? completedFiles,
    int? totalFiles,
    int? bytesOnDisk,
    int? bytesInFlight,
    DateTime? installedAt,
    DateTime? lastCheckedAt,
    String? message,
    bool clearInstalledVersion = false,
    bool clearUpdateVersion = false,
    bool clearMessage = false,
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
        bytesInFlight: bytesInFlight ?? this.bytesInFlight,
        installedAt: installedAt ?? this.installedAt,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        message: clearMessage ? null : message ?? this.message,
      );
}
