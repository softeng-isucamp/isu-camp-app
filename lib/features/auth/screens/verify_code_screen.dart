import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'help_screen.dart';
import 'set_new_password_screen.dart';

class VerifyCodeScreen extends StatefulWidget {
  final String email;

  const VerifyCodeScreen({super.key, this.email = 'user@gmail.com'});

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Header Animation
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  // Card Morph & Scale Animations
  late final Animation<double> _cardScale;
  late final Animation<double> _cardFade;
  late final Animation<double> _cardRadius;

  // Footer Animation
  late final Animation<double> _footerFade;

  // 6-digit OTP Controllers & Focus Nodes
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // 1. Header Transition
    _headerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeInOutCubic),
      ),
    );
    _headerSlide =
        Tween<Offset>(
          begin: const Offset(0.0, -0.20),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
          ),
        );

    // 2. Card Morph & Scale Transition
    _cardScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.20, 0.85, curve: Curves.easeOutQuart),
      ),
    );

    _cardRadius = Tween<double>(begin: 36.0, end: 18.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.20, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.20, 0.65, curve: Curves.easeIn),
      ),
    );

    // 3. Footer Transition
    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.60, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // --- OTP Verification Action ---
  void _handleVerify() {
    final code = _otpControllers.map((c) => c.text).join();

    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter all 6 digits of your verification code.',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Navigate to SetNewPasswordScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SetNewPasswordScreen(email: widget.email),
      ),
    );
  }

  // --- Resend Code Action ---
  void _handleResendCode() {
    for (final c in _otpControllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A new 6-digit code has been sent to your email.',
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: const Color(0xFF0F751B),
      ),
    );
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
              Color(0xFF072B18), // Deep ISU Forest Green
              Color(0xFF02170C), // Dark evergreen
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header: Back navigation to previous screen on tap
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 30,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ISU- CAMP',
                                style: GoogleFonts.montserrat(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: SizedBox(
                            width: 46,
                            height: 46,
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo_isucamp_app.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.school,
                                      color: Colors.white,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // 2. White "VERIFY CODE" Card
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _cardFade,
                      child: Transform.scale(
                        scale: _cardScale.value,
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              _cardRadius.value,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card Top Padding & Header
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 22.0,
                          right: 22.0,
                          top: 22.0,
                          bottom: 16.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VERIFY\nCODE',
                              style: GoogleFonts.merriweather(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                                color: const Color(0xFF0F4D20),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const HelpScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.help_outline,
                                color: Colors.black87,
                                size: 26,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),

                      // Grey Instructional Banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22.0,
                          vertical: 14.0,
                        ),
                        color: const Color(0xFFEBEBEB),
                        child: Text(
                          "We've sent you 6-digit verification code to the email address you provided, please check your inbox and enter the code here to continue resetting your password",
                          style: GoogleFonts.montserrat(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                            height: 1.35,
                          ),
                        ),
                      ),

                      // Input Fields & Submission
                      Padding(
                        padding: const EdgeInsets.all(22.0),
                        child: Column(
                          children: [
                            // "—— 6-digit code ——" Divider Label
                            Row(
                              children: [
                                const Expanded(child: Divider(thickness: 1)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Text(
                                    '6-digit code',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider(thickness: 1)),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // 6 OTP Digit Input Boxes
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(6, (index) {
                                return SizedBox(
                                  width: 44,
                                  height: 52,
                                  child: TextField(
                                    controller: _otpControllers[index],
                                    focusNode: _focusNodes[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    maxLength: 1,
                                    obscureText: true,
                                    obscuringCharacter: '●',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      counterText: '',
                                      filled: true,
                                      fillColor: const Color(0xFFDCDCDC),
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF0F751B),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      if (value.isNotEmpty && index < 5) {
                                        _focusNodes[index + 1].requestFocus();
                                      } else if (value.isEmpty && index > 0) {
                                        _focusNodes[index - 1].requestFocus();
                                      }
                                    },
                                  ),
                                );
                              }),
                            ),

                            const SizedBox(height: 14),

                            // "Didn't receive the code? Resend code"
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Didn't receive the code? ",
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _handleResendCode,
                                  child: Text(
                                    'Resend code',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E60D0),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Green "Verify and Continue" Button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _handleVerify,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F751B),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Verify and Continue',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Code Expiration Notice
                            Text(
                              'For security, this code expires in 15 minutes.',
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // 3. Footer: Shield + Campus Name
                FadeTransition(
                  opacity: _footerFade,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Isabela State University- Echague Campus',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
