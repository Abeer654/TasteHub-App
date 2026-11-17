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

/// Shared spacing scale. Screens should prefer these values over one-off
/// numbers so the revamp stays visually consistent.
abstract final class TasteHubSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Gap between the main sections of a scrolling screen.
  static const double section = 18;
}

/// Shared corner radii. Cards, fields and pills can now match across screens.
abstract final class TasteHubRadii {
  static const double field = 14;
  static const double card = 20;
  static const double hero = 24;
  static const double button = 13;

  static const BorderRadius fieldBorder = BorderRadius.all(
    Radius.circular(field),
  );
  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius heroBorder = BorderRadius.all(
    Radius.circular(hero),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Layout helpers shared by the scrolling screens.
abstract final class TasteHubLayout {
  static const double contentWidth = 920;
  static const double wideContentWidth = 1180;

  /// Comfortable page padding: tighter on phones, roomier on desktop.
  static EdgeInsets pagePadding(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return EdgeInsets.fromLTRB(
      compact ? TasteHubSpacing.lg : TasteHubSpacing.xxl,
      TasteHubSpacing.sm,
      compact ? TasteHubSpacing.lg : TasteHubSpacing.xxl,
      TasteHubSpacing.xxxl,
    );
  }
}

@immutable
class TasteHubColors extends ThemeExtension<TasteHubColors> {
  const TasteHubColors({
    required this.background,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentOnDark,
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

  /// Accent tuned for small text (< 18sp) sitting on a dark surface:
  /// the base accent is too dim against near-black to clear 4.5:1.
  /// In light mode there is no dark surface, so it equals [accent].
  final Color accentOnDark;
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
    accentOnDark: Color(0xFFBB4D2A),
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
    muted: Color(0xFFC4BAAE),
    line: Color(0xFF3B3027),
    accent: Color(0xFFE9875F),
    accentOnDark: Color(0xFFF0A27F),
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
    Color? accentOnDark,
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
      accentOnDark: accentOnDark ?? this.accentOnDark,
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
      accentOnDark: Color.lerp(accentOnDark, other.accentOnDark, t)!,
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
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: colors.ink,
      ),
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
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: colors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: colors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: colors.ink,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: colors.ink,
      ),
      // Body styles keep neutral tracking (spec G-02); only uppercase
      // Label styles may add positive letter-spacing.
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.55,
        letterSpacing: 0,
        color: colors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.55,
        letterSpacing: 0,
        color: colors.ink,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.45,
        letterSpacing: 0,
        color: colors.muted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: colors.ink,
      ),
      labelSmall: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: colors.muted,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(color: colors.muted),
      labelStyle: TextStyle(color: colors.muted),
      prefixIconColor: colors.muted,
      suffixIconColor: colors.muted,
      border: OutlineInputBorder(
        borderRadius: TasteHubRadii.fieldBorder,
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: TasteHubRadii.fieldBorder,
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: TasteHubRadii.fieldBorder,
        borderSide: BorderSide(color: colors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: TasteHubRadii.fieldBorder,
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: TasteHubRadii.fieldBorder,
        borderSide: BorderSide(color: colors.error, width: 1.6),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TasteHubRadii.hero),
      ),
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
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TasteHubRadii.button),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: colors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TasteHubRadii.button),
        ),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accentOnDark,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      elevation: 2,
      extendedTextStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TasteHubRadii.button + 4),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    chipTheme: ChipThemeData(
      backgroundColor: colors.card,
      side: BorderSide(color: colors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(color: colors.ink),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: colors.background,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
