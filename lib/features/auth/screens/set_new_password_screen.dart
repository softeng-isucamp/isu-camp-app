import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'help_screen.dart';
import 'login_screen.dart';

class SetNewPasswordScreen extends StatefulWidget {
  final String email;

  const SetNewPasswordScreen({super.key, this.email = 'user@gmail.com'});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen>
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

  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  // Real-time requirement flags
  bool _hasMinLength = false;
  bool _hasMixedCase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;
  bool _hasNoCommonPatterns = true;

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

    _newPasswordController.addListener(_validatePasswordRequirements);
  }

  void _validatePasswordRequirements() {
    final text = _newPasswordController.text;
    setState(() {
      _hasMinLength = text.length >= 8;
      _hasMixedCase =
          text.contains(RegExp(r'[a-z]')) && text.contains(RegExp(r'[A-Z]'));
      _hasNumber = text.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = text.contains(
        RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-\+=~/\\\[\]]'),
      );
      _hasNoCommonPatterns =
          text.isNotEmpty &&
          !text.toLowerCase().contains('password') &&
          !text.contains('123456');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleUpdatePassword() {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.isEmpty || confirmPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fill in both password fields.',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (newPass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Passwords do not match.',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_hasMinLength || !_hasMixedCase || !_hasNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please satisfy all required password criteria.',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.orangeAccent.shade700,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Password updated successfully! Please log in.',
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: const Color(0xFF0F751B),
      ),
    );

    // Return all the way back to LoginScreen
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildRequirementItem(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMet ? const Color(0xFF0F751B) : const Color(0xFF9E9E9E),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 10.5,
                fontWeight: isMet ? FontWeight.w600 : FontWeight.w500,
                color: isMet ? Colors.black87 : Colors.black54,
              ),
            ),
          ),
        ],
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
                // 1. Header: Logo and seal badge
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

                const SizedBox(height: 28),

                // 2. White "Set New Password" Card
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
                          bottom: 14.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set New\nPassword',
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
                          vertical: 12.0,
                        ),
                        color: const Color(0xFFEBEBEB),
                        child: Text(
                          "Your verification was successful. For security, please create a strong password that you haven't used before.",
                          style: GoogleFonts.montserrat(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                            height: 1.35,
                          ),
                        ),
                      ),

                      // Form Body
                      Padding(
                        padding: const EdgeInsets.all(22.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // New Password Field
                            Text(
                              'New Password',
                              style: GoogleFonts.montserrat(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _newPasswordController,
                              obscureText: !_isNewPasswordVisible,
                              decoration: InputDecoration(
                                hintText: 'LEADER_JUSTINE',
                                hintStyle: GoogleFonts.montserrat(
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13.5,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isNewPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isNewPasswordVisible =
                                          !_isNewPasswordVisible;
                                    });
                                  },
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0F4D20),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Confirm Password Field
                            Text(
                              'Confirm Password',
                              style: GoogleFonts.montserrat(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: !_isConfirmPasswordVisible,
                              decoration: InputDecoration(
                                hintText: 'LEADER_JUSTINE',
                                hintStyle: GoogleFonts.montserrat(
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13.5,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isConfirmPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isConfirmPasswordVisible =
                                          !_isConfirmPasswordVisible;
                                    });
                                  },
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0F4D20),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Requirements & reCAPTCHA Box Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Requirements column
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Password Requirements',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _buildRequirementItem(
                                        'At least 8 characters',
                                        _hasMinLength,
                                      ),
                                      _buildRequirementItem(
                                        'Mixed case letters',
                                        _hasMixedCase,
                                      ),
                                      _buildRequirementItem(
                                        'At least one number',
                                        _hasNumber,
                                      ),
                                      _buildRequirementItem(
                                        'At least one special character',
                                        _hasSpecialChar,
                                      ),
                                      _buildRequirementItem(
                                        'Does not contain common patterns',
                                        _hasNoCommonPatterns,
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // reCAPTCHA compact badge box
                                Container(
                                  width: 80,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9F9F9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.autorenew,
                                        color: Color(0xFF1B62D4),
                                        size: 24,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'reCAPTCHA',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        'Privacy - Terms',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 6.5,
                                          color: Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // Green "Update Password" Button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _handleUpdatePassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F751B),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Update Password',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // "Cancel and go to login"
                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginScreen(),
                                    ),
                                    (route) => false,
                                  );
                                },
                                child: Text(
                                  'Cancel and go to login',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1E60D0),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

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
