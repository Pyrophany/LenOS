import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fs/record_codec.dart';
import 'headspace.dart';

/// What a [HistoryEntry] is about; sets its icon in Settings → History.
enum HistoryKind {
  /// The [USER] name changed.
  user,

  /// Files were read from an NFC device.
  read,

  /// Files were written to an NFC device.
  write,

  /// A Headspace was written.
  headspace,

  /// A file in the File Manager was created, saved, renamed or deleted.
  file,

  /// A Terminal command was written (`fractionate` is one entry).
  terminal,

  /// Lena Kitty was bonked by the yarn.
  bonk,
}

/// One line of the History: what happened ([title]) and when, with any
/// [details] (one per line) shown below it.
class HistoryEntry {
  HistoryEntry({
    required this.kind,
    required this.title,
    this.details = const [],
    DateTime? time,
    this.from,
    this.newDevice = false,
  }) : time = time ?? DateTime.now();

  final HistoryKind kind;
  final String title;
  final List<String> details;
  final DateTime time;

  /// For [HistoryKind.user]: the name before the change, so typing a name
  /// one letter at a time is kept as one change.
  final String? from;

  /// For [HistoryKind.read]: the first time this device was ever scanned.
  final bool newDevice;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'title': title,
    'details': details,
    'time': time.toIso8601String(),
    if (from != null) 'from': from,
    if (newDevice) 'newDevice': true,
  };

  static HistoryEntry? fromJson(Object? json) {
    try {
      final m = json as Map<String, Object?>;
      return HistoryEntry(
        kind: HistoryKind.values.byName(m['kind'] as String),
        title: m['title'] as String,
        details: [for (final d in m['details'] as List? ?? const []) '$d'],
        time: DateTime.parse(m['time'] as String),
        from: m['from'] as String?,
        newDevice: m['newDevice'] == true,
      );
    } catch (_) {
      return null; // A kind from a newer version, or damaged data: skip it.
    }
  }
}

/// The app's History: [USER] changes, NFC reads and writes, File Manager
/// changes, Terminal commands and Lena Kitty bonks, newest first. Saved
/// between launches, keeping the newest [maxEntries].
class HistoryLog extends ChangeNotifier {
  HistoryLog({this.persist = true, Random? random})
    : _random = random ?? Random();

  final Random _random;

  /// What a bonk entry says, picked at random each time.
  static const bonkResponses = [
    'mean :(',
    'rude.',
    'mean and cruel to lenas everywhere',
    'really?',
    'stop it :(',
    'fucked up.',
  ];

  static const _storageKey = 'lenos.history';
  static const maxEntries = 500;

  /// Name changes this close together are one change (the name is applied
  /// as it is typed).
  static const userMergeWindow = Duration(seconds: 10);

  /// False in tests that should not touch storage.
  final bool persist;

  final List<HistoryEntry> _entries = []; // Newest first.

  /// Saving waits for [load], so entries added before it finishes don't
  /// replace the saved History.
  bool _loaded = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// The app's History, or null where none is provided (e.g. in tests).
  static HistoryLog? maybeOf(BuildContext context) {
    try {
      return context.read<HistoryLog>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void add(HistoryEntry entry) {
    _entries.insert(0, entry);
    _trim();
    _changed();
  }

  /// The [USER] name changed from [from] to [to].
  void userChanged(String from, String to) {
    if (from == to) return;
    final last = _entries.firstOrNull;
    if (last != null &&
        last.kind == HistoryKind.user &&
        last.from != null &&
        DateTime.now().difference(last.time) < userMergeWindow) {
      _entries.removeAt(0);
      from = last.from!;
      if (from == to) return _changed(); // Typed back to where it was.
    }
    add(
      HistoryEntry(
        kind: HistoryKind.user,
        title: 'USER changed',
        details: ['$from → $to'],
        from: from,
      ),
    );
  }

  void bonk() => add(
    HistoryEntry(
      kind: HistoryKind.bonk,
      title: 'Lena Kitty bonked',
      details: [bonkResponses[_random.nextInt(bonkResponses.length)]],
    ),
  );

  void clear() {
    _entries.clear();
    _changed();
  }

  /// How a file is shown: a Headspace file with its Headspace and Traits,
  /// anything else by [name] only.
  static String describeFile(String name, NdefRecord record) {
    final headspace = headspaceOf(record);
    if (headspace == null) return name;
    return '$name · ${describeHeadspace(headspace, withModifier: true)}';
  }

  static Headspace? headspaceOf(NdefRecord record) {
    final text = RecordCodec.decodeText(record);
    return text == null ? null : Headspace.parse(text);
  }

  /// The Headspace and Traits; with [withModifier] (for writes), also the
  /// Modifier if it has one.
  static String describeHeadspace(Headspace h, {bool withModifier = false}) => [
    'Headspace: ${h.name}',
    'Traits: ${h.traits.join(', ')}',
    if (withModifier && h.modifier.trim().isNotEmpty)
      'Modifier: ${h.modifier.trim()}',
  ].join(' · ');

  void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  Future<void> load() async {
    if (!persist) return;
    var addedWhileLoading = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      final loaded = stored == null
          ? const <HistoryEntry>[]
          : [
              for (final e in jsonDecode(stored) as List)
                ?HistoryEntry.fromJson(e),
            ];
      // Anything logged while loading is newer than what was saved.
      addedWhileLoading = _entries.isNotEmpty;
      _entries.addAll(loaded);
      _trim();
      notifyListeners();
    } catch (e) {
      debugPrint('Could not load the history: $e');
    }
    _loaded = true;
    if (addedWhileLoading) _save();
  }

  Future<void> _save() async {
    if (!persist || !_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode([for (final e in _entries) e.toJson()]),
      );
    } catch (e) {
      debugPrint('Could not save the history: $e');
    }
  }
}
