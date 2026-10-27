import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS-style semantic colors (Apple's system palette), in light and dark.
/// Screens read these instead of hard-coding colors, so both modes stay right.
@immutable
class TanimColors extends ThemeExtension<TanimColors> {
  const TanimColors({
    required this.background,
    required this.card,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.fill,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.dangerBackground,
  });

  /// systemGroupedBackground: the page behind grouped sections.
  final Color background;

  /// secondarySystemGroupedBackground: the sections themselves.
  final Color card;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color separator;

  /// tertiarySystemFill: chips, tracks, neutral buttons.
  final Color fill;

  /// Tanim green. Deep green on light (readable as text), lime on dark.
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color dangerBackground;

  static const light = TanimColors(
    background: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x993C3C43),
    tertiaryLabel: Color(0x4D3C3C43),
    separator: Color(0x4A3C3C43),
    fill: Color(0x1F767680),
    accent: Color(0xFF2E7D32),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFD70015),
    dangerBackground: Color(0xFFFFE5E3),
  );

  static const dark = TanimColors(
    background: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    tertiaryLabel: Color(0x4DEBEBF5),
    separator: Color(0xA6545458),
    fill: Color(0x3D767680),
    accent: Color(0xFFB9F27C),
    onAccent: Color(0xFF16210D),
    danger: Color(0xFFFF6961),
    dangerBackground: Color(0xFF3A1513),
  );

  @override
  TanimColors copyWith() => this;

  @override
  TanimColors lerp(TanimColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return TanimColors(
      background: c(background, other.background),
      card: c(card, other.card),
      label: c(label, other.label),
      secondaryLabel: c(secondaryLabel, other.secondaryLabel),
      tertiaryLabel: c(tertiaryLabel, other.tertiaryLabel),
      separator: c(separator, other.separator),
      fill: c(fill, other.fill),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      danger: c(danger, other.danger),
      dangerBackground: c(dangerBackground, other.dangerBackground),
    );
  }
}

extension TanimTheme on BuildContext {
  TanimColors get colors => Theme.of(this).extension<TanimColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? TanimColors.dark : TanimColors.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  // Apple's type ramp: tight large titles, 17 pt body and headline.
  final b = base.textTheme;
  TextStyle style(TextStyle? from, double size, FontWeight weight, double spacing, [double? height]) =>
      from!.copyWith(fontSize: size, fontWeight: weight, letterSpacing: spacing, height: height);
  final text = b
      .copyWith(
        displaySmall: style(b.displaySmall, 34, FontWeight.w700, -0.6, 1.1),
        headlineMedium: style(b.headlineMedium, 28, FontWeight.w700, -0.5, 1.15),
        titleLarge: style(b.titleLarge, 20, FontWeight.w600, -0.3),
        titleMedium: style(b.titleMedium, 17, FontWeight.w600, -0.3),
        bodyLarge: style(b.bodyLarge, 17, FontWeight.w400, -0.2, 1.35),
        bodyMedium: style(b.bodyMedium, 15, FontWeight.w400, -0.1, 1.4),
        bodySmall: style(b.bodySmall, 13, FontWeight.w400, 0, 1.35),
        labelLarge: style(b.labelLarge, 17, FontWeight.w600, -0.3),
        labelSmall: style(b.labelSmall, 13, FontWeight.w400, -0.05),
      )
      .apply(bodyColor: t.label, displayColor: t.label);

  return base.copyWith(
    extensions: [t],
    scaffoldBackgroundColor: t.background,
    textTheme: text,
    colorScheme: base.colorScheme.copyWith(
      primary: t.accent,
      onPrimary: t.onAccent,
      surface: t.background,
      onSurface: t.label,
      error: t.danger,
    ),
    // iOS: slide in from the right, swipe from the edge to go back.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      foregroundColor: t.accent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleMedium,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: t.onAccent,
      elevation: 0,
      highlightElevation: 0,
      shape: const StadiumBorder(),
      extendedTextStyle: text.labelLarge,
    ),
    dividerTheme: DividerThemeData(color: t.separator, thickness: 0.5, space: 0.5),
    splashFactory: NoSplash.splashFactory,
    highlightColor: t.fill,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: t.accent),
    cupertinoOverrideTheme: CupertinoThemeData(primaryColor: t.accent, brightness: brightness),
  );
}
