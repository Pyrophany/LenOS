import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_len_os/ascii_cat.dart';
import 'package:flutter_len_os/terminal_style.dart';
import 'package:flutter_len_os/theme_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sprites', () {
    final all = <String, Sprite>{
      'walk A': CatSprites.walk(true, 'o.o'),
      'walk B': CatSprites.walk(false, 'o.o'),
      'jump': CatSprites.jump('O.O'),
      'sit': CatSprites.sit('o.o'),
      'sleep': CatSprites.sleep(),
      'roll A': CatSprites.roll(true),
      'roll B': CatSprites.roll(false),
      'bonked': CatSprites.bonked(),
    };

    test('are all three lines, Whisker-sized', () {
      for (final MapEntry(:key, :value) in all.entries) {
        expect(value, hasLength(3), reason: key);
        expect(value.map((l) => l.length).reduce(max), lessThanOrEqualTo(12), reason: key);
      }
    });

    test('dazed: stars above the sitting cat', () {
      for (final frame in [true, false]) {
        final dazed = CatSprites.dazed(frame);
        expect(dazed, hasLength(4));
        expect(dazed.sublist(1), CatSprites.sit('@.@'));
        expect(dazed.first, contains('*'));
      }
    });

    test('mirror flips direction and back again', () {
      expect(mirrorSprite(CatSprites.walk(true, 'o.o')),
          [r'/\_/\     ', r'(o.o \_/~ ', r'  // \\   ']);
      for (final sprite in all.values) {
        final width = sprite.map((l) => l.length).reduce(max);
        expect(mirrorSprite(mirrorSprite(sprite)),
            [for (final l in sprite) l.padRight(width)]);
      }
    });
  });

  group('Behavior tree', () {
    CatSim cat({int seed = 1}) {
      final c = CatSim(charWidth: 7, random: Random(seed))..width = 400;
      c.update(0); // Places the cat and the yarn.
      return c;
    }

    void putAtYarn(CatSim c) {
      c.facingRight = true;
      c.x = c.ballX - (c.reach - c.x);
      expect(c.atYarn, isTrue);
    }

    Set<CatAction> choices(CatSim c, [int n = 300]) =>
        {for (var i = 0; i < n; i++) c.behavior.choose(c)!};

    test('tired: sleep, whatever else is going on', () {
      final c = cat()
        ..energy = 0.1
        ..ballV = 200;
      putAtYarn(c);
      expect(choices(c), {CatAction.sleep});
    });

    test('at the yarn: mostly jump on it, sometimes roll over or sit', () {
      final c = cat()..energy = 0.8;
      putAtYarn(c);
      final picks = [for (var i = 0; i < 600; i++) c.behavior.choose(c)!];
      expect(picks.toSet(), {CatAction.jump, CatAction.rollOver, CatAction.sit});
      final jumps = picks.where((a) => a == CatAction.jump).length;
      expect(jumps, greaterThan(picks.length * 0.5));

      c.energy = 0.3; // Too tired to roll over.
      expect(choices(c), {CatAction.jump, CatAction.sit});
    });

    test('yarn rolling: chase it', () {
      final c = cat()
        ..energy = 0.8
        ..ballV = 150
        ..x = 0
        ..ballX = 300;
      expect(choices(c), {CatAction.chase});
    });

    test('bored with energy: chase the still yarn', () {
      final c = cat()
        ..energy = 0.8
        ..boredom = 0.9
        ..x = 0
        ..ballX = 300;
      expect(choices(c), {CatAction.chase});
    });

    test('idle: sit, wander, roll over; nap only when getting tired', () {
      final c = cat()
        ..energy = 0.8
        ..boredom = 0.1
        ..x = 0
        ..ballX = 300;
      expect(choices(c), {CatAction.sit, CatAction.wander, CatAction.rollOver});
      c.energy = 0.4;
      expect(choices(c), {CatAction.sit, CatAction.wander, CatAction.sleep});
    });
  });

  group('Simulation', () {
    test('sleeping restores energy, then the cat wakes up', () {
      final c = CatSim(charWidth: 7, random: Random(2))..width = 400;
      c.update(0);
      c
        ..energy = 0.1
        ..start(CatAction.sleep);
      for (var i = 0; i < 400 && c.action == CatAction.sleep; i++) {
        c.update(0.05);
      }
      expect(c.action, isNot(CatAction.sleep));
      expect(c.energy, closeTo(1, 0.05));
    });

    test('a jump at the yarn bats it away and makes the cat happy', () {
      final c = CatSim(charWidth: 7, random: Random(3))..width = 400;
      c.update(0);
      c.facingRight = true;
      c.x = c.ballX - (c.reach - c.x);
      c.start(CatAction.jump);
      for (var i = 0; i < 12; i++) {
        c.update(0.05);
      }
      expect(c.ballV, isNot(0));
      expect(c.happy, greaterThan(0));
      expect(c.boredom, lessThan(0.05)); // Reset by playing.
    });

    test('a chase ends at the yarn', () {
      final c = CatSim(charWidth: 7, random: Random(4))..width = 400;
      c.update(0);
      c
        ..x = 0
        ..ballX = 350
        ..start(CatAction.chase);
      for (var i = 0; i < 200 && c.action == CatAction.chase; i++) {
        c.update(0.05);
      }
      expect(c.action, isNot(CatAction.chase));
      expect(c.distanceToYarn.abs(), lessThan(20));
    });

    test('over ten minutes it does everything and stays on screen', () {
      for (final seed in [1, 2, 3]) {
        final c = CatSim(charWidth: 7, random: Random(seed))..width = 400;
        final seen = <CatAction>{};
        for (var i = 0; i < 12000; i++) {
          c.update(0.05);
          seen.add(c.action);
          expect(c.x, inInclusiveRange(0, 400), reason: 'seed $seed');
          expect(c.ballX, inInclusiveRange(0, 400), reason: 'seed $seed');
          expect(c.energy, inInclusiveRange(0, 1));
          expect(c.sprite, hasLength(3));
        }
        // Everything except the reactions to taps and bonks, which only the
        // user triggers.
        expect(seen, CatAction.values.toSet()
          ..removeAll([CatAction.startled, CatAction.petted, CatAction.bonked]),
            reason: 'seed $seed');
      }
    });

    test('sleeping shows z\'s that always read "zZ", on either side', () {
      final c = CatSim(charWidth: 7, random: Random(5))..width = 400;
      c.update(0);
      c.start(CatAction.sleep);
      for (final right in [true, false]) {
        c.facingRight = right;
        for (var i = 0; i < 30; i++) {
          c.update(0.05);
          final top = c.sprite.first;
          expect(top.contains('Zz'), isFalse);
          expect(top.contains('z'), isTrue);
        }
      }
    });
  });

  group('Tapping', () {
    CatSim awake() {
      final c = CatSim(charWidth: 7, random: Random(6))..width = 400;
      c.update(0);
      return c;
    }

    test('a sleeping cat is startled, then sits grumpily', () {
      final c = awake()..start(CatAction.sleep);
      c.poke();
      expect(c.action, CatAction.startled);
      c.update(0.2);
      expect(c.hop, greaterThan(0));
      expect(c.sprite.first, contains('!'));
      expect(c.sprite[1], contains('O.O'));
      c.poke(); // Ignored while startled.
      expect(c.action, CatAction.startled);
      for (var i = 0; i < 20; i++) {
        c.update(0.05);
      }
      expect(c.action, CatAction.sit);
      expect(c.sprite[1], contains('-_-'));
    });

    test('an awake cat is petted: purrs, then sometimes rolls over', () {
      var rolled = 0;
      for (var seed = 0; seed < 40; seed++) {
        final c = CatSim(charWidth: 7, random: Random(seed))..width = 400;
        c.update(0);
        c
          ..start(CatAction.wander)
          ..poke();
        expect(c.action, CatAction.petted);
        final notes = <String>{};
        for (var i = 0; i < 45; i++) {
          c.update(0.05);
          if (c.action == CatAction.petted) {
            notes.add(c.note!);
            expect(c.sprite.first, contains(c.note!));
            expect(c.sprite[1], contains('^.^'));
          }
        }
        // One response for the whole petting; it doesn't flash between several.
        expect(notes, hasLength(1));
        expect(CatSim.pettedResponses, contains(notes.single));
        expect(c.action, isNot(CatAction.petted));
        if (c.action == CatAction.rollOver) rolled++;
      }
      expect(rolled, inInclusiveRange(4, 30));
    });

    test('petting again keeps it purring', () {
      final c = awake()..poke();
      for (var i = 0; i < 30; i++) {
        c.update(0.05);
        c.poke();
      }
      expect(c.action, CatAction.petted);
    });

    test('notes read the right way round when facing left', () {
      final c = awake()
        ..facingRight = false
        ..poke();
      c.update(0.05);
      final top = c.sprite.first;
      expect(top.startsWith(c.note!), isTrue);
    });

    group('Dragging the yarn', () {
      /// Holds the yarn right above her head, centered on it.
      CatSim holdOverHead(CatSim c, {double above = 30}) {
        c.start(CatAction.sit);
        c.update(0.01);
        final (l, r) = c.headSpan;
        c.grabYarn();
        c.moveYarn(Offset((l + r) / 2 - c.charWidth / 2, c.catRect.bottom + above));
        return c;
      }

      test('a held yarn follows the finger and stays put', () {
        final c = awake()..grabYarn();
        c.moveYarn(const Offset(120, 40));
        c.update(0.5);
        expect(c.ballX, 120);
        expect(c.ballY, 40);
        expect(c.ballHop, 40);
        expect(c.yarnRolling, isTrue, reason: 'she wants it');
      });

      test('a held yarn stays on screen', () {
        final c = awake()..grabYarn();
        c.moveYarn(const Offset(-50, -20));
        expect((c.ballX, c.ballY), (0, 0));
        c.moveYarn(const Offset(9999, 40));
        expect(c.ballX, 400 - c.charWidth);
      });

      test('dropped away from her, it falls, bounces and comes to rest', () {
        final c = awake()..grabYarn();
        final far = c.catRect.center.dx < 200 ? 380.0 : 10.0;
        c.moveYarn(Offset(far, 60));
        c.dropYarn();
        for (var i = 0; i < 200; i++) {
          c.update(0.02);
        }
        expect(c.ballY, 0);
        expect(c.ballVy, 0);
        expect(c.action, isNot(CatAction.bonked));
      });

      test('a thrown yarn flies sideways', () {
        final c = awake()..grabYarn();
        c.moveYarn(const Offset(200, 40));
        c.dropYarn(const Offset(300, 200));
        c.update(0.05);
        expect(c.ballX, greaterThan(200));
        expect(c.ballY, greaterThan(40));
      });

      test('dropped on her head: bonk! Squashed, then seeing stars, then grumpy',
          () {
        final c = holdOverHead(awake());
        c.dropYarn();
        for (var i = 0; i < 30 && c.action != CatAction.bonked; i++) {
          c.update(0.02);
        }
        expect(c.action, CatAction.bonked);
        expect(c.sprite.join(), contains('>o<'));
        // The yarn bounces off, and "bonk!" pops off her head.
        expect(c.ballVy, greaterThan(0));
        expect(c.toys.toys.map((t) => t.text), contains('bonk!'));

        c.update(0.3);
        expect(c.sprite, hasLength(4));
        expect(c.sprite.join(), contains('@.@'));
        expect(c.sprite.first, contains('*'));

        for (var i = 0; i < 120; i++) {
          c.update(0.02);
        }
        expect(c.action, CatAction.sit);
        expect(c.sprite.join(), contains('-_-'));
      });

      test('bonks work facing left too, and on a sleeping cat', () {
        final c = awake()
          ..facingRight = false
          ..start(CatAction.sleep);
        c.update(0.01);
        final (l, r) = c.headSpan;
        c.grabYarn();
        c.moveYarn(Offset((l + r) / 2 - c.charWidth / 2, c.catRect.bottom + 20));
        c.dropYarn();
        for (var i = 0; i < 30 && c.action != CatAction.bonked; i++) {
          c.update(0.02);
        }
        expect(c.action, CatAction.bonked);
      });

      test('missing her head: no bonk', () {
        final c = awake();
        c.start(CatAction.sit);
        c.update(0.01);
        final (_, r) = c.headSpan;
        c.grabYarn();
        c.moveYarn(Offset(r + 3 * c.charWidth, 60));
        c.dropYarn();
        for (var i = 0; i < 60; i++) {
          c.update(0.02);
        }
        expect(c.action, isNot(CatAction.bonked));
      });

      test('she does not bat a yarn held over her', () {
        final c = holdOverHead(awake(), above: 5);
        c.x = c.ballX - (c.reach - c.x);
        c.start(CatAction.jump);
        for (var i = 0; i < 30; i++) {
          c.update(0.02);
        }
        expect(c.yarnHeld, isTrue);
        expect(c.ballV, 0);
      });
    });

    test('tapping the yarn flicks it', () {
      final c = awake();
      expect(c.yarnRolling, isFalse);
      c.flickYarn();
      expect(c.yarnRolling, isTrue);
    });
  });

  group('Widget', () {
    Widget app({bool reduceMotion = false, bool tickers = true, VoidCallback? onTap}) =>
        MaterialApp(
          theme: ThemeModel.darkTheme(AccentColor.pink.onDark),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduceMotion),
            child: TickerMode(
              enabled: tickers,
              child: Scaffold(
                body: Stack(
                  children: [
                    // Something underneath the cat, to check taps pass through.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 52,
                      child: TextButton(onPressed: onTap, child: const SizedBox.expand()),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AsciiCat(random: Random(1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    Finder catText(String part) => find.textContaining(part);

    testWidgets('plays on screen: jumps, rolls over and naps', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 16));
      final seen = <String>{};
      for (var i = 0; i < 2400; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        for (final face in ['O.O', '^.^', '-.-', 'zZ', '(")(")']) {
          if (catText(face).evaluate().isNotEmpty) seen.add(face);
        }
      }
      expect(seen, containsAll(['O.O', '^.^', '(")(")']));
      expect(find.text('@'), findsOneWidget);
    });

    testWidgets('is drawn in the accent color', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 16));
      final text = tester.widget<Text>(find.textContaining('/\\_/\\'));
      expect(text.style!.color, AccentColor.pink.onDark);
      expect(text.style!.color,
          TerminalStyle.of(tester.element(find.textContaining('/\\_/\\'))).accent);
    });

    testWidgets('tapping the cat makes it react; taps elsewhere pass through',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(app(onTap: () => taps++));
      await tester.pump(const Duration(milliseconds: 16));

      final cat = find.textContaining('/\\_/\\');
      final catRect = tester.getRect(cat);
      final yarnRect = tester.getRect(find.text('@'));
      // Somewhere in the strip that is neither the cat nor the yarn.
      final screen = tester.getSize(find.byType(Scaffold));
      var empty = Offset(screen.width - 5, screen.height - 20);
      for (final x in [5.0, screen.width / 2, screen.width - 5]) {
        final p = Offset(x, screen.height - 20);
        if (!catRect.inflate(10).contains(p) && !yarnRect.inflate(16).contains(p)) empty = p;
      }
      await tester.tapAt(empty);
      expect(taps, 1);

      await tester.tap(cat);
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 1); // The tap went to the cat, not the button below.
      expect([...CatSim.pettedResponses, '!']
          .any((r) => find.textContaining(r).evaluate().isNotEmpty), isTrue);
      expect(
        find.ancestor(of: find.text('@'), matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
    });

    testWidgets('sleeps when reduce motion is on, and purrs when tapped',
        (tester) async {
      await tester.pumpWidget(app(reduceMotion: true));
      expect(catText('-.-'), findsOneWidget);
      expect(catText('zZ'), findsOneWidget);
      expect(find.text('@'), findsNothing);
      await tester.pumpAndSettle(); // Nothing keeps animating.

      await tester.tap(catText('zZ'));
      await tester.pump();
      expect(catText('<3'), findsOneWidget);
      expect(catText('^.^'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(catText('zZ'), findsOneWidget);
    });

    testWidgets('the yarn can be dragged and dropped on her head',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(app(onTap: () => taps++));
      await tester.pump(const Duration(milliseconds: 16));
      final yarn = find.text('@');
      final start = tester.getCenter(yarn);

      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      // Lifted up off the ground with the finger.
      expect(tester.getCenter(yarn).dy, closeTo(start.dy - 100, 1));

      // Over her head, then let go.
      final head = tester.getRect(find.textContaining(r'/\_/\'));
      await gesture.moveTo(Offset(head.center.dx, head.top - 40));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.textContaining('@.@'), findsOneWidget);
      expect(find.text('bonk!'), findsOneWidget);
      expect(taps, 0, reason: 'the drag was not a tap on the page');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('stops animating when its tab is hidden', (tester) async {
      await tester.pumpWidget(app(tickers: false));
      await tester.pump(const Duration(milliseconds: 16));
      final before = tester.getTopLeft(find.textContaining('/\\_/\\'));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getTopLeft(find.textContaining('/\\_/\\')), before);
      await tester.pumpAndSettle();
    });
  });
}
