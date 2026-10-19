import 'package:flutter/material.dart';

/// Standalone composition entry; reusable features live in their own package.
class CheckApp extends StatelessWidget {
  const CheckApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Raze Check',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f8c)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff087f8c),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const _StartupScreen(),
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/branding/raze_check_logo_master.png',
                    width: 144,
                    height: 144,
                    semanticLabel: 'Raze Check mascot',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Raze Check',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Local services are not configured yet.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
