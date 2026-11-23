import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fs/record_codec.dart';

/// An NFC device (tag) that has been scanned at least once, identified by UID.
class NfcDevice {
  NfcDevice({
    required this.uid,
    required this.firstSeen,
    required this.lastSeen,
    this.name,
    this.favorite = false,
    this.records,
    this.capacity,
    this.contentsRead,
    this.previousRecords,
    this.previousRead,
    this.pendingRecords,
    this.beforeWrite,
  });

  final String uid;

  /// User-given name, or null if unnamed.
  String? name;

  /// Favorited devices are listed on the Devices page.
  bool favorite;

  final DateTime firstSeen;
  DateTime lastSeen;

  /// The files (records) on the device when it was last read, or null if its
  /// contents have never been read.
  List<NdefRecord>? records;

  /// Maximum NDEF message size in bytes, from the last read.
  int? capacity;

  /// When [records] and [capacity] were read.
  DateTime? contentsRead;

  /// Backup: the device's last non-empty files before they last changed, so
  /// they can be written back if they were lost.
  List<NdefRecord>? previousRecords;

  /// When [previousRecords] were read.
  DateTime? previousRead;

  /// Files a write was putting on the device when it was interrupted, or null.
  /// While set, the device's real content is unknown and may be damaged.
  List<NdefRecord>? pendingRecords;

  /// The device's files just before the interrupted write ([pendingRecords]).
  List<NdefRecord>? beforeWrite;

  bool get writeInterrupted => pendingRecords != null;

  /// The last scan found no files, but the device had files before.
  /// Terminal inputs don't count: they are removed on purpose.
  bool get unexpectedlyEmpty =>
      (records?.isEmpty ?? false) && restorableBackup.isNotEmpty;

  /// The files in [previousRecords] that a restore would write back.
  List<NdefRecord> get restorableBackup =>
      RecordCodec.withoutTerminalInputs(previousRecords ?? const []);

  /// The name if set, otherwise the UID.
  String get label => name ?? uid;

  /// Bytes used by [records], or null if never read.
  int? get usedBytes =>
      records == null ? null : NdefMessage(records: records!).byteLength;

  /// Fraction of storage used (0–1), or null if unknown.
  double? get usage {
    final used = usedBytes;
    final cap = capacity;
    if (used == null || cap == null || cap <= 0) return null;
    return (used / cap).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
        'uid': uid,
        'name': name,
        'favorite': favorite,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        if (records != null)
          'records': [for (final r in records!) RecordCodec.toJson(r)],
        'capacity': capacity,
        'contentsRead': contentsRead?.toIso8601String(),
        if (previousRecords != null)
          'previousRecords': [for (final r in previousRecords!) RecordCodec.toJson(r)],
        'previousRead': previousRead?.toIso8601String(),
        if (pendingRecords != null)
          'pendingRecords': [for (final r in pendingRecords!) RecordCodec.toJson(r)],
        if (beforeWrite != null)
          'beforeWrite': [for (final r in beforeWrite!) RecordCodec.toJson(r)],
      };

  static List<NdefRecord>? _recordsFromJson(Object? json) => (json as List?)
      ?.map((r) => RecordCodec.fromJson((r as Map).cast<String, Object?>()))
      .toList();

  static DateTime? _dateFromJson(Object? json) =>
      json == null ? null : DateTime.parse(json as String);

  factory NfcDevice.fromJson(Map<String, Object?> json) => NfcDevice(
        uid: json['uid'] as String,
        name: json['name'] as String?,
        favorite: json['favorite'] as bool? ?? false,
        firstSeen: DateTime.parse(json['firstSeen'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        records: _recordsFromJson(json['records']),
        capacity: json['capacity'] as int?,
        contentsRead: _dateFromJson(json['contentsRead']),
        previousRecords: _recordsFromJson(json['previousRecords']),
        previousRead: _dateFromJson(json['previousRead']),
        pendingRecords: _recordsFromJson(json['pendingRecords']),
        beforeWrite: _recordsFromJson(json['beforeWrite']),
      );
}

/// How the Devices page orders favorite devices.
enum DeviceOrder {
  custom('Custom (drag to reorder)'),
  name('Name'),
  lastScanned('Last scanned'),
  storageUsed('Storage used');

  const DeviceOrder(this.label);
  final String label;
}

/// Every NFC device ever scanned, with its name, favorite flag and the
/// contents from its last read, saved to shared preferences.
class DeviceRegistry extends ChangeNotifier {
  static const _storageKey = 'lenos.devices.v1';

  final Map<String, NfcDevice> _byUid = {};

  /// UIDs of favorites in the user's custom order.
  final List<String> _favoriteOrder = [];
  DeviceOrder _order = DeviceOrder.custom;

  /// Saving waits for [load], or a scan made at startup would overwrite the
  /// stored list before it was read.
  bool _loaded = false;

  /// Set if stored data could not be read. Nothing is saved while set, so the
  /// stored data is never overwritten by a partial in-memory copy.
  Object? _loadError;
  Object? get loadError => _loadError;

  /// Stored devices that could not be read; written back unchanged on save.
  final List<Object?> _unreadable = [];

  NfcDevice? byUid(String uid) => _byUid[uid];

  /// All devices: named ones first (A–Z), then unnamed ones (most recent first).
  List<NfcDevice> get devices {
    final named = _byUid.values.where((d) => d.name != null).toList()
      ..sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
    final unnamed = _byUid.values.where((d) => d.name == null).toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return [...named, ...unnamed];
  }

  DeviceOrder get order => _order;

  set order(DeviceOrder value) {
    if (value == _order) return;
    _order = value;
    _save();
  }

  /// Favorited devices, sorted by [order].
  List<NfcDevice> get favorites {
    final list = [
      for (final uid in _favoriteOrder)
        if (_byUid[uid] case final d? when d.favorite) d,
    ];
    switch (_order) {
      case DeviceOrder.custom:
        break;
      case DeviceOrder.name:
        list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      case DeviceOrder.lastScanned:
        list.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      case DeviceOrder.storageUsed:
        // Fullest first; devices with unknown storage last.
        list.sort((a, b) => (b.usage ?? -1).compareTo(a.usage ?? -1));
    }
    return list;
  }

  /// Moves a favorite in the custom order (indexes into [favorites] while
  /// [order] is [DeviceOrder.custom]). [newIndex] is the final position.
  void moveFavorite(int oldIndex, int newIndex) {
    final list = favorites;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);
    _favoriteOrder
      ..clear()
      ..addAll(list.map((d) => d.uid));
    _save();
  }

  /// Remembers that [uid] was just scanned.
  void recordScan(String uid, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final device = _byUid[uid];
    if (device == null) {
      _byUid[uid] = NfcDevice(uid: uid, firstSeen: now, lastSeen: now);
    } else {
      device.lastSeen = now;
    }
    _save();
  }

  /// Stores what is on [uid] right now: its files and its capacity in bytes.
  void recordContents(String uid, List<NdefRecord> records, int capacity,
      {DateTime? at}) {
    final now = at ?? DateTime.now();
    final device = _byUid.putIfAbsent(
        uid, () => NfcDevice(uid: uid, firstSeen: now, lastSeen: now));
    final old = device.records;
    final pending = device.pendingRecords;
    final before = device.beforeWrite;
    // An interrupted write is resolved once the device reads back as either
    // the files being written or the files from before.
    if (pending != null &&
        (RecordCodec.sameRecords(records, pending) ||
            (before != null && RecordCodec.sameRecords(records, before)))) {
      device
        ..pendingRecords = null
        ..beforeWrite = null;
    }
    // Keep the old files as a backup whenever they change.
    if (old != null && old.isNotEmpty && !RecordCodec.sameRecords(old, records)) {
      device
        ..previousRecords = old
        ..previousRead = device.contentsRead;
    }
    device
      ..records = List.unmodifiable(records)
      ..capacity = capacity
      ..contentsRead = now
      ..lastSeen = now;
    _save();
  }

  /// Marks that [target] is about to be written to [uid]. Until the device
  /// reads back as [target] (or as its files from before), it is treated as
  /// possibly damaged and the Devices page offers to write again or restore.
  void beginWrite(String uid, List<NdefRecord> target,
      {required List<NdefRecord> before}) {
    final device = _byUid[uid];
    if (device == null) return;
    // Repeating an interrupted write keeps the files from before the first try.
    if (device.pendingRecords == null) device.beforeWrite = List.unmodifiable(before);
    device.pendingRecords = List.unmodifiable(target);
    _save();
  }

  /// Sets the device's name; blank clears it.
  void rename(String uid, String? name) {
    final device = _byUid[uid];
    if (device == null) return;
    final trimmed = name?.trim() ?? '';
    device.name = trimmed.isEmpty ? null : trimmed;
    _save();
  }

  void setFavorite(String uid, bool favorite) {
    final device = _byUid[uid];
    if (device == null || device.favorite == favorite) return;
    device.favorite = favorite;
    _favoriteOrder.remove(uid);
    if (favorite) _favoriteOrder.add(uid); // New favorites go to the end.
    _save();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final json = jsonDecode(raw);
        // The first version stored only the device list.
        final deviceList = json is List ? json : (json as Map)['devices'] as List;
        final stored = <String, NfcDevice>{};
        _unreadable.clear();
        for (final d in deviceList) {
          try {
            final device = NfcDevice.fromJson((d as Map).cast<String, Object?>());
            stored[device.uid] = device;
          } catch (e) {
            // Keep it as-is rather than dropping it on the next save.
            debugPrint('Skipping a saved device that could not be read: $e');
            _unreadable.add(d);
          }
        }
        final storedOrder = json is Map
            ? (json['favoriteOrder'] as List).cast<String>()
            : <String>[];
        if (json is Map && json['order'] is String) {
          _order = DeviceOrder.values.asNameMap()[json['order']] ?? _order;
        }

        // Anything scanned before loading finished is newer than storage.
        for (final scanned in _byUid.values) {
          final s = stored[scanned.uid];
          if (s == null) {
            stored[scanned.uid] = scanned;
            continue;
          }
          if (scanned.lastSeen.isAfter(s.lastSeen)) s.lastSeen = scanned.lastSeen;
          if (scanned.contentsRead != null) {
            s
              ..records = scanned.records
              ..capacity = scanned.capacity
              ..contentsRead = scanned.contentsRead;
          }
        }
        _byUid
          ..clear()
          ..addAll(stored);
        _favoriteOrder
          ..clear()
          ..addAll(storedOrder.where((uid) => stored[uid]?.favorite ?? false));
      }
      // Favorites missing from the order (e.g. from the first version) go last.
      for (final d in _byUid.values) {
        if (d.favorite && !_favoriteOrder.contains(d.uid)) _favoriteOrder.add(d.uid);
      }
      _loadError = null;
    } catch (e) {
      debugPrint('Could not load scanned devices: $e');
      _loadError = e;
    }
    _loaded = true;
    await _save(); // Also stores anything scanned while loading.
  }

  Future<void> _save() async {
    notifyListeners();
    if (!_loaded || _loadError != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'devices': [
            for (final d in _byUid.values) d.toJson(),
            ..._unreadable,
          ],
          'favoriteOrder': _favoriteOrder,
          'order': _order.name,
        }),
      );
    } catch (e) {
      debugPrint('Could not save scanned devices: $e');
    }
  }
}
