import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_style.dart';

/// An accent color choice, with a shade for each mode so it stays readable.
enum AccentColor {
  green('Green', Color(0xFF5FD75F), Color(0xFF1E7A34)),
  teal('Teal', Color(0xFF4DD0C4), Color(0xFF00796B)),
  blue('Blue', Color(0xFF64B5F6), Color(0xFF1565C0)),
  purple('Purple', Color(0xFFB39DDB), Color(0xFF6A1B9A)),
  pink('Pink', Color(0xFFF48FB1), Color(0xFFAD1457)),
  orange('Orange', Color(0xFFFFB74D), Color(0xFFBF4A00)),
  yellow('Yellow', Color(0xFFFFE066), Color(0xFF7A6200));

  const AccentColor(this.label, this.onDark, this.onLight);

  final String label;

  /// Shade used in dark mode.
  final Color onDark;

  /// Shade used in light mode (darker, for contrast on light backgrounds).
  final Color onLight;

  Color forBrightness(Brightness b) => b == Brightness.dark ? onDark : onLight;
}

/// App-wide light/dark mode and accent color, saved between launches.
class ThemeModel extends ChangeNotifier {
  static const _storageKey = 'lenos.theme.dark';
  static const _accentKey = 'lenos.theme.accent';
  static const _customKey = 'lenos.theme.accent.custom';
  static const _topBarKey = 'lenos.theme.topbar';
  static const _customTopBarKey = 'lenos.theme.topbar.custom';

  /// Saved value of [_accentKey] meaning the custom color is in use.
  static const _customName = 'custom';

  /// Dark is the default look; a saved choice overrides it.
  bool _dark = true;

  bool get dark => _dark;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;

  set dark(bool value) {
    if (value == _dark) return;
    _dark = value;
    notifyListeners();
    _save();
  }

  AccentColor _accent = AccentColor.green;

  /// The chosen preset (still remembered while a custom color is in use).
  AccentColor get accent => _accent;

  /// Chooses a preset accent.
  set accent(AccentColor value) {
    if (value == _accent && !_useCustom) return;
    _accent = value;
    _useCustom = false;
    notifyListeners();
    _save();
  }

  Color? _customAccent;
  bool _useCustom = false;

  /// The last custom color, kept even after switching back to a preset.
  Color? get customAccent => _customAccent;
  bool get usingCustom => _useCustom && _customAccent != null;

  /// Uses [color] as the accent in both modes.
  void useCustomAccent(Color color) {
    _customAccent = color.withAlpha(0xFF);
    _useCustom = true;
    notifyListeners();
    _save();
  }

  /// The accent in effect for [brightness].
  Color accentFor(Brightness brightness) =>
      usingCustom ? _customAccent! : _accent.forBrightness(brightness);

  /// Default background of every top bar (the Home page's teal).
  static const appBarColor = Color.fromARGB(255, 7, 82, 69);

  /// Top bar colors offered in Settings (besides Custom).
  static const topBarPresets = <({String label, Color color})>[
    (label: 'Teal', color: appBarColor),
    (label: 'Charcoal', color: Color(0xFF262626)),
    (label: 'Slate', color: Color(0xFF37474F)),
    (label: 'Navy', color: Color(0xFF1A2A6C)),
    (label: 'Plum', color: Color(0xFF4A1F5C)),
    (label: 'Forest', color: Color(0xFF1F4D2B)),
    (label: 'Maroon', color: Color(0xFF6B1D1D)),
  ];

  Color _topBar = appBarColor;
  Color? _customTopBar;

  /// The color of every top bar.
  Color get topBarColor => _topBar;

  /// The last custom top bar color, kept after switching to a preset.
  Color? get customTopBar => _customTopBar;

  /// Whether [topBarColor] is a custom color rather than a preset.
  bool get topBarIsCustom => !topBarPresets.any((p) => p.color == _topBar);

  /// Uses a preset top bar color.
  set topBarColor(Color color) {
    if (color == _topBar) return;
    _topBar = color;
    notifyListeners();
    _save();
  }

  /// Uses (and remembers) a custom top bar color.
  void useCustomTopBar(Color color) {
    _customTopBar = color.withAlpha(0xFF);
    _topBar = _customTopBar!;
    notifyListeners();
    _save();
  }

  /// Both modes use the LenOS (Headspace Manager) style; see [TerminalStyle].
  static ThemeData light([Color? accent, Color topBar = appBarColor]) => TerminalStyle.light
      .withAccent(accent ?? AccentColor.green.onLight)
      .theme(appBarColor: topBar);

  static ThemeData darkTheme([Color? accent, Color topBar = appBarColor]) => TerminalStyle.dark
      .withAccent(accent ?? AccentColor.green.onDark)
      .theme(appBarColor: topBar);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_storageKey);
      final accentName = prefs.getString(_accentKey);
      final accent = AccentColor.values.asNameMap()[accentName];
      final custom = prefs.getInt(_customKey);
      _dark = stored ?? _dark;
      _accent = accent ?? _accent;
      if (custom != null) _customAccent = Color(custom);
      final topBar = prefs.getInt(_topBarKey);
      if (topBar != null) _topBar = Color(topBar);
      final customTopBar = prefs.getInt(_customTopBarKey);
      if (customTopBar != null) _customTopBar = Color(customTopBar);
      _useCustom = accentName == _customName && _customAccent != null;
      notifyListeners();
    } catch (e) {
      debugPrint('Could not load the theme: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, _dark);
      await prefs.setString(_accentKey, usingCustom ? _customName : _accent.name);
      if (_customAccent != null) await prefs.setInt(_customKey, _customAccent!.toARGB32());
      await prefs.setInt(_topBarKey, _topBar.toARGB32());
      if (_customTopBar != null) {
        await prefs.setInt(_customTopBarKey, _customTopBar!.toARGB32());
      }
    } catch (e) {
      debugPrint('Could not save the theme: $e');
    }
  }
}
