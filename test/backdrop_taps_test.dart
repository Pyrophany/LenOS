import 'package:flutter/material.dart';
import 'package:flutter_len_os/ascii_cat.dart';
import 'package:flutter_len_os/cat_personality.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/settings_page.dart';
import 'package:flutter_len_os/theme_model.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Tapping Lena Kitty behind a page', () {
    late LenaKitty kitty;
    var tileTaps = 0;
    final scroll = ScrollController();

    Future<void> pump(WidgetTester tester, {required int tiles}) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      kitty = LenaKitty();
      tileTaps = 0;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CatPersonality()),
          Provider.value(value: kitty),
        ],
        child: MaterialApp(
          home: Scaffold(
            // A scrolling page, like Settings.
            body: CatBackdrop(
              child: ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < tiles; i++)
                    ListTile(title: Text('Tile $i'), onTap: () => tileTaps++),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      kitty.sim.start(CatAction.sit);
      await tester.pump(const Duration(milliseconds: 50));
    }

    Finder her() => find.textContaining('/\\_/\\');

    testWidgets('a tap on her, in the empty part of the page, reaches her',
        (tester) async {
      await pump(tester, tiles: 3);
      await tester.tap(her());
      await tester.pump(const Duration(milliseconds: 50));
      expect(kitty.sim.action, CatAction.petted);
      expect(tileTaps, 0);
    });

    testWidgets('a list item in front of her still gets its own tap', (tester) async {
      await pump(tester, tiles: 40); // Tiles cover the bottom, where she is.
      final at = tester.getCenter(her());
      final tile = find.byType(ListTile).hitTestable(at: Alignment.center);
      expect(tile, findsWidgets);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tileTaps, 1);
      expect(kitty.sim.action, isNot(CatAction.petted));
    });

    testWidgets('dragging from where she is still scrolls the page', (tester) async {
      await pump(tester, tiles: 40);
      await tester.dragFrom(tester.getCenter(her()), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(scroll.offset, greaterThan(100));
      expect(kitty.sim.action, isNot(CatAction.petted));
    });
  });

  group('Username', () {
    Future<void> pumpSettings(WidgetTester tester, LenOSUser user) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: user),
          ChangeNotifierProvider(create: (_) => TerminalSettings()),
          ChangeNotifierProvider(create: (_) => ThemeModel()),
          ChangeNotifierProvider(create: (_) => DeviceRegistry()),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ));
    }

    String field(WidgetTester tester) => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Username'))
        .controller!
        .text;

    testWidgets('is labelled Username', (tester) async {
      await pumpSettings(tester, LenOSUser());
      expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
      expect(find.text('User name'), findsNothing);
    });

    testWidgets('stays across restarts, even when Settings is built before it loads',
        (tester) async {
      // First run: type a name.
      await pumpSettings(tester, LenOSUser());
      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'lena');
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

      // "Restart": a new user object, with Settings built straight away (as
      // the Settings tab is), before the saved name has loaded.
      await tester.pumpWidget(const SizedBox());
      final user = LenOSUser();
      await pumpSettings(tester, user);
      expect(field(tester), LenOSUser.defaultName);
      await tester.runAsync(user.load);
      await tester.pump();
      expect(field(tester), 'lena');
      expect(find.text(r'Terminal prompt: lena@LenOS:~$'), findsOneWidget);
    });

    testWidgets('typing is not undone by its own save', (tester) async {
      final user = LenOSUser();
      await pumpSettings(tester, user);
      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'len');
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'lena');
      await tester.pump();
      expect(field(tester), 'lena');
      expect(user.name, 'lena');
    });
  });
}
