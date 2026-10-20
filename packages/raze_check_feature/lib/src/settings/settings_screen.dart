import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onOpenGuides});
  final VoidCallback onOpenGuides;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Help & Guides'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenGuides,
        ),
      ],
    ),
  );
}
