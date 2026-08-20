import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeGreetingScreen extends StatefulWidget {
  final String userName;

  const WelcomeGreetingScreen({super.key, this.userName = 'Leader Justine'});

  @override
  State<WelcomeGreetingScreen> createState() => _WelcomeGreetingScreenState();
}

class _WelcomeGreetingScreenState extends State<WelcomeGreetingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _handwritingController;
  late final Animation<double> _strokeProgress;

  late final AnimationController _uiController;
  late final Animation<double> _nameFade;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _buttonFade;
  late final Animation<double> _buttonScale;

  late final AnimationController _ambientController;
  late final Animation<double> _ambientPulse;

  @override
  void initState() {
    super.initState();

    _handwritingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _strokeProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _handwritingController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _uiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _nameFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _uiController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOut),
      ),
    );
    _nameSlide =
        Tween<Offset>(begin: const Offset(0.0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _uiController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutCubic),
      ),
    );

    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _uiController,
        curve: const Interval(0.40, 1.0, curve: Curves.easeIn),
      ),
    );
    _buttonScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _uiController,
        curve: const Interval(0.40, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _ambientPulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ambientController, curve: Curves.easeInOut),
    );

    _handwritingController.forward().then((_) {
      _uiController.forward();
    });
  }

  @override
  void dispose() {
    _handwritingController.dispose();
    _uiController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _handleProceed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Phase 1 Complete! Dashboard module coming in Phase 2.'),
        backgroundColor: Color(0xFF0F5A28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF041C0F),
              Color(0xFF072B18),
              Color(0xFF02120A),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _ambientPulse,
              builder: (context, child) {
                return Positioned(
                  top: size.height * 0.25,
                  child: Container(
                    width: 320 * _ambientPulse.value,
                    height: 320 * _ambientPulse.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFC5A059).withValues(alpha: 0.08),
                          blurRadius: 120,
                          spreadRadius: 40,
                        ),
                        BoxShadow(
                          color: const Color(0xFF0F751B).withValues(alpha: 0.15),
                          blurRadius: 150,
                          spreadRadius: 60,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28.0,
                  vertical: 20.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFC5A059),
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ISU- CAMP',
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Colors.white.withValues(alpha: .9),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 280,
                          height: 140,
                          child: AnimatedBuilder(
                            animation: _strokeProgress,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: AppleCursiveHelloPainter(
                                  progress: _strokeProgress.value,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeTransition(
                          opacity: _nameFade,
                          child: SlideTransition(
                            position: _nameSlide,
                            child: Column(
                              children: [
                                Text(
                                  widget.userName,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.merriweather(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFC5A059).withValues(alpha: .4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'Welcome to Echague Campus',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFE2E8F0),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        FadeTransition(
                          opacity: _buttonFade,
                          child: ScaleTransition(
                            scale: _buttonScale,
                            child: GestureDetector(
                              onTap: _handleProceed,
                              child: Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: const Color(0xFFC5A059),
                                    width: 1.5,
                                  ),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF385E2B),
                                      Color(0xFF0F3B1A),
                                    ],
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 14,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Proceed to Campus Map',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Color(0xFFC5A059),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeTransition(
                          opacity: _buttonFade,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Isabela State University - Echague',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppleCursiveHelloPainter extends CustomPainter {
  final double progress;

  AppleCursiveHelloPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = const Color(0xFFC5A059).withValues(alpha: .3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final sx = size.width / 280;
    final sy = size.height / 140;

    path.moveTo(20 * sx, 100 * sy);
    path.cubicTo(45 * sx, 10 * sy, 60 * sx, 0 * sy, 65 * sx, 20 * sy);
    path.cubicTo(70 * sx, 40 * sy, 50 * sx, 110 * sy, 52 * sx, 110 * sy);
    path.cubicTo(55 * sx, 75 * sy, 78 * sx, 65 * sy, 85 * sx, 85 * sy);
    path.cubicTo(90 * sx, 100 * sy, 88 * sx, 110 * sy, 98 * sx, 105 * sy);

    path.cubicTo(108 * sx, 95 * sy, 118 * sx, 65 * sy, 110 * sx, 68 * sy);
    path.cubicTo(98 * sx, 72 * sy, 95 * sx, 108 * sy, 118 * sx, 105 * sy);

    path.cubicTo(130 * sx, 100 * sy, 142 * sx, 20 * sy, 148 * sx, 25 * sy);
    path.cubicTo(154 * sx, 35 * sy, 138 * sx, 110 * sy, 148 * sx, 108 * sy);

    path.cubicTo(160 * sx, 100 * sy, 172 * sx, 20 * sy, 178 * sx, 25 * sy);
    path.cubicTo(184 * sx, 35 * sy, 168 * sx, 110 * sy, 178 * sx, 108 * sy);

    path.cubicTo(190 * sx, 95 * sy, 205 * sx, 65 * sy, 218 * sx, 78 * sy);
    path.cubicTo(230 * sx, 92 * sy, 222 * sx, 112 * sy, 205 * sx, 108 * sy);
    path.cubicTo(192 * sx, 104 * sy, 195 * sx, 75 * sy, 215 * sx, 75 * sy);
    path.cubicTo(230 * sx, 75 * sy, 245 * sx, 80 * sy, 260 * sx, 85 * sy);

    final totalLength = _computePathLength(path);
    final currentLength = totalLength * progress;

    final animatedPath = _extractSubPath(path, currentLength);

    canvas.drawPath(animatedPath, glowPaint);
    canvas.drawPath(animatedPath, paint);
  }

  double _computePathLength(Path path) {
    double length = 0.0;
    for (final metric in path.computeMetrics()) {
      length += metric.length;
    }
    return length;
  }

  Path _extractSubPath(Path path, double length) {
    final subPath = Path();
    double current = 0.0;

    for (final metric in path.computeMetrics()) {
      if (current + metric.length >= length) {
        final remaining = length - current;
        subPath.addPath(metric.extractPath(0.0, remaining), Offset.zero);
        break;
      } else {
        subPath.addPath(metric.extractPath(0.0, metric.length), Offset.zero);
        current += metric.length;
      }
    }
    return subPath;
  }

  @override
  bool shouldRepaint(covariant AppleCursiveHelloPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
