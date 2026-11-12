import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_len_os/ascii_cat.dart';
import 'package:flutter_len_os/cat_toys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lineHeight = 13.2;
  const charWidth = 7.0;

  CatToy toy(double x, double y, {String text = '<3'}) => CatToy(
        text: text,
        x: x,
        y: y,
        width: text.length * charWidth,
        height: lineHeight,
      );

  /// Runs [toys] for [seconds] in a 400 × 76 strip with her at [cat].
  void run(CatToys toys, double seconds, {Rect cat = const Rect.fromLTWH(1000, 0, 0, 0)}) {
    for (var t = 0.0; t < seconds; t += 0.02) {
      toys.step(0.02, width: 400, height: 76, cat: cat);
    }
  }

  group('One response per tap', () {
    CatSim awake() {
      final c = CatSim(charWidth: charWidth, random: Random(1))..width = 400;
      c.update(0);
      return c..start(CatAction.wander);
    }

    test('the response stays the same until the next tap', () {
      final c = awake()..poke();
      final first = c.note;
      expect(CatSim.pettedResponses, contains(first));
      for (var i = 0; i < 30; i++) {
        c.update(0.05);
        if (c.action == CatAction.petted) {
          expect(c.note, first);
          expect(c.sprite.first, contains(first!));
        }
      }
    });

    test('each new tap gives a different response', () {
      final c = awake();
      String? previous;
      for (var i = 0; i < 20; i++) {
        c.poke();
        expect(c.note, isNot(previous));
        previous = c.note;
        c.update(2); // Far enough apart not to start a streak.
      }
    });
  });

  group('Taps in a row', () {
    CatSim cat() {
      final c = CatSim(charWidth: charWidth, random: Random(2))
        ..width = 400
        ..height = 76;
      c.update(0);
      return c..start(CatAction.sit);
    }

    test('the third tap in a row turns responses into toys', () {
      final c = cat();
      c.poke();
      c.update(0.3);
      c.poke();
      c.update(0.3);
      expect(c.toys.toys, isEmpty);
      expect(c.note, isNotNull);

      c.poke();
      expect(c.tapStreak, 3);
      expect(c.toys.toys, hasLength(1));
      expect(c.note, isNull); // It flew off instead.
      c.update(0.3);
      c.poke();
      expect(c.toys.toys, hasLength(2));
    });

    test('slow taps never make toys; a pause starts a new streak', () {
      final c = cat();
      for (var i = 0; i < 6; i++) {
        c.poke();
        c.update(1.5);
      }
      expect(c.toys.toys, isEmpty);
      expect(c.tapStreak, 1);
    });

    test('a woken cat\'s "!" can become a toy too', () {
      final c = cat()..start(CatAction.sleep);
      for (var i = 0; i < 3; i++) {
        c.poke();
        c.update(0.2);
      }
      expect(c.toys.toys.map((t) => t.text), ['!']);
    });

    test('toys pile up on her and around her, then vanish after 20 seconds', () {
      final c = cat();
      for (var i = 0; i < 8; i++) {
        c.poke();
        c.update(0.25);
      }
      expect(c.toys.toys, hasLength(6));
      for (var i = 0; i < 100; i++) {
        c.update(0.05);
      }
      final her = c.catRect;
      for (final t in c.toys.toys) {
        expect(t.x, inInclusiveRange(0, 400 - t.width));
        expect(t.y, inInclusiveRange(0, 76 - t.height));
        // Nothing is stuck inside her.
        expect(t.rect.overlaps(her.deflate(1)), isFalse);
      }
      // Still there at 15 seconds...
      for (var i = 0; i < 180; i++) {
        c.update(0.05);
      }
      expect(c.toys.toys, isNotEmpty);
      // ...gone by 20 after the last one appeared.
      for (var i = 0; i < 120; i++) {
        c.update(0.05);
      }
      expect(c.toys.toys, isEmpty);
    });
  });

  group('Physics', () {
    test('a toy falls to the floor and comes to rest', () {
      final toys = CatToys()..spawn(toy(100, 60)..vx = 80);
      run(toys, 3);
      final t = toys.toys.single;
      expect(t.y, closeTo(0, 0.5));
      expect(t.vx, 0);
      expect(t.vy.abs(), lessThan(5));
    });

    test('toys stack on each other', () {
      final toys = CatToys()
        ..spawn(toy(100, 10))
        ..spawn(toy(100, 30))
        ..spawn(toy(100, 50));
      run(toys, 3);
      final heights = toys.toys.map((t) => t.y).toList()..sort();
      expect(heights[0], closeTo(0, 0.5));
      expect(heights[1], closeTo(lineHeight, 0.5));
      expect(heights[2], closeTo(2 * lineHeight, 0.5));
    });

    test('a toy dropped on her rests on top of her', () {
      const her = Rect.fromLTWH(90, 0, 70, 40);
      final toys = CatToys()..spawn(toy(110, 60));
      run(toys, 2, cat: her);
      expect(toys.toys.single.y, closeTo(40, 0.5));
    });

    test('she pushes toys out of the way when she moves into them', () {
      final toys = CatToys()..spawn(toy(100, 0));
      run(toys, 0.5);
      // She walks right, into the toy.
      for (var left = 20.0; left < 90; left += 2) {
        toys.step(0.02, width: 400, height: 76, cat: Rect.fromLTWH(left, 0, 70, 40));
      }
      final t = toys.toys.single;
      expect(t.rect.overlaps(const Rect.fromLTWH(88, 0, 70, 40).deflate(1)), isFalse);
    });

    test('they fade out at the end and disappear at 20 seconds', () {
      expect(CatToys.lifetime, 20);
      final toys = CatToys()..spawn(toy(100, 0));
      run(toys, 15);
      expect(toys.toys.single.opacity, 1);
      run(toys, 4.6);
      expect(toys.toys.single.opacity, lessThan(1));
      run(toys, 0.6);
      expect(toys.toys, isEmpty);
    });

    test('toys on her bounce off when she jumps', () {
      const ground = Rect.fromLTWH(90, 0, 70, 40);
      final toys = CatToys()
        ..spawn(toy(95, 60))
        ..spawn(toy(140, 80));
      run(toys, 2, cat: ground);
      for (final t in toys.toys) {
        expect(t.y, closeTo(40, 0.5)); // Resting on her.
      }
      // She jumps: up 14 px over a quarter of a second.
      var top = 0.0;
      final fastest = {for (final t in toys.toys) t: 0.0};
      for (var i = 0; i < 12; i++) {
        top += 14 / 12;
        toys.step(0.02,
            width: 400,
            height: 200,
            cat: Rect.fromLTWH(90, top, 70, 40),
            catVelocity: const Offset(0, 14 / 0.24));
        for (final t in toys.toys) {
          fastest[t] = max(fastest[t]!, t.vy);
        }
      }
      for (final t in toys.toys) {
        expect(fastest[t], greaterThan(150), reason: 'thrown up');
        expect(t.y, greaterThan(40 + top), reason: 'off her, in the air');
      }
      // Thrown away from her middle, to either side.
      final left = toys.toys.firstWhere((t) => t.x < 110);
      final right = toys.toys.firstWhere((t) => t.x >= 110);
      expect(left.vx, lessThan(0));
      expect(right.vx, greaterThan(0));
    });

    test('a stack on her is carried up together', () {
      final toys = CatToys()
        ..spawn(toy(110, 45))
        ..spawn(toy(110, 70));
      run(toys, 2, cat: const Rect.fromLTWH(90, 0, 70, 40));
      toys.step(0.02,
          width: 400,
          height: 200,
          cat: const Rect.fromLTWH(90, 2, 70, 40),
          catVelocity: const Offset(0, 80));
      for (final t in toys.toys) {
        expect(t.vy, greaterThan(100));
      }
    });

    test('toys on her stay put while she only walks', () {
      final toys = CatToys()..spawn(toy(110, 60));
      run(toys, 2, cat: const Rect.fromLTWH(90, 0, 70, 40));
      toys.step(0.02,
          width: 400,
          height: 76,
          cat: const Rect.fromLTWH(91, 0, 70, 40),
          catVelocity: const Offset(50, 0));
      expect(toys.toys.single.vy.abs(), lessThan(20));
    });

    test('a jump in the full app sends a toy flying', () {
      final c = CatSim(charWidth: charWidth, random: Random(4))
        ..width = 400
        ..height = 76;
      c.update(0);
      c.start(CatAction.sit);
      c.toys.spawn(toy(c.catRect.left + 10, 70));
      for (var i = 0; i < 40; i++) {
        c.update(0.05); // It lands on her.
      }
      c.start(CatAction.jump);
      var maxVy = 0.0;
      for (var i = 0; i < 10; i++) {
        c.update(0.05);
        maxVy = max(maxVy, c.toys.toys.single.vy);
      }
      expect(maxVy, greaterThan(100));
    });

    test('never more than the cap; the oldest go first', () {
      final toys = CatToys();
      for (var i = 0; i < CatToys.maxToys + 20; i++) {
        toys.spawn(toy((i * 9) % 380, 60, text: '$i'));
      }
      expect(toys.toys, hasLength(CatToys.maxToys));
      expect(toys.toys.first.text, '20');
    });
  });

  testWidgets('three quick taps on screen make toys that pile up, then vanish',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: AsciiCat(random: Random(3))),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    Finder cat() => find.textContaining('/\\_/\\');
    for (var i = 0; i < 4; i++) {
      await tester.tap(cat());
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Two flying responses, drawn as their own text, not taking taps.
    final toyTexts = find.byWidgetPredicate((w) =>
        w is Text &&
        [...CatSim.pettedResponses, '!'].contains(w.data) &&
        true);
    expect(toyTexts, findsNWidgets(2));
    expect(find.ancestor(of: toyTexts.first, matching: find.byType(IgnorePointer)),
        findsWidgets);

    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(toyTexts, findsNWidgets(2)); // Still there after 15 seconds.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(toyTexts, findsNothing); // Gone after 20.
  });
}
