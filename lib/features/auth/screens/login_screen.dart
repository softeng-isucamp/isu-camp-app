import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';

import 'get_started_screen.dart';
import 'help_screen.dart';
import 'register_screen.dart';
import '../services/user_session.dart';
import '../../onboarding/screens/welcome_greeting_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isCaptchaChecked = false;
  bool _isPasswordVisible = false;
  int _failedLoginAttempts = 0;
  Timer? _lockoutTimer;
  DateTime? _loginLockedUntil;

  bool get _isLoginLocked =>
      _loginLockedUntil != null && DateTime.now().isBefore(_loginLockedUntil!);

  int get _remainingLockoutSeconds {
    if (_loginLockedUntil == null) return 0;
    return _loginLockedUntil!.difference(DateTime.now()).inSeconds + 1;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

Future<void> _handleLogin() async {
  if (_isLoginLocked) {
    _showSnackBar(
      'Too many failed attempts. Try again in ${_formatLockoutTime()}.',
      Colors.orangeAccent.shade700,
    );
    return;
  }

  final identifier = _usernameController.text.trim();
  final password = _passwordController.text.trim();

  if (identifier.isEmpty || password.isEmpty) {
    _showSnackBar(
      'Please fill in both Username and Password.',
      Colors.redAccent,
    );
    return;
  }

  if (!_isCaptchaChecked) {
    _showSnackBar(
      'Please complete the verification checkbox.',
      Colors.orangeAccent.shade700,
    );
    return;
  }

  try {
    // Check credentials through backend
    final response = await AuthService.login(
      identifier: identifier,
      password: password,
    );

    // Get actual user returned by database
    final user = response['user'];
    final String username = user['username'];

    // Remember logged-in user
    UserSession.setLoggedInUser(
      username: username,
      token: response['access_token'] as String?,
    );

    if (!mounted) return;

    // Login successful → proceed
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => WelcomeGreetingScreen(
          userName: username,
        ),
      ),
    );
  } catch (error) {
    if (!mounted) return;

    String message = error.toString();

    if (error is LoginException && error.retryAfterSeconds != null) {
      _startLockout(error.retryAfterSeconds!);
    }

    if (error is LoginException && error.failedAttempts != null) {
      setState(() => _failedLoginAttempts = error.failedAttempts!);
    }

    // Remove "Exception: " from displayed message
    message = message.replaceFirst('Exception: ', '');

    _showSnackBar(
      message,
      Colors.redAccent,
    );
  }
}

void _startLockout(int seconds) {
  _lockoutTimer?.cancel();
  setState(() {
    _loginLockedUntil = DateTime.now().add(Duration(seconds: seconds));
  });
  _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (!mounted || !_isLoginLocked) {
      timer.cancel();
      if (mounted) {
        setState(() {
          _loginLockedUntil = null;
          _failedLoginAttempts = 0;
        });
      }
    } else {
      setState(() {});
    }
  });
}

String _formatLockoutTime() {
  final seconds = _remainingLockoutSeconds;
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message, style: GoogleFonts.montserrat()),
          backgroundColor: color),
    );
  }

  // =========================================================================
  // POP-UP FLOW 1: Forgot Password Sheet
  // =========================================================================
  void _showForgotPasswordSheet(BuildContext context) {
    final TextEditingController identifierController =
        TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Reset Password',
                  style: GoogleFonts.merriweather(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F4D20),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your username or email. We will send a verification code to your registered email.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Username or Email',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: identifierController,
                  decoration: InputDecoration(
                    hintText: 'Username or Email',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final identifier =
                          identifierController.text.trim();

                      if (identifier.isEmpty) {
                        _showSnackBar(
                          'Please enter your username or email.',
                          Colors.redAccent,
                        );
                        return;
                      }

                      try {
                        await AuthService.requestForgotPasswordOtp(
                          identifier: identifier,
                        );

                        if (!mounted) return;

                        Navigator.pop(sheetContext);

                        _showVerifyCodeSheet(
                          context,
                          identifier,
                        );

                        _showSnackBar(
                          'Verification code sent to your registered email.',
                          const Color(0xFF0F751B),
                        );
                      } catch (error) {
                        if (!mounted) return;

                        String message = error.toString();
                        message =
                            message.replaceFirst('Exception: ', '');

                        _showSnackBar(
                          message,
                          Colors.redAccent,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F751B),
                    ),
                    child: Text(
                      'Request Reset Code',
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        identifierController.dispose();
      });
    });
  }

  // =========================================================================
  // POP-UP FLOW 2: Verify 6-Digit Code Sheet
  // =========================================================================
  void _showVerifyCodeSheet(
    BuildContext context,
    String identifier,
  ) {
    final List<TextEditingController> otpControllers =
        List.generate(6, (index) => TextEditingController());

    final List<FocusNode> focusNodes =
        List.generate(6, (index) => FocusNode());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Verify Code',
                  style: GoogleFonts.merriweather(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F4D20),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit verification code sent to your registered email.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 42,
                      height: 50,
                      child: TextField(
                        controller: otpControllers[index],
                        focusNode: focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        obscureText: true,
                        obscuringCharacter: '●',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
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
                            focusNodes[index + 1].requestFocus();
                          } else if (value.isEmpty && index > 0) {
                            focusNodes[index - 1].requestFocus();
                          }
                        },
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final code =
                          otpControllers.map((c) => c.text).join();

                      if (code.length != 6) {
                        _showSnackBar(
                          'Please enter all 6 digits.',
                          Colors.redAccent,
                        );
                        return;
                      }

                      try {
                        await AuthService.verifyForgotPasswordOtp(
                          identifier: identifier,
                          otp: int.parse(code),
                        );

                        if (!mounted) return;

                        Navigator.pop(sheetContext);

                        _showSetNewPasswordSheet(
                          context,
                          identifier,
                        );

                        _showSnackBar(
                          'OTP verified successfully.',
                          const Color(0xFF0F751B),
                        );
                      } catch (error) {
                        if (!mounted) return;

                        String message = error.toString();
                        message =
                            message.replaceFirst('Exception: ', '');

                        _showSnackBar(
                          message,
                          Colors.redAccent,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F751B),
                    ),
                    child: Text(
                      'Verify and Continue',
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      for (final controller in otpControllers) {
        controller.dispose();
      }

      for (final focusNode in focusNodes) {
        focusNode.dispose();
      }
    });
  }

  // =========================================================================
  // POP-UP FLOW 3: Set New Password Sheet
  // =========================================================================
  void _showSetNewPasswordSheet(
    BuildContext context,
    String identifier,
  ) {
    final TextEditingController newPassController =
        TextEditingController();
    final TextEditingController confirmPassController =
        TextEditingController();

    bool isNewVisible = false;
    bool isConfirmVisible = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final text = newPassController.text;

            final bool hasMinLength = text.length >= 8;
            final bool hasMixedCase =
                text.contains(RegExp(r'[a-z]')) &&
                    text.contains(RegExp(r'[A-Z]'));
            final bool hasNumber = text.contains(RegExp(r'[0-9]'));
            final bool hasSpecialChar = text.contains(
              RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-\+=~/\\\[\]]'),
            );

            Widget buildRequirement(String label, bool met) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: met
                            ? const Color(0xFF0F751B)
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        color: met ? Colors.black87 : Colors.black54,
                        fontWeight:
                            met ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'Set New Password',
                        style: GoogleFonts.merriweather(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F4D20),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'New Password',
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: newPassController,
                        obscureText: !isNewVisible,
                        onChanged: (value) {
                          setSheetState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter new password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              isNewVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 20,
                            ),
                            onPressed: () {
                              setSheetState(() {
                                isNewVisible = !isNewVisible;
                              });
                            },
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildRequirement(
                        'At least 8 characters',
                        hasMinLength,
                      ),
                      buildRequirement(
                        'Mixed case letters (upper & lower)',
                        hasMixedCase,
                      ),
                      buildRequirement(
                        'At least one number',
                        hasNumber,
                      ),
                      buildRequirement(
                        'At least one special character',
                        hasSpecialChar,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Confirm Password',
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmPassController,
                        obscureText: !isConfirmVisible,
                        decoration: InputDecoration(
                          hintText: 'Re-enter new password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              isConfirmVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 20,
                            ),
                            onPressed: () {
                              setSheetState(() {
                                isConfirmVisible =
                                    !isConfirmVisible;
                              });
                            },
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final newPassword =
                                newPassController.text;
                            final confirmPassword =
                                confirmPassController.text;

                            if (newPassword.isEmpty ||
                                confirmPassword.isEmpty) {
                              _showSnackBar(
                                'Please enter and confirm your new password.',
                                Colors.redAccent,
                              );
                              return;
                            }

                            if (newPassword != confirmPassword) {
                              _showSnackBar(
                                'Passwords do not match.',
                                Colors.redAccent,
                              );
                              return;
                            }

                            if (!hasMinLength ||
                                !hasMixedCase ||
                                !hasNumber ||
                                !hasSpecialChar) {
                              _showSnackBar(
                                'Please meet all password requirements.',
                                Colors.orangeAccent,
                              );
                              return;
                            }

                            try {
                              await AuthService.resetForgotPassword(
                                identifier: identifier,
                                password: newPassword,
                                confirmPassword: confirmPassword,
                              );

                              if (!mounted) return;

                              Navigator.pop(sheetContext);

                              _showSnackBar(
                                'Password updated successfully. You can now log in.',
                                const Color(0xFF0F751B),
                              );
                            } catch (error) {
                              if (!mounted) return;

                              String message = error.toString();
                              message = message.replaceFirst(
                                'Exception: ',
                                '',
                              );

                              _showSnackBar(
                                message,
                                Colors.redAccent,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF0F751B),
                          ),
                          child: Text(
                            'Update Password',
                            style: GoogleFonts.montserrat(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      newPassController.dispose();
      confirmPassController.dispose();
    });
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
            colors: [Color(0xFF072B18), Color(0xFF02170C)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                GestureDetector(
                  onTap: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GetStartedScreen(),
                        ),
                      );
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo_kumpas_app.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.navigation,
                                        color: Colors.white),
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
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo_isu_png.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.school, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Login Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 16,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Log in',
                            style: GoogleFonts.merriweather(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F4D20),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const HelpScreen()),
                            ),
                            icon: const Icon(Icons.help_outline,
                                color: Colors.black87, size: 26),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Username field
                      Text('Username',
                          style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          hintText: 'LEADER_JUSTINE',
                          hintStyle: GoogleFonts.montserrat(
                              color: Colors.grey.shade400, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password field & Forgot Link triggering the sheet
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Password',
                              style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87)),
                          GestureDetector(
                            onTap: () => _showForgotPasswordSheet(context),
                            child: Text(
                              'Forgot Password?',
                              style: GoogleFonts.montserrat(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E60D0)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          hintText: 'LEADER_JUSTINE',
                          hintStyle: GoogleFonts.montserrat(
                              color: Colors.grey.shade400, fontSize: 14),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 20),
                            onPressed: () => setState(
                                () => _isPasswordVisible = !_isPasswordVisible),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // reCAPTCHA Box
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F9F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _isCaptchaChecked,
                              activeColor: const Color(0xFF1B62D4),
                              onChanged: (value) => setState(
                                  () => _isCaptchaChecked = value ?? false),
                            ),
                            Text("I'm not a robot",
                                style: GoogleFonts.montserrat(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const Spacer(),
                            Column(
                              children: [
                                const Icon(Icons.autorenew,
                                    color: Color(0xFF1B62D4), size: 22),
                                Text('reCAPTCHA',
                                    style: GoogleFonts.montserrat(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Create Account Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const RegisterScreen()),
                          ),
                          child: Text(
                            'Create new account',
                            style: GoogleFonts.montserrat(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1E60D0)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoginLocked ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F751B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(
                            _isLoginLocked
                                ? 'Try again in ${_formatLockoutTime()}'
                                : 'Log in',
                            style: GoogleFonts.montserrat(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isLoginLocked)
                        Text(
                          'Too many login attempts. Try again in ${_formatLockoutTime()}.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_failedLoginAttempts > 0)
                        Text(
                          'Login attempt $_failedLoginAttempts of 6',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Isabela State University- Echague Campus',
                      style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
