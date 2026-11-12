import 'dart:math';

import 'package:flutter/painting.dart';

/// One of Lena Kitty's responses turned into a physics object (a "toy"):
/// a small box of text that falls, bounces, slides and stacks.
///
/// Coordinates are in pixels, with y measured up from the bottom of her
/// strip (as `Positioned.bottom` uses).
class CatToy {
  CatToy({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.vx = 0,
    this.vy = 0,
  });

  final String text;
  final double width;
  final double height;
  double x;
  double y;
  double vx;
  double vy;

  /// Seconds since it appeared.
  double age = 0;

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  /// Fades out over the last second of its life.
  double get opacity => ((CatToys.lifetime - age) / 1.0).clamp(0.0, 1.0);
}

/// The toys, and the physics that move them: gravity, the floor, walls and
/// ceiling of the strip, each other, and Lena Kitty herself (an obstacle
/// that can push and lift them).
class CatToys {
  static const lifetime = 20.0;
  static const maxToys = 50;

  /// How much harder than her own jump a toy is thrown when she jumps into it.
  static const jumpBoost = 1.8;

  /// Extra upward speed given to a toy she jumps into, so even a small hop
  /// sends it flying.
  static const jumpKick = 110.0;
  static const gravity = 700.0;

  final List<CatToy> toys = [];

  void spawn(CatToy toy) {
    toys.add(toy);
    // Too many: the oldest goes first.
    while (toys.length > maxToys) {
      toys.removeAt(0);
    }
  }

  /// Moves everything on by [dt] seconds inside a [width] × [height] strip,
  /// with Lena Kitty occupying [cat] and moving at [catVelocity] (pixels per
  /// second, y up): when she jumps, toys on her or in her way bounce off.
  void step(
    double dt, {
    required double width,
    required double height,
    required Rect cat,
    Offset catVelocity = Offset.zero,
  }) {
    if (toys.isEmpty) return;
    for (final t in toys) {
      t.age += dt;
    }
    toys.removeWhere((t) => t.age >= lifetime);
    if (dt <= 0) return;

    // Small substeps keep fast toys from passing through each other.
    const substeps = 4;
    final h = dt / substeps;
    for (var s = 0; s < substeps; s++) {
      for (final t in toys) {
        t.vy -= gravity * h;
        t.x += t.vx * h;
        t.y += t.vy * h;
      }
      // A few passes let a stack settle from the bottom up.
      for (var pass = 0; pass < 3; pass++) {
        toys.sort((a, b) => a.y.compareTo(b.y));
        for (final t in toys) {
          _bounds(t, width, height);
          _pushOut(t, cat, catVelocity);
        }
        for (var i = 0; i < toys.length; i++) {
          for (var j = i + 1; j < toys.length; j++) {
            _separate(toys[i], toys[j]);
          }
        }
      }
    }
  }

  static void _bounds(CatToy t, double width, double height) {
    if (t.y < 0) {
      t.y = 0;
      _land(t);
    }
    if (t.y + t.height > height) {
      t.y = max(0, height - t.height);
      if (t.vy > 0) t.vy = 0;
    }
    final right = max(0.0, width - t.width);
    if (t.x < 0) {
      t.x = 0;
      t.vx = t.vx.abs() * 0.4;
    } else if (t.x > right) {
      t.x = right;
      t.vx = -t.vx.abs() * 0.4;
    }
  }

  /// Something solid is underneath: a small bounce when falling fast,
  /// otherwise come to rest, with friction on the sideways slide.
  static void _land(CatToy t) {
    t.vy = t.vy < -120 ? -t.vy * 0.25 : 0;
    t.vx *= 0.85;
    if (t.vx.abs() < 2) t.vx = 0;
  }

  /// Lena Kitty doesn't move for toys: they are pushed out of her, the short
  /// way. Landing on her makes them ride along on top; when she jumps, they
  /// bounce off her and fly.
  static void _pushOut(CatToy t, Rect cat, Offset catVelocity) {
    final r = t.rect;
    if (!r.overlaps(cat)) return;
    final overlapX = min(r.right, cat.right) - max(r.left, cat.left);
    final overlapY = min(r.top + r.height, cat.top + cat.height) - max(r.top, cat.top);
    // In this space, "top" is the bottom edge (y is measured upwards).
    if (overlapY <= overlapX) {
      if (r.center.dy >= cat.center.dy) {
        t.y = cat.top + cat.height; // On top of her.
        if (catVelocity.dy > 20) {
          // She is jumping: send it flying, away from her middle.
          t.vy = max(t.vy, catVelocity.dy * jumpBoost + jumpKick);
          final away = r.center.dx >= cat.center.dx ? 1.0 : -1.0;
          t.vx += away * 50 + catVelocity.dx * 0.5;
        } else {
          _land(t);
        }
      } else {
        t.y = max(0, cat.top - t.height);
        if (t.vy > 0) t.vy = 0;
      }
    } else {
      final pushRight = r.center.dx >= cat.center.dx;
      t.x = pushRight ? cat.right : cat.left - t.width;
      t.vx = (pushRight ? 1 : -1) * max(t.vx.abs() * 0.4, 20);
    }
  }

  /// Two toys overlapping: the upper one rests on the lower, or they are
  /// pushed apart sideways.
  static void _separate(CatToy a, CatToy b) {
    final ra = a.rect;
    final rb = b.rect;
    if (!ra.overlaps(rb)) return;
    final overlapX = min(ra.right, rb.right) - max(ra.left, rb.left);
    final overlapY = min(a.y + a.height, b.y + b.height) - max(a.y, b.y);
    if (overlapY <= overlapX) {
      final (lower, upper) = a.y <= b.y ? (a, b) : (b, a);
      upper.y = lower.y + lower.height;
      if (lower.vy > 0 && lower.vy > upper.vy) {
        // Thrown upwards from below (e.g. by her jump): carried along.
        upper.vy = lower.vy * 0.9;
      } else {
        _land(upper);
      }
    } else {
      final (left, right) = ra.center.dx <= rb.center.dx ? (a, b) : (b, a);
      final push = overlapX / 2;
      left.x -= push;
      right.x += push;
      final v = (left.vx - right.vx) * 0.5;
      if (v > 0) {
        left.vx -= v;
        right.vx += v;
      }
    }
  }
}
