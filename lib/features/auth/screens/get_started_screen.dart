import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login_screen.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Logo Animations (Spin, Scale, and Fade - No Shadow)
  late final Animation<double> _logoRotation;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  // Bottom Content Animations (Slide & Fade)
  late final Animation<Offset> _bottomSlide;
  late final Animation<double> _bottomFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 1. Logo spins 1 full turn smoothly
    _logoRotation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Logo scales up gently
    _logoScale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutQuart),
      ),
    );

    // 3. Gentle logo fade-in
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.50, curve: Curves.easeInOutCubic),
      ),
    );

    // 4. Smooth bottom card upward drift
    _bottomSlide =
        Tween<Offset>(begin: const Offset(0.0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    // 5. Bottom card content fade-in
    _bottomFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.90, curve: Curves.easeInOutCubic),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double logoDiameter = 300.0;

    return Scaffold(
      body: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 1. Isolated Full Background
          RepaintBoundary(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Image.asset(
                'assets/images/Appdev_background1.png',
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 2. Spinning Logo Badge (Clean - No rotating box shadow)
          Positioned(
            top: size.height * 0.44 - (logoDiameter / 2),
            left: 0,
            right: 0,
            child: Center(
              child: FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: RotationTransition(
                    turns: _logoRotation,
                    child: SizedBox(
                      width: logoDiameter,
                      height: logoDiameter,
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo_isucamp_app.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.account_balance,
                              size: 80,
                              color: Color(0xFF0F3B20),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. Smoothly Emerging Bottom Card Elements
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: size.height * 0.44,
            child: SafeArea(
              child: SlideTransition(
                position: _bottomSlide,
                child: FadeTransition(
                  opacity: _bottomFade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        // App Title
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.antonSc(
                              fontSize: 70,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.80,
                              height: 1.30,
                            ),
                            children: const [
                              TextSpan(
                                text: 'ISU-',
                                style: TextStyle(
                                  color: Color.fromARGB(255, 55, 56, 56),
                                ),
                              ),
                              TextSpan(
                                text: 'CAMP',
                                style: TextStyle(
                                  color: Color.fromARGB(255, 19, 64, 34),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 1),

                        // Subtitle
                        Text(
                          'Isabela State University\nCampus Assistance and Mapping Platform',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                            height: 1.1,
                          ),
                        ),

                        const Spacer(),

                        // Native Gold/Green Action Button
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(27),
                              border: Border.all(
                                color: const Color(0xFFC5A059),
                                width: 1.5,
                              ),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF385E2B), Color(0xFF0F3B1A)],
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'GET STARTED',
                              style: GoogleFonts.montserrat(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Campus Label
                        Text(
                          'Isabela State University - Echague Campus',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),

                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
