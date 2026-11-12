import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';

/// Why writing to a tag failed. [message] is shown to the user.
class NfcWriteException implements Exception {
  NfcWriteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown to the requester when a pending write is cancelled before a tag is found.
class NfcWriteCancelled implements Exception {
  @override
  String toString() => 'Write cancelled';
}

/// Work waiting for the next tag that is scanned. Completes with the UID of
/// the tag it ran on, or fails with the reason it did not.
abstract class NfcTagJob {
  /// Completes like the future returned when the job was queued.
  Future<String> get done => _completer.future;

  final _completer = Completer<String>();

  bool get isDone => _completer.isCompleted;

  /// Reports success with the UID of the tag the job ran on.
  void complete(String uid) {
    if (!isDone) _completer.complete(uid);
  }

  void fail(Object error) {
    if (!isDone) _completer.completeError(error);
  }
}

/// A write waiting for the next tag that is scanned.
class NfcWriteRequest extends NfcTagJob {
  NfcWriteRequest({
    required this.build,
    this.uid,
    this.force = false,
    this.keepTerminalInputs = false,
  });

  /// Given the files currently on the tag, returns the files it should hold
  /// afterwards. May throw [NfcWriteException] to refuse the write.
  final List<NdefRecord> Function(List<NdefRecord> existing) build;

  /// If set, only the device with this UID may be written.
  final String? uid;

  /// Write even if the device's current files cannot be read or look wrong.
  /// Only for repairing a device the user chose to overwrite.
  final bool force;

  /// Terminal inputs are removed from every write except the Terminal's own,
  /// which keeps them and adds its new one after them.
  final bool keepTerminalInputs;
}

/// A tag that stays connected while a [NfcHoldRequest] runs: every call goes
/// to the same device, as long as it stays in range.
abstract class HeldTag {
  String get uid;

  /// Whether the device can still be read, i.e. is still in range.
  Future<bool> isPresent();

  /// Replaces the device's files with what [build] returns for its current
  /// files, with the same checks as [NfcModel.writeToNextTag]. Throws
  /// [NfcWriteException] if nothing or not everything was written.
  Future<void> write(
    List<NdefRecord> Function(List<NdefRecord> existing) build, {
    bool keepTerminalInputs = false,
  });
}

/// Work that keeps hold of the next tag scanned until [run] finishes, for
/// several writes to one device while it is held against the phone.
class NfcHoldRequest extends NfcTagJob {
  NfcHoldRequest(this.run);

  final Future<void> Function(HeldTag tag) run;
}

/// Holds the NDEF records read from each tag, keyed by the tag's UID, and
/// queues writes for the app-wide NFC reader session to carry out.
class NfcModel extends ChangeNotifier {
  final Map<String, List<NdefRecord>> _recordsByUid = {};
  String? _lastUid;
  bool _readerActive = false;
  NfcWriteRequest? _pendingWrite;
  NfcHoldRequest? _pendingHold;

  /// All scanned tags: UID (uppercase hex, e.g. `04A1B2C3D4E5F6`) -> records.
  Map<String, List<NdefRecord>> get recordsByUid =>
      Map.unmodifiable(_recordsByUid);

  /// UID of the most recently scanned tag.
  String? get lastUid => _lastUid;

  /// Records of the most recently scanned tag.
  List<NdefRecord> get lastRecords =>
      _lastUid == null ? const [] : recordsFor(_lastUid!);

  List<NdefRecord> recordsFor(String uid) =>
      List.unmodifiable(_recordsByUid[uid] ?? const <NdefRecord>[]);

  /// Stores every record of [message] under [uid]. Rescanning a tag replaces
  /// its previous records, so the list always matches the tag's current content.
  void setMessage(String uid, NdefMessage? message) {
    _recordsByUid[uid] = List.of(message?.records ?? const <NdefRecord>[]);
    _lastUid = uid;
    notifyListeners();
  }

  void remove(String uid) {
    _recordsByUid.remove(uid);
    if (_lastUid == uid) _lastUid = null;
    notifyListeners();
  }

  void clear() {
    _recordsByUid.clear();
    _lastUid = null;
    notifyListeners();
  }

  // --- Writing ------------------------------------------------------------

  /// Whether the NFC reader session is running, i.e. tags can be detected.
  bool get readerActive => _readerActive;

  /// Called by the owner of the NFC session when it starts or stops.
  void setReaderActive(bool active) {
    if (_readerActive == active) return;
    _readerActive = active;
    if (!active) {
      final error = NfcWriteException('NFC stopped before a device was found.');
      _pendingWrite?.fail(error);
      _pendingHold?.fail(error);
      _pendingWrite = null;
      _pendingHold = null;
    }
    notifyListeners();
  }

  bool get isWaitingToWrite => _pendingWrite != null || _pendingHold != null;

  /// Appends [records] after the existing records of the next tag scanned.
  /// Completes with the tag's UID, or throws [NfcWriteException] /
  /// [NfcWriteCancelled]. Only one write can be pending at a time.
  ///
  /// With [keepTerminalInputs] (only for the Terminal), Terminal inputs
  /// already on the device stay; otherwise they are removed.
  Future<String> appendToNextTag(List<NdefRecord> records,
      {bool keepTerminalInputs = false}) {
    final added = List<NdefRecord>.unmodifiable(records);
    return writeToNextTag(
      build: (existing) => [...existing, ...added],
      keepTerminalInputs: keepTerminalInputs,
    );
  }

  /// Replaces the files on the next tag scanned with whatever [build] returns
  /// for its current files. With [uid], any other device is refused.
  ///
  /// [force] skips the checks that protect files that could not be read;
  /// use it only to repair a device whose files the user chose to replace.
  Future<String> writeToNextTag({
    required List<NdefRecord> Function(List<NdefRecord> existing) build,
    String? uid,
    bool force = false,
    bool keepTerminalInputs = false,
  }) {
    final busy = _checkCanQueue();
    if (busy != null) return busy;
    final request = NfcWriteRequest(
      build: build,
      uid: uid,
      force: force,
      keepTerminalInputs: keepTerminalInputs,
    );
    _pendingWrite = request;
    notifyListeners();
    return request._completer.future;
  }

  /// Keeps hold of the next tag scanned and runs [run] with it. Completes
  /// with the tag's UID when [run] finishes, or throws what [run] threw (or
  /// [NfcWriteCancelled]). Shares the one pending slot with writes.
  Future<String> holdNextTag(Future<void> Function(HeldTag tag) run) {
    final busy = _checkCanQueue();
    if (busy != null) return busy;
    final request = NfcHoldRequest(run);
    _pendingHold = request;
    notifyListeners();
    return request._completer.future;
  }

  Future<String>? _checkCanQueue() {
    if (!_readerActive) {
      return Future.error(
          NfcWriteException('NFC is unavailable or turned off on this phone.'));
    }
    if (isWaitingToWrite) {
      return Future.error(
          NfcWriteException('Another write is already waiting for a device.'));
    }
    return null;
  }

  /// Hands the pending hold (if any) to the NFC session, which must then
  /// complete or fail it.
  NfcHoldRequest? takePendingHold() {
    final request = _pendingHold;
    if (request != null) {
      _pendingHold = null;
      notifyListeners();
    }
    return request;
  }

  /// Hands the pending write (if any) to the NFC session, which must then
  /// complete or fail it.
  NfcWriteRequest? takePendingWrite() {
    final request = _pendingWrite;
    if (request != null) {
      _pendingWrite = null;
      notifyListeners();
    }
    return request;
  }

  /// Cancels a write or hold that has not reached a tag yet.
  void cancelWrite() {
    final NfcTagJob? request = _pendingWrite ?? _pendingHold;
    if (request == null) return;
    _pendingWrite = null;
    _pendingHold = null;
    request.fail(NfcWriteCancelled());
    notifyListeners();
  }

  static String uidToHex(Uint8List uid) => uid
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
