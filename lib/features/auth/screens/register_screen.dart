import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'help_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
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

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isAgreedToTerms = false;

  // Real-time password requirement flags
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

    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.60, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    _passwordController.addListener(_validatePasswordRequirements);
  }

  void _validatePasswordRequirements() {
    final text = _passwordController.text;
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
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- Terms and Conditions Dialog ---
  Future<bool?> _showTermsDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold Banner Header
              Container(
                color: const Color(0xFFECC700),
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: Text(
                  'Terms And Condition',
                  style: GoogleFonts.merriweather(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.black87,
                          height: 1.35,
                        ),
                        children: const [
                          TextSpan(text: 'By using '),
                          TextSpan(
                            text: 'ISU-CAMP',
                            style: TextStyle(
                              color: Color(0xFF0F751B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: ', you agree to use the application responsibly and for its intended purpose of campus mapping and navigation.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildDialogBullet(
                      'ISU-CAMP helps users locate campus buildings, offices, rooms, facilities, and walking routes.',
                      boldGreenPrefix: 'ISU-CAMP ',
                    ),
                    _buildDialogBullet(
                      'Map and route information is provided for guidance and may change as campus conditions are updated.',
                    ),
                    _buildDialogBullet(
                      'Offline maps may become outdated and should be updated when an internet connection is available.',
                    ),
                    _buildDialogBullet(
                      'Users are responsible for following actual campus signs, rules, and safety instructions.',
                    ),
                    _buildDialogBullet(
                      'Users must not misuse the application or access it for unauthorized purposes.',
                    ),
                    _buildDialogBullet(
                      'ISU-CAMP may be updated or modified to improve its features and information.',
                      boldGreenPrefix: 'ISU-CAMP ',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'By creating an account or using the application, you agree to these Terms and Conditions.',
                      style: GoogleFonts.montserrat(
                        fontSize: 11.5,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Proceed Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFF5B30D9),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                          ),
                          child: Text(
                            'Proceed',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4322B6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Privacy Policy Dialog ---
  Future<bool?> _showPrivacyDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold Banner Header
              Container(
                color: const Color(0xFFECC700),
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: Text(
                  'Privacy Policy',
                  style: GoogleFonts.merriweather(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.black87,
                          height: 1.35,
                        ),
                        children: const [
                          TextSpan(
                            text: 'ISU-CAMP',
                            style: TextStyle(
                              color: Color(0xFF0F751B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: ' respects your privacy and collects only information needed to provide its services.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildDialogBullet(
                      'Username – used to create and identify your account.',
                    ),
                    _buildDialogBullet(
                      'Location Data – may be used when navigation features require your current location.',
                    ),
                    _buildDialogBullet(
                      'Offline Data – downloaded maps and navigation information may be stored on your device for offline use.',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your information is used to provide account navigation and app functionality and is not intentionally sold for advertising purposes. Reasonable measures are taken to protect your information from unauthorized access.\n\nBy creating an account, you acknowledge that you have read and understood this Privacy Policy.',
                      style: GoogleFonts.montserrat(
                        fontSize: 11.5,
                        color: Colors.black87,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Proceed Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFF5B30D9),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                          ),
                          child: Text(
                            'Proceed',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4322B6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Dialog Bullet point widget
  Widget _buildDialogBullet(String text, {String? boldGreenPrefix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14, height: 1.3)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.montserrat(
                  fontSize: 11.5,
                  color: Colors.black87,
                  height: 1.3,
                ),
                children: [
                  if (boldGreenPrefix != null &&
                      text.startsWith(boldGreenPrefix)) ...[
                    TextSpan(
                      text: boldGreenPrefix,
                      style: const TextStyle(
                        color: Color(0xFF0F751B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: text.substring(boldGreenPrefix.length)),
                  ] else
                    TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Sequential Terms + Privacy Flow on Checkbox Tap ---
  Future<void> _handleCheckboxTap(bool? val) async {
    if (val == true) {
      final termsAccepted = await _showTermsDialog();
      if (termsAccepted == true && mounted) {
        final privacyAccepted = await _showPrivacyDialog();
        if (privacyAccepted == true && mounted) {
          setState(() {
            _isAgreedToTerms = true;
          });
        }
      }
    } else {
      setState(() {
        _isAgreedToTerms = false;
      });
    }
  }

  void _handleSignUp() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fill in all fields.',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
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
            'Please meet all required password criteria.',
            style: GoogleFonts.montserrat(),
          ),
          backgroundColor: Colors.orangeAccent.shade700,
        ),
      );
      return;
    }

    if (!_isAgreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please agree to the Terms & Conditions and Privacy Policy.',
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
          'Account created successfully! Please log in.',
          style: GoogleFonts.montserrat(),
        ),
        backgroundColor: const Color(0xFF0F751B),
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
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
                // 1. Header: Back navigation & Campus Logo
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

                // 2. White "Sign up" Card
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _cardFade,
                      child: Transform.scale(
                        scale: _cardScale.value,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22.0),
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
                      // Header Row: "Sign up" & Help Icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sign up',
                            style: GoogleFonts.merriweather(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
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

                      const SizedBox(height: 18),

                      // Username
                      Text(
                        'Username',
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          hintText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
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

                      // Password
                      Text(
                        'Password',
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          hintText: 'LEADER_JUSTINE',
                          hintStyle: GoogleFonts.montserrat(
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                            fontSize: 13.5,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
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

                      // Confirm Password
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
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
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

                      // Password Requirements & reCAPTCHA Box
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                          Container(
                            width: 80,
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F9F9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
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

                      const SizedBox(height: 12),

                      // "Already have account" Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Already have account',
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E60D0),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Terms & Conditions Checkbox Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _isAgreedToTerms,
                              activeColor: const Color(0xFF0F751B),
                              onChanged: _handleCheckboxTap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: Colors.black87,
                                ),
                                children: [
                                  const TextSpan(text: 'I agree to the '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: GestureDetector(
                                      onTap: () => _showTermsDialog(),
                                      child: Text(
                                        'Terms and Conditions',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 11,
                                          color: const Color(0xFF1E60D0),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(text: ' and '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: GestureDetector(
                                      onTap: () => _showPrivacyDialog(),
                                      child: Text(
                                        'Privacy Policy',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 11,
                                          color: const Color(0xFF1E60D0),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Green "Sign in" / Register Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _handleSignUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F751B),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            'Sign in',
                            style: GoogleFonts.montserrat(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
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
