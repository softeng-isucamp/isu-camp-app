import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const supportPhone = String.fromEnvironment('SUPPORT_PHONE');

  Future<void> _copySupportDetails(BuildContext context) async {
    final details = supportPhone.isNotEmpty
        ? supportPhone
        : 'KUMPAS issue report\nLocation:\nWhat happened:\nExpected result:\n';
    try {
      await Clipboard.setData(ClipboardData(text: details));
    } catch (_) {
      if (!context.mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(supportPhone.isNotEmpty
                    ? 'Support number'
                    : 'Issue report'),
                content: SingleChildScrollView(child: SelectableText(details)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ],
              ));
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(supportPhone.isNotEmpty
            ? 'Support number copied.'
            : 'Issue report template copied. Add your details and share it with your campus administrator.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF072B18), // Deep ISU Forest Green (top)
              Color(0xFF02170C), // Dark evergreen (bottom)
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // --- Top Bar: Back Button and Centered Help Title ---
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.help_outline,
                            color: Color(0xFFC5A059), // Gold accent
                            size: 28,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Help',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48), // Balances the back button width
                  ],
                ),
              ),

              // --- Main Help Guide Body ---
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section: How to Use KUMPAS
                      Text(
                        'How to Use KUMPAS',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Item 1
                      _buildHelpItem(
                        stepNumber: '1.',
                        title: 'Search for a Location',
                        bulletPoints: [
                          'Use the search bar to find a building, office, room, or other campus location.',
                        ],
                      ),

                      // Item 2
                      _buildHelpItem(
                        stepNumber: '2.',
                        title: 'View Location',
                        bulletPoints: [
                          'Select a result to see its building, floor, room, or location details.',
                        ],
                      ),

                      // Item 3
                      _buildHelpItem(
                        stepNumber: '3.',
                        title: 'Get Directions',
                        bulletPoints: [
                          'Select your starting point and destination, then tap Get Directions.',
                        ],
                      ),

                      // Item 4
                      _buildHelpItem(
                        stepNumber: '4.',
                        title: 'Choose a Route',
                        bulletPoints: [
                          'Select your preferred route:',
                          '• Shortest – shortest available path.',
                          '• Shaded – route with more shaded areas.',
                          '• Shaded Path – prefers shaded pathways.',
                        ],
                      ),

                      // Item 5
                      _buildHelpItem(
                        stepNumber: '5.',
                        title: 'Use Offline Mode',
                        bulletPoints: [
                          'Download the campus map and required navigation data while connected to the internet.',
                          'Once downloaded, the map and available navigation features can be accessed without an internet connection.',
                        ],
                      ),

                      // Item 6
                      _buildHelpItem(
                        stepNumber: '6.',
                        title: 'Update Map Data',
                        bulletPoints: [
                          'To update a downloaded map, connect to the internet, open Profile → Offline Map, check for updates, and choose Download update. Updates are installed only when you choose.',
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Section: Need Assistance?
                      Text(
                        'Need Assistance?',
                        style: GoogleFonts.montserrat(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'For incorrect or missing locations and other issues, contact your campus administrator or IT help desk. Copy an issue report and add the details to help them investigate.',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),

                      if (supportPhone.isNotEmpty)
                        Text('Support: $supportPhone',
                            style: const TextStyle(color: Colors.white)),
                      TextButton.icon(
                        onPressed: () => _copySupportDetails(context),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFECC700)),
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(supportPhone.isNotEmpty
                            ? 'Copy support number'
                            : 'Copy issue report'),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper Widget for numbered help steps
  Widget _buildHelpItem({
    required String stepNumber,
    required String title,
    required List<String> bulletPoints,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stepNumber,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: bulletPoints.map((point) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3.0),
                  child: Text(
                    point.startsWith('•') ? point : '• $point',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
