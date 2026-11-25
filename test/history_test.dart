import 'package:LenOS/fs/file_system_model.dart';
import 'package:LenOS/fs/record_codec.dart';
import 'package:LenOS/headspace.dart';
import 'package:LenOS/history.dart';
import 'package:LenOS/history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final headspace = Headspace(name: 'Calm', traits: ['Soft', 'Slow', 'Warm']);

  group('HistoryLog', () {
    test('a name typed letter by letter is one USER change', () {
      final log = HistoryLog(persist: false);
      log.userChanged('user', 'l');
      log.userChanged('l', 'le');
      log.userChanged('le', 'lena');
      expect(log.entries, hasLength(1));
      expect(log.entries.single.details, ['user → lena']);

      // Typed back to the start: no change left.
      log.userChanged('lena', 'user');
      expect(log.entries, isEmpty);
    });

    test(
      'Headspace files show the Headspace and Traits, others just a name',
      () {
        expect(
          HistoryLog.describeFile('headspace.len', headspace.toRecord()),
          'headspace.len · Headspace: Calm · Traits: Soft, Slow, Warm',
        );
        expect(
          HistoryLog.describeFile(
            'notes.len',
            RecordCodec.fromText('notes.len', 'hello'),
          ),
          'notes.len',
        );
        // Writes show the Modifier, but only when there is one.
        final withModifier = Headspace(
          name: 'Calm',
          traits: ['Soft', 'Slow', 'Warm'],
          modifier: 'Sleepy',
        );
        expect(
          HistoryLog.describeFile('headspace.len', withModifier.toRecord()),
          'headspace.len · Headspace: Calm · Traits: Soft, Slow, Warm · '
          'Modifier: Sleepy',
        );
      },
    );

    test('is saved and loaded, newest first', () async {
      final log = HistoryLog();
      await log.load();
      log.bonk();
      log.userChanged('user', 'lena');
      await Future<void>.delayed(Duration.zero);

      final reloaded = HistoryLog();
      await reloaded.load();
      expect(reloaded.entries.map((e) => e.kind), [
        HistoryKind.user,
        HistoryKind.bonk,
      ]);
    });
  });

  test('File Manager changes are logged with the file name', () {
    final log = HistoryLog(persist: false);
    final fs = FileSystemModel(history: log);
    final file = fs.createFile('/a.len', RecordCodec.fromText('a.len', 'x'));
    fs.updateRecord(file.id, RecordCodec.fromText('a.len', 'y'));
    fs.moveFile(file.id, '/b.len');
    fs.deleteFile(file.id);
    expect(log.entries.reversed.map((e) => '${e.title}: ${e.details.single}'), [
      'File created: a.len',
      'File saved: a.len',
      'File renamed: a.len → b.len',
      'File deleted: b.len',
    ]);
  });

  testWidgets('History lists entries and can be cleared', (tester) async {
    final log = HistoryLog(persist: false)
      ..bonk()
      ..userChanged('user', 'lena');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: log,
        child: const MaterialApp(home: HistoryPage()),
      ),
    );
    expect(find.text('USER changed'), findsOneWidget);
    expect(find.text('user → lena'), findsOneWidget);
    expect(find.text('Lena Kitty bonked'), findsOneWidget);
    expect(HistoryLog.bonkResponses, contains(log.entries.last.details.single));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Clear'),
      ),
    );
    await tester.pumpAndSettle();
    expect(log.entries, isEmpty);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });
}
