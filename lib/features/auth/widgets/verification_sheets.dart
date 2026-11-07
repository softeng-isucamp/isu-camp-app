import 'package:isu_camp_app/core/error_messages.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/verification_security_controller.dart';
import 'otp_code_input.dart';

/// Shared bottom sheets for emailed-code flows: forgot password, change
/// password and change email. Each sheet closes itself when [security]
/// times out; the caller shows the timeout message and cancels [security]
/// once the flow ends.

const _green = Color(0xFF0F751B);
const _darkGreen = Color(0xFF0F4D20);


Widget _handle() => Center(
    child: Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2))));

Widget _title(String text) => Text(text,
    style: GoogleFonts.merriweather(
        fontSize: 24, fontWeight: FontWeight.bold, color: _darkGreen));

/// Pops [context]'s sheet once when [security] expires.
mixin _ClosesOnTimeout<T extends StatefulWidget> on State<T> {
  VerificationSecurityController get security;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    security.addListener(_onSecurityChanged);
  }

  void _onSecurityChanged() {
    if (_closed || security.stage != VerificationStage.expired) return;
    _closed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  void closeWith(bool result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    security.removeListener(_onSecurityChanged);
    super.dispose();
  }
}

class VerifyCodeSheet extends StatefulWidget {
  const VerifyCodeSheet({
    super.key,
    required this.security,
    required this.description,
    required this.onVerify,
    required this.onResend,
    this.onVerified,
  });

  final VerificationSecurityController security;
  final String description;
  final Future<void> Function(int otp) onVerify;
  final Future<void> Function() onResend;

  /// Runs after a correct code, before the sheet closes.
  final VoidCallback? onVerified;

  /// Resolves to true only when the code was verified.
  static Future<bool> show(
    BuildContext context, {
    required VerificationSecurityController security,
    required String description,
    required Future<void> Function(int otp) onVerify,
    required Future<void> Function() onResend,
    VoidCallback? onVerified,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => VerifyCodeSheet(
          security: security,
          description: description,
          onVerify: onVerify,
          onResend: onResend,
          onVerified: onVerified,
        ),
      ) ??
      false;

  @override
  State<VerifyCodeSheet> createState() => _VerifyCodeSheetState();
}

class _VerifyCodeSheetState extends State<VerifyCodeSheet>
    with _ClosesOnTimeout {
  final _code = TextEditingController();
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  VerificationSecurityController get security => widget.security;

  Future<void> _verify(String code) async {
    if (_verifying || _resending || !security.canVerify || code.length != 6)
      return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.onVerify(int.parse(code));
      if (!mounted || !security.canVerify) return;
      widget.onVerified?.call();
      closeWith(true);
    } catch (error) {
      if (!mounted) return;
      if (error is OtpException && error.isIncorrectCode) {
        security.recordIncorrectAttempt(
            serverRemaining: error.attemptsRemaining);
        _code.clear();
      } else {
        _code.selection =
            TextSelection(baseOffset: 0, extentOffset: _code.text.length);
      }
      setState(() => _error = AuthService.verificationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await widget.onResend();
      if (!mounted || !security.isOtpStage) return;
      security.recordResend();
      _code.clear();
    } catch (error) {
      if (mounted) setState(() => _error = ErrorMessages.present(error, 'Could not send the verification code. Please try again.'));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: security,
        builder: (context, _) => SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _handle(),
                    _title('Verify Code'),
                    const SizedBox(height: 8),
                    Text(widget.description,
                        style: GoogleFonts.montserrat(
                            fontSize: 12.5, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: Text(
                        security.isVerificationLocked
                            ? 'Try again in ${security.format(security.verificationLockRemaining)}'
                            : 'Code expires in ${security.format(security.codeRemaining)} • ${security.attemptsRemaining} attempts left',
                        style: GoogleFonts.montserrat(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: security.isVerificationLocked
                                ? Colors.redAccent
                                : Colors.grey.shade600),
                      )),
                      TextButton(
                        onPressed:
                            security.canResend && !_verifying && !_resending
                                ? _resend
                                : null,
                        child: Text(_resending
                            ? 'Sending…'
                            : security.canResend
                                ? 'Resend'
                                : 'Resend ${security.format(security.resendRemaining)}'),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    OtpCodeInput(
                      controller: _code,
                      busy: _verifying,
                      enabled: security.canVerify && !_resending,
                      error: _error,
                      onActivity: () {
                        security.recordActivity();
                        if (_error != null) setState(() => _error = null);
                      },
                      onCompleted: _verify,
                    ),
                  ]),
            )),
      );
}

class SetNewPasswordSheet extends StatefulWidget {
  const SetNewPasswordSheet({
    super.key,
    required this.security,
    required this.onSubmit,
    this.requireCurrentPassword = false,
  });

  final VerificationSecurityController security;
  final bool requireCurrentPassword;
  final Future<void> Function(
          String password, String confirmPassword, String? currentPassword)
      onSubmit;

  /// Resolves to true only when the password was saved.
  static Future<bool> show(
    BuildContext context, {
    required VerificationSecurityController security,
    required Future<void> Function(
            String password, String confirmPassword, String? currentPassword)
        onSubmit,
    bool requireCurrentPassword = false,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SetNewPasswordSheet(
            security: security,
            onSubmit: onSubmit,
            requireCurrentPassword: requireCurrentPassword),
      ) ??
      false;

  @override
  State<SetNewPasswordSheet> createState() => _SetNewPasswordSheetState();
}

class _SetNewPasswordSheetState extends State<SetNewPasswordSheet>
    with _ClosesOnTimeout {
  final _currentPassword = TextEditingController();
  bool _currentVisible = false;
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _newVisible = false;
  bool _confirmVisible = false;
  bool _saving = false;

  /// Shown inside the sheet; a snackbar would be hidden behind it.
  String? _error;

  @override
  VerificationSecurityController get security => widget.security;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Widget _requirement(String label, bool met) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: met ? _green : Colors.grey)),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: met ? Colors.black87 : Colors.black54,
                  fontWeight: met ? FontWeight.w600 : FontWeight.w400)),
        ]),
      );

  Widget _label(String text) => Text(text,
      style:
          GoogleFonts.montserrat(fontSize: 13.5, fontWeight: FontWeight.w600));

  Widget _passwordField({
    required TextEditingController controller,
    required bool visible,
    required String hint,
    required VoidCallback onToggle,
    required ValueChanged<String> onChanged,
  }) =>
      TextField(
        controller: controller,
        obscureText: !visible,
        enabled: !_saving,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: IconButton(
            icon: Icon(visible ? Icons.visibility : Icons.visibility_off,
                size: 20),
            onPressed: () {
              security.recordActivity();
              onToggle();
            },
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  Future<void> _submit(bool meetsRules) async {
    if (_saving) return;
    final password = _newPassword.text;
    final confirm = _confirmPassword.text;
    final problem =
        widget.requireCurrentPassword && _currentPassword.text.isEmpty
            ? 'Enter your current password.'
            : password.isEmpty || confirm.isEmpty
                ? 'Enter and confirm your new password.'
                : password != confirm
                    ? 'Passwords do not match.'
                    : !meetsRules
                        ? 'Meet all password requirements.'
                        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(password, confirm,
          widget.requireCurrentPassword ? _currentPassword.text : null);
      if (mounted) closeWith(true);
    } catch (error) {
      if (mounted) setState(() => _error = ErrorMessages.present(error, 'Could not update your password. Please try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _newPassword.text;
    final hasMinLength = text.length >= 8;
    final hasMixedCase =
        text.contains(RegExp(r'[a-z]')) && text.contains(RegExp(r'[A-Z]'));
    final hasNumber = text.contains(RegExp(r'[0-9]'));
    final hasSpecialChar =
        text.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-\+=~/\\\[\]]'));

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _handle(),
              _title('Set New Password'),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: security,
                builder: (context, _) => Text(
                  'Session expires in ${security.format(security.setupRemaining)}',
                  style: GoogleFonts.montserrat(
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.requireCurrentPassword) ...[
                _label('Current Password'),
                const SizedBox(height: 6),
                _passwordField(
                  controller: _currentPassword,
                  visible: _currentVisible,
                  hint: 'Enter current password',
                  onToggle: () =>
                      setState(() => _currentVisible = !_currentVisible),
                  onChanged: (_) {
                    security.recordActivity();
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: 16),
              ],
              _label('New Password'),
              const SizedBox(height: 6),
              _passwordField(
                controller: _newPassword,
                visible: _newVisible,
                hint: 'Enter new password',
                onToggle: () => setState(() => _newVisible = !_newVisible),
                onChanged: (_) {
                  security.recordActivity();
                  setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              _requirement('At least 8 characters', hasMinLength),
              _requirement('Mixed case letters (upper & lower)', hasMixedCase),
              _requirement('At least one number', hasNumber),
              _requirement('At least one special character', hasSpecialChar),
              const SizedBox(height: 16),
              _label('Confirm Password'),
              const SizedBox(height: 6),
              _passwordField(
                controller: _confirmPassword,
                visible: _confirmVisible,
                hint: 'Re-enter new password',
                onToggle: () =>
                    setState(() => _confirmVisible = !_confirmVisible),
                onChanged: (_) {
                  security.recordActivity();
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      key: const ValueKey('set_password_error'),
                      style: GoogleFonts.montserrat(
                          fontSize: 12.5, color: Colors.redAccent)),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () => _submit(hasMinLength &&
                          hasMixedCase &&
                          hasNumber &&
                          hasSpecialChar),
                  style: ElevatedButton.styleFrom(backgroundColor: _green),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Update Password',
                          style: GoogleFonts.montserrat(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
