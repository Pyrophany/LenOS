import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PLACEHOLDER for the [USER] class, which will be written elsewhere.
///
/// The Terminal shows [name] as `[USER]@LenOS:~$` and Settings edits it. A
/// replacement must stay a [ChangeNotifier] provided above the app and keep a
/// `name` getter/setter, or those two pages must be updated to match.
class LenOSUser extends ChangeNotifier {
  static const _storageKey = 'lenos.user.name';
  static const defaultName = 'user';

  String _name = defaultName;

  String get name => _name;

  /// Sets and saves the name. Pass a name that passes [validateName];
  /// blank resets to [defaultName].
  set name(String value) {
    final trimmed = value.trim();
    final next = trimmed.isEmpty ? defaultName : trimmed;
    if (next == _name) return;
    _name = next;
    notifyListeners();
    _save();
  }

  /// Returns an error message for an unusable name, else null.
  static String? validateName(String value) {
    final n = value.trim();
    if (n.isEmpty) return 'Name cannot be empty';
    if (n.length > 32) return 'At most 32 characters';
    if (RegExp(r'[\s@:$/~]').hasMatch(n)) {
      return r'No spaces or @ : $ / ~';
    }
    return null;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null && validateName(stored) == null && stored != _name) {
        _name = stored;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Could not load the user name: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, _name);
    } catch (e) {
      debugPrint('Could not save the user name: $e');
    }
  }
}
