import 'dart:convert';

import 'package:LenOS/device_registry.dart';
import 'package:LenOS/fs/file_system_model.dart';
import 'package:LenOS/fs/record_codec.dart';
import 'package:LenOS/nfc_model.dart';
import 'package:LenOS/tag_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a fake read behaves.
enum Read { ok, nothing, empty, fails }

/// How a fake write behaves.
enum Write { ok, failsBefore, breaksOff, storesWrong }

/// A tag in memory whose reads and writes can be made to go wrong, like a
/// real tag moving out of range.
class FakeNdef implements Ndef {
  FakeNdef(List<NdefRecord> files, {this.maxSize = 500, bool cached = true})
      : stored = RecordCodec.messageOf(files),
        cachedMessage = cached ? RecordCodec.messageOf(files) : null;

  NdefMessage stored;
  @override
  NdefMessage? cachedMessage;

  /// The tag leaves and comes back: a new detection sees its current content.
  void redetect() => cachedMessage = stored;
  @override
  final int maxSize;
  @override
  bool get isWritable => true;
  @override
  Map<String, dynamic> get additionalData => const {};

  /// Behaviour of upcoming reads, in order; then reads work.
  final reads = <Read>[];
  Write nextWrite = Write.ok;
  int writeCount = 0;

  List<NdefRecord> get files => RecordCodec.filesOf(stored.records);

  @override
  Future<NdefMessage?> read() async {
    switch (reads.isEmpty ? Read.ok : reads.removeAt(0)) {
      case Read.ok:
        return stored;
      case Read.nothing:
        return null;
      case Read.empty:
        return RecordCodec.messageOf(const []);
      case Read.fails:
        throw Exception('Tag was lost');
    }
  }

  @override
  Future<void> write({required NdefMessage message}) async {
    writeCount++;
    switch (nextWrite) {
      case Write.ok:
        stored = message;
      case Write.failsBefore:
        throw Exception('Tag was lost');
      case Write.breaksOff:
        // Only part of the message made it.
        stored = NdefMessage(records: [message.records.first]);
        throw Exception('Tag was lost');
      case Write.storesWrong:
        stored = NdefMessage(records: [message.records.first]);
    }
  }

  @override
  Future<void> writeLock() => throw UnimplementedError();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final a = RecordCodec.fromText('a.txt', 'file A');
  final b = RecordCodec.fromText('b.txt', 'file B');
  final c = RecordCodec.fromText('c.txt', 'file C');

  late NfcModel nfc;
  late DeviceRegistry devices;
  late TagIo io;

  /// Haptic taps so far.
  var taps = 0;

  /// Notices of cleared Terminal inputs: "device: count".
  final notices = <String>[];

  TagIo newIo() {
    taps = 0;
    notices.clear();
    return TagIo(nfc, devices,
        haptic: () async => taps++,
        onTerminalInputsCleared: (device, n) => notices.add('$device: $n'));
  }

  /// A device "T1" that the app last saw holding [a, b].
  Future<FakeNdef> knownTag({bool cached = true}) async {
    nfc = NfcModel()..setReaderActive(true);
    devices = DeviceRegistry();
    await devices.load();
    io = newIo();
    devices.recordContents('T1', [a, b], 500);
    return FakeNdef([a, b], cached: cached);
  }

  /// Runs a write the way the NFC session does and returns its error, if any.
  Future<NfcWriteException?> write(FakeNdef tag, Future<String> Function() start,
      {String uid = 'T1'}) async {
    final result = start().then<NfcWriteException?>((_) => null,
        onError: (Object e) => e as NfcWriteException);
    await io.write(uid, tag, nfc.takePendingWrite()!);
    return result;
  }

  List<String?> texts(List<NdefRecord>? records) =>
      records!.map(RecordCodec.decodeText).toList();

  group('Reading', () {
    test('a read that returns nothing keeps the files seen at detection', () async {
      final tag = await knownTag();
      tag.reads.addAll([Read.nothing, Read.nothing]);
      await io.read('T1', tag);
      expect(texts(devices.byUid('T1')!.records), ['file A', 'file B']);
    });

    test('a failed read keeps the saved files', () async {
      final tag = await knownTag(cached: false);
      tag.reads.addAll([Read.fails, Read.fails]);
      await io.read('T1', tag);
      expect(texts(devices.byUid('T1')!.records), ['file A', 'file B']);
    });

    test('an empty read is retried', () async {
      final tag = await knownTag(cached: false);
      tag.reads.add(Read.empty);
      await io.read('T1', tag);
      expect(texts(devices.byUid('T1')!.records), ['file A', 'file B']);
    });

    test('a really empty device is recorded, with a backup and a warning', () async {
      await knownTag();
      final emptyTag = FakeNdef(const []);
      await io.read('T1', emptyTag);
      final d = devices.byUid('T1')!;
      expect(d.records, isEmpty);
      expect(d.unexpectedlyEmpty, isTrue);
      expect(texts(d.previousRecords), ['file A', 'file B']);
    });
  });

  group('Writing', () {
    test('a verified write updates the saved files', () async {
      final tag = await knownTag();
      final error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error, isNull);
      expect(texts(tag.files), ['file A', 'file B', 'file C']);
      final d = devices.byUid('T1')!;
      expect(texts(d.records), ['file A', 'file B', 'file C']);
      expect(d.writeInterrupted, isFalse);
      expect(texts(d.previousRecords), ['file A', 'file B']); // Undo copy.
    });

    test('appending is refused when the files cannot be read', () async {
      final tag = await knownTag(cached: false);
      tag.reads.addAll([Read.fails, Read.fails]);
      final error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error!.message, contains('Could not read'));
      expect(tag.writeCount, 0);
      expect(texts(tag.files), ['file A', 'file B']);
    });

    test('appending is refused when a device with files reads as empty', () async {
      final tag = await knownTag(cached: false);
      tag.reads.addAll([Read.empty, Read.empty]);
      final error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error!.message, contains('read as empty'));
      expect(tag.writeCount, 0);
      expect(texts(tag.files), ['file A', 'file B']);
      // The saved copy is not replaced by the bad read either.
      expect(texts(devices.byUid('T1')!.records), ['file A', 'file B']);
    });

    test('the wrong device is refused', () async {
      final tag = await knownTag();
      final error = await write(
          tag, () => nfc.writeToNextTag(uid: 'OTHER', build: (_) => [c]));
      expect(error!.message, contains('Wrong device'));
      expect(tag.writeCount, 0);
    });

    test('a write that stores the wrong data is caught by the check', () async {
      final tag = await knownTag();
      tag.nextWrite = Write.storesWrong;
      final error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error!.message, contains('did not finish correctly'));
      final d = devices.byUid('T1')!;
      expect(d.writeInterrupted, isTrue);
      expect(texts(d.beforeWrite), ['file A', 'file B']);
      expect(texts(d.pendingRecords), ['file A', 'file B', 'file C']);
    });

    test('a write that breaks off is flagged, blocks writes, and can be repaired',
        () async {
      final tag = await knownTag();
      tag.nextWrite = Write.breaksOff;
      var error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error!.message, contains('may be damaged'));
      expect(texts(tag.files), ['file A']); // Damaged: only part was written.
      var d = devices.byUid('T1')!;
      expect(d.writeInterrupted, isTrue);

      // Scanning the damaged device keeps the warning and the copies.
      tag.redetect();
      await io.read('T1', tag);
      d = devices.byUid('T1')!;
      expect(d.writeInterrupted, isTrue);
      expect(texts(d.beforeWrite), ['file A', 'file B']);

      // Normal writes are refused until it is repaired.
      tag.nextWrite = Write.ok;
      error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error!.message, contains('did not finish'));
      expect(texts(tag.files), ['file A']);

      // "Restore previous files": a forced write of the files from before.
      final before = d.beforeWrite!;
      error = await write(tag, () => nfc.writeToNextTag(
          uid: 'T1', force: true, build: (_) => before));
      expect(error, isNull);
      expect(texts(tag.files), ['file A', 'file B']);
      d = devices.byUid('T1')!;
      expect(d.writeInterrupted, isFalse);
      expect(texts(d.records), ['file A', 'file B']);
    });

    test('a write that failed before changing anything clears on the next scan',
        () async {
      final tag = await knownTag();
      tag.nextWrite = Write.failsBefore;
      final error = await write(tag, () => nfc.appendToNextTag([c]));
      expect(error, isNotNull);
      expect(devices.byUid('T1')!.writeInterrupted, isTrue);
      tag.redetect();
      await io.read('T1', tag); // Still holds the files from before.
      expect(devices.byUid('T1')!.writeInterrupted, isFalse);
    });

    test('the interrupted state survives a restart', () async {
      final tag = await knownTag();
      tag.nextWrite = Write.breaksOff;
      await write(tag, () => nfc.appendToNextTag([c]));
      await Future<void>.delayed(Duration.zero);
      final reloaded = DeviceRegistry();
      await reloaded.load();
      final d = reloaded.byUid('T1')!;
      expect(d.writeInterrupted, isTrue);
      expect(texts(d.beforeWrite), ['file A', 'file B']);
    });
  });

  group('Saved data', () {
    test('unreadable saved device data is never overwritten', () async {
      SharedPreferences.setMockInitialValues({'lenos.devices.v1': '{not json'});
      final r = DeviceRegistry();
      await r.load();
      expect(r.loadError, isNotNull);
      r.recordScan('T1');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lenos.devices.v1'), '{not json');
    });

    test('one unreadable device is kept as-is when saving', () async {
      final bad = {'uid': 'BAD', 'firstSeen': 'not a date'};
      SharedPreferences.setMockInitialValues({
        'lenos.devices.v1': jsonEncode({
          'devices': [bad],
          'favoriteOrder': [],
          'order': 'custom',
        }),
      });
      final r = DeviceRegistry();
      await r.load();
      expect(r.loadError, isNull);
      r.recordScan('T1');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('lenos.devices.v1')!) as Map;
      expect(saved['devices'], anyElement(equals(bad)));
      expect((saved['devices'] as List).length, 2);
    });

    test('unreadable saved files are never overwritten', () async {
      SharedPreferences.setMockInitialValues({'lenos.fs.v1': '{not json'});
      final fs = FileSystemModel();
      await fs.load();
      expect(fs.loadError, isNotNull);
      fs.createFile('/x.txt', RecordCodec.fromText('x.txt', 'x'));
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lenos.fs.v1'), '{not json');
    });
  });

  group('Terminal inputs', () {
    final cmd1 = RecordCodec.terminalRecord(r'lena@LenOS:~$ one');
    final cmd2 = RecordCodec.terminalRecord(r'lena@LenOS:~$ two');
    // Terminal syntax saved as an ordinary text file.
    final cmdAsText = RecordCodec.fromText('c.txt', r'lena@LenOS:~$ three');
    final notes = RecordCodec.fromText('n.txt', 'lena@LenOS:~\$ one\nmore notes');

    Future<FakeNdef> tagWith(List<NdefRecord> files) async {
      nfc = NfcModel()..setReaderActive(true);
      devices = DeviceRegistry();
      await devices.load();
      io = newIo();
      return FakeNdef(files);
    }

    test('recognises Terminal syntax only on a single line', () {
      expect(RecordCodec.isTerminalInput(cmd1), isTrue);
      expect(RecordCodec.isTerminalInput(cmdAsText), isTrue);
      expect(RecordCodec.isTerminalInput(notes), isFalse);
      expect(RecordCodec.isTerminalInput(a), isFalse);
    });

    test('a scan clears them from the device', () async {
      final tag = await tagWith([a, cmd1, notes, cmdAsText]);
      await io.read('T1', tag);
      expect(tag.writeCount, 1);
      expect(texts(tag.files), texts([a, notes]));
      final d = devices.byUid('T1')!;
      expect(texts(d.records), texts([a, notes]));
      expect(d.writeInterrupted, isFalse);
    });

    test('a scan of a device without them writes nothing', () async {
      final tag = await tagWith([a, b]);
      await io.read('T1', tag);
      expect(tag.writeCount, 0);
    });

    test('a scan that cannot clear them still counts as a read', () async {
      final tag = await tagWith([a, cmd1]);
      tag.nextWrite = Write.failsBefore;
      expect(await io.read('T1', tag), isTrue);
      expect(texts(tag.files), texts([a, cmd1]));
    });

    test('the Terminal clears earlier inputs and adds only its own', () async {
      final tag = await tagWith([a, cmd1, cmdAsText]);
      devices.recordContents('T1', [a, cmd1, cmdAsText], 500);
      final error = await write(tag, () => nfc.appendToNextTag([cmd2],
          addsTerminalInputs: true));
      expect(error, isNull);
      expect(texts(tag.files), ['file A', r'lena@LenOS:~$ two']);
    });

    test('the Terminal sending the same command again leaves one copy',
        () async {
      final tag = await tagWith([a, cmd1]);
      devices.recordContents('T1', [a, cmd1], 500);
      final error = await write(tag, () => nfc.appendToNextTag([cmd1],
          addsTerminalInputs: true));
      expect(error, isNull);
      expect(texts(tag.files), ['file A', r'lena@LenOS:~$ one']);
    });

    test('other writes remove them', () async {
      final tag = await tagWith([a, cmd1]);
      devices.recordContents('T1', [a, cmd1], 500);
      final error = await write(tag, () => nfc.appendToNextTag([b]));
      expect(error, isNull);
      expect(texts(tag.files), ['file A', 'file B']);
      expect(devices.byUid('T1')!.writeInterrupted, isFalse);
    });

    test('a command just sent is cleared by the next scan', () async {
      final tag = await tagWith([a]);
      devices.recordContents('T1', [a], 500);
      await write(tag, () => nfc.appendToNextTag([cmd1], addsTerminalInputs: true));
      tag.redetect();
      await io.read('T1', tag);
      expect(texts(tag.files), ['file A']);
    });

    test('a damaged device is not touched', () async {
      // A write of [a] broke off, leaving only part of the old files.
      final tag = await tagWith([cmd1]);
      devices.recordContents('T1', [a, cmd1], 500);
      devices.beginWrite('T1', [a], before: [a, cmd1]);
      tag.redetect();
      await io.read('T1', tag);
      expect(tag.writeCount, 0);
    });
  });

  group('Haptics', () {
    test('a haptic tap for each read and each write, none for failures',
        () async {
      var tag = await knownTag();
      await io.read('T1', tag);
      expect(taps, 1);
      await write(tag, () => nfc.appendToNextTag([c]));
      expect(taps, 2);

      tag = await knownTag(cached: false);
      tag.reads.addAll([Read.fails, Read.fails, Read.fails, Read.fails]);
      await io.read('T1', tag);
      await write(tag, () => nfc.appendToNextTag([c]));
      expect(taps, 0);
    });

    test('a scan that clears Terminal inputs taps once', () async {
      nfc = NfcModel()..setReaderActive(true);
      devices = DeviceRegistry();
      await devices.load();
      io = newIo();
      final tag = FakeNdef([a, RecordCodec.terminalRecord(r'lena@LenOS:~$ x')]);
      await io.read('T1', tag);
      expect(tag.writeCount, 1);
      expect(taps, 1);
    });
  });

  group('Cleared notice', () {
    final cmd1 = RecordCodec.terminalRecord(r'lena@LenOS:~$ one');
    final cmd2 = RecordCodec.terminalRecord(r'lena@LenOS:~$ two');

    Future<FakeNdef> tagWith(List<NdefRecord> files) async {
      nfc = NfcModel()..setReaderActive(true);
      devices = DeviceRegistry();
      await devices.load();
      io = newIo();
      devices.recordContents('T1', files, 500);
      return FakeNdef(files);
    }

    test('a scan that clears them gives one notice with the count', () async {
      final tag = await tagWith([a, cmd1, cmd2]);
      await io.read('T1', tag);
      expect(notices, ['T1: 2']);
    });

    test('a write that clears them gives a notice', () async {
      final tag = await tagWith([a, cmd1]);
      await write(tag, () => nfc.appendToNextTag([b]));
      expect(notices, ['T1: 1']);
    });

    test('a Terminal send counts only the earlier inputs', () async {
      final tag = await tagWith([a, cmd1]);
      await write(tag,
          () => nfc.appendToNextTag([cmd2], addsTerminalInputs: true));
      expect(notices, ['T1: 1']);
    });

    test('nothing cleared, failed clears and fractionate give no notice',
        () async {
      var tag = await tagWith([a, b]);
      await io.read('T1', tag);
      await write(tag,
          () => nfc.appendToNextTag([cmd1], addsTerminalInputs: true));
      expect(notices, isEmpty);

      tag = await tagWith([a, cmd1]);
      tag.nextWrite = Write.failsBefore;
      await io.read('T1', tag);
      expect(notices, isEmpty);

      tag = await tagWith([a, cmd1]);
      final done = nfc.holdNextTag(
          (held) => held.write((files) => files, addsTerminalInputs: true));
      await io.hold('T1', tag, nfc.takePendingHold()!);
      await done;
      expect(texts(tag.files), ['file A']);
      expect(notices, isEmpty);
    });
  });
}
