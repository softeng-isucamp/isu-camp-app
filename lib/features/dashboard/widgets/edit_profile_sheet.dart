import 'package:flutter/material.dart';
import '../../auth/services/remembered_session_store.dart';
import '../../auth/services/user_session.dart';
import '../services/profile_service.dart';

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key});
  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _username = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _sessionToken = UserSession.accessToken;
  String _email = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ProfileService.load();
      if (!mounted || _sessionToken != UserSession.accessToken) return;
      _username.text = profile.username;
      _email = profile.email;
      UserSession.currentUsername = profile.username;
      UserSession.currentEmail = profile.email;
    } catch (error) {
      if (mounted)
        _error = error is ProfileException
            ? error.message
            : 'Could not load your profile. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await ProfileService.updateUsername(_username.text);
      if (!mounted || _sessionToken != UserSession.accessToken) return;
      UserSession.currentUsername = profile.username;
      UserSession.currentEmail = profile.email;
      String message = 'Username updated.';
      try {
        await RememberedSessionStore.updateProfile(
            username: profile.username, email: profile.email);
      } catch (_) {
        message =
            'Username updated. This device could not refresh its saved profile.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() => _error = error is ProfileException
            ? error.message
            : 'Could not save your username. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SafeArea(
              top: false,
              child: SingleChildScrollView(
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
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(4)))),
                      Row(children: [
                        const Expanded(
                            child: Text('Edit Profile',
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F4D20)))),
                        IconButton(
                            tooltip: 'Close profile editor',
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ]),
                      const SizedBox(height: 20),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_email.isEmpty) ...[
                        Text(_error ?? 'Could not load your account.'),
                        TextButton(
                            onPressed: _load, child: const Text('Retry')),
                      ] else ...[
                        TextFormField(
                          key: const ValueKey('profile_username'),
                          controller: _username,
                          enabled: !_saving,
                          maxLength: 30,
                          decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder()),
                          validator: (value) => RegExp(r'^[A-Za-z0-9_]{3,30}$')
                                  .hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Use 3–30 letters, numbers, or underscores.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                            initialValue: _email,
                            readOnly: true,
                            decoration: const InputDecoration(
                                labelText: 'Email',
                                suffixIcon: Icon(Icons.lock_outline),
                                border: OutlineInputBorder())),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.redAccent))),
                        const SizedBox(height: 24),
                        Row(children: [
                          TextButton(
                              onPressed:
                                  _saving ? null : () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          const SizedBox(width: 16),
                          Expanded(
                              child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F751B),
                                padding: const EdgeInsets.all(14)),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Save changes'),
                          )),
                        ]),
                      ],
                    ]),
              ))),
        ),
      );
}
