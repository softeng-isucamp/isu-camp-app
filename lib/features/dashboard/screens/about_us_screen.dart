import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B351E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF072B18),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'About Us',
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Campus Background Watermark
          Positioned.fill(
            child: Opacity(
              opacity: 0.12,
              child: Image.asset(
                'assets/images/Appdev_background1.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ),

          // 2. Scrollable Content Area
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Faded Top Campus Gateway Banner
                Stack(
                  children: [
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      child: Image.asset(
                        'assets/images/Appdev_background1.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(color: Colors.white),
                      ),
                    ),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.3),
                            const Color(0xFF0B351E).withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Main Dark Green Rounded Container
                Container(
                  transform: Matrix4.translationValues(0.0, -28.0, 0.0),
                  padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 20.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B351E),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Gold Group Icon & "About Us"
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.groups_outlined,
                              color: Color(0xFFECC700),
                              size: 48,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'About Us',
                            style: GoogleFonts.montserrat(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.25),
                        thickness: 1,
                      ),
                      const SizedBox(height: 18),

                      // App Title & Seal Badge Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ISU Campus Seal with Location Pin
                          Container(
                            width: 105,
                            height: 105,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo_kumpas_app.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                Icons.school,
                                color: Color(0xFFECC700),
                                size: 50,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'KUMPAS',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Kampus Unified Mapping & Pathfinding Assistance System',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.95),
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Version 1.0.0',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Description White Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22.0,
                          vertical: 24.0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Description',
                              style: GoogleFonts.montserrat(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF222222),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'KUMPAS is an interactive campus mapping and navigation system designed to help students, faculty, staff, and visitors easily find specific locations within the campus. It provides a centralized platform where users can search for buildings, offices, classrooms, laboratories, and other important destinations and receive route recommendations based on their preferences.',
                              textAlign: TextAlign.justify,
                              style: GoogleFonts.montserrat(
                                fontSize: 13,
                                color: const Color(0xFF374151),
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 26),

                      // Narrative Paragraph 1
                      RichText(
                        textAlign: TextAlign.justify,
                        text: TextSpan(
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.5,
                          ),
                          children: const [
                            TextSpan(
                              text: 'KUMPAS ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            TextSpan(
                              text:
                                  'is a mobile campus mapping and navigation system developed by a team of student developers from Isabela State University. The project was created to help students, faculty, staff, and visitors easily locate campus buildings, offices, rooms, and other important destinations.',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Narrative Paragraph 2
                      Text(
                        'Our goal is to make campus navigation faster, easier, and more accessible by providing interactive maps, location searching, route recommendations, and offline campus navigation. Downloaded building outlines, walking paths, and indoor locations support offline maps and walking routes. Street and satellite imagery are available when connected. Through KUMPAS, we aim to reduce confusion when finding unfamiliar locations and provide users with a more convenient way to navigate the campus.',
                        textAlign: TextAlign.justify,
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.95),
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Developers Section
                      Text(
                        'Developed by:',
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Justine Asuncion\nBilly Jacob Butac\nChristan Jade Caluag\nKarl Justine Tungpalan',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'BSCS 3 students',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Institution Section
                      Text(
                        'Institution:',
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Isabela State University',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
