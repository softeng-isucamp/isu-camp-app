import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'help_screen.dart';
import '../services/user_session.dart';
import '../services/auth_service.dart';
import '../../onboarding/screens/welcome_greeting_screen.dart';

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

  // Form Step State (1: Enter Username & Email, 2: Code Verification, 3: Set Password)
  int _currentStep = 1;

  // Step 1 Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Step 2 Controllers
  final List<TextEditingController> _otpControllers =
      List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (index) => FocusNode());

  // Step 3 Controllers & Flags
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
    _headerSlide = Tween<Offset>(
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
      _hasNoCommonPatterns = text.isNotEmpty &&
          !text.toLowerCase().contains('password') &&
          !text.contains('123456');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.montserrat()),
        backgroundColor: color,
      ),
    );
  }

  // --- Step 1 Navigation: Validate Email & Username ---
Future<void> _handleStep1Continue() async {
  final username = _usernameController.text.trim();
  final email = _emailController.text.trim();

  if (username.isEmpty || email.isEmpty) {
    _showSnackBar(
      'Please fill in both Username and Email.',
      Colors.redAccent,
    );
    return;
  }

  final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');

  if (!emailRegex.hasMatch(email)) {
    _showSnackBar(
      'Please enter a valid email address.',
      Colors.orangeAccent.shade700,
    );
    return;
  }

  try {
    await AuthService.requestSignupOtp(
      username: username,
      email: email,
    );

    if (!mounted) return;

    setState(() {
      _currentStep = 2;
    });

    _showSnackBar(
      'Verification code sent to $email.',
      const Color(0xFF0F751B),
    );
  } catch (error) {
    if (!mounted) return;

    String message = error.toString();
    message = message.replaceFirst('Exception: ', '');

    _showSnackBar(
      message,
      Colors.redAccent,
    );
  }
}

  // --- Step 2 Navigation: Validate 6-Digit Code ---
Future<void> _handleStep2Verify() async {
  final code = _otpControllers.map((c) => c.text).join();

  if (code.length != 6) {
    _showSnackBar(
      'Please enter the full 6-digit verification code.',
      Colors.redAccent,
    );
    return;
  }

  try {
    await AuthService.verifySignupOtp(
      email: _emailController.text.trim(),
      otp: int.parse(code),
    );

    if (!mounted) return;

    setState(() {
      _currentStep = 3;
    });

    _showSnackBar(
      'Email verified! Now set a strong password.',
      const Color(0xFF0F751B),
    );
  } catch (error) {
    if (!mounted) return;

    String message = error.toString();
    message = message.replaceFirst('Exception: ', '');

    _showSnackBar(
      message,
      Colors.redAccent,
    );
  }
}

  // --- Step 3 Navigation: Complete Sign Up ---
Future<void> _handleStep3Complete() async {
  final password = _passwordController.text;
  final confirmPassword = _confirmPasswordController.text;

  if (password.isEmpty || confirmPassword.isEmpty) {
    _showSnackBar(
      'Please enter and confirm your password.',
      Colors.redAccent,
    );
    return;
  }

  if (password != confirmPassword) {
    _showSnackBar(
      'Passwords do not match.',
      Colors.redAccent,
    );
    return;
  }

  if (!_hasMinLength ||
      !_hasMixedCase ||
      !_hasNumber ||
      !_hasSpecialChar ||
      !_hasNoCommonPatterns) {
    _showSnackBar(
      'Please meet all required password criteria.',
      Colors.orangeAccent.shade700,
    );
    return;
  }

  if (!_isAgreedToTerms) {
    _showSnackBar(
      'Please agree to the Terms & Conditions and Privacy Policy.',
      Colors.orangeAccent.shade700,
    );
    return;
  }

  try {
    final response = await AuthService.setSignupPassword(
      email: _emailController.text.trim(),
      password: password,
      confirmPassword: confirmPassword,
    );

    if (!mounted) return;

    final registeredUsername = _usernameController.text.trim();
    final registeredEmail = _emailController.text.trim();

    UserSession.setRegisteredUser(
      username: registeredUsername,
      email: registeredEmail,
    );

    UserSession.setLoggedInUser(
      username: registeredUsername,
      token: response['access_token'] as String?,
    );

    _showSnackBar(
      'Account created successfully! Welcome to ISU-CAMP.',
      const Color(0xFF0F751B),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => WelcomeGreetingScreen(
          userName: registeredUsername,
        ),
      ),
      (route) => false,
    );
  } catch (error) {
    if (!mounted) return;

    String message = error.toString();
    message = message.replaceFirst('Exception: ', '');

    _showSnackBar(
      message,
      Colors.redAccent,
    );
  }
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
                            text: 'KUMPAS',
                            style: TextStyle(
                              color: Color(0xFF0F751B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text:
                                ', you agree to use the application responsibly and for its intended purpose of campus mapping and navigation.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildDialogBullet(
                      'KUMPAS helps users locate campus buildings, offices, rooms, facilities, and walking routes.',
                      boldGreenPrefix: 'KUMPAS ',
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
                      'KUMPAS may be updated or modified to improve its features and information.',
                      boldGreenPrefix: 'KUMPAS ',
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
                            text: 'KUMPAS',
                            style: TextStyle(
                              color: Color(0xFF0F751B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' respects your privacy and collects only information needed to provide its services.',
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

  // --- Step Indicator Widget ---
  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (index) {
        final stepNum = index + 1;
        final isActive = stepNum == _currentStep;
        final isPassed = stepNum < _currentStep;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < 2 ? 6.0 : 0.0),
            height: 4,
            decoration: BoxDecoration(
              color: isPassed
                  ? const Color(0xFF0F751B)
                  : isActive
                      ? const Color(0xFFECC700)
                      : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  // =========================================================================
  // STEP 1 UI: Enter Username & Email Address
  // =========================================================================
  Widget _buildStep1() {
    return KeyedSubtree(
      key: const ValueKey('step_1_account_info'),
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
                  fontSize: 30,
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

          const SizedBox(height: 4),
          Text(
            'Enter your username and email to get started.',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 18),

          // Username Field
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
              hintText: 'LEADER_JUSTINE',
              hintStyle: GoogleFonts.montserrat(
                color: Colors.grey.shade400,
                fontSize: 13.5,
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

          const SizedBox(height: 16),

          // Email Address Field
          Text(
            'Email Address',
            style: GoogleFonts.montserrat(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'user@isu.edu.ph or gmail.com',
              hintStyle: GoogleFonts.montserrat(
                color: Colors.grey.shade400,
                fontSize: 13.5,
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

          const SizedBox(height: 16),

          // Already have account Link
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Text(
                'Already have account? Log in',
                style: GoogleFonts.montserrat(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E60D0),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Continue Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _handleStep1Continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F751B),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                'Continue & Send Code',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STEP 2 UI: Enter 6-Digit Email Verification Code
  // =========================================================================
  Widget _buildStep2() {
    return KeyedSubtree(
      key: const ValueKey('step_2_code_verification'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Verify Email',
                style: GoogleFonts.merriweather(
                  fontSize: 28,
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

          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.black87,
                height: 1.35,
              ),
              children: [
                const TextSpan(text: "We've sent a 6-digit code to "),
                TextSpan(
                  text: _emailController.text.trim(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F751B),
                  ),
                ),
                const TextSpan(text: '. Enter it below to verify your email.'),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 6 OTP Digit Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 40,
                height: 48,
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF3F3F3),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF0F751B),
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    } else if (value.isEmpty && index > 0) {
                      _otpFocusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              );
            }),
          ),

          const SizedBox(height: 14),

          // Resend Code & Edit Email Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _currentStep = 1;
                  });
                },
                child: Text(
                  'Edit Email',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  _showSnackBar(
                    'A new verification code has been sent to ${_emailController.text.trim()}.',
                    const Color(0xFF0F751B),
                  );
                },
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

          const SizedBox(height: 22),

          // Verify and Proceed Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _handleStep2Verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F751B),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                'Verify & Continue',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STEP 3 UI: Create New Password & Terms Agreement
  // =========================================================================
  Widget _buildStep3() {
    return KeyedSubtree(
      key: const ValueKey('step_3_set_password'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Set Password',
                style: GoogleFonts.merriweather(
                  fontSize: 28,
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

          const SizedBox(height: 4),
          Text(
            'Create a strong password for ${_usernameController.text.trim()}.',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 16),

          // Password Field
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
              hintText: 'Enter password',
              hintStyle: GoogleFonts.montserrat(
                color: Colors.grey.shade400,
                fontSize: 13.5,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
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
              hintText: 'Re-enter password',
              hintStyle: GoogleFonts.montserrat(
                color: Colors.grey.shade400,
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
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
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

          const SizedBox(height: 12),

          // Password Requirements Checklist
          Column(
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
              _buildRequirementItem('At least 8 characters', _hasMinLength),
              _buildRequirementItem(
                  'Mixed case letters (upper & lower)', _hasMixedCase),
              _buildRequirementItem('At least one number', _hasNumber),
              _buildRequirementItem(
                  'At least one special character', _hasSpecialChar),
              _buildRequirementItem(
                  'Does not contain common patterns', _hasNoCommonPatterns),
            ],
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

          // Green "Complete Registration" Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _handleStep3Complete,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F751B),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                'Complete Registration',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
                          onTap: () {
                            if (_currentStep > 1) {
                              setState(() {
                                _currentStep--;
                              });
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          child: Row(
                            children: [
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/logo_kumpas_app.png',
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                      Icons.navigation,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'KUMPAS',
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
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/logo_isu_png.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                Icons.school,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. White Registration Card with In-Card Dynamic Step Switcher
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStepIndicator(),
                              const SizedBox(height: 18),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 320),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  );
                                },
                                child: _currentStep == 1
                                    ? _buildStep1()
                                    : _currentStep == 2
                                        ? _buildStep2()
                                        : _buildStep3(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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
