import 'package:flutter/material.dart';

@immutable
class CheckStatusColors extends ThemeExtension<CheckStatusColors> {
  const CheckStatusColors({
    required this.attention,
    required this.attentionContainer,
  });

  final Color attention, attentionContainer;

  @override
  CheckStatusColors copyWith({Color? attention, Color? attentionContainer}) =>
      CheckStatusColors(
        attention: attention ?? this.attention,
        attentionContainer: attentionContainer ?? this.attentionContainer,
      );

  @override
  CheckStatusColors lerp(CheckStatusColors? other, double t) {
    if (other == null) return this;
    return CheckStatusColors(
      attention: Color.lerp(attention, other.attention, t)!,
      attentionContainer: Color.lerp(
        attentionContainer,
        other.attentionContainer,
        t,
      )!,
    );
  }
}

abstract final class CheckTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = Color(dark ? 0xff13171c : 0xfff6f7f9);
    final surface = Color(dark ? 0xff1d232b : 0xffffffff);
    final text = Color(dark ? 0xffedf1f5 : 0xff17232f);
    final muted = Color(dark ? 0xffa0adba : 0xff62717f);
    final border = Color(dark ? 0xff323a44 : 0xffe5e9ef);
    final accent = Color(dark ? 0xff78d2da : 0xff087f8c);
    final onAccent = Color(dark ? 0xff123037 : 0xffffffff);
    final accentTint = Color(dark ? 0xff203b40 : 0xffe9f5f6);
    final quiet = Color(dark ? 0xff262d36 : 0xfff1f3f6);

    // Material surfaces stay neutral; teal identifies actions and selection.
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff087f8c),
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: onAccent,
          primaryContainer: accentTint,
          onPrimaryContainer: Color(dark ? 0xff78d2da : 0xff076f7b),
          secondary: accent,
          onSecondary: onAccent,
          secondaryContainer: quiet,
          onSecondaryContainer: text,
          tertiary: accent,
          onTertiary: onAccent,
          tertiaryContainer: quiet,
          onTertiaryContainer: text,
          primaryFixed: const Color(0xffe9f5f6),
          primaryFixedDim: const Color(0xffb5e3e7),
          onPrimaryFixed: const Color(0xff123037),
          onPrimaryFixedVariant: const Color(0xff08717c),
          secondaryFixed: const Color(0xfff1f3f6),
          secondaryFixedDim: const Color(0xffdce2e8),
          onSecondaryFixed: const Color(0xff17232f),
          onSecondaryFixedVariant: const Color(0xff52616f),
          tertiaryFixed: const Color(0xfff1f3f6),
          tertiaryFixedDim: const Color(0xffdce2e8),
          onTertiaryFixed: const Color(0xff17232f),
          onTertiaryFixedVariant: const Color(0xff52616f),
          surface: surface,
          onSurface: text,
          onSurfaceVariant: muted,
          surfaceDim: Color(dark ? 0xff101419 : 0xffe1e5ea),
          surfaceBright: Color(dark ? 0xff343d48 : 0xffffffff),
          surfaceContainerLowest: Color(dark ? 0xff0e1217 : 0xffffffff),
          surfaceContainerLow: surface,
          surfaceContainer: Color(dark ? 0xff212831 : 0xfff6f7f9),
          surfaceContainerHigh: quiet,
          surfaceContainerHighest: Color(dark ? 0xff303945 : 0xffe9edf2),
          outline: Color(dark ? 0xff7f8e9e : 0xff81909c),
          outlineVariant: border,
          inverseSurface: Color(dark ? 0xffedf1f5 : 0xff28323c),
          onInverseSurface: Color(dark ? 0xff17232f : 0xfff6f7f9),
          inversePrimary: Color(dark ? 0xff087f8c : 0xff78d2da),
          surfaceTint: Colors.transparent,
        );
    const size = WidgetStatePropertyAll(Size(48, 48));
    const buttonShape = WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      extensions: [
        CheckStatusColors(
          attention: Color(dark ? 0xffedc477 : 0xff966313),
          attentionContainer: Color(dark ? 0xff3b3122 : 0xfffff4df),
        ),
      ],
      scaffoldBackgroundColor: background,
      fontFamily: 'Manrope',
      package: 'raze_check_feature',
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarThemeData(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          package: 'raze_check_feature',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: size, shape: buttonShape),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: size,
          shape: buttonShape,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: size,
          shape: buttonShape,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? text.withValues(alpha: .38)
                : colors.onPrimaryContainer,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: size,
          shape: buttonShape,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? text.withValues(alpha: .38)
                : text,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        fillColor: surface,
        filled: true,
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accentTint,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? accent : muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
