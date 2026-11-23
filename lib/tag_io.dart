import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import 'device_registry.dart';
import 'fs/record_codec.dart';
import 'nfc_model.dart';

/// Reads and writes the files on NFC tags for the app's NFC session, with
/// the checks that keep files from being lost to bad reads or broken writes.
///
/// Terminal inputs (`.trm` files) are cleared from a device every time it is
/// read: by a scan, and by the read before every write, the Terminal's own
/// included (which then adds only its new input). The phone gives a medium
/// [haptic] tap after each successful read or write.
class TagIo {
  TagIo(
    this.nfc,
    this.devices, {
    this.haptic = HapticFeedback.mediumImpact,
    this.onTerminalInputsCleared,
  });

  final NfcModel nfc;
  final DeviceRegistry devices;
  final Future<void> Function() haptic;

  /// Called with the device's label and how many Terminal inputs were
  /// cleared from it, after a read or write that cleared any. Not called
  /// for `fractionate`'s held writes, which delete `trance.trm` every step
  /// and log it in the Terminal.
  final void Function(String device, int count)? onTerminalInputsCleared;

  /// Reads [uid]'s files and saves them to [devices], then clears any
  /// Terminal inputs from the device. A failed read keeps the saved copy,
  /// since it says nothing about what is on the device.
  /// Returns false if the files could not be read.
  Future<bool> read(String uid, Ndef ndef) async {
    final files = await readFiles(ndef);
    if (files == null) {
      debugPrint('Could not read $uid; keeping its saved files.');
      return false;
    }
    nfc.setMessage(uid, RecordCodec.messageOf(files));
    devices.recordContents(uid, files, ndef.maxSize);
    debugPrint('Tag $uid: ${files.length} file(s).');
    if (files.any(RecordCodec.isTerminalInput)) {
      try {
        // A checked write like any other: a damaged device is refused, and
        // one cut short keeps the files from before it for recovery.
        await _write(uid, ndef, build: (existing) => existing);
      } on NfcWriteException catch (e) {
        debugPrint('Could not clear Terminal inputs from $uid: $e');
      }
    }
    _tap();
    return true;
  }

  void _tap() => unawaited(haptic().catchError((Object e) {
        debugPrint('Haptic feedback failed: $e');
      }));

  /// Reads the files on a tag, or returns null if they could not be read.
  ///
  /// Reads that come back empty are retried once, and a read that finds fewer
  /// files than the tag reported when it was detected is not trusted, since
  /// both happen when a tag moves out of range mid-read.
  /// With [useCached] false the copy from detection is never used.
  Future<List<NdefRecord>?> readFiles(Ndef ndef, {bool useCached = true}) async {
    final cached = useCached
        ? RecordCodec.filesOf(ndef.cachedMessage?.records ?? const [])
        : const <NdefRecord>[];
    Future<List<NdefRecord>?> readOnce() async {
      try {
        final message = await ndef.read();
        return message == null ? null : RecordCodec.filesOf(message.records);
      } catch (e) {
        debugPrint('NDEF read failed: $e');
        return null;
      }
    }

    var files = await readOnce();
    if (files == null || files.isEmpty) files = await readOnce() ?? files;
    if (files == null) {
      // Nothing could be read now; the message from detection is still valid.
      return !useCached || ndef.cachedMessage == null ? null : cached;
    }
    if (files.length < cached.length) return cached;
    return files;
  }

  /// Reads the tag's files and writes the files the request builds from them,
  /// then reads the tag again to check the write.
  Future<void> write(String uid, Ndef? ndef, NfcWriteRequest request) async {
    try {
      await _write(uid, ndef,
          build: request.build,
          wanted: request.uid,
          force: request.force,
          addsTerminalInputs: request.addsTerminalInputs);
      _tap();
      request.complete(uid);
    } catch (e) {
      request.fail(e);
    }
  }

  /// Keeps hold of the tag while [request] runs, so it can write to the same
  /// device several times while it stays in range.
  Future<void> hold(String uid, Ndef? ndef, NfcHoldRequest request) async {
    try {
      if (ndef == null) {
        final label = devices.byUid(uid)?.label ?? uid;
        throw NfcWriteException('$label does not support NDEF.');
      }
      await request.run(_HeldNdefTag(this, uid, ndef));
      request.complete(uid);
    } catch (e) {
      request.fail(e);
    }
  }

  /// One checked write; throws [NfcWriteException] if it did not succeed.
  Future<void> _write(
    String uid,
    Ndef? ndef, {
    required List<NdefRecord> Function(List<NdefRecord> existing) build,
    String? wanted,
    bool force = false,
    bool addsTerminalInputs = false,
    bool notify = true,
  }) async {
    final label = devices.byUid(uid)?.label ?? uid;
    var writeStarted = false;
    try {
      if (wanted != null && wanted != uid) {
        final name = devices.byUid(wanted)?.label ?? wanted;
        throw NfcWriteException(
            'Wrong device: this is $label, not $name. Nothing was written.');
      }
      if (ndef == null) {
        throw NfcWriteException('$label does not support NDEF.');
      }
      if (!ndef.isWritable) throw NfcWriteException('$label is read-only.');

      // Never write without knowing the current files, or they would be lost.
      final read = await readFiles(ndef);
      final known = devices.byUid(uid)?.records;
      if (!force) {
        if (read == null) {
          throw NfcWriteException(
              'Could not read the files on $label, so nothing was written. '
              'Hold the device still against the phone and try again.');
        }
        // An empty read of a device that had files is far more likely a bad
        // read than a really empty device. Writing would erase those files.
        if (read.isEmpty && (known?.isNotEmpty ?? false)) {
          throw NfcWriteException(
              '$label read as empty, but it had ${known!.length} file(s) when '
              'last scanned. Nothing was written, so they are not overwritten. '
              'Hold the device still and try again. If it really is empty now, '
              'cancel, scan it once on its own, then try again.');
        }
        if (devices.byUid(uid)?.writeInterrupted ?? false) {
          throw NfcWriteException(
              'The last write to $label did not finish. Open it in Devices to '
              'write it again or restore its previous files first.');
        }
      }
      final files = read ?? const <NdefRecord>[];
      // What was read is the device's current content, even if the write is refused.
      if (read != null) devices.recordContents(uid, read, ndef.maxSize);

      // Reading the device clears the Terminal inputs it held, so only the
      // ones this write adds (the Terminal's) can stay. [build] gets copies
      // of the device's files, so those are told apart by identity even
      // when a new input is the same command again.
      final copies = [for (final r in files) RecordCodec.copyOf(r)];
      final onDevice = Set<NdefRecord>.identity()..addAll(copies);
      final built = build(copies);
      final target = addsTerminalInputs
          ? built
              .where((r) =>
                  !onDevice.contains(r) || !RecordCodec.isTerminalInput(r))
              .toList()
          : RecordCodec.withoutTerminalInputs(built);
      final message = RecordCodec.messageOf(target);
      if (message.byteLength > ndef.maxSize) {
        throw NfcWriteException(
            'Not enough storage on $label: needs ${message.byteLength} bytes, '
            'the device holds ${ndef.maxSize}.');
      }

      devices.beginWrite(uid, target, before: files);
      writeStarted = true;
      await ndef.write(message: message);

      // Check that the device now holds exactly what was written. The copy
      // from detection is from before the write, so it must not stand in.
      final check = await readFiles(ndef, useCached: false);
      if (check == null) {
        throw NfcWriteException(
            'The files were sent to $label, but it could not be read back to '
            'check them. Scan it again to confirm; if its files look wrong, '
            'open it in Devices to write again or restore its previous files.');
      }
      devices.recordContents(uid, check, ndef.maxSize);
      if (!RecordCodec.sameRecords(check, target)) {
        throw NfcWriteException(
            'The write to $label did not finish correctly. Open it in Devices '
            'to write again or restore its previous files.');
      }
      nfc.setMessage(uid, message);
      final cleared = files.where(RecordCodec.isTerminalInput).length;
      if (notify && cleared > 0) onTerminalInputsCleared?.call(label, cleared);
    } on NfcWriteException {
      rethrow;
    } catch (e) {
      debugPrint('Failed to write to $uid: $e');
      throw NfcWriteException(writeStarted
          ? 'Lost connection to $label while writing, so its files may be '
              'damaged. Your previous files are kept in the app: open $label '
              'in Devices to write again or restore them.'
          : 'Lost connection to $label before writing; nothing was changed. '
              'Hold the device still and try again.');
    }
  }
}

class _HeldNdefTag implements HeldTag {
  _HeldNdefTag(this._io, this.uid, this._ndef);

  final TagIo _io;
  final Ndef _ndef;

  @override
  final String uid;

  @override
  Future<bool> isPresent() async =>
      await _io.readFiles(_ndef, useCached: false) != null;

  @override
  Future<void> write(
    List<NdefRecord> Function(List<NdefRecord> existing) build, {
    bool addsTerminalInputs = false,
  }) =>
      _io._write(uid, _ndef,
          build: build,
          addsTerminalInputs: addsTerminalInputs,
          notify: false);
}
