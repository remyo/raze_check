import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';
import 'profile_commands.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.identity,
    required this.profile,
    required this.onUnlocked,
    required this.onCancel,
  });
  final IdentityService identity;
  final LocalProfile profile;
  final ValueChanged<SessionHandle> onUnlocked;
  final VoidCallback onCancel;
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ProfileCommands(
      widget.identity,
    ).unlock(widget.profile.personId, _secret.text);
    if (!mounted) {
      widget.identity.lock();
      return;
    }
    _secret.clear();
    switch (result) {
      case Committed<SessionHandle>(:final value):
        widget.onUnlocked(value);
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
      appBar: AppBar(title: Text('Unlock ${widget.profile.displayName}')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('unlock-passphrase'),
                    controller: _secret,
                    enabled: !_busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                    onSubmitted: _busy ? null : (_) => _unlock(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_error!),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _unlock,
                    child: Text(_busy ? 'Unlocking…' : 'Unlock'),
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
  );
}
