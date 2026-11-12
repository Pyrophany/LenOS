import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_len_os/code_editor_page.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/fs/editor_session.dart';
import 'package:flutter_len_os/fs/file_system_model.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_len_os/loaded_files_page.dart';
import 'package:flutter_len_os/nfc_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final hello = RecordCodec.fromText('a.txt', 'hello world');
  final term = RecordCodec.terminalRecord(r'lena@LenOS:~$ ls');

  Future<DeviceRegistry> registryWith3Favorites() async {
    final r = DeviceRegistry();
    await r.load();
    r
      ..recordScan('AA', at: DateTime(2026, 1, 3))
      ..recordScan('BB', at: DateTime(2026, 1, 1))
      ..recordScan('CC', at: DateTime(2026, 1, 2))
      ..rename('AA', 'zulu')
      ..rename('BB', 'alpha')
      ..setFavorite('CC', true)
      ..setFavorite('AA', true)
      ..setFavorite('BB', true)
      ..recordContents('AA', [hello], 100, at: DateTime(2026, 1, 3))
      ..recordContents('BB', [hello, term], 200, at: DateTime(2026, 1, 1));
    return r;
  }

  group('DeviceRegistry contents and order', () {
    test('storage usage comes from the last read', () async {
      final r = await registryWith3Favorites();
      final a = r.byUid('AA')!;
      expect(a.usedBytes, hello.byteLength);
      expect(a.usage, closeTo(hello.byteLength / 100, 1e-9));
      expect(r.byUid('CC')!.usage, isNull);
    });

    test('orders: custom, name, last scanned, storage used', () async {
      final r = await registryWith3Favorites();
      List<String> uids() => r.favorites.map((d) => d.uid).toList();
      expect(uids(), ['CC', 'AA', 'BB']); // Order favorited.
      r.moveFavorite(2, 0);
      expect(uids(), ['BB', 'CC', 'AA']);
      r.order = DeviceOrder.name;
      expect(uids(), ['BB', 'CC', 'AA']); // alpha, CC, zulu
      r.order = DeviceOrder.lastScanned;
      expect(uids(), ['AA', 'CC', 'BB']);
      r.order = DeviceOrder.storageUsed;
      expect(uids(), ['BB', 'AA', 'CC']); // Unknown storage last.
      r.setFavorite('BB', false);
      expect(uids(), ['AA', 'CC']);
    });

    test('contents, order and sort mode survive a reload', () async {
      final r = await registryWith3Favorites();
      r
        ..moveFavorite(2, 0)
        ..order = DeviceOrder.lastScanned;
      await Future<void>.delayed(Duration.zero);

      final reloaded = DeviceRegistry();
      await reloaded.load();
      expect(reloaded.order, DeviceOrder.lastScanned);
      reloaded.order = DeviceOrder.custom;
      expect(reloaded.favorites.map((d) => d.uid), ['BB', 'CC', 'AA']);
      final b = reloaded.byUid('BB')!;
      expect(b.capacity, 200);
      expect(b.records!.map(RecordCodec.decodeText), [
        'hello world',
        r'lena@LenOS:~$ ls',
      ]);
    });

    test('reads the first saved format (a plain device list)', () async {
      SharedPreferences.setMockInitialValues({
        'lenos.devices.v1': jsonEncode([
          {
            'uid': 'AA',
            'name': null,
            'favorite': true,
            'firstSeen': '2026-01-01T00:00:00.000',
            'lastSeen': '2026-01-01T00:00:00.000',
          },
        ]),
      });
      final r = DeviceRegistry();
      await r.load();
      expect(r.favorites.single.uid, 'AA');
      expect(r.byUid('AA')!.records, isNull);
    });
  });

  late FileSystemModel fs;
  late EditorSession session;
  late NfcModel nfc;

  /// Devices page with every provider the device pages use.
  Future<DeviceRegistry> pump(WidgetTester tester) async {
    late DeviceRegistry r;
    await tester.runAsync(() async {
      r = await registryWith3Favorites();
      fs = FileSystemModel();
      await fs.load();
    });
    session = EditorSession(fs);
    nfc = NfcModel()..setReaderActive(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: r),
          ChangeNotifierProvider.value(value: fs),
          ChangeNotifierProvider.value(value: session),
          ChangeNotifierProvider.value(value: nfc),
        ],
        child: const MaterialApp(home: LoadedFilesPage()),
      ),
    );
    return r;
  }

  group('LoadedFilesPage', () {
    testWidgets('lists favorites with storage bars and sorts from the menu', (
      tester,
    ) async {
      final r = await pump(tester);
      expect(find.byType(StorageBar), findsNWidgets(3));
      expect(find.textContaining('Storage unknown'), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));

      await tester.tap(find.byTooltip('Order devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(r.order, DeviceOrder.name);
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      expect(
        tester.getTopLeft(find.text('alpha')).dy,
        lessThan(tester.getTopLeft(find.text('zulu')).dy),
      );
    });

    testWidgets('tapping a device previews its files', (tester) async {
      await pump(tester);
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(find.text('File 1 · Text'), findsOneWidget);
      expect(find.text('File 2 · Terminal command'), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);

      await tester.tap(find.text(r'lena@LenOS:~$ ls'));
      await tester.pumpAndSettle();
      // Expands in place; no separate screen.
      expect(find.text('File 2 · Terminal command'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('tapping a preview expands it to scroll; tap again collapses', (
      tester,
    ) async {
      final r = await pump(tester);
      final lines = [for (var i = 1; i <= 60; i++) 'line $i'].join('\n');
      r.recordContents('CC', [RecordCodec.fromText('long.txt', lines)], 2000);
      await tester.pump();
      await tester.tap(find.text('CC'));
      await tester.pumpAndSettle();

      Text preview() => tester.widget<Text>(find.text(lines));
      expect(preview().maxLines, 6);
      final collapsedHeight = tester.getSize(find.byType(Card).first).height;

      await tester.tap(find.text(lines));
      await tester.pumpAndSettle();
      expect(preview().maxLines, isNull);
      expect(
        tester.getSize(find.byType(Card).first).height,
        greaterThan(collapsedHeight),
      );
      final scrollable = find.descendant(
        of: find.byType(Card).first,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      await tester.drag(scrollable, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, position.maxScrollExtent);
      expect(position.maxScrollExtent, greaterThan(0));

      // Tapping the title collapses it too.
      await tester.tap(find.text('File 1 · Text'));
      await tester.pumpAndSettle();
      expect(preview().maxLines, 6);
    });

    testWidgets('page is titled Devices', (tester) async {
      await pump(tester);
      expect(find.text('Devices'), findsOneWidget);
    });

    testWidgets('empty state when nothing is favorited', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => DeviceRegistry(),
          child: const MaterialApp(home: LoadedFilesPage()),
        ),
      );
      expect(find.textContaining('No favorite devices yet'), findsOneWidget);
    });
  });

  group('Editing a device', () {
    /// Opens device BB ("alpha": [hello, term], 200 bytes capacity).
    Future<DeviceRegistry> openAlpha(WidgetTester tester) async {
      final r = await pump(tester);
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      return r;
    }

    Future<void> longPressMenu(
      WidgetTester tester,
      String preview,
      String item,
    ) async {
      await tester.longPress(find.text(preview));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a saved file with the same content adds its name to the title',
      (tester) async {
        final r = await pump(tester);
        fs.createFile(
          '/notes/greeting.txt',
          RecordCodec.fromText('greeting.txt', 'hello world'),
        );
        await tester.pump();
        await tester.tap(find.text('alpha'));
        await tester.pumpAndSettle();
        expect(find.text('File 1 · greeting.txt'), findsOneWidget);
        expect(find.text('File 2 · Terminal command'), findsOneWidget);
        expect(r.byUid('BB')!.records!.length, 2);
      },
    );

    testWidgets('Delete outlines the file in red; Cancel restores the list', (
      tester,
    ) async {
      await openAlpha(tester);
      expect(find.text('Accept'), findsNothing);
      final sizeBefore = tester
          .widget<Text>(find.textContaining('% used'))
          .data;
      await longPressMenu(tester, 'hello world', 'Delete');

      // Still listed, outlined red and labelled, but not counted.
      expect(find.text('hello world'), findsOneWidget);
      expect(find.text('DELETED'), findsOneWidget);
      final card = tester.widget<Card>(
        find
            .ancestor(of: find.text('hello world'), matching: find.byType(Card))
            .first,
      );
      final side = (card.shape! as RoundedRectangleBorder).side;
      expect(
        side.color,
        Theme.of(tester.element(find.text('DELETED'))).colorScheme.error,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.textContaining('After changes'), findsOneWidget);
      expect(
        tester.widget<Text>(find.textContaining('% used')).data,
        isNot(sizeBefore),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('DELETED'), findsNothing);
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets(
      'Undo delete brings a file back; deleted files are not written',
      (tester) async {
        await openAlpha(tester);
        await longPressMenu(tester, 'hello world', 'Delete');
        await tester.longPress(find.text('hello world'));
        await tester.pumpAndSettle();
        expect(find.text('Delete'), findsNothing);
        // Editing a file marked for deletion is not offered.
        final edit = tester.widget<PopupMenuItem<Object>>(
          find.ancestor(
            of: find.text('Edit'),
            matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
          ),
        );
        expect(edit.enabled, isFalse);
        await tester.tap(find.text('Undo delete'));
        await tester.pumpAndSettle();
        expect(find.text('DELETED'), findsNothing);

        await longPressMenu(tester, r'lena@LenOS:~$ ls', 'Delete');
        await tester.tap(find.text('Accept'));
        await tester.pump();
        final written = nfc.takePendingWrite()!.build([hello, term]);
        expect(texts(written), ['hello world']);
      },
    );

    testWidgets('deleting everything says the device will be erased', (
      tester,
    ) async {
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Delete');
      await longPressMenu(tester, r'lena@LenOS:~$ ls', 'Delete');
      expect(find.textContaining('All files will be removed'), findsOneWidget);
      expect(find.text('DELETED'), findsNWidgets(2));
    });

    testWidgets('Accept writes the draft to that device only', (tester) async {
      final r = await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Delete');
      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(find.text('NFC writing enabled'), findsOneWidget);

      // What the Home page's NFC session does when the device is held near.
      final request = nfc.takePendingWrite()!;
      expect(request.uid, 'BB');
      final base = r.byUid('BB')!.records!;
      final written = request.build(base);
      expect(written.map(RecordCodec.decodeText), [r'lena@LenOS:~$ ls']);
      // The device changed since it was scanned: the write is refused.
      expect(() => request.build([hello]), throwsA(isA<NfcWriteException>()));

      r.recordContents('BB', written, 200);
      request.complete('BB');
      await tester.pumpAndSettle();
      expect(find.text('NFC writing enabled'), findsNothing);
      expect(find.text('Written to alpha.'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('hello world'), findsNothing);
    });

    testWidgets('a failed write shows the error and keeps the changes', (
      tester,
    ) async {
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Delete');
      await tester.tap(find.text('Accept'));
      await tester.pump();
      nfc.takePendingWrite()!.fail(
        NfcWriteException('Device BB is read-only.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Write failed'), findsOneWidget);
      expect(find.text('Device BB is read-only.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('+ adds a File Manager file; too big disables Accept', (
      tester,
    ) async {
      await pump(tester);
      fs.createFile('/big.txt', RecordCodec.fromText('big.txt', 'x' * 80));
      fs.createFile('/small.txt', RecordCodec.fromText('small.txt', 'hi'));
      await tester.pump();
      await tester.tap(find.text('zulu')); // AA: [hello], 100 bytes.
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('small.txt'));
      await tester.pumpAndSettle();
      expect(find.text('File 2 · small.txt'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      final accept = find.widgetWithText(FilledButton, 'Accept');
      expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Add file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('big.txt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Too big for this device'), findsOneWidget);
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    });

    testWidgets('Move shows drag handles and reorders the draft', (
      tester,
    ) async {
      await openAlpha(tester);
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      await longPressMenu(tester, 'hello world', 'Move');
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      expect(find.text('Accept'), findsOneWidget);

      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 40));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('File 1 · Terminal command'), findsOneWidget);
      expect(find.text('File 2 · Text'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pump();
      final request = nfc.takePendingWrite()!;
      expect(request.build([hello, term]).map(RecordCodec.decodeText), [
        r'lena@LenOS:~$ ls',
        'hello world',
      ]);
    });

    testWidgets('Edit opens the matching saved file, else a new tab', (
      tester,
    ) async {
      await pump(tester);
      final saved = fs.createFile(
        '/greeting.txt',
        RecordCodec.fromText('greeting.txt', 'hello world'),
      );
      await tester.pump();
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      await longPressMenu(tester, 'hello world', 'Edit');
      expect(find.byType(CodeEditorPage), findsOneWidget);
      expect(session.active!.fileId, saved.id);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await longPressMenu(tester, r'lena@LenOS:~$ ls', 'Edit');
      final b = session.active!;
      expect(b.fileId, isNull);
      expect(session.nameOf(b), 'alpha-file2.trm');
      expect(b.controller.text, r'lena@LenOS:~$ ls');
    });

    testWidgets('leaving with changes asks first', (tester) async {
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Delete');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Devices'), findsOneWidget);
    });
  });

  group('Edit returns to the device', () {
    Future<void> openAlpha(WidgetTester tester) async {
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
    }

    Future<void> longPressMenu(
      WidgetTester tester,
      String preview,
      String item,
    ) async {
      await tester.longPress(find.text(preview));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    /// Saves in the editor. A file not in the File Manager first gets the
    /// Save to File Manager dialog, answered with [dialog] (Cancel or Save).
    Future<void> saveInEditor(
      WidgetTester tester, {
      String dialog = 'Cancel',
    }) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save File'));
      await tester.pumpAndSettle();
      if (find.text('Save to File Manager').evaluate().isNotEmpty) {
        await tester.tap(find.text(dialog));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('an unsaved device file offers a File Manager copy first', (
      tester,
    ) async {
      await pump(tester);
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Edit');
      session.active!.controller.text = 'hello edited';
      await tester.pump();

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Save As…'), findsNothing);
      await tester.tap(find.text('Save File'));
      await tester.pumpAndSettle();
      expect(find.text('Save to File Manager'), findsOneWidget);
      expect(
        find.textContaining('Cancel to only save it to the device'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Saved to the File Manager and back on the device list, named.
      expect(fs.files.single.name, 'alpha-file1.len');
      expect(find.byType(CodeEditorPage), findsNothing);
      expect(find.text('File 1 · alpha-file1.len'), findsOneWidget);
      expect(find.text('hello edited'), findsOneWidget);
      expect(find.text('EDITED'), findsOneWidget);
    });

    testWidgets('a device file already in the File Manager saves directly', (
      tester,
    ) async {
      await pump(tester);
      fs.createFile(
        '/greeting.txt',
        RecordCodec.fromText('greeting.txt', 'hello world'),
      );
      await tester.pump();
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Edit');
      session.active!.controller.text = 'hello edited';
      await tester.pump();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save File'));
      await tester.pumpAndSettle();
      expect(find.text('Save to File Manager'), findsNothing);
      expect(find.byType(CodeEditorPage), findsNothing);
      expect(find.text('hello edited'), findsOneWidget);
    });

    testWidgets('saving replaces the file in the list, in place', (
      tester,
    ) async {
      await pump(tester);
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Edit');
      expect(find.byType(CodeEditorPage), findsOneWidget);
      expect(
        find.textContaining('Save returns it to the device list'),
        findsOneWidget,
      );

      session.active!.controller.text = 'hello edited';
      await tester.pump();
      await saveInEditor(tester);

      expect(find.byType(CodeEditorPage), findsNothing);
      expect(find.text('File 1 · Text'), findsOneWidget);
      expect(find.text('hello edited'), findsOneWidget);
      expect(find.text('hello world'), findsNothing);
      expect(find.text('EDITED'), findsOneWidget);
      expect(session.buffers, isEmpty); // The temporary tab is closed.
      expect(fs.files, isEmpty); // Nothing was saved to the File Manager.

      await tester.tap(find.text('Accept'));
      await tester.pump();
      final written = nfc.takePendingWrite()!.build([hello, term]);
      expect(texts(written), ['hello edited', r'lena@LenOS:~$ ls']);
      expect(RecordCodec.isTextRecord(written.first), isTrue); // Same kind.
    });

    testWidgets('a matching saved file is saved too', (tester) async {
      await pump(tester);
      final saved = fs.createFile(
        '/greeting.txt',
        RecordCodec.fromText('greeting.txt', 'hello world'),
      );
      await tester.pump();
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Edit');
      session.active!.controller.text = 'hello again';
      await tester.pump();
      await saveInEditor(tester);

      expect(RecordCodec.decodeText(fs.byId(saved.id)!.record), 'hello again');
      expect(find.text('File 1 · greeting.txt'), findsOneWidget);
      expect(find.text('EDITED'), findsOneWidget);
      expect(session.buffers.single.fileId, saved.id); // Its tab stays open.
    });

    testWidgets('saving without changes leaves the list alone', (tester) async {
      await pump(tester);
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Edit');
      await saveInEditor(tester);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('EDITED'), findsNothing);
    });

    testWidgets('leaving the editor without saving changes nothing', (
      tester,
    ) async {
      await pump(tester);
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Edit');
      session.active!.controller.text = 'not saved';
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('hello world'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
    });

    testWidgets('editing during a move keeps the new order', (tester) async {
      await pump(tester);
      await openAlpha(tester);
      await longPressMenu(tester, 'hello world', 'Move');
      expect(
        find.text('Drag the handles to move files, then Accept.'),
        findsOneWidget,
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
      ); // Nothing covers the last handle.

      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 40));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('File 2 · Text'), findsOneWidget);

      await longPressMenu(tester, 'hello world', 'Edit');
      session.active!.controller.text = 'moved and edited';
      await tester.pump();
      await saveInEditor(tester);
      expect(find.text('File 2 · Text'), findsOneWidget);
      expect(find.text('moved and edited'), findsOneWidget);
    });
  });

  group('Recovery', () {
    final link = RecordCodec.fromText('l.url', 'https://example.com');

    testWidgets('interrupted write: only recovery options; restore is forced', (
      tester,
    ) async {
      final r = await pump(tester);
      r.recordContents('BB', [hello, link], 200);
      r.beginWrite('BB', [link], before: [hello, link]);
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(find.textContaining('did not finish'), findsOneWidget);
      expect(find.byTooltip('Add file'), findsNothing);

      await tester.tap(find.text('Restore previous files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pump();
      final request = nfc.takePendingWrite()!;
      expect(request.force, isTrue);
      // Written whatever the damaged device holds now.
      expect(texts(request.build([])), ['hello world', 'https://example.com']);
    });

    testWidgets(
      'unexpectedly empty: warning and restore (without Terminal inputs)',
      (tester) async {
        final r = await pump(tester);
        r.recordContents('BB', [hello, link, term], 200);
        r.recordContents('BB', const [], 200);
        await tester.tap(find.text('alpha'));
        await tester.pumpAndSettle();
        expect(find.textContaining('found no files'), findsOneWidget);

        await tester.tap(find.text('Restore 2 file(s)'));
        await tester.pumpAndSettle();
        expect(find.text('hello world'), findsOneWidget);
        expect(find.text(r'lena@LenOS:~$ ls'), findsNothing);
        expect(find.text('NEW'), findsNothing);
        await tester.tap(find.text('Accept'));
        await tester.pump();
        final request = nfc.takePendingWrite()!;
        expect(request.force, isFalse);
        expect(texts(request.build(const [])), [
          'hello world',
          'https://example.com',
        ]);
        // If the device turns out to hold something after all, nothing is overwritten.
        expect(() => request.build([hello]), throwsA(isA<NfcWriteException>()));
      },
    );

    testWidgets('clearing only Terminal inputs is not reported as unexpected', (
      tester,
    ) async {
      final r = await pump(tester);
      r.recordContents('BB', [term], 200);
      r.recordContents('BB', const [], 200);
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(find.textContaining('found no files'), findsNothing);
      expect(find.byTooltip('Restore previous files'), findsNothing);
    });

    testWidgets('history button loads the previous files', (tester) async {
      final r = await pump(tester);
      r.recordContents('BB', [hello, link], 200);
      r.recordContents('BB', [hello], 200); // Previous: [hello, link].
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Restore previous files'));
      await tester.pumpAndSettle();
      expect(find.text('https://example.com'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('only files added in the current draft are marked NEW', (
      tester,
    ) async {
      await pump(tester);
      fs.createFile('/small.txt', RecordCodec.fromText('small.txt', 'hi'));
      await tester.pump();
      await tester.tap(find.text('zulu'));
      await tester.pumpAndSettle();
      for (var round = 0; round < 2; round++) {
        await tester.tap(find.byTooltip('Add file'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('small.txt'));
        await tester.pumpAndSettle();
        expect(find.text('NEW'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });
  });
}

List<String?> texts(List<NdefRecord> records) =>
    records.map(RecordCodec.decodeText).toList();
