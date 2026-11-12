import 'package:flutter/material.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/main.dart' show welcomeTitle;
import 'package:flutter_len_os/settings_page.dart';
import 'package:flutter_len_os/theme_model.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DeviceRegistry', () {
    test('named devices first, then most recently seen; favorites', () {
      final r = DeviceRegistry()
        ..recordScan('AA', at: DateTime(2026, 1, 1))
        ..recordScan('BB', at: DateTime(2026, 1, 3))
        ..recordScan('CC', at: DateTime(2026, 1, 2))
        ..recordScan('DD', at: DateTime(2026, 1, 4));
      r
        ..rename('CC', 'zeta')
        ..rename('AA', 'Alpha')
        ..setFavorite('BB', true)
        ..setFavorite('AA', true);
      expect(r.devices.map((d) => d.uid), ['AA', 'CC', 'DD', 'BB']);
      // Custom order by default: the order they were favorited.
      expect(r.favorites.map((d) => d.uid), ['BB', 'AA']);

      r.rename('CC', '   '); // Blank clears the name.
      expect(r.byUid('CC')!.name, isNull);
      expect(r.devices.map((d) => d.uid), ['AA', 'DD', 'BB', 'CC']);
    });

    test('saves and reloads, keeping scans made before loading', () async {
      final first = DeviceRegistry();
      await first.load();
      first
        ..recordScan('AA', at: DateTime(2026, 1, 1))
        ..rename('AA', 'Interface')
        ..setFavorite('AA', true);
      await Future<void>.delayed(Duration.zero);

      final reloaded = DeviceRegistry()..recordScan('BB');
      await reloaded.load();
      expect(reloaded.byUid('AA')!.name, 'Interface');
      // The scan made before loading is now saved too.
      final third = DeviceRegistry();
      await third.load();
      expect(third.byUid('BB'), isNotNull);
      expect(reloaded.byUid('AA')!.favorite, isTrue);
      expect(reloaded.byUid('BB'), isNotNull);
    });
  });

  test('user name and theme persist', () async {
    LenOSUser().name = 'lena';
    expect(ThemeModel().dark, isTrue); // Dark is the default.
    ThemeModel().dark = false;
    await Future<void>.delayed(Duration.zero);
    final user = LenOSUser();
    final theme = ThemeModel();
    await Future.wait([user.load(), theme.load()]);
    expect(user.name, 'lena');
    expect(theme.mode, ThemeMode.light);
    expect(LenOSUser.validateName('a b'), isNotNull);
    expect(LenOSUser.validateName('a@b'), isNotNull);
    expect(LenOSUser.validateName('lena_2'), isNull);
  });

  group('SettingsPage', () {
    late LenOSUser user;
    late ThemeModel theme;
    late DeviceRegistry devices;
    late TerminalSettings terminal;

    Future<void> pump(WidgetTester tester) async {
      user = LenOSUser();
      theme = ThemeModel();
      devices = DeviceRegistry();
      terminal = TerminalSettings();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: user),
          ChangeNotifierProvider.value(value: terminal),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: devices),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ));
    }

    testWidgets('edits the user name and toggles dark mode', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'lena');
      await tester.pump();
      expect(user.name, 'lena');
      expect(find.text(r'Terminal prompt: lena@LenOS:~$'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'le na');
      await tester.pump();
      expect(user.name, 'lena'); // Invalid input is not applied.
      expect(find.text(r'No spaces or @ : $ / ~'), findsOneWidget);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Dark mode'));
      await tester.pump();
      expect(theme.dark, isFalse); // Was on by default.
    });

    testWidgets('toggles dynamic intervals, which persist', (tester) async {
      await pump(tester);
      expect(terminal.dynamicIntervals, isFalse); // Off by default.
      final tile = find.widgetWithText(SwitchListTile, 'Dynamic intervals');
      await tester.scrollUntilVisible(tile, 100,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.tap(tile);
      await tester.pump();
      expect(terminal.dynamicIntervals, isTrue);
      final reloaded = TerminalSettings();
      await reloaded.load();
      expect(reloaded.dynamicIntervals, isTrue);
    });

    testWidgets('devices list: name and favorite', (tester) async {
      await pump(tester);
      devices
        ..recordScan('04AA', at: DateTime(2026, 1, 1))
        ..recordScan('04BB', at: DateTime(2026, 1, 2));
      await tester.pump();
      expect(find.text('2 devices'), findsOneWidget);

      await tester.tap(find.text('Scanned devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('04AA'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Interface');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(devices.byUid('04AA')!.name, 'Interface');
      expect(find.text('Named'), findsOneWidget);
      // Named device is listed above the unnamed one.
      expect(tester.getTopLeft(find.text('Interface')).dy,
          lessThan(tester.getTopLeft(find.text('04BB')).dy));

      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pump();
      expect(devices.favorites.map((d) => d.uid), ['04BB']);
    });
  });

  test('every top bar uses the Home teal in light and dark mode', () {
    for (final theme in [ThemeModel.light(), ThemeModel.darkTheme()]) {
      expect(theme.appBarTheme.backgroundColor, ThemeModel.appBarColor);
      expect(theme.appBarTheme.foregroundColor, Colors.white);
    }
  });

  test('the Home greeting capitalizes only the first letter', () {
    expect(welcomeTitle('lena'), 'Welcome, Lena');
    expect(welcomeTitle('Lena'), 'Welcome, Lena');
    expect(welcomeTitle('mcLena'), 'Welcome, McLena');
    expect(welcomeTitle('_user2'), 'Welcome, _user2');
  });
}
