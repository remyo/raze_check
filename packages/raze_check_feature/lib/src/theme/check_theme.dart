import 'package:flutter/material.dart';

abstract final class CheckTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff126653),
          brightness: brightness,
        ).copyWith(
          primary: Color(dark ? 0xff85dcb5 : 0xff126653),
          onPrimary: Color(dark ? 0xff123b2d : 0xffffffff),
          surface: Color(dark ? 0xff1e2f29 : 0xffffffff),
          onSurface: Color(dark ? 0xffe5f1ed : 0xff172e2b),
        );
    const size = WidgetStatePropertyAll(Size(48, 48));
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: Color(dark ? 0xff15211e : 0xfff5f7f3),
      fontFamily: 'Manrope',
      package: 'raze_check_feature',
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: size),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: size,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(minimumSize: size),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(minimumSize: size),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}
