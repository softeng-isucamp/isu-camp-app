import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/offline_map_screen.dart';
import '../services/offline_pack_service.dart';

/// Tells the user a newer campus map exists and offers to open the download
/// screen. Nothing is downloaded until they ask for it there.
class OfflineUpdateBanner extends StatelessWidget {
  const OfflineUpdateBanner({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF0B351E),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt,
                    color: Color(0xFFECC700), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Updated campus map available',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: onDismiss,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 34, right: 8),
              child: Text(
                'Your offline map still works. Download the update when you '
                'are ready.',
                style: GoogleFonts.montserrat(
                    fontSize: 11.5, color: Colors.white70, height: 1.35),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  onDismiss();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const OfflineMapScreen()),
                  );
                },
                style:
                    TextButton.styleFrom(foregroundColor: const Color(0xFFECC700)),
                child: Text(
                  'View update',
                  style: GoogleFonts.montserrat(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience predicate so screens do not reach into the status fields.
bool hasOfflineUpdate() => OfflinePackService.instance.status.hasUpdate;
