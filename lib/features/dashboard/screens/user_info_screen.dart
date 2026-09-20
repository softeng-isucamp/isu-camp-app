import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/screens/help_screen.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/services/user_session.dart';
import '../data/campus_dataset.dart';
import '../models/navigation_history.dart';
import '../services/navigation_history_service.dart';
import 'about_us_screen.dart';

// =========================================================================
// 1. MAIN USER INFO SCREEN
// =========================================================================
class UserInfoScreen extends StatefulWidget {
  final ValueChanged<NavigationHistoryEntry>? onNavigateToHistory;

  const UserInfoScreen({
    super.key,
    this.onNavigateToHistory,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  @override
  Widget build(BuildContext context) {
    final username = UserSession.currentUsername;

    return Scaffold(
      backgroundColor: const Color(0xFF0B351E),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 1. Top Header with Faded Campus Image, "Done" button, and Curved Arch
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                ClipPath(
                  clipper: _UserHeaderCurveClipper(),
                  child: Container(
                    height: 250,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/Appdev_background1.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: Colors.grey.shade200),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.90),
                                Colors.white.withValues(alpha: 0.45),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          bottom: false,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 18.0,
                                right: 24.0,
                              ),
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Text(
                                  'Done',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Circular Avatar centered over the curved arch
                Positioned(
                  bottom: -48,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEDF0F2),
                      border: Border.all(
                        color: const Color(0xFF1F2937),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_outline,
                        size: 58,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 58),

            // 2. Dynamic Username Text from Authentication
            Text(
              username,
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),

            const SizedBox(height: 28),

            // 3. User Menu Cards Section
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    // Card 1: Offline Map
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const _OfflineMapSubScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_download_outlined,
                              color: Color(0xFF757575),
                              size: 22,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Offline Map',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF9CA3AF),
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Card 2: Grouped Menu (History, About us, Help)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildMenuRow(
                            icon: Icons.access_time,
                            label: 'History',
                            onTap: () async {
                              final destination =
                                  await Navigator.push<NavigationHistoryEntry>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const _HistorySubScreen(),
                                ),
                              );
                              if (!context.mounted || destination == null) {
                                return;
                              }
                              Navigator.pop(context);
                              widget.onNavigateToHistory?.call(destination);
                            },
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF1F5F9),
                          ),
                          _buildMenuRow(
                            icon: Icons.people_outline,
                            label: 'About us',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AboutUsScreen(),
                                ),
                              );
                            },
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF1F5F9),
                          ),
                          _buildMenuRow(
                            icon: Icons.help_outline,
                            label: 'Help',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HelpScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 4. Log Out Outlined Button
                    SizedBox(
                      width: 175,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () {
                          UserSession.logout();
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Colors.white,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          'Log Out',
                          style: GoogleFonts.montserrat(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6B7280), size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF9CA3AF),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserHeaderCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width / 2,
      size.height + 25,
      size.width,
      size.height - 40,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// =========================================================================
// 2. OFFLINE MAP VIEW (Compiled into user_info_screen.dart)
// =========================================================================
enum DownloadStatus {
  notDownloaded,
  downloading,
  paused,
  completed,
}

class _OfflineMapSubScreen extends StatefulWidget {
  const _OfflineMapSubScreen();

  @override
  State<_OfflineMapSubScreen> createState() => _OfflineMapSubScreenState();
}

class _OfflineMapSubScreenState extends State<_OfflineMapSubScreen> {
  DownloadStatus _status = DownloadStatus.notDownloaded;
  double _progress = 0.0;
  Timer? _downloadTimer;
  final double _totalSizeMb = 30.0;

  @override
  void dispose() {
    _downloadTimer?.cancel();
    super.dispose();
  }

  void _startOrResumeDownload() {
    setState(() {
      _status = DownloadStatus.downloading;
    });

    _downloadTimer?.cancel();
    _downloadTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _progress += 0.025;
        if (_progress >= 1.0) {
          _progress = 1.0;
          _status = DownloadStatus.completed;
          timer.cancel();
          _showCompletedSnackbar();
        }
      });
    });
  }

  void _pauseDownload() {
    _downloadTimer?.cancel();
    setState(() {
      _status = DownloadStatus.paused;
    });
  }

  void _deleteDownload() {
    _downloadTimer?.cancel();
    setState(() {
      _status = DownloadStatus.notDownloaded;
      _progress = 0.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Offline map deleted from storage.',
          style: GoogleFonts.montserrat(fontSize: 12.5),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCompletedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'KUMPAS Campus Map downloaded successfully! Offline navigation is now active.',
                style: GoogleFonts.montserrat(fontSize: 12.5),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F751B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadedMb = (_progress * _totalSizeMb).toStringAsFixed(1);
    final percentage = (_progress * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF0B351E),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar with Back and "Done" buttons
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white70,
                      size: 20,
                    ),
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

                    // Gold Cloud Outline Icon + "Offline Map" Title
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_download_outlined,
                          size: 52,
                          color: Color(0xFFECC700),
                        ),
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

                    // Description Paragraph
                    Text(
                      'To use KUMPAS offline, start by downloading the map. Then you\'ll be able to search and get directions with the map even without internet connection.',
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Download Card with Interactive Pause / Resume / Cancel Controls
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildStatusIcon(),
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
                                      _status == DownloadStatus.completed
                                          ? '30 MB • Offline Ready'
                                          : _status ==
                                                  DownloadStatus.downloading
                                              ? '$downloadedMb MB / 30 MB • $percentage%'
                                              : _status == DownloadStatus.paused
                                                  ? '$downloadedMb MB / 30 MB • Paused'
                                                  : '30 MB',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildActionButton(),
                            ],
                          ),
                          if (_status == DownloadStatus.downloading ||
                              _status == DownloadStatus.paused) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _progress,
                                minHeight: 6,
                                backgroundColor: Colors.white24,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _status == DownloadStatus.paused
                                      ? const Color(0xFFECC700)
                                      : const Color(0xFF00B2FE),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Feature Highlights Card
                    Container(
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
                    ),

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

  Widget _buildStatusIcon() {
    switch (_status) {
      case DownloadStatus.completed:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF0F751B),
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 22),
        );
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 38,
          height: 38,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00B2FE)),
          ),
        );
      case DownloadStatus.paused:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFECC700),
          ),
          child: const Icon(Icons.pause, color: Colors.black87, size: 22),
        );
      case DownloadStatus.notDownloaded:
        return const Icon(
          Icons.cloud_download_outlined,
          color: Colors.white70,
          size: 38,
        );
    }
  }

  Widget _buildActionButton() {
    switch (_status) {
      case DownloadStatus.notDownloaded:
        return ElevatedButton.icon(
          onPressed: _startOrResumeDownload,
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      case DownloadStatus.downloading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.pause_circle_outline,
                  color: Color(0xFFECC700), size: 28),
              tooltip: 'Pause Download',
              onPressed: _pauseDownload,
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined,
                  color: Colors.redAccent, size: 24),
              tooltip: 'Cancel Download',
              onPressed: _deleteDownload,
            ),
          ],
        );
      case DownloadStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline,
                  color: Color(0xFF22C55E), size: 28),
              tooltip: 'Resume Download',
              onPressed: _startOrResumeDownload,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 24),
              tooltip: 'Delete Download',
              onPressed: _deleteDownload,
            ),
          ],
        );
      case DownloadStatus.completed:
        return IconButton(
          icon:
              const Icon(Icons.delete_outline, color: Colors.white60, size: 24),
          tooltip: 'Delete Offline Map',
          onPressed: _deleteDownload,
        );
    }
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
                  fontSize: 11.5,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// 3. NAVIGATION HISTORY
// =========================================================================
class _HistorySubScreen extends StatefulWidget {
  const _HistorySubScreen();
  @override
  State<_HistorySubScreen> createState() => _HistorySubScreenState();
}

class _HistorySubScreenState extends State<_HistorySubScreen> {
  final _searchController = TextEditingController();
  List<NavigationHistoryEntry> _items = [];
  bool _loading = true;
  bool _mutating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await NavigationHistoryService.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _deleteHistory([NavigationHistoryEntry? entry]) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry == null
            ? 'Clear navigation history?'
            : 'Delete history item?'),
        content: Text(entry == null
            ? 'This will remove all your saved destinations.'
            : 'Remove ${entry.destinationName} from your history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(entry == null ? 'Clear' : 'Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      if (entry == null) {
        await NavigationHistoryService.clear();
      } else {
        await NavigationHistoryService.delete(entry.id);
      }
      if (!mounted) return;
      setState(() {
        if (entry == null) {
          _items.clear();
        } else {
          _items.removeWhere((item) => item.id == entry.id);
        }
      });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _getDirections(NavigationHistoryEntry entry) {
    final building = isuCampusBuildings
        .where((b) => b.id == entry.destinationId)
        .firstOrNull;
    if (building == null ||
        (entry.roomId != null &&
            !building.rooms.any((room) => room.id == entry.roomId))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'This destination is no longer available. Refresh the map and try again.')));
      return;
    }
    Navigator.pop(context, entry);
  }

  String _timestamp(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final label = day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
            ? 'Yesterday'
            : '${local.month}/${local.day}/${local.year}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$label, $time';
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = _items
        .where((item) =>
            '${item.destinationName} ${item.destinationAcronym} ${item.roomName ?? ''}'
                .toLowerCase()
                .contains(query))
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: const Color(0xFF0F751B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: 'Refresh history',
              onPressed: _loading || _mutating ? null : _loadHistory,
              icon: const Icon(Icons.refresh)),
          if (_items.isNotEmpty)
            IconButton(
                tooltip: 'Clear history',
                onPressed:
                    _loading || _mutating ? null : () => _deleteHistory(),
                icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search destinations',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
        if (_mutating) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                                onPressed: _loadHistory,
                                child: const Text('Retry')),
                          ])))
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                              _items.isEmpty
                                  ? 'No navigation history yet.\nPreviewed and started routes will appear here.'
                                  : 'No matching destinations found.',
                              textAlign: TextAlign.center))
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                            itemCount: visible.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = visible[index];
                              return Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            const Icon(Icons.location_on,
                                                color: Color(0xFF0F751B)),
                                            const SizedBox(width: 10),
                                            Expanded(
                                                child: Text(
                                                    entry.destinationName,
                                                    style:
                                                        GoogleFonts.montserrat(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 14))),
                                            IconButton(
                                                tooltip: 'Delete item',
                                                onPressed: _mutating
                                                    ? null
                                                    : () =>
                                                        _deleteHistory(entry),
                                                icon: const Icon(
                                                    Icons.delete_outline)),
                                          ]),
                                          if (entry.roomName != null)
                                            Text(entry.roomName!),
                                          const SizedBox(height: 8),
                                          Text(_timestamp(entry.createdAt),
                                              style: const TextStyle(
                                                  color: Colors.grey)),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                onPressed: _mutating
                                                    ? null
                                                    : () =>
                                                        _getDirections(entry),
                                                icon: const Icon(
                                                    Icons.directions),
                                                label: const Text(
                                                    'Get directions'),
                                                style: OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        const Color(
                                                            0xFF0F751B)),
                                              )),
                                        ],
                                      )));
                            },
                          )),
        ),
      ]),
    );
  }
}
