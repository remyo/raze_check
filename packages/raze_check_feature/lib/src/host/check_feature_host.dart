import 'package:flutter/material.dart';

final class CheckFeatureHost {
  const CheckFeatureHost({
    required this.onExit,
    this.themeBuilder,
    this.iconBuilder,
    this.navigate,
  });
  final VoidCallback onExit;

  /// Returning the inherited host theme preserves the host's typography.
  final ThemeData Function(BuildContext, Brightness)? themeBuilder;
  final Widget Function(BuildContext)? iconBuilder;
  final Future<void> Function(BuildContext, Widget, String)? navigate;
  Future<void> open(BuildContext context, Widget page, String name) =>
      navigate?.call(context, page, name) ??
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => page,
          settings: RouteSettings(name: name),
        ),
      );
}
