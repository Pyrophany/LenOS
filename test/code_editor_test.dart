import 'package:flutter/material.dart';
import 'package:flutter_len_os/code_editor_page.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/fs/editor_session.dart';
import 'package:flutter_len_os/fs/file_system_model.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_len_os/nfc_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FileSystemModel fs;
  late EditorSession session;
  late DeviceRegistry devices;
  late NfcModel nfc;

  Future<void> pump(WidgetTester tester) async {
    await tester.runAsync(() async {
      fs = FileSystemModel();
      await fs.load();
      devices = DeviceRegistry();
      await devices.load();
    });
    session = EditorSession(fs);
    nfc = NfcModel()..setReaderActive(true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: nfc),
        ChangeNotifierProvider.value(value: fs),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: devices),
      ],
      child: const MaterialApp(home: CodeEditorPage()),
    ));
  }

  Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last); // The menu is on top.

    await tester.pumpAndSettle();
  }

  testWidgets('New File uses the LenOS template; Save File picks a folder',
      (tester) async {
    await pump(tester);
    fs.createFolder('/scripts');
    await menu(tester, 'New File');
    expect(session.active!.controller.text,
        'mixin LenOS-DEVICE\nimport.LenOS: FileType\n{\n}');
    expect(find.textContaining('Ln 4, Col 1'), findsOneWidget);

    await menu(tester, 'Save File');
    expect(find.text('Save to File Manager'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('untitled-1.len')),
        findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/scripts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = fs.fileAt('/scripts/untitled-1.len')!;
    expect(RecordCodec.mimeType(saved.record), RecordCodec.lenosMime);
    expect(session.active!.dirty, isFalse);
  });

  testWidgets('Open File picks from the File Manager, through folders',
      (tester) async {
    await pump(tester);
    fs.createFile('/notes/a.txt', RecordCodec.fromText('a.txt', 'from fs'));
    await menu(tester, 'Open File');
    expect(find.text('Open file'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.txt'));
    await tester.pumpAndSettle();

    expect(find.byType(CodeEditorPage), findsOneWidget);
    expect(session.active!.controller.text, 'from fs');
    expect(session.nameOf(session.active!), 'a.txt');
  });

  testWidgets('Import File takes a text file from a favorite device',
      (tester) async {
    await pump(tester);
    devices
      ..recordScan('04AA')
      ..rename('04AA', 'my tag')
      ..setFavorite('04AA', true)
      ..recordContents('04AA', [
        RecordCodec.terminalRecord(r'lena@LenOS:~$ ls'),
      ], 200);
    await menu(tester, 'Import File');
    expect(find.text('Import from Devices'), findsOneWidget);
    await tester.tap(find.text('my tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'lena@LenOS:~$ ls'));
    await tester.pumpAndSettle();

    expect(find.byType(CodeEditorPage), findsOneWidget);
    final b = session.active!;
    expect(b.controller.text, r'lena@LenOS:~$ ls');
    expect(session.nameOf(b), 'my-tag-file1.trm');
    expect(b.extension, 'trm');
    expect(b.dirty, isTrue); // Imported, not saved yet.
  });

  Future<void> renameTo(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
  }

  testWidgets('rename a saved file from the menu', (tester) async {
    await pump(tester);
    final file = fs.createFile('/notes/a.txt', RecordCodec.fromText('a.txt', 'x'));
    fs.createFile('/notes/taken.txt', RecordCodec.fromText('taken.txt', 'y'));
    session.openFile(file.id);
    await tester.pump();

    await menu(tester, 'Rename File');
    await renameTo(tester, 'taken.txt');
    expect(find.text('A file or folder with this name already exists'),
        findsOneWidget);
    await renameTo(tester, 'b.txt');
    expect(fs.byId(file.id)!.path, '/notes/b.txt');
    expect(find.text('b.txt'), findsOneWidget); // The tab shows the new name.
  });

  testWidgets('tapping the open tab renames; other tabs just switch',
      (tester) async {
    await pump(tester);
    await menu(tester, 'New File');
    await menu(tester, 'New File');
    expect(session.activeIndex, 1);

    await tester.tap(find.text('untitled-1.len'));
    await tester.pumpAndSettle();
    expect(session.activeIndex, 0);
    expect(find.text('Rename file'), findsNothing);

    await tester.tap(find.text('untitled-1.len'));
    await tester.pumpAndSettle();
    expect(find.text('Rename file'), findsOneWidget);
    await renameTo(tester, 'data.json');
    final b = session.active!;
    expect(session.nameOf(b), 'data.json');

    // An unsaved tab keeps its new name and type when saved.
    await menu(tester, 'Save File');
    expect(find.text('data.json'), findsWidgets);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(RecordCodec.mimeType(fs.fileAt('/data.json')!.record),
        'application/json');
  });

  group('Export File', () {
    final existing = RecordCodec.fromText('x.txt', 'already here');

    Future<void> setUpDevice({required int capacity}) async {
      devices
        ..recordScan('04AA')
        ..rename('04AA', 'my tag')
        ..setFavorite('04AA', true)
        ..recordContents('04AA', [existing], capacity)
        ..recordScan('04BB')
        ..rename('04BB', 'never read')
        ..setFavorite('04BB', true);
    }

    testWidgets('is right above Import File', (tester) async {
      await pump(tester);
      session.newFile();
      await tester.pump();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      final export = tester.getTopLeft(find.text('Export File')).dy;
      final import = tester.getTopLeft(find.text('Import File')).dy;
      expect(export, lessThan(import));
      expect(tester.getTopLeft(find.text('Rename File')).dy, lessThan(export));
    });

    testWidgets('appends the current tab to the chosen device', (tester) async {
      await pump(tester);
      await setUpDevice(capacity: 500);
      session.newFile();
      session.active!.controller.text = 'exported text';
      await tester.pump();

      await menu(tester, 'Export File');
      expect(find.text('Export to which device?'), findsOneWidget);
      await tester.tap(find.text('my tag'));
      await tester.pumpAndSettle();
      expect(find.text('already here'), findsOneWidget);
      expect(find.text('exported text'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pump();
      final request = nfc.takePendingWrite()!;
      expect(request.uid, '04AA');
      final written = request.build([existing]);
      expect(written.map(RecordCodec.decodeText), ['already here', 'exported text']);
      expect(RecordCodec.mimeType(written.last), RecordCodec.lenosMime);

      devices.recordContents('04AA', written, 500);
      request.complete('04AA');
      await tester.pumpAndSettle();
      expect(find.byType(CodeEditorPage), findsOneWidget);
      expect(find.text('Exported untitled-1.len to my tag.'), findsOneWidget);
    });

    testWidgets('shows an error when the file would not fit', (tester) async {
      await pump(tester);
      await setUpDevice(capacity: 40);
      session.newFile();
      session.active!.controller.text = 'x' * 100;
      await tester.pump();

      await menu(tester, 'Export File');
      await tester.tap(find.text('my tag'));
      await tester.pumpAndSettle();
      expect(find.text('Not enough storage'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too big for this device'), findsOneWidget);
      final accept = find.widgetWithText(FilledButton, 'Accept');
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    });

    testWidgets('a device that was never read cannot be chosen', (tester) async {
      await pump(tester);
      await setUpDevice(capacity: 500);
      session.newFile();
      await tester.pump();
      await menu(tester, 'Export File');
      await tester.tap(find.text('never read'));
      await tester.pumpAndSettle();
      expect(find.textContaining('have not been read yet'), findsOneWidget);
      expect(find.text('Export to which device?'), findsOneWidget);
    });
  });
}
