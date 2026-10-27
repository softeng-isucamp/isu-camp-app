import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/captcha_service.dart';
import 'captcha_origin.dart';
import 'captcha_surface.dart';

class CaptchaVerification extends StatefulWidget {
  const CaptchaVerification(
      {super.key, required this.onToken, this.enabled = true});
  final ValueChanged<String?> onToken;
  final bool enabled;

  @override
  State<CaptchaVerification> createState() => _CaptchaVerificationState();
}

class _CaptchaVerificationState extends State<CaptchaVerification> {
  bool _verified = false;
  bool _opening = false;
  String? _error;
  Timer? _expiry;

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening || !widget.enabled) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await CaptchaService.checkAvailability(parentOrigin: captchaParentOrigin);
      if (!mounted) return;
      final token = await showDialog<String>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          child: SizedBox(
              width: 420,
              height: 560,
              child: Column(children: [
                Row(children: [
                  const Expanded(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Human verification',
                              style: TextStyle(fontWeight: FontWeight.bold)))),
                  IconButton(
                      tooltip: 'Close verification',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close)),
                ]),
                Expanded(
                    child: CaptchaSurface(
                  url: Uri.parse('${AuthService.baseUrl}/auth/captcha'),
                  onMessage: (message) {
                    if (!dialogContext.mounted) return;
                    try {
                      final data = jsonDecode(message);
                      if (data['type'] == 'verified' &&
                          data['token'] is String &&
                          (data['token'] as String).isNotEmpty) {
                        Navigator.pop(dialogContext, data['token'] as String);
                      }
                    } catch (_) {/* Ignore malformed bridge messages. */}
                  },
                )),
              ])),
        ),
      );
      if (!mounted || token == null) return;
      widget.onToken(token);
      setState(() => _verified = true);
      _expiry?.cancel();
      _expiry = Timer(const Duration(seconds: 110), () {
        if (!mounted) return;
        widget.onToken(null);
        setState(() => _verified = false);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is CaptchaException
            ? error.message
            : 'Human verification could not open. Please try again later.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  widget.enabled && !_opening && !_verified ? _open : null,
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18)),
              icon: Icon(_verified ? Icons.check_circle : Icons.shield_outlined,
                  color: _verified ? const Color(0xFF0F751B) : null),
              label: Text(_opening
                  ? 'Opening verification…'
                  : _verified
                      ? 'Human verification completed'
                      : "I'm not a robot — verify"),
            )),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent))),
      ]);
}
