import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headspace.dart';

/// Favorite Headspaces (name, Traits and Modifier; comments are not part of
/// a favorite), saved between visits in the order they were added.
class HeadspaceFavorites {
  HeadspaceFavorites._(this._items);

  static const _key = 'lenos.headspace.favorites';

  final List<Headspace> _items;

  List<Headspace> get items => List.unmodifiable(_items);

  static Future<HeadspaceFavorites> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        return HeadspaceFavorites._([
          for (final e in jsonDecode(raw) as List)
            ?_fromJson(e as Map<String, Object?>),
        ]);
      }
    } catch (e) {
      debugPrint('Could not load Headspace favorites: $e');
    }
    return HeadspaceFavorites._([]);
  }

  /// Whether [h] is a favorite (same name, Traits and Modifier).
  bool contains(Headspace h) => _items.any((f) => same(f, h));

  /// Adds [h] if it is not a favorite, otherwise removes it.
  /// Returns whether it is a favorite now.
  Future<bool> toggle(Headspace h) async {
    final before = _items.length;
    _items.removeWhere((f) => same(f, h));
    final added = _items.length == before;
    if (added) {
      _items.add(
        Headspace(
          name: h.name.trim(),
          traits: [for (final t in h.traits) t.trim()],
          modifier: _modifier(h),
        ),
      );
    }
    await _save();
    return added;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([
          for (final h in _items)
            {'name': h.name, 'traits': h.traits, 'modifier': h.modifier},
        ]),
      );
    } catch (e) {
      debugPrint('Could not save Headspace favorites: $e');
    }
  }

  static Headspace? _fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final traits = json['traits'];
    if (name is! String || traits is! List) return null;
    final list = traits.whereType<String>().toList();
    if (list.length != Headspace.traitCount) return null;
    final modifier = json['modifier'];
    return Headspace(
      name: name,
      traits: list,
      modifier: modifier is String ? modifier : '',
    );
  }

  static bool same(Headspace a, Headspace b) =>
      a.name.trim() == b.name.trim() &&
      listEquals(
        [for (final t in a.traits) t.trim()],
        [for (final t in b.traits) t.trim()],
      ) &&
      _modifier(a) == _modifier(b);

  /// The Modifier, with `none` written out counted as no Modifier.
  static String _modifier(Headspace h) {
    final m = h.modifier.trim();
    return m == Headspace.noModifier ? '' : m;
  }
}
