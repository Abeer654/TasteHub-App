// ============================================================
//  theme.dart - warm, food-inspired colours and typography
//
//  TasteHubColors is a ThemeExtension so every widget reads the same
//  named colours in both light and dark mode:
//
//      final colors = context.tasteHubColors;
//      color: colors.card
//
//  Do not use hardcoded light colours in screens: they would stay
//  light when the user picks Dark.
// ============================================================

import 'package:flutter/material.dart';

@immutable
class TasteHubColors extends ThemeExtension<TasteHubColors> {
  const TasteHubColors({
    required this.background,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.gold,
    required this.error,
    required this.success,
    required this.onAccent,
    required this.field,
    required this.goldWash,
  });

  final Color background;
  final Color card;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color gold;
  final Color error;
  final Color success;
  final Color onAccent;

  /// Slightly darker surface used for tabs and small chips.
  final Color field;

  /// Soft gold surface used behind the "Top pick" badge.
  final Color goldWash;

  static const TasteHubColors light = TasteHubColors(
    background: Color(0xFFFAF6F0),
    card: Color(0xFFFFFDFA),
    ink: Color(0xFF2D241C),
    muted: Color(0xFF7D6E60),
    line: Color(0xFFE9DED0),
    accent: Color(0xFFBB4D2A),
    gold: Color(0xFFD98A2B),
    error: Color(0xFFA32C1D),
    success: Color(0xFF5B7B4B),
    onAccent: Colors.white,
    field: Color(0xFFF1E7DB),
    goldWash: Color(0xFFF7E2B8),
  );

  static const TasteHubColors dark = TasteHubColors(
    background: Color(0xFF16120F),
    card: Color(0xFF221C17),
    ink: Color(0xFFF4EAE0),
    muted: Color(0xFFB6A594),
    line: Color(0xFF3B3027),
    accent: Color(0xFFE9875F),
    gold: Color(0xFFE6AE55),
    error: Color(0xFFEF8B7B),
    success: Color(0xFF9CBE82),
    onAccent: Color(0xFF1A110C),
    field: Color(0xFF2C241D),
    goldWash: Color(0xFF3A2E1C),
  );

  @override
  TasteHubColors copyWith({
    Color? background,
    Color? card,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? gold,
    Color? error,
    Color? success,
    Color? onAccent,
    Color? field,
    Color? goldWash,
  }) {
    return TasteHubColors(
      background: background ?? this.background,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      gold: gold ?? this.gold,
      error: error ?? this.error,
      success: success ?? this.success,
      onAccent: onAccent ?? this.onAccent,
      field: field ?? this.field,
      goldWash: goldWash ?? this.goldWash,
    );
  }

  @override
  TasteHubColors lerp(ThemeExtension<TasteHubColors>? other, double t) {
    if (other is! TasteHubColors) return this;
    return TasteHubColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      field: Color.lerp(field, other.field, t)!,
      goldWash: Color.lerp(goldWash, other.goldWash, t)!,
    );
  }
}

extension TasteHubTheme on BuildContext {
  TasteHubColors get tasteHubColors =>
      Theme.of(this).extension<TasteHubColors>()!;
}

ThemeData buildTasteHubTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? TasteHubColors.dark
      : TasteHubColors.light;

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.gold,
        surface: colors.background,
        onSurface: colors.ink,
        error: colors.error,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.background,
    visualDensity: VisualDensity.standard,
    extensions: [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.6,
        height: 1.05,
        color: colors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: colors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: colors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: colors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: colors.ink),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.45, color: colors.muted),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: colors.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: TextStyle(color: colors.muted),
      labelStyle: TextStyle(color: colors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.error),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: colors.line, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    chipTheme: ChipThemeData(
      backgroundColor: colors.card,
      side: BorderSide(color: colors.line),
      labelStyle: TextStyle(color: colors.ink),
    ),
  );
}
