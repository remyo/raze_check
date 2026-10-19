import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'profile_commands.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.identity,
    required this.onCreated,
    required this.onCancel,
  });
  final IdentityService identity;
  final ValueChanged<SessionHandle> onCreated;
  final VoidCallback onCancel;
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ProfileCommands(
      widget.identity,
    ).create(_name.text, _secret.text);
    if (!mounted) {
      widget.identity.lock();
      return;
    }
    _secret.clear();
    _confirm.clear();
    switch (result) {
      case Committed<SessionHandle>(:final value):
        widget.onCreated(value);
      case Rejected<SessionHandle>(:final error):
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      case VersionConflict<SessionHandle>():
        setState(() {
          _busy = false;
          _error = 'Profile changed. Try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Create local profile')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your profile stays on this phone. No network account is required.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('profile-name'),
                      controller: _name,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      maxLength: 100,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your name.'
                          : null,
                    ),
                    TextFormField(
                      key: const Key('profile-passphrase'),
                      controller: _secret,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Passphrase',
                      ),
                      validator: (value) => (value?.runes.length ?? 0) < 12
                          ? 'Use at least 12 characters.'
                          : null,
                    ),
                    TextFormField(
                      key: const Key('profile-confirm'),
                      controller: _confirm,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                      ),
                      validator: (value) => value != _secret.text
                          ? 'Passphrases must match.'
                          : null,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_error!, semanticsLabel: _error),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Save profile'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
