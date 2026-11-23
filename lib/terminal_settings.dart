import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Terminal options from Settings, saved on the phone.
class TerminalSettings extends ChangeNotifier {
  static const _dynamicIntervalsKey = 'lenos.terminal.dynamicIntervals';

  bool _dynamicIntervals = false;

  /// Whether `fractionate` speeds up as it goes (see `tranceInterval`)
  /// instead of always waiting 2 s.
  bool get dynamicIntervals => _dynamicIntervals;

  set dynamicIntervals(bool value) {
    if (value == _dynamicIntervals) return;
    _dynamicIntervals = value;
    notifyListeners();
    _save();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_dynamicIntervalsKey);
      if (stored != null && stored != _dynamicIntervals) {
        _dynamicIntervals = stored;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Could not load the Terminal settings: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dynamicIntervalsKey, _dynamicIntervals);
    } catch (e) {
      debugPrint('Could not save the Terminal settings: $e');
    }
  }
}
