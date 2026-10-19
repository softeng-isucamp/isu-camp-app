import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/offline_pack.dart';
import '../services/offline_pack_service.dart';

/// Download, resume, update, and delete the offline campus pack.
///
/// Updates are only ever announced here. Replacing the stored map always takes
/// a deliberate tap, so a download never starts on mobile data by surprise.
class OfflineMapScreen extends StatefulWidget {
  const OfflineMapScreen({super.key, OfflinePackService? pack}) : _pack = pack;

  final OfflinePackService? _pack;

  @override
  State<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends State<OfflineMapScreen> {
  late final OfflinePackService _pack =
      widget._pack ?? OfflinePackService.instance;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _pack.addListener(_onPackChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _pack.load();
      await _checkForUpdate(announceNoUpdate: false);
    });
  }

  @override
  void dispose() {
    _pack.removeListener(_onPackChanged);
    super.dispose();
  }

  void _onPackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkForUpdate({bool announceNoUpdate = true}) async {
    // Reached from a post-frame callback, so the screen may already be gone.
    if (!mounted ||
        !_pack.status.isSupported ||
        _pack.status.installedVersion == null) {
      return;
    }
    setState(() => _isCheckingUpdate = true);
    final hasUpdate = await _pack.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);
    if (announceNoUpdate && !hasUpdate) {
      _notify('The downloaded campus map is already up to date.',
          const Color(0xFF0F751B));
    }
  }

  Future<void> _download() async {
    final wasInstalled = _pack.status.installedVersion != null;
    await _pack.download();
    if (!mounted) return;
    final status = _pack.status;
    if (status.isReady) {
      _notify(
        wasInstalled
            ? 'Campus map updated. Offline navigation is using the new data.'
            : 'Campus map downloaded. Offline navigation is now active.',
        const Color(0xFF0F751B),
      );
    } else if (status.message != null) {
      _notify(status.message!, Colors.red.shade700);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete offline map?',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w700)),
        content: Text(
          'KUMPAS will need an internet connection for search and directions '
          'until you download the map again.',
          style: GoogleFonts.montserrat(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _pack.delete();
    if (!mounted) return;
    _notify('Offline map deleted from storage.', Colors.red.shade700);
  }

  void _notify(String message, Color background) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.montserrat(fontSize: 12.5)),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final status = _pack.status;

    return Scaffold(
      backgroundColor: const Color(0xFF0B351E),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      'Done',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.cloud_download_outlined,
                            size: 52, color: Color(0xFFECC700)),
                        const SizedBox(width: 16),
                        Text(
                          'Offline Map',
                          style: GoogleFonts.montserrat(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'To use KUMPAS offline, start by downloading the map. '
                      "Then you'll be able to search and get directions with "
                      'the map even without internet connection.',
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (status.hasUpdate) ...[
                      _buildUpdateCard(),
                      const SizedBox(height: 16),
                    ],
                    _buildDownloadCard(status),
                    if (status.isSupported) ...[
                      const SizedBox(height: 14),
                      _buildUpdateCheckRow(status),
                    ],
                    const SizedBox(height: 24),
                    _buildFeatureCard(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateCard() {
    return Container(
      key: const ValueKey('offline-update-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECC700).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECC700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt,
                  color: Color(0xFFECC700), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A newer campus map is available',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your downloaded map keeps working as it is. The update is only '
            'installed when you choose to download it.',
            style: GoogleFonts.montserrat(
                fontSize: 12, color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pack.status.isBusy ? null : _download,
              icon: const Icon(Icons.download, size: 17, color: Colors.black87),
              label: Text(
                'Download update',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFECC700),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(OfflinePackStatus status) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIcon(status),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ISU Map (Echague Campus)',
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitleFor(status),
                      key: const ValueKey('offline-pack-subtitle'),
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _buildActionButton(status),
            ],
          ),
          if (status.state == OfflinePackState.downloading ||
              status.state == OfflinePackState.incomplete) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                // A file-count ratio is not a byte total. Keep paused bars still.
                value: status.isBusy ? null : 0,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                  status.state == OfflinePackState.incomplete
                      ? const Color(0xFFECC700)
                      : const Color(0xFF00B2FE),
                ),
              ),
            ),
          ],
          if (status.message != null) ...[
            const SizedBox(height: 12),
            Text(
              status.message!,
              style: GoogleFonts.montserrat(
                  fontSize: 11.5, color: const Color(0xFFFFD4D4)),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitleFor(OfflinePackStatus status) {
    switch (status.state) {
      case OfflinePackState.unsupported:
        return 'Available in the installed KUMPAS app';
      case OfflinePackState.absent:
        return 'Map, campus data, and photos';
      case OfflinePackState.downloading:
        return '${status.downloadSizeLabel} downloaded';
      case OfflinePackState.incomplete:
        return '${status.sizeLabel} downloaded • Paused';
      case OfflinePackState.ready:
        return '${status.sizeLabel} • Offline Ready';
    }
  }

  Widget _buildStatusIcon(OfflinePackStatus status) {
    switch (status.state) {
      case OfflinePackState.ready:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFF0F751B)),
          child: const Icon(Icons.check, color: Colors.white, size: 22),
        );
      case OfflinePackState.downloading:
        return const SizedBox(
          width: 38,
          height: 38,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00B2FE)),
          ),
        );
      case OfflinePackState.incomplete:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFFECC700)),
          child: const Icon(Icons.pause, color: Colors.black87, size: 22),
        );
      case OfflinePackState.absent:
      case OfflinePackState.unsupported:
        return const Icon(Icons.cloud_download_outlined,
            color: Colors.white70, size: 38);
    }
  }

  Widget _buildActionButton(OfflinePackStatus status) {
    switch (status.state) {
      case OfflinePackState.unsupported:
        return const SizedBox.shrink();
      case OfflinePackState.absent:
        return ElevatedButton.icon(
          key: const ValueKey('offline-download-button'),
          onPressed: _download,
          icon: const Icon(Icons.download, size: 16, color: Colors.black87),
          label: Text(
            'Download',
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFECC700),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      case OfflinePackState.downloading:
        return IconButton(
          key: const ValueKey('offline-pause-button'),
          icon: const Icon(Icons.pause_circle_outline,
              color: Color(0xFFECC700), size: 28),
          tooltip: 'Pause download',
          onPressed: _pack.pause,
        );
      case OfflinePackState.incomplete:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('offline-resume-button'),
              icon: const Icon(Icons.play_circle_outline,
                  color: Color(0xFF22C55E), size: 28),
              tooltip: 'Resume download',
              onPressed: _download,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 24),
              tooltip: 'Delete partial download',
              onPressed: _confirmDelete,
            ),
          ],
        );
      case OfflinePackState.ready:
        return IconButton(
          key: const ValueKey('offline-delete-button'),
          icon:
              const Icon(Icons.delete_outline, color: Colors.white60, size: 24),
          tooltip: 'Delete offline map',
          onPressed: _confirmDelete,
        );
    }
  }

  Widget _buildUpdateCheckRow(OfflinePackStatus status) {
    final checked = status.lastCheckedAt;
    return Row(
      children: [
        Expanded(
          child: Text(
            status.installedVersion == null
                ? 'Download the map to receive update notices.'
                : checked == null
                    ? 'Updates have not been checked yet.'
                    : 'Last checked ${_timeAgo(checked)}.',
            style:
                GoogleFonts.montserrat(fontSize: 11.5, color: Colors.white60),
          ),
        ),
        if (status.installedVersion != null)
          TextButton(
            onPressed: _isCheckingUpdate ? null : _checkForUpdate,
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFECC700),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(
              _isCheckingUpdate ? 'Checking...' : 'Check for updates',
              style: GoogleFonts.montserrat(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  static String _timeAgo(DateTime moment) {
    final elapsed = DateTime.now().difference(moment);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }

  Widget _buildFeatureCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildFeatureRow(
            icon: Icons.search,
            title: 'Offline Building Search',
            subtitle:
                'Search all colleges, offices, and rooms with zero mobile data.',
          ),
          const SizedBox(height: 14),
          _buildFeatureRow(
            icon: Icons.directions_walk,
            title: 'Turn-by-Turn Offline Routing',
            subtitle:
                'Navigate shortest and comfortable shaded paths anywhere on campus.',
          ),
          const SizedBox(height: 14),
          _buildFeatureRow(
            icon: Icons.local_parking,
            title: 'Parking & Facilities Locator',
            subtitle:
                'Find vehicle & motorcycle parking spots without internet.',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFECC700), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.montserrat(
                    fontSize: 11.5, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
