import 'package:flutter/material.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_len_os/nfc_model.dart';
import 'package:flutter_len_os/terminal_page.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Terminal record', () {
    test('is a textual media record holding the line', () {
      final r = RecordCodec.terminalRecord(r'user@LenOS:~$ ls');
      expect(RecordCodec.isTerminalRecord(r), isTrue);
      expect(RecordCodec.decodeText(r), r'user@LenOS:~$ ls');
      expect(RecordCodec.extensionFor(r), 'trm');
      // A Terminal command saved as plain text is a .trm too.
      final asText = RecordCodec.fromText('a.txt', r'user@LenOS:~$ ls');
      expect(RecordCodec.extensionFor(asText), 'trm');
    });
  });

  group('NfcModel writes', () {
    test('fails when the reader is not running', () {
      expect(NfcModel().appendToNextTag([]), throwsA(isA<NfcWriteException>()));
    });

    test('pending write is handed to the session and completed', () async {
      final nfc = NfcModel()..setReaderActive(true);
      final future = nfc.appendToNextTag([RecordCodec.terminalRecord('x')]);
      expect(nfc.isWaitingToWrite, isTrue);
      final request = nfc.takePendingWrite()!;
      expect(nfc.isWaitingToWrite, isFalse);
      expect(nfc.takePendingWrite(), isNull);
      request.complete('04AB');
      expect(await future, '04AB');
    });

    test('only one write at a time; cancel and reader stop fail it', () async {
      final nfc = NfcModel()..setReaderActive(true);
      final first = nfc.appendToNextTag([]);
      expect(nfc.appendToNextTag([]), throwsA(isA<NfcWriteException>()));
      nfc.cancelWrite();
      await expectLater(first, throwsA(isA<NfcWriteCancelled>()));

      final second = nfc.appendToNextTag([]);
      nfc.setReaderActive(false);
      await expectLater(second, throwsA(isA<NfcWriteException>()));
    });
  });

  group('TerminalPage', () {
    Future<NfcModel> pump(WidgetTester tester, {bool reader = true}) async {
      final nfc = NfcModel()..setReaderActive(reader);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: nfc),
          ChangeNotifierProvider(create: (_) => LenOSUser()..name = 'lena'),
          ChangeNotifierProvider(create: (_) => TerminalSettings()),
        ],
        child: const MaterialApp(home: TerminalPage()),
      ));
      return nfc;
    }

    testWidgets('sending queues a Terminal style file for the next device',
        (tester) async {
      final nfc = await pump(tester);
      expect(find.text(r'lena@LenOS:~$ '), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'release -vr');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.text(r'lena@LenOS:~$ release -vr'), findsOneWidget);
      expect(find.text('Waiting for NFC device'), findsOneWidget);
      final request = nfc.takePendingWrite()!;
      expect(RecordCodec.decodeText(request.build(const []).single),
          r'lena@LenOS:~$ release -vr');

      request.complete('04AB');
      await tester.pump();
      expect(find.text('Written to device 04AB.'), findsOneWidget);
      expect(find.text('Waiting for NFC device'), findsNothing);
    });

    testWidgets('sudo commands are written as root', (tester) async {
      final nfc = await pump(tester);
      Future<String> send(String command) async {
        await tester.enterText(find.byType(TextField), command);
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        final request = nfc.takePendingWrite()!;
        final text = RecordCodec.decodeText(request.build(const []).single)!;
        request.complete('04AB');
        await tester.pump();
        return text;
      }

      expect(await send('sudo reboot'), r'root@LenOS:~$ sudo reboot');
      expect(find.text(r'root@LenOS:~$ sudo reboot'), findsOneWidget);
      expect(await send('sudo'), r'root@LenOS:~$ sudo');
      expect(await send('  sudo  ls'), r'root@LenOS:~$ sudo  ls');
      // Only the word sudo, not commands that merely start with the letters.
      expect(await send('sudoku'), r'lena@LenOS:~$ sudoku');
      expect(await send('echo sudo'), r'lena@LenOS:~$ echo sudo');
      // The prompt still shows the user.
      expect(find.text(r'lena@LenOS:~$ '), findsOneWidget);
    });

    testWidgets('errors are shown and empty commands do not write',
        (tester) async {
      final nfc = await pump(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(nfc.isWaitingToWrite, isFalse);

      await tester.enterText(find.byType(TextField), 'ls');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      nfc.takePendingWrite()!.fail(NfcWriteException('Not enough storage'));
      await tester.pump();
      expect(find.text('Write failed: Not enough storage'), findsOneWidget);
    });

    testWidgets('cancel drops the pending write', (tester) async {
      final nfc = await pump(tester);
      await tester.enterText(find.byType(TextField), 'ls');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(nfc.isWaitingToWrite, isFalse);
      expect(find.text('^C  Write cancelled.'), findsOneWidget);
    });
  });
}
