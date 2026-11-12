import 'package:flutter/material.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/fs/record_codec.dart';
import 'package:flutter_len_os/headspace.dart';
import 'package:flutter_len_os/headspace_manager_page.dart';
import 'package:flutter_len_os/nfc_model.dart';
import 'package:flutter_len_os/terminal_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const template = 'mixin LenOS-INTERFACE\n'
      'import.LenOS:Headspace\n'
      '{\n'
      'Headspace:Template\n'
      'Traits:[Trait1],[Trait2],[Trait3]\n'
      'Modifier:(none)\n'
      '}';

  group('Headspace format', () {
    test('matches the template exactly; blank modifier is (none)', () {
      final h = Headspace(name: 'Template', traits: ['Trait1', 'Trait2', 'Trait3']);
      expect(h.toText(), template);
      final withMod = Headspace(
          name: 'Focus', traits: ['a', 'b', 'c'], modifier: ' calm ');
      expect(withMod.toText(), contains('Modifier:(calm)'));
    });

    test('parses its own output and tolerates comments', () {
      final h = Headspace.parse('// note\n$template\n')!;
      expect(h.name, 'Template');
      expect(h.traits, ['Trait1', 'Trait2', 'Trait3']);
      expect(h.modifier, '');
      expect(Headspace.parse('mixin LenOS-DEVICE\nimport.LenOS: FileType\n{\n}'), isNull);
    });

    test('comments go after the package, one // per line', () {
      final h = Headspace(
        name: 'Template',
        traits: ['Trait1', 'Trait2', 'Trait3'],
        comments: 'first note\n\n  // already a comment\nlast note  \n',
      );
      expect(h.toText(),
          '$template\n//first note\n// already a comment\n//last note');
      final parsed = Headspace.parse(h.toText())!;
      expect(parsed.comments, 'first note\n already a comment\nlast note');
      expect(Headspace(name: 'a', traits: ['b', 'c', 'd']).toText(),
          isNot(contains('//')));
    });

    test('rejects values that would break the format', () {
      expect(Headspace.validatePart('', what: 'Trait 1'), isNotNull);
      expect(Headspace.validatePart('a,b', what: 'Trait 1'), isNotNull);
      expect(Headspace.validatePart('[x]', what: 'Trait 1'), isNotNull);
      expect(Headspace.validatePart('Deep Focus', what: 'Headspace'), isNull);
      expect(Headspace.validateModifier(''), isNull);
      expect(Headspace.validateModifier('a (b)'), isNotNull);
    });

    test('header match tolerates spacing, case, BOM and a brace', () {
      expect(Headspace.isHeadspaceText(template), isTrue);
      for (final text in [
        'mixin LenOS-INTERFACE\nimport.LenOS: Headspace\n{\n}',
        '\uFEFFmixin LenOS-INTERFACE\r\nimport.LenOS:Headspace\r\n{',
        '  mixin  LenOS - INTERFACE\nimport.LenOS:Headspace {\n}',
        'Mixin lenos-interface\nIMPORT.LENOS:HEADSPACE',
        'mixin LenOS-DEVICE\nimport.LenOS: Headspace\n{\n}',
        'mixin\u00A0LenOS-INTERFACE\nimport.LenOS:\u200BHeadspace',
        '//note\n\nmixin LenOS-INTERFACE\n// c\nimport.LenOS:Headspace',
      ]) {
        expect(Headspace.isHeadspaceText(text), isTrue, reason: text);
      }
      expect(Headspace.isHeadspaceText('mixin LenOS-INTERFACE\nimport.LenOS:Task'),
          isFalse);
      expect(Headspace.isHeadspaceText('import.LenOS:Headspace'), isFalse);
      expect(Headspace.isHeadspaceText('mixin LenOS-OTHER\nimport.LenOS:Headspace'),
          isFalse);
    });

    test('Terminal inputs before the Headspace file are skipped', () {
      final term = RecordCodec.terminalRecord('lena@LenOS:~\$ hi');
      final old = RecordCodec.fromText('h.len', template);
      final other = RecordCodec.fromText('o.txt', 'notes');
      final next = Headspace(name: 'New', traits: ['x', 'y', 'z']).toRecord();
      final placed = Headspace.replaceOnDevice(next, [term, old, other])!;
      expect(placed.map(RecordCodec.decodeText),
          [term, next, other].map(RecordCodec.decodeText));
      expect(Headspace.mismatchReason(other), contains('notes'));
    });

    test('replaces only a Headspace first file', () {
      final old = RecordCodec.fromText('h.len', template);
      final other = RecordCodec.fromText('o.txt', 'notes');
      final next = Headspace(name: 'New', traits: ['x', 'y', 'z']).toRecord();
      final placed = Headspace.replaceOnDevice(next, [old, other])!;
      expect(placed.map(RecordCodec.decodeText),
          [next, other].map(RecordCodec.decodeText));
      expect(Headspace.replaceOnDevice(next, [other, old]), isNull);
      expect(Headspace.replaceOnDevice(next, const []), isNull);
      expect(RecordCodec.describe(old), 'Headspace');
    });
  });

  group('HeadspaceManagerPage', () {
    late NfcModel nfc;
    late DeviceRegistry devices;

    Future<void> pump(WidgetTester tester) async {
      await tester.runAsync(() async {
        devices = DeviceRegistry();
        await devices.load();
      });
      nfc = NfcModel()..setReaderActive(true);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: nfc),
          ChangeNotifierProvider.value(value: devices),
        ],
        child: const MaterialApp(home: HeadspaceManagerPage()),
      ));
    }

    Future<void> choose(WidgetTester tester, String hint, String option) async {
      await tester.ensureVisible(find.text(hint));
      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    /// Picks Custom for the field with [hint] and types [text] into it.
    Future<void> custom(WidgetTester tester, String hint, String text) async {
      await choose(tester, hint, 'Custom…');
      await tester.enterText(
          find.widgetWithText(TextField, 'Custom ${hint.toLowerCase()}'), text);
      // Done typing, so the selection handle doesn't cover the next field.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    Future<void> fillTraits(WidgetTester tester) async {
      await custom(tester, 'Trait 1', 'Calm');
      await custom(tester, 'Trait 2', 'Focused');
      await custom(tester, 'Trait 3', 'Quiet');
    }

    Future<void> tapWrite(WidgetTester tester) async {
      // The page scrolls; WRITE is only built once it is scrolled to.
      await tester.scrollUntilVisible(find.text('WRITE'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('WRITE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WRITE'));
      await tester.pump();
    }

    testWidgets('looks like the file; no preset options, only Custom',
        (tester) async {
      await pump(tester);
      expect(find.text('mixin LenOS-INTERFACE'), findsOneWidget);
      expect(find.text('import.LenOS:Headspace'), findsOneWidget);
      await tester.tap(find.text('Headspace').first);
      await tester.pumpAndSettle();
      expect(find.text('Custom…'), findsWidgets);
      expect(find.text('Template'), findsNothing);
      expect(find.text('Trait1'), findsNothing);
    });

    testWidgets('Custom replaces the dropdown with a green text input',
        (tester) async {
      await pump(tester);
      final dropdowns = find.byType(DropdownButton<String>);
      expect(dropdowns, findsNWidgets(4));
      await custom(tester, 'Headspace', 'Deep Focus');
      expect(dropdowns, findsNWidgets(3));
      final field = tester.widget<TextField>(
          find.ancestor(of: find.text('Deep Focus'), matching: find.byType(TextField)));
      expect(field.style!.color,
          TerminalStyle.of(tester.element(find.text('Deep Focus'))).accent);
      expect(find.text('Custom…'), findsNothing); // No separate "custom" line.
    });

    testWidgets('missing choices are reported and nothing is written',
        (tester) async {
      await pump(tester);
      await tapWrite(tester);
      expect(find.text('Choose a Headspace.'), findsOneWidget);
      await custom(tester, 'Headspace', '');
      await tapWrite(tester);
      expect(find.text('Headspace is required'), findsOneWidget);
      expect(nfc.isWaitingToWrite, isFalse);
    });

    testWidgets('writes over the Headspace file that is first on the device',
        (tester) async {
      await pump(tester);
      await custom(tester, 'Headspace', 'Deep Focus');
      await fillTraits(tester);
      await tapWrite(tester);
      expect(find.text('NFC writing enabled'), findsOneWidget);

      final request = nfc.takePendingWrite()!;
      final old = RecordCodec.fromText('h.len', template);
      final other = RecordCodec.fromText('o.txt', 'notes');
      final written = request.build([old, other]);
      expect(
          RecordCodec.decodeText(written.first),
          template
              .replaceFirst('Headspace:Template', 'Headspace:Deep Focus')
              .replaceFirst('[Trait1],[Trait2],[Trait3]', '[Calm],[Focused],[Quiet]'));
      expect(RecordCodec.decodeText(written.last), 'notes');

      // No Headspace file first: refused, nothing written.
      expect(() => request.build([other, old]), throwsA(isA<NfcWriteException>()));
      expect(() => request.build(const []), throwsA(isA<NfcWriteException>()));

      request.complete('04AA');
      await tester.pumpAndSettle();
      expect(find.text('Headspace "Deep Focus" written to 04AA.'), findsOneWidget);
    });

    testWidgets('a refused write shows the error on the page', (tester) async {
      await pump(tester);
      await custom(tester, 'Headspace', 'Rest');
      await fillTraits(tester);
      await tapWrite(tester);
      final request = nfc.takePendingWrite()!;
      try {
        request.build([RecordCodec.fromText('o.txt', 'notes')]);
      } on NfcWriteException catch (e) {
        request.fail(e);
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('not a Headspace file'), findsOneWidget);
      expect(find.text('NFC writing enabled'), findsNothing);
    });

    testWidgets('comments are written after the Headspace', (tester) async {
      await pump(tester);
      await custom(tester, 'Headspace', 'Rest');
      await fillTraits(tester);
      final comments = find.widgetWithText(TextField, 'One comment per line');
      await tester.ensureVisible(comments);
      await tester.enterText(comments, 'slow down\nbreathe');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapWrite(tester);

      final request = nfc.takePendingWrite()!;
      final old = RecordCodec.fromText('h.len', template);
      final text = RecordCodec.decodeText(request.build([old]).first)!;
      expect(text, endsWith('Modifier:(none)\n}\n//slow down\n//breathe'));
    });

    testWidgets('comments stay when the Headspace changes and between visits',
        (tester) async {
      await pump(tester);
      final comments = find.widgetWithText(TextField, 'One comment per line');
      await tester.ensureVisible(comments);
      await tester.enterText(comments, 'keep me');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await custom(tester, 'Headspace', 'Focus');
      expect(find.text('keep me'), findsOneWidget);

      // Leave and open the Headspace Manager again.
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pumpAndSettle();
      expect(find.text('keep me'), findsOneWidget);
    });

    String knownFile(String name, List<String> traits, String modifier) =>
        Headspace(name: name, traits: traits, modifier: modifier).toText();

    test('last known is the newest device whose first file is a Headspace',
        () async {
      final r = DeviceRegistry();
      await r.load();
      expect(Headspace.lastKnown(r), isNull);
      r
        ..recordContents('A', [RecordCodec.fromText('h.len', knownFile('Old', ['a', 'b', 'c'], ''))],
            500, at: DateTime(2026, 1, 1))
        ..recordContents('B', [RecordCodec.fromText('h.len', knownFile('New', ['x', 'y', 'z'], 'soft'))],
            500, at: DateTime(2026, 1, 2))
        // Newer, but its first file is not a Headspace.
        ..recordContents('C', [RecordCodec.fromText('n.txt', 'notes')], 500,
            at: DateTime(2026, 1, 3));
      final h = Headspace.lastKnown(r)!;
      expect(h.name, 'New');
      expect(h.traits, ['x', 'y', 'z']);
      expect(h.modifier, 'soft');
    });

    testWidgets('placeholders show the last known inputs', (tester) async {
      await pump(tester);
      devices.recordContents('04AA', [
        RecordCodec.fromText('h.len', knownFile('Rest', ['Calm', 'Focused', 'Quiet'], 'gentle')),
      ], 500);
      await tester.pump();
      for (final t in ['Rest', 'Calm', 'Focused', 'Quiet', 'gentle']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Trait 1'), findsNothing);

      // The Custom input shows the same placeholder.
      await choose(tester, 'Rest', 'Custom…');
      expect(find.widgetWithText(TextField, 'Rest'), findsOneWidget);
    });

    testWidgets('empty fields fall back to the last known values', (tester) async {
      await pump(tester);
      final old = RecordCodec.fromText(
          'h.len', knownFile('Rest', ['Calm', 'Focused', 'Quiet'], 'gentle'));
      devices.recordContents('04AA', [old], 500);
      await tester.pump();
      expect(find.textContaining('Empty fields use the last known values'), findsOneWidget);
      expect(find.textContaining('Type none for no Modifier'), findsOneWidget);

      // Change only Trait 2; leave Headspace's Custom input empty.
      await choose(tester, 'Rest', 'Custom…');
      await choose(tester, 'Focused', 'Custom…');
      await tester.enterText(find.widgetWithText(TextField, 'Focused'), 'Alert');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapWrite(tester);
      final request = nfc.takePendingWrite()!;
      final written = Headspace.parse(RecordCodec.decodeText(request.build([old]).first)!)!;
      expect(written.name, 'Rest');
      expect(written.traits, ['Calm', 'Alert', 'Quiet']);
      expect(written.modifier, 'gentle');
    });

    testWidgets('typing none clears a known Modifier', (tester) async {
      await pump(tester);
      final old = RecordCodec.fromText(
          'h.len', knownFile('Rest', ['Calm', 'Focused', 'Quiet'], 'gentle'));
      devices.recordContents('04AA', [old], 500);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'gentle'), 'none');
      await tapWrite(tester);
      final text = RecordCodec.decodeText(nfc.takePendingWrite()!.build([old]).first)!;
      expect(text, contains('Modifier:(none)'));
      expect(text, contains('Traits:[Calm],[Focused],[Quiet]'));
    });

    testWidgets('a favorite with no Modifier leaves the field blank',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'lenos.headspace.favorites':
            '[{"name":"Fav","traits":["a","b","c"],"modifier":""}]',
      });
      await pump(tester);
      final old = RecordCodec.fromText(
          'h.len', knownFile('Rest', ['Calm', 'Focused', 'Quiet'], 'gentle'));
      devices.recordContents('04AA', [old], 500);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fav'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).at(4));
      expect(field.controller!.text, '');
      expect(find.text('none'), findsNothing);
      expect(find.text('gentle'), findsNothing); // No known Modifier hint.
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);
      await tapWrite(tester);
      final text = RecordCodec.decodeText(nfc.takePendingWrite()!.build([old]).first)!;
      expect(text, contains('Modifier:(none)'));
    });

    testWidgets('trait and Modifier inputs line up; ) matches Modifier:(',
        (tester) async {
      await pump(tester);
      expect(find.text('{'), findsNothing);
      expect(find.text('}'), findsNothing);
      expect(find.text('],'), findsNothing);
      expect(find.text(']'), findsNWidgets(Headspace.traitCount));
      expect(tester.widget<Text>(find.text(')')).style!.color,
          tester.widget<Text>(find.text('Modifier:(')).style!.color);

      final modifierRight =
          tester.getTopRight(find.byType(TextField).first).dx;
      for (final hint in ['Trait 1', 'Trait 2', 'Trait 3']) {
        final dropdown = find.ancestor(
            of: find.text(hint), matching: find.byType(DropdownButton<String>));
        expect(tester.getTopRight(dropdown).dx, closeTo(modifierRight, 0.5),
            reason: hint);
      }
    });

    testWidgets('Modifier is blank when no Modifier is known', (tester) async {
      await pump(tester);
      expect(find.text('none'), findsNothing);
      devices.recordContents('04AA', [
        RecordCodec.fromText('h.len', knownFile('Rest', ['Calm', 'Focused', 'Quiet'], '')),
      ], 500);
      await tester.pump();
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('none'), findsNothing);
    });

    testWidgets('star saves a favorite; the menu fills the form with it',
        (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();
      // Nothing to favorite yet: the star reports what is missing.
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pump();
      expect(find.text('Choose a Headspace.'), findsOneWidget);

      await custom(tester, 'Headspace', 'Deep Focus');
      await fillTraits(tester);
      await tester.ensureVisible(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);
      expect(find.text('"Deep Focus" added to favorites.'), findsOneWidget);

      // Change the form, then pick the favorite from the menu.
      await tester.enterText(
          find.widgetWithText(TextField, 'Deep Focus'), 'Other');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add to favorites'), findsOneWidget);
      await tester.tap(find.byTooltip('Favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deep Focus').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Deep Focus'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Quiet'), findsOneWidget);
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);

      // Favorites are kept between visits.
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('Deep Focus'), findsOneWidget);
      await tester.tap(find.text('Deep Focus'));
      await tester.pumpAndSettle();

      // Tapping the star again removes it.
      await tester.ensureVisible(find.byTooltip('Remove from favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from favorites'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add to favorites'), findsOneWidget);
      await tester.tap(find.byTooltip('Favorites'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No favorites yet'), findsOneWidget);
    });
  });
}
