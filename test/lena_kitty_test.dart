import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_len_os/ascii_cat.dart';
import 'package:flutter_len_os/cat_personality.dart';
import 'package:flutter_len_os/device_registry.dart';
import 'package:flutter_len_os/lena_kitty_page.dart';
import 'package:flutter_len_os/settings_page.dart';
import 'package:flutter_len_os/theme_model.dart';
import 'package:flutter_len_os/terminal_settings.dart';
import 'package:flutter_len_os/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Weights', () {
    test('defaults match the flowchart; chances are per group', () {
      final w = CatWeights.defaults;
      expect(w[CatWeight.yarnJump], 3);
      expect(w.chanceOf(CatWeight.yarnJump), closeTo(3 / 4.5, 1e-9));
      expect(w.chanceOf(CatWeight.idleNap), closeTo(1 / 5.2, 1e-9));
      final none = CatWeight.values
          .where((x) => x.atYarn)
          .fold(w, (acc, x) => acc.withValue(x, 0));
      expect(none.chanceOf(CatWeight.yarnJump), 0);
      expect(w.withValue(CatWeight.idleSit, 99)[CatWeight.idleSit], CatWeight.max);
      expect(w.withValue(CatWeight.idleSit, 2), w); // Same values, equal.
      expect(w == w.withValue(CatWeight.idleSit, 3), isFalse);
      // Comparing with something that isn't a set of weights is just false.
      expect(w == (Object() as dynamic), isFalse);
      CatWeights? never;
      expect(w != never, isTrue);
      expect(w.hashCode, w.withValue(CatWeight.idleSit, 2).hashCode);
    });

    CatSim cat(CatWeights weights) {
      final c = CatSim(charWidth: 7, random: Random(1), behavior: catBehaviorFor(weights))
        ..width = 400;
      c.update(0);
      return c;
    }

    Set<CatAction> picks(CatSim c) => {for (var i = 0; i < 300; i++) c.behavior.choose(c)!};

    test('the tree follows the weights; 0 means never', () {
      var w = CatWeights.defaults
          .withValue(CatWeight.yarnJump, 0)
          .withValue(CatWeight.yarnSit, 0);
      final c = cat(w)..energy = 0.8;
      c.facingRight = true;
      c.x = c.ballX - (c.reach - c.x);
      expect(picks(c), {CatAction.rollOver});

      w = CatWeights.defaults
          .withValue(CatWeight.idleSit, 0)
          .withValue(CatWeight.idleRoll, 0)
          .withValue(CatWeight.idleNap, 0);
      final idle = cat(w)
        ..energy = 0.4
        ..boredom = 0
        ..x = 0
        ..ballX = 300;
      expect(picks(idle), {CatAction.wander});
    });

    test('with every weight at 0 the cat still behaves and stays on screen', () {
      final zero = CatWeight.values.fold(CatWeights.defaults, (w, x) => w.withValue(x, 0));
      final c = CatSim(charWidth: 7, random: Random(2), behavior: catBehaviorFor(zero))
        ..width = 400;
      for (var i = 0; i < 6000; i++) {
        c.update(0.05);
        expect(c.x, inInclusiveRange(0, 400));
      }
      // Never picked by weight; sitting is the fallback.
      expect(c.action, isNot(CatAction.jump));
    });
  });

  group('CatPersonality', () {
    test('changes, saves, loads and resets', () async {
      final p = CatPersonality()..set(CatWeight.idleWander, 4.2);
      expect(p.weights[CatWeight.idleWander], 4.2);
      await p.save();
      final loaded = CatPersonality();
      await loaded.load();
      expect(loaded.weights[CatWeight.idleWander], 4.2);
      loaded.resetToDefaults();
      expect(loaded.weights, CatWeights.defaults);
      await Future<void>.delayed(Duration.zero);
      final again = CatPersonality();
      await again.load();
      expect(again.weights, CatWeights.defaults);
    });
  });

  group('Lena Kitty page', () {
    Future<CatPersonality> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final personality = CatPersonality();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: personality),
          ChangeNotifierProvider(create: (_) => ThemeModel()),
          ChangeNotifierProvider(create: (_) => LenOSUser()),
          ChangeNotifierProvider(create: (_) => TerminalSettings()),
          ChangeNotifierProvider(create: (_) => DeviceRegistry()),
        ],
        child: MaterialApp(theme: ThemeModel.darkTheme(), home: home),
      ));
      return personality;
    }

    testWidgets('Settings opens Lena Kitty', (tester) async {
      await pump(tester, const SettingsPage());
      await tester.ensureVisible(find.text('Lena Kitty'));
      await tester.tap(find.text('Lena Kitty'));
      await tester.pump(); // Starts the page transition.
      // The page's preview cat never stops moving, so wait a fixed time
      // rather than for everything to settle.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LenaKittyPage), findsOneWidget);
    });

    testWidgets('a slider for every weight, with its chance', (tester) async {
      final p = await pump(tester, const LenaKittyPage());
      expect(find.byType(Slider), findsNWidgets(CatWeight.values.length));
      expect(find.text('At the yarn'), findsOneWidget);
      expect(find.text('When idle'), findsOneWidget);
      expect(find.text('3.0 · 67%'), findsOneWidget); // Jump on it.
      expect(find.byType(AsciiCat), findsOneWidget); // The preview.

      // Reset is off until something changes.
      final reset = find.widgetWithText(TextButton, 'Reset');
      expect(tester.widget<TextButton>(reset).onPressed, isNull);

      // Drag "Jump on it" all the way down.
      await tester.drag(find.byType(Slider).first, const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(p.weights[CatWeight.yarnJump], 0);
      expect(find.text('0.0 · 0%'), findsOneWidget);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

      // Saved when the slider is let go.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('lenos.cat.weight.yarnJump'), 0);

      await tester.tap(reset);
      await tester.pump(const Duration(milliseconds: 300));
      expect(p.weights, CatWeights.defaults);
    });
  });

  testWidgets('the cat on screen follows the saved weights', (tester) async {
    Future<bool> jumpsWithin(CatWeights weights) async {
      final personality = CatPersonality();
      for (final w in CatWeight.values) {
        personality.set(w, weights[w]);
      }
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: personality,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(body: Align(
              alignment: Alignment.bottomCenter,
              child: AsciiCat(random: Random(1)),
            )),
          ),
        ),
      ));
      for (var i = 0; i < 2400; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.textContaining('O.O').evaluate().isNotEmpty) return true;
      }
      return false;
    }

    expect(await jumpsWithin(CatWeights.defaults), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(await jumpsWithin(CatWeights.defaults.withValue(CatWeight.yarnJump, 0)), isFalse);
  });

  group('On other pages', () {
    Widget page(CatPersonality p, {VoidCallback? onTap}) => ChangeNotifierProvider.value(
          value: p,
          child: MaterialApp(
            home: Scaffold(
              body: CatBackdrop(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: 80,
                    width: double.infinity,
                    child: TextButton(onPressed: onTap, child: const Text('content')),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('Lena Kitty walks behind the content, which stays tappable',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(page(CatPersonality(), onTap: () => taps++));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AsciiCat), findsOneWidget);
      // The cat is painted first (behind), the content after (on top).
      final stack = tester.widget<Stack>(find
          .ancestor(
            of: find.byType(AsciiCat),
            matching: find.byWidgetPredicate((w) => w is Stack),
          )
          .last);
      expect(stack.children.last, isA<Positioned>());
      await tester.tap(find.text('content'));
      expect(taps, 1);
    });

    testWidgets('can be turned off, and the choice is saved', (tester) async {
      final p = CatPersonality();
      await tester.pumpWidget(page(p));
      expect(find.byType(AsciiCat), findsOneWidget);
      p.roams = false;
      await tester.pump();
      expect(find.byType(AsciiCat), findsNothing);
      expect(find.text('content'), findsOneWidget);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final loaded = CatPersonality();
        await loaded.load();
        expect(loaded.roams, isFalse);
      });
    });

    testWidgets('not shown when the app has no Lena Kitty settings', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CatBackdrop(child: Text('content'))),
      ));
      expect(find.byType(AsciiCat), findsNothing);
    });

    testWidgets('the switch is on the Lena Kitty page', (tester) async {
      final p = CatPersonality();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: p,
        child: MaterialApp(theme: ThemeModel.darkTheme(), home: const LenaKittyPage()),
      ));
      await tester.tap(find.text('Show on other pages'));
      await tester.pump();
      expect(p.roams, isFalse);
    });
  });

  group('One Lena Kitty', () {
    testWidgets('the same cat on every page', (tester) async {
      final kitty = LenaKitty(random: Random(7));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(Provider.value(
        value: kitty,
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: AsciiCat())),
        ),
      ));
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final before = (x: kitty.sim.x, action: kitty.sim.action, clock: kitty.sim.clock);
      expect(before.clock, greaterThan(5)); // She has been busy on the first page.

      // Another page: she carries on where she was, rather than starting over.
      nav.currentState!.push(MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: AsciiCat()),
        ),
      ));
      await tester.pump();
      expect(kitty.sim.x, closeTo(before.x, 5));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(kitty.sim.clock, greaterThan(before.clock));

      // A tap on this page's cat reaches the same Lena Kitty.
      kitty.sim.start(CatAction.sleep);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.textContaining('-.-').last);
      await tester.pump(const Duration(milliseconds: 50));
      expect(kitty.sim.action, CatAction.startled);
    });

    testWidgets('two cats on screen at once do not speed her up', (tester) async {
      Future<double> simulated(int cats) async {
        final kitty = LenaKitty(random: Random(8));
        await tester.pumpWidget(Provider.value(
          value: kitty,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [for (var i = 0; i < cats; i++) const AsciiCat()],
              ),
            ),
          ),
        ));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        return kitty.sim.clock;
      }

      final one = await simulated(1);
      await tester.pumpWidget(const SizedBox());
      final two = await simulated(2);
      expect(two, closeTo(one, 0.2));
      expect(one, closeTo(5, 0.3)); // 100 frames of 50 ms.
    });

    test('resizing keeps her and the yarn on screen', () {
      final c = CatSim(charWidth: 7, random: Random(9))..width = 800;
      c.update(0);
      c
        ..x = 700
        ..ballX = 780
        ..resize(300);
      expect(c.x, lessThanOrEqualTo(300));
      expect(c.ballX, lessThanOrEqualTo(300));
    });
  });
}
