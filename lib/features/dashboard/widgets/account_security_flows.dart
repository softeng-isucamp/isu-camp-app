import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/services/remembered_session_store.dart';
import '../../auth/services/user_session.dart';
import '../../auth/services/verification_security_controller.dart';
import '../../auth/widgets/verification_sheets.dart';
import '../services/profile_service.dart';

/// Change-password and change-email flows for a logged-in user. Both reuse
/// the forgot-password sheets and timers.

const _green = Color(0xFF0F751B);

String _message(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

void _snack(ScaffoldMessengerState messenger, String message, Color color) {
  messenger.showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.montserrat()),
      backgroundColor: color));
}

VerificationSecurityController _security(ScaffoldMessengerState messenger) =>
    VerificationSecurityController(onTimeout: (reason) {
      _snack(
          messenger,
          switch (reason) {
            VerificationTimeoutReason.inactivity =>
              'Closed because there was no activity.',
            VerificationTimeoutReason.codeExpired =>
              'Verification code expired. Please request a new code.',
            VerificationTimeoutReason.setupExpired =>
              'Password setup session expired. Please try again.',
          },
          Colors.orangeAccent.shade700);
    });

/// Code to the account email → verify → new password. The user stays logged in.
Future<void> startChangePasswordFlow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  // Sending the email can take several seconds; show that something is happening.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 18),
          Text('Sending code…'),
        ]),
      ),
    ),
  );
  final String sentTo;
  try {
    sentTo = await ProfileService.requestPasswordChangeCode();
  } catch (error) {
    navigator.pop();
    _snack(messenger, _message(error), Colors.redAccent);
    return;
  }
  navigator.pop();
  if (!context.mounted) return;
  final security = _security(messenger)..startOtpChallenge();
  try {
    final verified = await VerifyCodeSheet.show(
      context,
      security: security,
      description: 'Enter the 6-digit verification code sent to $sentTo.',
      onVerify: ProfileService.verifyPasswordChangeCode,
      onResend: ProfileService.requestPasswordChangeCode,
      onVerified: security.beginPasswordSetup,
    );
    if (!verified || !context.mounted) return;
    final updated = await SetNewPasswordSheet.show(
      context,
      security: security,
      onSubmit: ProfileService.changePassword,
    );
    if (updated) _snack(messenger, 'Password updated.', _green);
  } finally {
    security.cancel();
    security.dispose();
  }
}

/// New address → code to the new address → the email changes once confirmed.
Future<void> startChangeEmailFlow(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final email = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const ChangeEmailSheet(),
  );
  if (email == null || !context.mounted) return;
  final security = _security(messenger)..startOtpChallenge();
  AccountProfile? profile;
  try {
    final verified = await VerifyCodeSheet.show(
      context,
      security: security,
      description: 'Enter the 6-digit verification code sent to $email.',
      onVerify: (otp) async =>
          profile = await ProfileService.confirmEmailChange(email, otp),
      onResend: () => ProfileService.requestEmailChangeCode(email),
    );
    final changed = profile;
    if (!verified || changed == null) return;
    UserSession.currentEmail = changed.email;
    var message = 'Email updated to ${changed.email}.';
    try {
      await RememberedSessionStore.updateProfile(
          username: changed.username, email: changed.email);
    } catch (_) {
      message =
          'Email updated. This device could not refresh its saved profile.';
    }
    _snack(messenger, message, _green);
  } finally {
    security.cancel();
    security.dispose();
  }
}

/// Asks for the new address and sends the code; pops with the address.
class ChangeEmailSheet extends StatefulWidget {
  const ChangeEmailSheet({super.key});
  @override
  State<ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<ChangeEmailSheet> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sending = false;
  bool _showValidation = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final email = value?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (email.toLowerCase() == UserSession.currentEmail.toLowerCase()) {
      return 'That is already your email.';
    }
    return null;
  }

  Future<void> _send() async {
    if (_sending) return;
    _showValidation = true;
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ProfileService.requestEmailChangeCode(email);
      if (mounted) Navigator.pop(context, email);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_sending,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            child: Form(
              key: _form,
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
                              borderRadius: BorderRadius.circular(2)))),
                  Text('Change Email',
                      style: GoogleFonts.merriweather(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F4D20))),
                  const SizedBox(height: 8),
                  Text(
                      'We will send a verification code to your new email. Your email changes once you enter it.',
                      style: GoogleFonts.montserrat(
                          fontSize: 12.5, color: Colors.grey.shade700)),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const ValueKey('change_email_input'),
                    controller: _email,
                    enabled: !_sending,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'New email',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (value) =>
                        _showValidation ? _validate(value) : null,
                    onChanged: (_) {
                      _showValidation = false;
                      _form.currentState!.validate();
                      if (_error != null) setState(() => _error = null);
                    },
                    onFieldSubmitted: (_) => _send(),
                  ),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.redAccent))),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(backgroundColor: _green),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text('Send Code',
                              style: GoogleFonts.montserrat(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
