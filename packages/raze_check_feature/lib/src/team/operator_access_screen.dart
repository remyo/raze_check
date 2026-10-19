import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

class OperatorAccessScreen extends StatefulWidget {
  const OperatorAccessScreen({
    super.key,
    required this.membership,
    required this.onGrant,
    required this.onActivate,
    required this.onCancel,
    this.busy = false,
    this.error,
  });
  final Membership membership;
  final Future<void> Function(Set<Capability>) onGrant;
  final Future<void> Function(String) onActivate;
  final VoidCallback onCancel;
  final bool busy;
  final String? error;
  @override
  State<OperatorAccessScreen> createState() => _OperatorAccessScreenState();
}

class _OperatorAccessScreenState extends State<OperatorAccessScreen> {
  late final _caps = Set<Capability>.of(widget.membership.capabilities);
  final _pass = TextEditingController(),
      _confirmation = TextEditingController();
  String? _validation;
  @override
  void dispose() {
    _pass.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Operator access', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        'Only the owner can grant management access. This credential unlocks this company only.',
      ),
      for (final cap in Capability.values.where(
        (c) => !AccessPolicy.ownerOnly.contains(c),
      ))
        CheckboxListTile(
          title: Text(cap.name),
          value: _caps.contains(cap),
          onChanged: widget.busy
              ? null
              : (on) => setState(() {
                  if (on!) {
                    _caps.add(cap);
                  } else {
                    _caps.remove(cap);
                  }
                }),
        ),
      FilledButton(
        onPressed: widget.busy ? null : () => widget.onGrant(_caps),
        child: const Text('Save capabilities'),
      ),
      TextField(
        controller: _pass,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Operator passphrase (at least 12 characters)',
        ),
      ),
      TextField(
        controller: _confirmation,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Confirm operator passphrase',
        ),
      ),
      if (_validation != null) Text(_validation!),
      if (widget.error != null) Text(widget.error!),
      FilledButton(
        onPressed: widget.busy
            ? null
            : () {
                if (_pass.text.runes.length < 12 ||
                    _pass.text != _confirmation.text) {
                  setState(
                    () => _validation =
                        'Use at least 12 characters and matching confirmation.',
                  );
                  return;
                }
                widget.onActivate(_pass.text);
              },
        child: const Text('Activate operator credential'),
      ),
      TextButton(
        onPressed: widget.onCancel,
        child: const Text('Back to staff'),
      ),
    ],
  );
}

class OperatorUnlockScreen extends StatefulWidget {
  const OperatorUnlockScreen({
    super.key,
    required this.companies,
    required this.onUnlocked,
    required this.onCancel,
  });
  final CompanyService companies;
  final ValueChanged<SessionHandle> onUnlocked;
  final VoidCallback onCancel;
  @override
  State<OperatorUnlockScreen> createState() => _OperatorUnlockScreenState();
}

class _OperatorUnlockScreenState extends State<OperatorUnlockScreen> {
  late Future<List<OperatorChoice>> _choices = widget.companies
      .operatorChoices();
  final _secret = TextEditingController();
  OperatorChoice? _selected;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final choice = _selected;
    if (choice == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.companies.unlockOperator(
        choice.companyId,
        choice.membershipId,
        _secret.text,
      );
      if (mounted) widget.onUnlocked(session);
    } on CheckException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Operator could not unlock (${e.code.name}).';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unlock company operator')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        FutureBuilder<List<OperatorChoice>>(
          future: _choices,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('Could not read local operators.'),
                  TextButton(
                    onPressed: () => setState(
                      () => _choices = widget.companies.operatorChoices(),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Text(
                'The owner must first activate a staff operator on this device.',
              );
            }
            return Column(
              children: [
                for (final choice in snapshot.data!)
                  ListTile(
                    title: Text(choice.displayName),
                    subtitle: Text(choice.companyName),
                    selected: identical(choice, _selected),
                    leading: Icon(
                      identical(choice, _selected)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: _busy
                        ? null
                        : () => setState(() => _selected = choice),
                  ),
              ],
            );
          },
        ),
        TextField(
          controller: _secret,
          obscureText: true,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Operator passphrase'),
        ),
        if (_error != null) Text(_error!),
        FilledButton(
          onPressed: _busy || _selected == null ? null : _unlock,
          child: Text(_busy ? 'Unlocking…' : 'Unlock operator'),
        ),
        TextButton(
          onPressed: _busy ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
