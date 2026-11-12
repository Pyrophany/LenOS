import 'dart:async';

import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';

import 'fs/record_codec.dart';
import 'nfc_model.dart';

/// The Terminal's `fractionate` command, run on a device held against the
/// phone: sends [trance] (a `trance.trm`), and after each wait while the same
/// device is still in range, deletes it and sends it again, alternating until
/// the device leaves range (or [stopped] returns true). Each wait is
/// [intervalFor] the number of sends so far: [fixedTranceInterval] (2 s), or
/// [tranceInterval] to speed up as it goes (the dynamic intervals setting).
///
/// Every write is a full checked write, and each one starts only after the
/// device was just read, so a device taken away between steps is not written.
/// The phone vibrates (via [vibrate]) after each send and each delete,
/// without waiting for it, so the timing does not depend on the vibration.
/// Returns the number of times [trance] was sent.
Future<int> fractionate(
  HeldTag tag,
  NdefRecord trance, {
  Duration Function(int sent) intervalFor = fixedTranceInterval,
  bool Function()? stopped,
  void Function(String message)? log,
  Future<void> Function() vibrate = HapticFeedback.vibrate,
}) async {
  var sent = 0;
  Future<void> send() async {
    await tag.write((files) => [...files, trance], keepTerminalInputs: true);
    sent++;
    unawaited(vibrate());
    log?.call('Sent trance.trm ($sent).');
  }

  /// Waits, then whether to go on: not stopped and still in range.
  Future<bool> next() async {
    await Future<void>.delayed(intervalFor(sent));
    if (stopped?.call() ?? false) {
      log?.call('^C  Fractionation stopped.');
      return false;
    }
    if (await tag.isPresent()) return true;
    log?.call('Device left range.');
    return false;
  }

  await send();
  while (await next()) {
    await tag.write((files) => withoutLast(files, trance),
        keepTerminalInputs: true);
    unawaited(vibrate());
    log?.call('Deleted trance.trm.');
    if (!await next()) break;
    await send();
  }
  return sent;
}

/// The wait between fractionate steps without dynamic intervals.
Duration fixedTranceInterval(int sent) => const Duration(seconds: 2);

/// The dynamic wait between fractionate steps once trance was sent [sent] times:
/// 2 s, 1.5 s from the 6th send, 1 s from the 10th.
Duration tranceInterval(int sent) => sent >= 10
    ? const Duration(seconds: 1)
    : sent >= 6
        ? const Duration(milliseconds: 1500)
        : const Duration(seconds: 2);

/// [files] without the last file equal to [record]. Throws
/// [NfcWriteException] if there is none, so nothing else is written.
List<NdefRecord> withoutLast(List<NdefRecord> files, NdefRecord record) {
  for (var i = files.length - 1; i >= 0; i--) {
    if (RecordCodec.sameRecord(files[i], record)) {
      return [...files.sublist(0, i), ...files.sublist(i + 1)];
    }
  }
  throw NfcWriteException(
      'trance.trm is no longer on the device, so nothing was deleted.');
}
