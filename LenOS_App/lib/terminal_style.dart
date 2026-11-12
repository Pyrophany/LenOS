import 'package:flutter/material.dart';

/// The LenOS look (first made for the Terminal and Headspace Manager):
/// monospace text, outlined boxes and green accents, in a dark and a light
/// palette. The whole app theme is built from it (see [ThemeModel]); pages
/// that draw their own colors get the current palette with [of].
final class TerminalStyle {
  const TerminalStyle._({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.raised,
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.dim,
    required this.faint,
    required this.error,
    required this.warning,
  });

  static const dark = TerminalStyle._(
    brightness: Brightness.dark,
    background: Color(0xFF101010),
    surface: Color(0xFF1C1C1C),
    raised: Color(0xFF2A2A2A),
    accent: Color(0xFF5FD75F),
    onAccent: Colors.black,
    text: Colors.white,
    dim: Colors.white60,
    faint: Colors.white24,
    error: Color(0xFFFF6B6B),
    warning: Color(0xFFFFC857),
  );

  static const light = TerminalStyle._(
    brightness: Brightness.light,
    background: Color(0xFFF2F4F1),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFE4E8E2),
    // Darker green so it stays readable on light backgrounds.
    accent: Color(0xFF1E7A34),
    onAccent: Colors.white,
    text: Color(0xFF111111),
    dim: Color(0xFF555555),
    faint: Color(0xFFB5BBB2),
    error: Color(0xFFC62828),
    warning: Color(0xFF8A5A00),
  );

  /// The palette for the current theme: its brightness and accent color.
  static TerminalStyle of(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.brightness == Brightness.dark ? dark : light;
    return base.withAccent(theme.colorScheme.primary);
  }

  /// This palette with [color] as the accent (text on it is black or white,
  /// whichever reads better).
  TerminalStyle withAccent(Color color) => color == accent
      ? this
      : TerminalStyle._(
          brightness: brightness,
          background: background,
          surface: surface,
          raised: raised,
          accent: color,
          onAccent: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
          text: text,
          dim: dim,
          faint: faint,
          error: error,
          warning: warning,
        );

  final Brightness brightness;

  /// Page background.
  final Color background;

  /// Boxes and cards on [background].
  final Color surface;

  /// Raised parts: menus, bars, highlighted rows.
  final Color raised;

  /// Green for keywords, custom values, focus and primary buttons.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;
  final Color text;

  /// Secondary text.
  final Color dim;

  /// Borders, placeholders and disabled things.
  final Color faint;
  final Color error;
  final Color warning;

  static const fontFamily = 'monospace';
  static const font = TextStyle(fontFamily: fontFamily, fontSize: 14, height: 1.4);

  /// An underline in [faint] that turns [accent] when focused.
  InputDecoration underline({String? hintText, Widget? suffixIcon}) => InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: font.copyWith(color: faint),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: faint)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
        suffixIcon: suffixIcon,
      );

  /// The app theme in this palette.
  ThemeData theme({required Color appBarColor}) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: error,
      onError: brightness == Brightness.dark ? Colors.black : Colors.white,
      errorContainer: error.withValues(alpha: 0.18),
      onErrorContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: dim,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: raised,
      outline: faint,
      outlineVariant: faint,
    );
    final base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      useMaterial3: true,
    );
    // White titles and icons on dark top bars, black on light ones.
    final onBar = ThemeData.estimateBrightnessForColor(appBarColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final box = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: faint),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: faint,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarColor,
        foregroundColor: onBar,
        titleTextStyle: base.textTheme.titleLarge
            ?.copyWith(color: onBar, fontFamily: fontFamily),
      ),
      cardTheme: CardThemeData(color: surface, elevation: 0, shape: box),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: box),
      popupMenuTheme: PopupMenuThemeData(color: raised, shape: box),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: font.copyWith(color: text),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: box,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: dim,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: faint),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: faint)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.3),
        selectionHandleColor: accent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: onAccent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: faint,
      ),
      listTileTheme: ListTileThemeData(iconColor: accent),
    );
  }
}
