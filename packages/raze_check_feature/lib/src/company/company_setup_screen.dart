import 'package:flutter/material.dart';
import 'package:raze_check_core/raze_check_core.dart';

class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({
    super.key,
    required this.onSave,
    required this.onCancel,
    this.busy = false,
    this.error,
  });
  final Future<void> Function(CompanyDraft) onSave;
  final VoidCallback onCancel;
  final bool busy;
  final String? error;
  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final _name = TextEditingController();
  String? _zone;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Create company', style: Theme.of(context).textTheme.headlineSmall),
      TextField(
        controller: _name,
        decoration: InputDecoration(
          labelText: 'Company name',
          helperText: 'Up to 120 Unicode characters',
          errorText: _name.text.isNotEmpty && !compatibleCompanyName(_name.text)
              ? 'Enter a name of 1–120 Unicode characters.'
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: widget.busy
            ? null
            : () async {
                final zone = await showSearch<String>(
                  context: context,
                  delegate: _ZoneSearch(CompanyTimeZones.all),
                );
                if (zone != null && zone.isNotEmpty && mounted) {
                  setState(() => _zone = zone);
                }
              },
        child: Text(_zone ?? 'Select IANA time zone'),
      ),
      const Text(
        'Choose the company time zone explicitly. All zones are bundled for offline use.',
      ),
      if (widget.error != null) Text(widget.error!),
      const SizedBox(height: 16),
      FilledButton(
        onPressed:
            widget.busy || _zone == null || !compatibleCompanyName(_name.text)
            ? null
            : () => widget.onSave(CompanyDraft(_name.text, _zone!)),
        child: Text(widget.busy ? 'Saving…' : 'Create company'),
      ),
      TextButton(
        onPressed: widget.busy ? null : widget.onCancel,
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _ZoneSearch extends SearchDelegate<String> {
  _ZoneSearch(this.zones) : super(searchFieldLabel: 'Search IANA time zones');
  final List<String> zones;
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, ''),
    icon: const Icon(Icons.arrow_back),
  );
  Widget _list(BuildContext context) => ListView(
    children: [
      for (final zone in zones.where(
        (z) => z.toLowerCase().contains(query.toLowerCase()),
      ))
        ListTile(title: Text(zone), onTap: () => close(context, zone)),
    ],
  );
  @override
  Widget buildResults(BuildContext context) => _list(context);
  @override
  Widget buildSuggestions(BuildContext context) => _list(context);
}
