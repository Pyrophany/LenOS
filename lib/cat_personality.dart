import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ascii_cat.dart';

/// Lena Kitty's personality: the weights of the cat's behavior tree, set in
/// Settings → Lena Kitty and saved between launches.
class CatPersonality extends ChangeNotifier {
  static const _keyPrefix = 'lenos.cat.weight.';
  static const _roamsKey = 'lenos.cat.roams';

  CatWeights _weights = CatWeights.defaults;
  CatWeights get weights => _weights;

  bool _roams = true;

  /// Whether Lena Kitty also appears behind Settings, Headspace Manager,
  /// Devices and the File Manager (not just Home).
  bool get roams => _roams;

  set roams(bool value) {
    if (value == _roams) return;
    _roams = value;
    notifyListeners();
    save();
  }

  /// Changes one weight right away. Call [save] when the change is done
  /// (e.g. when a slider is let go) to store it.
  void set(CatWeight weight, double value) {
    final next = _weights.withValue(weight, value);
    if (next == _weights) return;
    _weights = next;
    notifyListeners();
  }

  void resetToDefaults() {
    _weights = CatWeights.defaults;
    notifyListeners();
    save();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var loaded = CatWeights.defaults;
      for (final w in CatWeight.values) {
        final v = prefs.getDouble('$_keyPrefix${w.name}');
        if (v != null) loaded = loaded.withValue(w, v);
      }
      // Keep anything changed while loading.
      if (_weights == CatWeights.defaults && loaded != _weights) _weights = loaded;
      _roams = prefs.getBool(_roamsKey) ?? _roams;
      notifyListeners();
    } catch (e) {
      debugPrint('Could not load Lena Kitty\'s personality: $e');
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final w in CatWeight.values) {
        await prefs.setDouble('$_keyPrefix${w.name}', _weights[w]);
      }
      await prefs.setBool(_roamsKey, _roams);
    } catch (e) {
      debugPrint('Could not save Lena Kitty\'s personality: $e');
    }
  }
}
