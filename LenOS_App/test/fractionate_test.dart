import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_len_os/fractionate.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_len_os/nfc_model.dart';
import 'package:flutter_len_os/terminal_page.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A held device that stays in range for [presentChecks] presence checks.
class FakeHeldTag implements HeldTag {
  FakeHeldTag(this.files, {required this.presentChecks});

  List<NdefRecord> files;
  int presentChecks;
  final writes = <List<String?>>[];

  @override
  String get uid => '04AB';

  @override
  Future<bool> isPresent() async => presentChecks-- > 0;

  @override
  Future<void> write(List<NdefRecord> Function(List<NdefRecord>) build,
      {bool keepTerminalInputs = false}) async {
    // Terminal writes must keep earlier Terminal inputs.
    if (!keepTerminalInputs) throw StateError('Terminal inputs dropped');
    files = build(files);
    writes.add(files.map(RecordCodec.decodeText).toList());
  }
}

Future<void> noVibrate() async {}

void main() {
  final note = RecordCodec.fromText('a.txt', 'notes');
  final ls = RecordCodec.terminalRecord(r'lena@LenOS:~$ ls');
  final trance = RecordCodec.terminalRecord(r'lena@LenOS:~$ trance');
  const t = r'lena@LenOS:~$ trance';

  group('fractionate', () {
    test('sends, deletes and sends again every 2 s until out of range', () {
      fakeAsync((async) {
        final tag = FakeHeldTag([note, ls], presentChecks: 3);
        int? sent;
        var buzzes = 0;
        fractionate(tag, trance, vibrate: () async => buzzes++)
            .then((n) => sent = n);

        async.flushMicrotasks();
        expect(tag.writes, [
          ['notes', r'lena@LenOS:~$ ls', t],
        ]);
        async.elapse(const Duration(milliseconds: 1999));
        expect(tag.writes, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(tag.writes.last, ['notes', r'lena@LenOS:~$ ls']);
        async.elapse(const Duration(seconds: 2));
        expect(tag.writes.last, ['notes', r'lena@LenOS:~$ ls', t]);
        async.elapse(const Duration(seconds: 2));
        expect(tag.writes.last, ['notes', r'lena@LenOS:~$ ls']);
        expect(sent, isNull);
        // The 4th check finds no device: nothing more is written.
        async.elapse(const Duration(seconds: 2));
        expect(tag.writes, hasLength(4));
        expect(sent, 2);
        // One vibration per send and per delete.
        expect(buzzes, 4);
      });
    });

    test('a device gone after the first send keeps its trance', () {
      fakeAsync((async) {
        final tag = FakeHeldTag([], presentChecks: 0);
        int? sent;
        fractionate(tag, trance, vibrate: noVibrate).then((n) => sent = n);
        async.elapse(const Duration(seconds: 2));
        expect(tag.writes, [
          [t],
        ]);
        expect(sent, 1);
      });
    });

    test('stops when asked, between steps', () {
      fakeAsync((async) {
        final tag = FakeHeldTag([], presentChecks: 100);
        var stop = false;
        int? sent;
        fractionate(tag, trance, stopped: () => stop, vibrate: noVibrate)
            .then((n) => sent = n);
        async.elapse(const Duration(seconds: 2));
        stop = true;
        async.elapse(const Duration(seconds: 2));
        expect(tag.writes, hasLength(2));
        expect(sent, 1);
      });
    });

    test('dynamic intervals: 1.5 s after 6 sends and 1 s after 10', () {
      // Without the setting, every wait is 2 s.
      expect(fixedTranceInterval(25), const Duration(seconds: 2));
      expect(tranceInterval(1), const Duration(seconds: 2));
      expect(tranceInterval(5), const Duration(seconds: 2));
      expect(tranceInterval(6), const Duration(milliseconds: 1500));
      expect(tranceInterval(9), const Duration(milliseconds: 1500));
      expect(tranceInterval(10), const Duration(seconds: 1));
      expect(tranceInterval(25), const Duration(seconds: 1));

      fakeAsync((async) {
        final tag = FakeHeldTag([], presentChecks: 1000);
        var stop = false;
        final sendTimes = <Duration>[];
        var lastCount = 0;
        fractionate(tag, trance,
            intervalFor: tranceInterval,
            stopped: () => stop,
            vibrate: noVibrate,
            log: (m) {
              if (m.startsWith('Sent')) sendTimes.add(async.elapsed);
            });
        async.flushMicrotasks();
        while (sendTimes.length < 12) {
          async.elapse(const Duration(milliseconds: 100));
          expect(sendTimes.length, greaterThanOrEqualTo(lastCount));
          lastCount = sendTimes.length;
        }
        stop = true;
        async.elapse(const Duration(seconds: 5));
        // Time from each send to the next: two waits (delete, then send).
        final gaps = [
          for (var i = 1; i < sendTimes.length; i++)
            sendTimes[i] - sendTimes[i - 1]
        ];
        expect(gaps.take(5), everyElement(const Duration(seconds: 4)));
        expect(gaps.skip(5).take(4), everyElement(const Duration(seconds: 3)));
        expect(gaps.skip(9), everyElement(const Duration(seconds: 2)));
      });
    });

    test('only the last trance is deleted; missing one refuses', () {
      final older = RecordCodec.terminalRecord(r'lena@LenOS:~$ trance');
      expect(
          withoutLast([older, note, trance], trance)
              .map(RecordCodec.decodeText),
          [t, 'notes']);
      expect(() => withoutLast([note], trance),
          throwsA(isA<NfcWriteException>()));
    });
  });

  group('NfcModel holds', () {
    test('share the pending slot with writes and can be cancelled', () async {
      final nfc = NfcModel()..setReaderActive(true);
      final hold = nfc.holdNextTag((_) async {});
      expect(nfc.isWaitingToWrite, isTrue);
      expect(nfc.appendToNextTag([]), throwsA(isA<NfcWriteException>()));
      expect(nfc.takePendingWrite(), isNull);
      nfc.cancelWrite();
      await expectLater(hold, throwsA(isA<NfcWriteCancelled>()));
      expect(NfcModel().holdNextTag((_) async {}),
          throwsA(isA<NfcWriteException>()));
    });
  });

  testWidgets('Terminal fractionate holds the next device', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final nfc = NfcModel()..setReaderActive(true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: nfc),
        ChangeNotifierProvider(create: (_) => LenOSUser()..name = 'lena'),
        ChangeNotifierProvider(create: (_) => TerminalSettings()),
      ],
      child: const MaterialApp(home: TerminalPage()),
    ));
    await tester.enterText(find.byType(TextField), 'fractionate');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(nfc.takePendingWrite(), isNull);
    final hold = nfc.takePendingHold()!;

    final tag = FakeHeldTag([note], presentChecks: 1);
    final done = hold.run(tag).then((_) => hold.complete(tag.uid));
    await tester.pump();
    expect(find.text('Fractionating: keep the device in range'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await done;
    await tester.pump();
    expect(tag.writes, [
      ['notes', t],
      ['notes'],
    ]);
    expect(find.text('Device left range.'), findsOneWidget);
    expect(find.text('Fractionated device 04AB: trance sent 1 time(s).'),
        findsOneWidget);
    expect(find.text('Waiting for NFC device'), findsNothing);
  });

  testWidgets('trance.trm is written as the set user, or root with sudo',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final nfc = NfcModel()..setReaderActive(true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: nfc),
        ChangeNotifierProvider(create: (_) => LenOSUser()..name = 'mira'),
        ChangeNotifierProvider(create: (_) => TerminalSettings()),
      ],
      child: const MaterialApp(home: TerminalPage()),
    ));
    Future<String?> firstWrite(String command) async {
      await tester.enterText(find.byType(TextField), command);
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      final hold = nfc.takePendingHold()!;
      final tag = FakeHeldTag([], presentChecks: 0);
      final done = hold.run(tag).then((_) => hold.complete(tag.uid));
      await tester.pump(const Duration(seconds: 2));
      await done;
      await tester.pump();
      return tag.writes.first.single;
    }

    expect(await firstWrite('fractionate'), r'mira@LenOS:~$ trance');
    expect(await firstWrite('sudo fractionate'), r'root@LenOS:~$ trance');
    // Anything after the command is allowed.
    expect(await firstWrite('fractionate --test'), r'mira@LenOS:~$ trance');
    expect(await firstWrite('sudo fractionate -v x'), r'root@LenOS:~$ trance');
  });
}
