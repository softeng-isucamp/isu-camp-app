import 'package:isu_camp_app/core/app_motion.dart';
import 'package:isu_camp_app/core/widgets/app_pressable.dart';
import 'dart:math' as math;
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

  bool _started = false;

  // A brief logo entrance; the primary action is visible from the first frame.
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );

    // 2. Logo scales up gently
    _logoScale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutQuart),
      ),
    );

    // 3. Gentle logo fade-in
    _logoFade = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.50, curve: Curves.easeInOutCubic),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _controller.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoDiameter =
        math.min(400.0, MediaQuery.sizeOf(context).width * 0.9);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
            child: Image.asset('assets/images/Appdev_background1.webp',
                fit: BoxFit.cover)),
        SafeArea(
            child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: SizedBox(
                          width: logoDiameter,
                          height: logoDiameter,
                          child: Image.asset(
                              'assets/images/logo_kumpas_app.webp',
                              fit: BoxFit.contain)),
                    ),
                  ),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.antonSc(
                        fontSize: 65,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        height: 1.25,
                      ),
                      children: const [
                        TextSpan(
                          text: 'KUM',
                          style: TextStyle(
                            color: Color.fromARGB(255, 55, 56, 56),
                          ),
                        ),
                        TextSpan(
                          text: 'PAS',
                          style: TextStyle(
                            color: Color.fromARGB(255, 19, 64, 34),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kampus Unified Mapping & \nPathfinding Assistance System',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AppPressable(
                    onPressed: () {
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
                  Text(
                    'Isabela State University - Echague Campus',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          )),
        )),
      ]),
    );
  }
}
