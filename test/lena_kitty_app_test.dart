import 'package:flutter/material.dart';
import 'package:flutter_len_os/ascii_cat.dart';
import 'package:flutter_len_os/cat_personality.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/fs/editor_session.dart';
import 'package:flutter_len_os/fs/file_system_model.dart';
import 'package:flutter_len_os/nfc_model.dart';
import 'package:flutter_len_os/settings_page.dart';
import 'package:flutter_len_os/theme_model.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final prefs in <String, Map<String, Object>>{
    'fresh install': {},
    'saved weights + old keys': {
      'lenos.cat.weight.yarnJump': 2.5,
      'lenos.cat.roams': true,
      'lenos.theme.dark': true,
      'lenos.theme.accent': 'custom',
      'lenos.theme.accent.custom': 0xFF12AB34,
      'lenos.theme.topbar': 0xFF262626,
    },
  }.entries) {
    // Uses the same app-wide services as main.dart.
    testWidgets('open Lena Kitty from Settings (${prefs.key})', (tester) async {
      SharedPreferences.setMockInitialValues(prefs.value);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NfcModel()),
          ChangeNotifierProvider(create: (_) => LenOSUser()..load()),
          ChangeNotifierProvider(create: (_) => TerminalSettings()),
          ChangeNotifierProvider(create: (_) => ThemeModel()..load()),
          ChangeNotifierProvider(create: (_) => CatPersonality()..load()),
          Provider(create: (_) => LenaKitty()),
          ChangeNotifierProvider(create: (_) => DeviceRegistry()..load()),
          ChangeNotifierProvider(create: (_) => FileSystemModel()..load()),
          ChangeNotifierProvider(create: (c) => EditorSession(c.read<FileSystemModel>())),
        ],
        child: Builder(builder: (context) {
          final t = context.watch<ThemeModel>();
          return MaterialApp(
            theme: ThemeModel.light(t.accentFor(Brightness.light), t.topBarColor),
            darkTheme: ThemeModel.darkTheme(t.accentFor(Brightness.dark), t.topBarColor),
            themeMode: t.mode,
            home: const SettingsPage(),
          );
        }),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.ensureVisible(find.text('Lena Kitty'));
      await tester.tap(find.text('Lena Kitty'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('At the yarn'), findsOneWidget);
    });
  }
}
