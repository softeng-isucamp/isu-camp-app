import 'package:isu_camp_app/core/error_messages.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/sheet_controller_scope.dart';
import '../widgets/captcha_verification.dart';
import '../widgets/verification_sheets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'get_started_screen.dart';
import 'help_screen.dart';
import 'register_screen.dart';
import '../services/user_session.dart';
import '../services/remembered_session_store.dart';
import '../services/verification_security_controller.dart';
import '../../onboarding/screens/welcome_greeting_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _captchaToken;
  int _captchaRevision = 0;
  bool _isPasswordVisible = false;
  bool _isLoggingIn = false;
  bool _keepSignedIn = false;
  int _failedLoginAttempts = 0;
  int? _serverRemainingAttempts;
  Timer? _lockoutTimer;
  DateTime? _loginLockedUntil;
  late final VerificationSecurityController _forgotSecurity;

  bool get _isLoginLocked =>
      _loginLockedUntil != null && DateTime.now().isBefore(_loginLockedUntil!);

  int get _remainingLockoutSeconds {
    if (_loginLockedUntil == null) return 0;
    return _loginLockedUntil!.difference(DateTime.now()).inSeconds + 1;
  }

  @override
  void initState() {
    super.initState();
    _forgotSecurity = VerificationSecurityController(
      onTimeout: _handleForgotPasswordTimeout,
    );
  }

  void _handleForgotPasswordTimeout(VerificationTimeoutReason reason) {
    // The open sheet closes itself; this only explains why.
    if (!mounted) return;
    final message = switch (reason) {
      VerificationTimeoutReason.inactivity =>
        'Password reset closed because there was no activity.',
      VerificationTimeoutReason.codeExpired =>
        'Verification code expired. Please request a new code.',
      VerificationTimeoutReason.setupExpired =>
        'Password setup session expired. Please try again.',
    };
    _showSnackBar(message, Colors.orangeAccent.shade700);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _lockoutTimer?.cancel();
    _forgotSecurity.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoggingIn) return;
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
        'Enter your username or email and password.',
        Colors.redAccent,
      );
      return;
    }

    if (_captchaToken == null) {
      _showSnackBar(
        'Please complete human verification.',
        Colors.orangeAccent.shade700,
      );
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      // Check credentials through backend
      final response = await AuthService.login(
        identifier: identifier,
        password: password,
        captchaToken: _captchaToken,
      );

      // Get actual user returned by database
      final user = response['user'];
      final String username = user['username'];

      // Remember logged-in user
      UserSession.setLoggedInUser(
        username: username,
        token: response['access_token'] as String?,
        email: user['email'] as String? ?? '',
      );

      try {
        await RememberedSessionStore.save(
          username: username,
          token: response['access_token'] as String?,
          email: user['email'] as String? ?? '',
          keepSignedIn: _keepSignedIn,
        );
      } catch (_) {
        if (mounted && _keepSignedIn) {
          _showSnackBar(
              'Signed in, but this device could not remember your session.',
              Colors.orangeAccent.shade700);
        }
      }

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

      String message =
          ErrorMessages.present(error, 'Could not sign in. Please try again.');

      if (error is LoginException && error.retryAfterSeconds != null) {
        _startLockout(error.retryAfterSeconds!);
        message =
            'Too many failed attempts. Try again in ${_formatLockoutTime()}.';
      }

      if (error is LoginException && error.failedAttempts != null) {
        setState(() {
          _failedLoginAttempts = error.failedAttempts!;
          _serverRemainingAttempts = error.remainingAttempts;
        });
      }

      _passwordController.clear();
      setState(() {
        _captchaToken = null;
        _captchaRevision++;
      });

      // Remove "Exception: " from displayed message
      message = message.replaceFirst('Exception: ', '');

      _showSnackBar(
        message,
        Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
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
            _serverRemainingAttempts = null;
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
    final TextEditingController identifierController = TextEditingController();

    String? requestError;
    bool requesting = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          return SheetControllerScope(
              controllers: [identifierController],
              child: Padding(
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
                        enabled: !requesting,
                        onChanged: (_) =>
                            setSheetState(() => requestError = null),
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
                      if (requestError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(requestError!,
                              key: const ValueKey('reset_request_error'),
                              style: const TextStyle(color: Colors.redAccent)),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: requesting
                              ? null
                              : () async {
                                  final identifier =
                                      identifierController.text.trim();

                                  if (identifier.isEmpty) {
                                    setSheetState(() => requestError =
                                        'Enter your username or email.');
                                    return;
                                  }

                                  setSheetState(() {
                                    requesting = true;
                                    requestError = null;
                                  });
                                  try {
                                    await AuthService.requestForgotPasswordOtp(
                                      identifier: identifier,
                                    );

                                    if (!mounted || !sheetContext.mounted)
                                      return;

                                    _forgotSecurity.startOtpChallenge();

                                    Navigator.pop(sheetContext);

                                    _continuePasswordReset(identifier);

                                    _showSnackBar(
                                      'Verification code sent to your registered email.',
                                      const Color(0xFF0F751B),
                                    );
                                  } catch (error) {
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() => requestError =
                                        ErrorMessages.present(error,
                                            'Could not send the password reset code. Please try again.'));
                                  } finally {
                                    if (sheetContext.mounted) {
                                      setSheetState(() => requesting = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F751B),
                          ),
                          child: Text(
                            requesting ? 'Sending…' : 'Request Reset Code',
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
              ));
        });
      },
    );
  }

  // =========================================================================
  // POP-UP FLOW 2 + 3: Verify the emailed code, then set a new password
  // =========================================================================
  Future<void> _continuePasswordReset(String identifier) async {
    final verified = await VerifyCodeSheet.show(
      context,
      security: _forgotSecurity,
      description:
          'Enter the 6-digit verification code sent to your registered email.',
      onVerify: (otp) =>
          AuthService.verifyForgotPasswordOtp(identifier: identifier, otp: otp),
      onResend: () =>
          AuthService.requestForgotPasswordOtp(identifier: identifier),
      onVerified: _forgotSecurity.beginPasswordSetup,
    );
    if (!mounted) return;
    if (!verified) {
      _forgotSecurity.cancel();
      return;
    }
    final updated = await SetNewPasswordSheet.show(
      context,
      security: _forgotSecurity,
      onSubmit: (password, confirm, _) => AuthService.resetForgotPassword(
        identifier: identifier,
        password: password,
        confirmPassword: confirm,
      ),
    );
    // Stop the timers on every exit so no timeout fires after the flow ends.
    _forgotSecurity.cancel();
    if (updated && mounted) {
      _showSnackBar(
        'Password updated successfully. You can now log in.',
        const Color(0xFF0F751B),
      );
    }
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
                                'assets/images/logo_kumpas_app.webp',
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
                            'assets/images/logo_isu.webp',
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

                      Row(
                        key: const ValueKey('login_keep_signed_in'),
                        children: [
                          Checkbox(
                            value: _keepSignedIn,
                            onChanged: (value) =>
                                setState(() => _keepSignedIn = value ?? false),
                            activeColor: const Color.fromARGB(255, 49, 94, 243),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _keepSignedIn = !_keepSignedIn),
                            child: Text('Keep me signed in',
                                style: GoogleFonts.montserrat(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      CaptchaVerification(
                        key: ValueKey(_captchaRevision),
                        enabled: !_isLoggingIn && !_isLoginLocked,
                        onToken: (token) =>
                            setState(() => _captchaToken = token),
                      ),
                      const SizedBox(height: 10),

                      // Create Account Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
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
                          onPressed: _isLoginLocked || _isLoggingIn
                              ? null
                              : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F751B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          child: _isLoggingIn
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
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
                      if (_failedLoginAttempts > 0 && !_isLoginLocked) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            '${_serverRemainingAttempts ?? (6 - _failedLoginAttempts).clamp(0, 6)} ${(_serverRemainingAttempts ?? (6 - _failedLoginAttempts).clamp(0, 6)) == 1 ? 'sign-in attempt' : 'sign-in attempts'} remaining',
                            style: GoogleFonts.montserrat(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
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
