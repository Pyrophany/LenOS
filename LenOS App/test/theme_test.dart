import 'package:flutter/material.dart';
import 'package:flutter_len_os/color_picker_dialog.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/home_sections.dart';
import 'package:flutter_len_os/settings_page.dart';
import 'package:flutter_len_os/terminal_style.dart';
import 'package:flutter_len_os/theme_model.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Theme', () {
    test('both modes use the LenOS style with the chosen accent', () {
      final dark = ThemeModel.darkTheme();
      final light = ThemeModel.light();
      expect(dark.scaffoldBackgroundColor, TerminalStyle.dark.background);
      expect(light.scaffoldBackgroundColor, TerminalStyle.light.background);
      expect(dark.colorScheme.primary, AccentColor.green.onDark);
      expect(light.colorScheme.primary, AccentColor.green.onLight);
      expect(ThemeModel.darkTheme(AccentColor.blue.onDark).colorScheme.primary,
          AccentColor.blue.onDark);
      expect(dark.textTheme.bodyMedium!.fontFamily, TerminalStyle.fontFamily);
    });

    test('preset shades are readable in their mode', () {
      for (final a in AccentColor.values) {
        expect(contrastRatio(a.onDark, TerminalStyle.dark.background),
            greaterThanOrEqualTo(minReadableContrast), reason: '${a.label} dark');
        expect(contrastRatio(a.onLight, TerminalStyle.light.background),
            greaterThanOrEqualTo(minReadableContrast), reason: '${a.label} light');
      }
    });

    test('accent and custom color are saved; presets keep the custom color',
        () async {
      final t = ThemeModel()..accent = AccentColor.pink;
      await Future<void>.delayed(Duration.zero);
      var r = ThemeModel();
      await r.load();
      expect(r.accent, AccentColor.pink);
      expect(r.usingCustom, isFalse);

      r.useCustomAccent(const Color(0xFF12AB34));
      await Future<void>.delayed(Duration.zero);
      r = ThemeModel();
      await r.load();
      expect(r.usingCustom, isTrue);
      expect(r.accentFor(Brightness.dark), const Color(0xFF12AB34));
      expect(r.accentFor(Brightness.light), const Color(0xFF12AB34));

      r.accent = AccentColor.teal;
      expect(r.usingCustom, isFalse);
      expect(r.customAccent, const Color(0xFF12AB34)); // Remembered.
      expect(r.accentFor(Brightness.light), AccentColor.teal.onLight);
      expect(t.dark, isTrue);
    });
  });

  group('Top bar color', () {
    test('defaults to teal; presets and custom are saved', () async {
      final t = ThemeModel();
      expect(t.topBarColor, ThemeModel.appBarColor);
      t.topBarColor = ThemeModel.topBarPresets[3].color;
      await Future<void>.delayed(Duration.zero);
      var r = ThemeModel();
      await r.load();
      expect(r.topBarColor, ThemeModel.topBarPresets[3].color);
      expect(r.topBarIsCustom, isFalse);

      r.useCustomTopBar(const Color(0xFFEEDD00));
      await Future<void>.delayed(Duration.zero);
      r = ThemeModel();
      await r.load();
      expect(r.topBarColor, const Color(0xFFEEDD00));
      expect(r.topBarIsCustom, isTrue);
      r.topBarColor = ThemeModel.appBarColor;
      expect(r.customTopBar, const Color(0xFFEEDD00)); // Remembered.
    });

    test('bar titles stay readable on light and dark bars', () {
      final darkBar = ThemeModel.darkTheme(null, const Color(0xFF262626)).appBarTheme;
      expect(darkBar.backgroundColor, const Color(0xFF262626));
      expect(darkBar.foregroundColor, Colors.white);
      final lightBar = ThemeModel.light(null, const Color(0xFFEEDD00)).appBarTheme;
      expect(lightBar.foregroundColor, Colors.black);
      expect(lightBar.titleTextStyle!.color, Colors.black);
    });
  });

  group('Hex and contrast helpers', () {
    test('hex round-trips and accepts short and # forms', () {
      expect(colorToHex(const Color(0xFF1E7A34)), '#1E7A34');
      expect(colorFromHex('#1e7a34'), const Color(0xFF1E7A34));
      expect(colorFromHex('1E7A34'), const Color(0xFF1E7A34));
      expect(colorFromHex('#fa0'), const Color(0xFFFFAA00));
      expect(colorFromHex('#12345'), isNull);
      expect(colorFromHex('zzzzzz'), isNull);
    });

    test('contrast ratio', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.01));
    });
  });

  group('Color picker dialog', () {
    Future<Future<Color?>> open(WidgetTester tester, Color initial) async {
      late Future<Color?> result;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeModel.darkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showColorPickerDialog(context, initial: initial),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    Finder field(String label) => find.widgetWithText(TextField, label);
    String text(WidgetTester tester, String label) =>
        tester.widget<TextField>(field(label)).controller!.text;

    testWidgets('hex, RGB and sliders stay in sync', (tester) async {
      final result = await open(tester, const Color(0xFF336699));
      expect(text(tester, 'Hex'), '#336699');
      expect([text(tester, 'R'), text(tester, 'G'), text(tester, 'B')], ['51', '102', '153']);

      await tester.enterText(field('Hex'), '#FF8000');
      await tester.pump();
      expect([text(tester, 'R'), text(tester, 'G'), text(tester, 'B')], ['255', '128', '0']);

      await tester.enterText(field('G'), '0');
      await tester.pump();
      expect(text(tester, 'Hex'), '#FF0000');

      // Brightness slider all the way down: black.
      final brightness = find.byType(Slider).at(2);
      await tester.drag(brightness, const Offset(-400, 0));
      await tester.pump();
      expect(text(tester, 'Hex'), '#000000');

      await tester.enterText(field('Hex'), '#12AB34');
      await tester.pump();
      await tester.tap(find.text('Use color'));
      await tester.pumpAndSettle();
      expect(await result, const Color(0xFF12AB34));
    });

    testWidgets('invalid hex shows an error; low contrast is flagged', (tester) async {
      // Readable on both backgrounds.
      await open(tester, const Color(0xFF1E9A44));
      expect(find.textContaining('hard to read'), findsNothing);
      await tester.enterText(field('Hex'), '#12');
      await tester.pump();
      expect(find.text('Use #RRGGBB'), findsOneWidget);

      await tester.enterText(field('Hex'), '#111111'); // Near-black.
      await tester.pump();
      expect(find.text('Dark: hard to read'), findsOneWidget);
      expect(find.text('Light ✓'), findsOneWidget);
    });

    testWidgets('Cancel returns nothing', (tester) async {
      final result = await open(tester, Colors.blue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('Settings accent picker', () {
    Future<ThemeModel> pump(WidgetTester tester) async {
      final theme = ThemeModel();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LenOSUser()),
          ChangeNotifierProvider(create: (_) => TerminalSettings()),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider(create: (_) => DeviceRegistry()),
        ],
        child: Consumer<ThemeModel>(
          builder: (context, t, _) => MaterialApp(
            theme: ThemeModel.light(t.accentFor(Brightness.light), t.topBarColor),
            darkTheme: ThemeModel.darkTheme(t.accentFor(Brightness.dark), t.topBarColor),
            themeMode: t.mode,
            home: const SettingsPage(),
          ),
        ),
      ));
      return theme;
    }

    testWidgets('choosing a preset changes the app accent', (tester) async {
      final theme = await pump(tester);
      expect(find.text('Green'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Purple accent'));
      await tester.pumpAndSettle();
      expect(theme.accent, AccentColor.purple);
      final context = tester.element(find.byType(SettingsPage));
      expect(Theme.of(context).colorScheme.primary, AccentColor.purple.onDark);
    });

    testWidgets('top bar presets and Custom change every top bar', (tester) async {
      final theme = await pump(tester);
      await tester.ensureVisible(find.bySemanticsLabel('Navy top bar'));
      await tester.tap(find.bySemanticsLabel('Navy top bar'));
      await tester.pumpAndSettle();
      final bar = tester.widget<Material>(find.descendant(
          of: find.byType(AppBar), matching: find.byType(Material)).first);
      expect(bar.color, ThemeModel.topBarPresets[3].color);

      await tester.ensureVisible(find.bySemanticsLabel('Custom top bar'));
      await tester.tap(find.bySemanticsLabel('Custom top bar'));
      await tester.pumpAndSettle();
      expect(find.text('Custom top bar color'), findsOneWidget);
      expect(find.textContaining('hard to read'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#FFD000');
      await tester.pump();
      await tester.tap(find.text('Use color'));
      await tester.pumpAndSettle();
      expect(theme.topBarColor, const Color(0xFFFFD000));
      expect(find.text('#FFD000'), findsOneWidget);
    });

    testWidgets('Custom opens the picker and uses its color', (tester) async {
      final theme = await pump(tester);
      await tester.tap(find.bySemanticsLabel('Custom accent'));
      await tester.pumpAndSettle();
      expect(find.text('Custom accent color'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#FF00AA');
      await tester.pump();
      await tester.tap(find.text('Use color'));
      await tester.pumpAndSettle();
      expect(theme.usingCustom, isTrue);
      expect(find.text('#FF00AA'), findsOneWidget);
      final context = tester.element(find.byType(SettingsPage));
      expect(Theme.of(context).colorScheme.primary, const Color(0xFFFF00AA));
    });
  });

  testWidgets('Home cards have centered titles and no arrow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeModel.darkTheme(),
      home: Scaffold(
        body: HomeSectionList(sections: [
          HomeSection(title: 'Devices', icon: Icons.nfc, onTap: () {}),
        ]),
      ),
    ));
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    final card = tester.getRect(find.byType(Card));
    final title = tester.getRect(find.text('Devices'));
    expect(title.center.dx, closeTo(card.center.dx, 1));
    // The icon stays at the left edge (inside the card's margin and padding).
    expect(tester.getRect(find.byIcon(Icons.nfc)).left, lessThan(card.left + 48));
  });
}
