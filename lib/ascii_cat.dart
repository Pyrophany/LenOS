import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'cat_personality.dart';
import 'cat_toys.dart';
import 'terminal_style.dart';

// ---------------------------------------------------------------------------
// Sprites ("Whisker"). All are drawn facing right; [mirrorSprite] makes the
// left-facing ones. Every sprite is three lines, except the dazed one after
// a bonk, which has a line of stars above.
// ---------------------------------------------------------------------------

typedef Sprite = List<String>;

abstract final class CatSprites {
  static Sprite walk(bool stepA, String eyes) => [
    r'     /\_/\',
    ' ~\\_/ $eyes)',
    stepA ? r'   // \\' : r'   \\ //',
  ];

  /// Mid-air: stretched out, front paws reaching.
  static Sprite jump(String eyes) => [
    r'       /\_/\',
    ' ~\\___/ $eyes)',
    r'  //    \\',
  ];

  static Sprite sit(String eyes) => [r'   /\_/\', '  ( $eyes )', r' ~(_| |_)'];

  /// Curled up. The z's are added after mirroring so they always read "zZ".
  static Sprite sleep() => [r'   /\_/\', ' ~( -.- )', '  (_____)'];

  /// Woken with a fright: wide eyes, legs splayed.
  static Sprite startled() => [r'   /\_/\', ' ~( O.O )', r'  /|   |\'];

  /// On its back, paws up, ears (upside down) at the bottom; two frames that
  /// wiggle the paws and swish the tail.
  static Sprite roll(bool frameA) => frameA
      ? ['  (")(")', ' ~( ^.^ )', r'   \/_\/']
      : [' (") (")', '  ( ^.^ )~', r'   \/_\/'];

  /// The moment the yarn lands on her head: ears flattened, eyes squeezed.
  static Sprite bonked() => ['   ^___^', '  ( >o< )', r' ~(_| |_)'];

  /// Seeing stars after a bonk; the stars twinkle between two frames.
  static Sprite dazed(bool frameA) => [
    frameA ? '  *  +  *' : '  +  *  +',
    r'   /\_/\',
    '  ( @.@ )',
    r' ~(_| |_)',
  ];
}

const _mirrorChars = {'/': r'\', r'\': '/', '(': ')', ')': '('};

/// [sprite] facing the other way: lines padded to the same width, reversed,
/// and slashes and brackets swapped.
Sprite mirrorSprite(Sprite sprite) {
  final width = sprite.map((l) => l.length).reduce(max);
  return [
    for (final line in sprite)
      line
          .padRight(width)
          .split('')
          .reversed
          .map((c) => _mirrorChars[c] ?? c)
          .join(),
  ];
}

// ---------------------------------------------------------------------------
// The cat's brain: a behavior tree.
//
// Each time the current action finishes, the tree is walked from the top and
// the first branch whose condition holds picks the next action:
//
//   ┌───────────────────────────────┐
//   │      What should I do next?   │
//   └───────────────┬───────────────┘
//                   ▼
//   energy < 0.2 ? ──yes──▶ SLEEP (until fully rested)
//        │ no
//        ▼
//   at the yarn ? ──yes──▶ pick by chance:  JUMP on it      (3)
//        │ no                               ROLL OVER       (1, if energy > 0.4)
//        │                                  SIT and watch   (0.5)
//        ▼
//   yarn rolling ? ──yes──▶ CHASE it
//        │ no
//        ▼
//   bored and energy > 0.35 ? ──yes──▶ CHASE the yarn (to play)
//        │ no
//        ▼
//   idle, by chance:  SIT and blink   (2)
//                     WANDER          (1.5)
//                     ROLL OVER       (0.7, if energy > 0.5)
//                     NAP             (1, if energy < 0.45)
//
// Energy drains while moving and playing and refills while sleeping (and a
// little while sitting). Boredom grows while idle and resets after playing.
// A JUMP that lands at the yarn bats it away, which sets up the next CHASE.
//
// Tapping the cat interrupts whatever it is doing (see [CatSim.poke]):
//
//   asleep ? ──yes──▶ STARTLED (hop, "!"), then a grumpy SIT (-_-)
//      │ no
//      ▼
//   PETTED (purrs "prr <3"), then sometimes ROLL OVER, else back to the tree
//
// Tapping the yarn flicks it, which the cat will usually CHASE. Dragging it
// picks it up (she follows it around); letting go drops or throws it, and if
// it lands on her head she is BONKED: squashed, then dazed and seeing stars,
// then a grumpy SIT.
// ---------------------------------------------------------------------------

enum CatAction {
  sleep,
  chase,
  jump,
  rollOver,
  sit,
  wander,

  /// Reactions to being tapped; never chosen by the tree.
  startled,
  petted,

  /// The yarn was dropped on her head; never chosen by the tree.
  bonked,
}

/// A node of the behavior tree: returns an action, or null to let the next
/// branch decide.
abstract class CatNode {
  const CatNode();
  CatAction? choose(CatSim cat);
}

/// Tries its children in order; the first that chooses wins.
class Selector extends CatNode {
  const Selector(this.children);
  final List<CatNode> children;

  @override
  CatAction? choose(CatSim cat) {
    for (final child in children) {
      final action = child.choose(cat);
      if (action != null) return action;
    }
    return null;
  }
}

/// Runs [child] only when [condition] holds.
class Guard extends CatNode {
  const Guard(this.condition, this.child);
  final bool Function(CatSim cat) condition;
  final CatNode child;

  @override
  CatAction? choose(CatSim cat) => condition(cat) ? child.choose(cat) : null;
}

/// Picks one action at random, in proportion to the weights (which may
/// depend on the cat, and be 0 to rule an option out).
class Weighted extends CatNode {
  const Weighted(this.options);
  final List<(CatAction, double Function(CatSim cat))> options;

  @override
  CatAction? choose(CatSim cat) {
    final weights = [for (final (_, w) in options) max(0.0, w(cat))];
    final total = weights.fold(0.0, (a, b) => a + b);
    if (total <= 0) return null;
    var pick = cat.random.nextDouble() * total;
    for (var i = 0; i < options.length; i++) {
      pick -= weights[i];
      if (pick <= 0) return options[i].$1;
    }
    return options.last.$1;
  }
}

/// Always chooses [action].
class Do extends CatNode {
  const Do(this.action);
  final CatAction action;

  @override
  CatAction? choose(CatSim cat) => action;
}

/// The weighted choices in the tree, adjustable in Settings → Lena Kitty.
enum CatWeight {
  yarnJump('Jump on it', 3, atYarn: true),
  yarnRoll('Roll over', 1, atYarn: true, note: 'only with energy to spare'),
  yarnSit('Sit and watch', 0.5, atYarn: true),
  idleSit('Sit and blink', 2),
  idleWander('Wander', 1.5),
  idleRoll('Roll over', 0.7, note: 'only with energy to spare'),
  idleNap('Nap', 1, note: 'only when getting tired');

  const CatWeight(
    this.label,
    this.defaultValue, {
    this.atYarn = false,
    this.note,
  });

  final String label;
  final double defaultValue;

  /// Chosen at the yarn (otherwise when idle).
  final bool atYarn;

  /// When the option is available, if not always.
  final String? note;

  static const max = 5.0;
}

/// A value for every [CatWeight].
@immutable
class CatWeights {
  const CatWeights._(this._values);

  static final defaults = CatWeights._({
    for (final w in CatWeight.values) w: w.defaultValue,
  });

  final Map<CatWeight, double> _values;

  double operator [](CatWeight w) => _values[w] ?? w.defaultValue;

  CatWeights withValue(CatWeight w, double value) =>
      CatWeights._({..._values, w: value.clamp(0.0, CatWeight.max)});

  /// [w]'s share of its group, from 0 to 1 (ignoring tiredness).
  double chanceOf(CatWeight w) {
    final group = CatWeight.values.where((o) => o.atYarn == w.atYarn);
    final total = group.fold(0.0, (sum, o) => sum + this[o]);
    return total == 0 ? 0 : this[w] / total;
  }

  // A plain loop, with no closure over `other`: on the phone, comparing
  // with a never-set (null) value called this with null, and a closure
  // reading `other[w]` then failed with "'[]' was called on null".
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CatWeights) return false;
    for (final w in CatWeight.values) {
      if (this[w] != other[w]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll([for (final w in CatWeight.values) this[w]]);
}

/// The tree drawn in the flowchart above, with [weights] for its choices.
CatNode catBehaviorFor(CatWeights weights) => Selector([
  Guard((c) => c.energy < 0.2, const Do(CatAction.sleep)),
  Guard(
    (c) => c.atYarn,
    Weighted([
      (CatAction.jump, (_) => weights[CatWeight.yarnJump]),
      (
        CatAction.rollOver,
        (c) => c.energy > 0.4 ? weights[CatWeight.yarnRoll] : 0,
      ),
      (CatAction.sit, (_) => weights[CatWeight.yarnSit]),
    ]),
  ),
  Guard((c) => c.yarnRolling, const Do(CatAction.chase)),
  // Not when already at the yarn (if every at-the-yarn weight is 0).
  Guard(
    (c) => c.boredom > 0.6 && c.energy > 0.35 && !c.atYarn,
    const Do(CatAction.chase),
  ),
  Weighted([
    (CatAction.sit, (_) => weights[CatWeight.idleSit]),
    (CatAction.wander, (_) => weights[CatWeight.idleWander]),
    (
      CatAction.rollOver,
      (c) => c.energy > 0.5 ? weights[CatWeight.idleRoll] : 0,
    ),
    (CatAction.sleep, (c) => c.energy < 0.45 ? weights[CatWeight.idleNap] : 0),
  ]),
]);

/// The tree with the default weights.
final catBehavior = catBehaviorFor(CatWeights.defaults);

/// The cat and its yarn, in pixels along the bottom of the screen.
class CatSim {
  CatSim({
    required this.charWidth,
    this.lineHeight = 13.2,
    Random? random,
    CatNode? behavior,
  }) : random = random ?? Random(),
       behavior = behavior ?? catBehavior {
    energy = 0.6 + this.random.nextDouble() * 0.4;
  }

  final double charWidth;

  /// Height of one line of a sprite, in pixels.
  final double lineHeight;

  /// Height of the strip she lives in (toys can pile up to here).
  double height = 52;

  /// Her responses turned into physics objects (from the third tap in a row).
  final toys = CatToys();

  /// Where she was last frame, to tell how fast she is moving (for the toys).
  Rect? _lastCatRect;
  final Random random;

  /// Decides what to do next; replaced when the weights change.
  CatNode behavior;

  double width = 0;

  /// Sets the width of the strip she lives in, keeping her and the yarn on it.
  void resize(double newWidth, [double? newHeight]) {
    if (newHeight != null) height = newHeight;
    if (newWidth == width) return;
    width = newWidth;
    if (!_started) return;
    x = x.clamp(0.0, _maxX);
    ballX = ballX.clamp(0.0, max(0.0, width - charWidth));
  }

  // Yarn.
  double ballX = 0;
  double ballV = 0;

  /// Height of the yarn above the ground (when dropped or thrown), and its
  /// vertical speed (up is positive).
  double ballY = 0;
  double ballVy = 0;

  /// Whether the yarn is being held (dragged by a finger).
  bool yarnHeld = false;

  /// Moving in any way, held, or in the air: worth chasing.
  bool get yarnRolling => ballV != 0 || ballY > 0 || yarnHeld;

  static const gravity = 900.0;

  /// How high the yarn can be carried, above the bottom of her strip.
  static const maxBallY = 1000.0;

  // Cat.
  double x = 0;
  bool facingRight = true;
  double energy = 1;
  double boredom = 0.5;

  /// Time left to look happy (^.^) after playing.
  double happy = 0;

  CatAction action = CatAction.sit;
  double actionTime = 0;
  double _actionLength = 2;
  double _wanderTo = 0;

  /// Whether the current jump started at the yarn (and so will bat it).
  bool _jumpOnYarn = false;

  /// Time left to look grumpy (-_-) after being woken.
  double grumpy = 0;

  /// Things she says when petted; each tap picks one.
  static const pettedResponses = ['<3', 'prr', 'mrrp', ':3'];

  /// Taps closer together than this count as "in a row".
  static const tapStreakGap = 1.2;

  /// From this many taps in a row, responses become physics objects.
  static const toyStreak = 3;

  /// The response shown beside her head (one per tap), or null.
  String? note;

  /// Taps in a row so far.
  int tapStreak = 0;
  double? _lastTap;

  /// She was tapped: one response, and from the third tap in a row it pops
  /// off her head as a physics object instead of staying beside it.
  void poke() {
    final last = _lastTap;
    tapStreak = last != null && _clock - last <= tapStreakGap ? tapStreak + 1 : 1;
    _lastTap = _clock;

    final String response;
    switch (action) {
      case CatAction.sleep:
        start(CatAction.startled);
        response = '!';
      case CatAction.startled:
        response = '!'; // Still recovering.
      default:
        // Being petted again keeps her purring; a new response each time.
        start(CatAction.petted);
        final options = pettedResponses.where((r) => r != note).toList();
        response = options[random.nextInt(options.length)];
    }

    if (tapStreak >= toyStreak) {
      note = null;
      _spawnToy(response);
    } else {
      note = response;
    }
  }

  void _spawnToy(String text) {
    final w = text.length * charWidth;
    final head = catRect;
    toys.spawn(CatToy(
      text: text,
      width: w,
      height: lineHeight,
      // Pops up from her head, on the face side.
      x: (facingRight ? head.right - w : head.left).clamp(0.0, max(0.0, width - w)),
      y: min(head.top + head.height, max(0.0, height - lineHeight)),
      vx: (random.nextDouble() - 0.5) * 160,
      vy: 220 + random.nextDouble() * 120,
    ));
  }

  /// Left edge of the current sprite. Left-facing sprites are anchored at the
  /// face side, like right-facing ones.
  double get spriteLeft {
    final s = sprite;
    return facingRight ? x : x + spriteWidth(_walkSprite) - spriteWidth(s);
  }

  /// Where she is, for the toys (y measured up from the bottom).
  Rect get catRect {
    final s = sprite;
    return Rect.fromLTWH(spriteLeft, hop, spriteWidth(s), s.length * lineHeight);
  }

  /// The yarn was picked up.
  void grabYarn() {
    yarnHeld = true;
    ballV = 0;
    ballVy = 0;
  }

  /// The held yarn was moved to [position] (x from the left, y up from the
  /// bottom of her strip).
  void moveYarn(Offset position) {
    if (!yarnHeld) return;
    ballX = position.dx.clamp(0.0, max(0.0, width - charWidth));
    ballY = position.dy.clamp(0.0, maxBallY);
  }

  /// The held yarn was let go, moving at [velocity] (pixels per second, y
  /// up): it falls (or flies) from there.
  void dropYarn([Offset velocity = Offset.zero]) {
    if (!yarnHeld) return;
    yarnHeld = false;
    ballV = velocity.dx.clamp(-700.0, 700.0);
    ballVy = velocity.dy.clamp(-900.0, 900.0);
  }

  /// The yarn was tapped: flick it away from the tap's side.
  void flickYarn() {
    final direction = ballX < width / 2 ? 1.0 : -1.0;
    ballV = direction * (160 + random.nextDouble() * 100);
  }

  double _clock = 0;

  /// Seconds simulated so far.
  double get clock => _clock;
  bool _started = false;

  /// Height of the current jump above the ground, in pixels.
  double hop = 0;

  /// Height of the yarn above the ground: its little bounce while rolling,
  /// or how high it was carried or thrown.
  double get ballHop => ballY > 0 || yarnHeld
      ? ballY
      : (sin(_clock * 12)).abs() * 6 * (ballV.abs() / 200).clamp(0.0, 1.0);

  /// Width of [sprite] in pixels.
  double spriteWidth(Sprite sprite) =>
      sprite.map((l) => l.length).reduce(max) * charWidth;

  /// Where the cat's front paws are.
  double get reach =>
      facingRight ? x + spriteWidth(_walkSprite) - charWidth : x;
  Sprite get _walkSprite => CatSprites.walk(true, 'o.o');

  double get distanceToYarn => ballX - reach;
  bool get atYarn => distanceToYarn.abs() < 14;

  double get _maxX => max(0.0, width - spriteWidth(_walkSprite));

  /// Starts [next], the action chosen by the tree.
  void start(CatAction next) {
    action = next;
    actionTime = 0;
    _actionLength = switch (next) {
      CatAction.sleep => 6 + random.nextDouble() * 6,
      CatAction.chase => 8,
      CatAction.jump => 0.5,
      CatAction.rollOver => 2.5 + random.nextDouble(),
      CatAction.sit => 2 + random.nextDouble() * 2,
      CatAction.wander => 10,
      CatAction.startled => 0.9,
      CatAction.petted => 1.8,
      CatAction.bonked => 2.2,
    };
    if (next == CatAction.wander) _wanderTo = random.nextDouble() * _maxX;
    if (next == CatAction.chase) _faceYarn();
    // Only a yarn on the ground can be batted.
    if (next == CatAction.jump) _jumpOnYarn = atYarn && ballY == 0 && !yarnHeld;
  }

  void update(double dt) {
    if (width <= 0) return;
    if (!_started) {
      x = _maxX * 0.2;
      ballX = width * 0.6;
      _started = true;
      start(behavior.choose(this) ?? CatAction.sit);
    }
    _clock += dt;
    actionTime += dt;
    happy = max(0, happy - dt);
    _updateYarn(dt);

    final done = switch (action) {
      CatAction.sleep => _sleep(dt),
      CatAction.chase => _chase(dt),
      CatAction.wander => _walkTowards(_wanderTo, 40, dt),
      CatAction.jump => _jump(dt),
      CatAction.rollOver => _roll(dt),
      CatAction.sit => _sit(dt),
      CatAction.startled => _startled(),
      CatAction.petted => _petted(dt),
      CatAction.bonked => _bonked(),
    };
    grumpy = max(0, grumpy - dt);
    final her = catRect;
    final last = _lastCatRect;
    final velocity = last == null || dt <= 0
        ? Offset.zero
        : Offset((her.left - last.left) / dt, (her.top - last.top) / dt);
    _lastCatRect = her;
    toys.step(dt, width: width, height: height, cat: her, catVelocity: velocity);
    energy = energy.clamp(0.0, 1.0);
    boredom = boredom.clamp(0.0, 1.0);
    if (done || actionTime > _actionLength && action != CatAction.sleep) {
      hop = 0;
      start(_afterReaction() ?? behavior.choose(this) ?? CatAction.sit);
    }
  }

  void _updateYarn(double dt) {
    if (yarnHeld) return;
    if (ballY > 0 || ballVy != 0) _fly(dt);
    ballX += ballV * dt;
    // Rolls to a stop on the ground; barely slows in the air.
    ballV *= exp((ballY > 0 ? -0.2 : -0.9) * dt);
    if (ballV.abs() < 4 && ballY == 0) ballV = 0;
    final ballMax = max(0.0, width - charWidth);
    if (ballX < 0) {
      ballX = 0;
      ballV = ballV.abs() * 0.6;
    } else if (ballX > ballMax) {
      ballX = ballMax;
      ballV = -ballV.abs() * 0.6;
    }
  }

  /// The yarn in the air: falls, bonks her if it lands on her head, and
  /// bounces a little on the ground.
  void _fly(double dt) {
    final before = ballY;
    ballVy -= gravity * dt;
    ballY += ballVy * dt;

    final head = headSpan;
    final headTop = catRect.bottom;
    final overHead =
        ballX + charWidth > head.$1 && ballX < head.$2;
    if (ballVy < 0 &&
        overHead &&
        action != CatAction.bonked &&
        ballY <= headTop &&
        before > headTop - lineHeight * 0.6) {
      _bonk(headTop);
      return;
    }

    if (ballY <= 0) {
      ballY = 0;
      // Bounces, less each time, then rolls.
      ballVy = ballVy.abs() > 120 ? -ballVy * 0.35 : 0;
    }
  }

  /// Left and right edges of her head (the line with her ears).
  (double, double) get headSpan {
    final s = _body;
    final ears = s[s.length - 3];
    final first = ears.indexOf(RegExp(r'\S'));
    // A note drawn on the left (when facing left) shifts the body right.
    final left = spriteLeft +
        (facingRight ? 0 : spriteWidth(sprite) - spriteWidth(s));
    if (first < 0) return (left, left + spriteWidth(s));
    final last = ears.lastIndexOf(RegExp(r'\S'));
    return (left + first * charWidth, left + (last + 1) * charWidth);
  }

  /// The yarn landed on her head: it bounces off and she is bonked.
  void _bonk(double headTop) {
    ballY = headTop;
    ballVy = 240;
    final middle = catRect.center.dx;
    ballV = (ballX < middle ? -1 : 1) * (90 + random.nextDouble() * 60);
    hop = 0;
    note = null;
    start(CatAction.bonked);
    toys.spawn(CatToy(
      text: 'bonk!',
      width: 5 * charWidth,
      height: lineHeight,
      x: (ballX - 2 * charWidth).clamp(0.0, max(0.0, width - 5 * charWidth)),
      y: min(headTop, max(0.0, height - lineHeight)),
      vx: -ballV * 0.5,
      vy: 200,
    ));
  }

  bool _sleep(double dt) {
    energy += 0.12 * dt;
    boredom = max(0, boredom - 0.05 * dt);
    return energy >= 1 && actionTime > 4;
  }

  /// Faces the yarn, judged from the middle of the cat (so a yarn ball under
  /// its body doesn't make it spin back and forth).
  void _faceYarn() {
    final middle = x + spriteWidth(_walkSprite) / 2;
    if ((ballX - middle).abs() > charWidth) facingRight = ballX > middle;
  }

  bool _chase(double dt) {
    if (atYarn) return true;
    _faceYarn();
    // Stand with the front paws at the yarn.
    final target = facingRight ? ballX - (reach - x) : ballX;
    return _walkTowards(target, 70, dt, turn: false);
  }

  bool _walkTowards(
    double target,
    double speed,
    double dt, {
    bool turn = true,
  }) {
    final goal = target.clamp(0.0, _maxX);
    final distance = goal - x;
    if (distance.abs() < 3) return true;
    if (turn) facingRight = distance > 0;
    // Slower when tired.
    final pace = speed * (0.6 + 0.4 * energy);
    x += min(pace * dt, distance.abs()) * distance.sign;
    energy -= 0.03 * dt;
    boredom += 0.02 * dt;
    return false;
  }

  bool _jump(double dt) {
    final p = (actionTime / 0.5).clamp(0.0, 1.0);
    hop = sin(pi * p) * 14;
    // A little leap forward.
    x = (x + (facingRight ? 40 : -40) * dt).clamp(0.0, _maxX);
    if (p < 1) return false;
    energy -= 0.08;
    if (_jumpOnYarn) {
      // Bat the yarn away, usually towards the open side of the screen.
      final push = 120 + random.nextDouble() * 140;
      final towardsRoom = ballX < width / 2 ? 1.0 : -1.0;
      ballV = push * (random.nextDouble() < 0.75 ? towardsRoom : -towardsRoom);
      boredom = 0;
      happy = 0.8;
    }
    return true;
  }

  bool _roll(double dt) {
    energy -= 0.04 * dt;
    boredom = max(0, boredom - 0.3 * dt);
    if (actionTime >= _actionLength) happy = 0.8;
    return false;
  }

  /// What follows a reaction to a tap, or null to ask the tree.
  CatAction? _afterReaction() => switch (action) {
    CatAction.startled => CatAction.sit,
    CatAction.bonked => CatAction.sit,
    CatAction.petted when random.nextDouble() < 0.35 => CatAction.rollOver,
    _ => null,
  };

  bool _startled() {
    final p = (actionTime / 0.4).clamp(0.0, 1.0);
    hop = p < 1 ? sin(pi * p) * 10 : 0;
    if (actionTime >= _actionLength) grumpy = 2.5;
    return false;
  }

  /// How long the bonk's squash lasts before she sees stars.
  static const bonkSquash = 0.25;

  bool _bonked() {
    if (actionTime >= _actionLength) grumpy = 2.5;
    return false;
  }

  bool _petted(double dt) {
    happy = max(happy, 0.5);
    boredom = max(0, boredom - 0.4 * dt);
    energy += 0.02 * dt;
    return false;
  }

  bool _sit(double dt) {
    energy += 0.02 * dt;
    boredom += 0.1 * dt;
    return false;
  }

  /// What to draw now.
  Sprite get sprite {
    final facing = _body;
    final note = switch (action) {
      // The z's float above, getting bigger.
      CatAction.sleep => ((_clock / 0.6).floor()).isEven ? 'z' : 'zZ',
      // One response per tap, shown until the next.
      CatAction.startled || CatAction.petted => this.note,
      _ => null,
    };
    return note == null ? facing : _withNote(facing, note);
  }

  /// Her sprite for now, facing the right way, without a note.
  Sprite get _body {
    final eyes = happy > 0 ? '^.^' : 'o.o';
    final Sprite base = switch (action) {
      CatAction.sleep => CatSprites.sleep(),
      CatAction.chase || CatAction.wander => CatSprites.walk(
        ((_clock / (action == CatAction.chase ? 0.18 : 0.26)).floor()).isEven,
        eyes,
      ),
      CatAction.jump => CatSprites.jump(happy > 0 ? '^.^' : 'O.O'),
      CatAction.rollOver => CatSprites.roll(((_clock / 0.25).floor()).isEven),
      // Blinks for a moment every few seconds; grumpy after being woken.
      CatAction.sit => CatSprites.sit(
        grumpy > 0
            ? '-_-'
            : (_clock % 3.2) < 0.15
            ? '-.-'
            : eyes,
      ),
      CatAction.startled => CatSprites.startled(),
      CatAction.petted => CatSprites.sit('^.^'),
      CatAction.bonked => actionTime < bonkSquash
          ? CatSprites.bonked()
          : CatSprites.dazed(((_clock / 0.2).floor()).isEven),
    };
    return facingRight ? base : mirrorSprite(base);
  }

  /// [sprite] with [note] beside its top line, on the face side. Added after
  /// mirroring so it always reads the right way round.
  Sprite _withNote(Sprite sprite, String note) {
    if (facingRight) return ['${sprite[0]} $note', sprite[1], sprite[2]];
    final pad = ' ' * (note.length + 1);
    return ['$note ${sprite[0]}', '$pad${sprite[1]}', '$pad${sprite[2]}'];
  }
}

// ---------------------------------------------------------------------------
// The widget.
// ---------------------------------------------------------------------------

const _catStyle = TextStyle(
  fontFamily: TerminalStyle.fontFamily,
  fontSize: 12,
  height: 1.1,
);

/// Width of one character of the cat, in pixels.
double catCharWidth() {
  final painter = TextPainter(
    text: const TextSpan(text: 'MMMMMMMMMM', style: _catStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width / 10;
}

/// Height of one line of the cat, in pixels.
double catLineHeight() {
  final painter = TextPainter(
    text: const TextSpan(text: 'M\nM', style: _catStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.height / 2;
}

/// The one Lena Kitty shared by every [AsciiCat] in the app, so she is the
/// same cat on every page: what she is doing, where she is, how tired she
/// is. Provide one above the app.
class LenaKitty {
  LenaKitty({Random? random})
      : sim = CatSim(
          charWidth: catCharWidth(),
          lineHeight: catLineHeight(),
          random: random,
        );

  final CatSim sim;
  Duration? _lastFrame;

  /// Moves her on to the frame at [frameTime]. Every cat on screen calls
  /// this each frame, but only the first call in a frame moves her, so two
  /// cats on screen at once (e.g. during a page transition) don't make her
  /// go twice as fast. After a pause (no cat on screen) she simply resumes.
  void advance(Duration frameTime) {
    final last = _lastFrame;
    _lastFrame = frameTime;
    if (last == null || frameTime <= last) return sim.update(0);
    sim.update(((frameTime - last).inMicroseconds / 1e6).clamp(0.0, 0.1));
  }
}

/// Lena Kitty, a small ASCII cat living along the bottom of the screen, drawn
/// in the accent color: she chases, jumps on and rolls about with a ball of
/// yarn, sits, wanders and naps, as decided by [catBehavior]. Tapping her
/// makes her react, tapping the yarn flicks it, and dragging the yarn picks
/// it up (drop it on her head for a bonk); everywhere else, touches
/// pass through. She is decorative, so screen readers skip her. With reduced
/// motion turned on, she just sleeps (and purrs for a moment when tapped).
///
/// Every [AsciiCat] shows the app's one [LenaKitty] when one is provided.
class AsciiCat extends StatefulWidget {
  const AsciiCat({
    super.key,
    this.height = defaultHeight,
    this.random,
    this.weights,
  });

  /// Overrides the weights saved in [CatPersonality] (if one is provided
  /// above); the defaults are used when neither is.
  final CatWeights? weights;

  /// Tall enough for responses to pile up on her.
  static const defaultHeight = 76.0;

  final double height;

  /// For tests: makes the cat's choices repeatable.
  final Random? random;

  @override
  State<AsciiCat> createState() => _AsciiCatState();
}

class _AsciiCatState extends State<AsciiCat>
    with SingleTickerProviderStateMixin {
  static const _style = _catStyle;

  late final Ticker _ticker = createTicker(_tick);

  /// The app's Lena Kitty, if one is provided (and no [AsciiCat.random] asks
  /// for a private, repeatable cat, as tests do).
  LenaKitty? _shared;

  /// Used when there is no shared cat.
  CatSim? _local;

  CatSim get _cat => _shared?.sim ?? (_local ??= CatSim(
        charWidth: catCharWidth(),
        lineHeight: catLineHeight(),
        random: widget.random,
      ));
  Duration _last = Duration.zero;
  CatWeights? _appliedWeights;

  /// The saved weights, if the app provides a [CatPersonality].
  static CatWeights _personality(BuildContext context) {
    try {
      return context.watch<CatPersonality>().weights;
    } on ProviderNotFoundException {
      return CatWeights.defaults;
    }
  }

  /// With reduced motion: purring for a moment after a tap.
  bool _stillPurring = false;
  int _purrs = 0;

  void _pokeCat() {
    HapticFeedback.selectionClick();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      final purr = ++_purrs;
      setState(() => _stillPurring = true);
      Future.delayed(const Duration(seconds: 2), () {
        // Only the latest tap's timer ends the purring.
        if (mounted && purr == _purrs) setState(() => _stillPurring = false);
      });
    } else {
      setState(_cat.poke);
    }
  }

  void _flickYarn() {
    // A short drag can still end in a tap; it was a drag.
    if (_dragging) return;
    HapticFeedback.selectionClick();
    setState(_cat.flickYarn);
  }

  // Dragging the yarn. Raw pointer events rather than a drag gesture, so
  // the yarn can be picked up even behind a scrolling page (whose own drag
  // would otherwise win). A tap is still a gesture, so a button drawn over
  // the yarn keeps its taps.
  final _stripKey = GlobalKey();
  int? _yarnPointer;
  Offset _yarnDownAt = Offset.zero;
  bool _dragging = false;

  /// From the finger to the yarn, so it doesn't jump when picked up.
  Offset _grabOffset = Offset.zero;
  VelocityTracker? _yarnVelocity;

  /// Movement before a touch on the yarn becomes a drag rather than a tap.
  static const _dragSlop = 6.0;

  /// [global] in the sim's coordinates: x from the left, y up from the
  /// bottom of the strip.
  Offset? _toSim(Offset global) {
    final box = _stripKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    return Offset(local.dx, box.size.height - local.dy);
  }

  void _yarnDown(PointerDownEvent event) {
    if (_yarnPointer != null) return;
    _yarnPointer = event.pointer;
    _yarnDownAt = event.position;
    _dragging = false;
    _yarnVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _yarnMove(PointerMoveEvent event) {
    if (event.pointer != _yarnPointer) return;
    _yarnVelocity?.addPosition(event.timeStamp, event.position);
    final at = _toSim(event.position);
    if (at == null) return;
    if (!_dragging) {
      if ((event.position - _yarnDownAt).distance < _dragSlop) return;
      _dragging = true;
      HapticFeedback.selectionClick();
      final start = _toSim(_yarnDownAt) ?? at;
      _grabOffset = Offset(_cat.ballX, _cat.ballHop) - start;
      _cat.grabYarn();
    }
    setState(() => _cat.moveYarn(at + _grabOffset));
  }

  void _yarnUp(PointerUpEvent event) {
    if (event.pointer != _yarnPointer) return;
    if (_dragging) {
      final v = _yarnVelocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
      // Screen y is down; the sim's is up.
      setState(() => _cat.dropYarn(Offset(v.dx, -v.dy)));
    }
    // [_dragging] stays set until the next touch, for [_flickYarn].
    _yarnPointer = null;
  }

  void _yarnCancel(PointerCancelEvent event) {
    if (event.pointer != _yarnPointer) return;
    if (_dragging) setState(() => _cat.dropYarn());
    _yarnPointer = null;
    _dragging = false;
  }

  /// A tap target around some text, a little bigger than the text itself.
  static Widget _tappable({
    required VoidCallback onTap,
    required Widget child,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.all(_touchPad), child: child),
  );

  static const _touchPad = 6.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.random == null) {
      try {
        _shared = context.read<LenaKitty>();
      } on ProviderNotFoundException {
        _shared = null;
      }
    }
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final shared = _shared;
    if (shared != null) {
      // Shared frame time, so all cats on screen agree on how far to move her.
      final frame = SchedulerBinding.instance.currentFrameTimeStamp;
      setState(() => shared.advance(frame));
      return;
    }
    final dt = _last == Duration.zero
        ? 0.0
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    setState(() => _cat.update(dt));
  }

  @override
  Widget build(BuildContext context) {
    final style = _style.copyWith(color: TerminalStyle.of(context).accent);
    final weights = widget.weights ?? _personality(context);
    // Compare only once there is something to compare with.
    final applied = _appliedWeights;
    if (applied == null || weights != applied) {
      _cat.behavior = catBehaviorFor(weights);
      _appliedWeights = weights;
    }
    final asleep = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return ExcludeSemantics(
      child: SizedBox(
        key: _stripKey,
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _cat.resize(constraints.maxWidth, widget.height);
            if (asleep) {
              final purring = _stillPurring;
              final cat = purring ? CatSprites.sit('^.^') : CatSprites.sleep();
              return Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24 - _touchPad),
                  child: _tappable(
                    onTap: _pokeCat,
                    child: Text(
                      [
                        '${cat[0]} ${purring ? '<3' : 'zZ'}',
                        cat[1],
                        cat[2],
                      ].join('\n'),
                      style: style,
                    ),
                  ),
                ),
              );
            }
            final sprite = _cat.sprite;
            // Sprites drawn facing left are anchored at the face side too.
            final left = _cat.spriteLeft;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: left - _touchPad,
                  bottom: _cat.hop - _touchPad,
                  child: _tappable(
                    onTap: _pokeCat,
                    child: Text(
                      sprite.join('\n'),
                      style: style,
                      softWrap: false,
                    ),
                  ),
                ),
                Positioned(
                  // A bigger target for the small yarn ball.
                  left: _cat.ballX - _touchPad * 2,
                  bottom: _cat.ballHop - _touchPad * 2,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _yarnDown,
                    onPointerMove: _yarnMove,
                    onPointerUp: _yarnUp,
                    onPointerCancel: _yarnCancel,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _flickYarn,
                      child: Padding(
                        padding: const EdgeInsets.all(_touchPad * 2),
                        child: Text('@', style: style),
                      ),
                    ),
                  ),
                ),
                // Her responses as physics objects. They never take taps.
                for (final toy in _cat.toys.toys)
                  Positioned(
                    left: toy.x,
                    bottom: toy.y,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: toy.opacity,
                        child: Text(toy.text, style: style, softWrap: false),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Puts Lena Kitty along the bottom of a page, behind [child] (so the page's
/// content always draws on top and gets touches first). Shown only when the
/// app provides a [CatPersonality] with [CatPersonality.roams] on.
class CatBackdrop extends StatelessWidget {
  const CatBackdrop({super.key, required this.child});

  final Widget child;

  static bool _roams(BuildContext context) {
    try {
      return context.watch<CatPersonality>().roams;
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_roams(context)) return child;
    // She is drawn behind the content but still hears taps the content
    // doesn't want (see [_TouchThroughStack]).
    return _TouchThroughStack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          bottom: 4,
          child: SafeArea(top: false, child: AsciiCat()),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// A [Stack] that offers each touch to every child, not just the topmost
/// one that is hit. A plain Stack stops at the content, and a scrolling page
/// counts as "hit" everywhere, so nothing behind it ever gets a tap.
///
/// Because the content is still asked first, its buttons, tiles and cards
/// win any tap they want; the children behind only get taps that nothing in
/// front claims (such as on empty space, where scrolling ignores a tap).
class _TouchThroughStack extends Stack {
  const _TouchThroughStack({required super.children});

  @override
  RenderStack createRenderObject(BuildContext context) => _RenderTouchThroughStack(
        alignment: alignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
        fit: fit,
        clipBehavior: clipBehavior,
      );
}

class _RenderTouchThroughStack extends RenderStack {
  _RenderTouchThroughStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var hit = false;
    // Front to back, so the content's handlers come first in the arena.
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as StackParentData;
      final current = child;
      hit = result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, transformed) =>
                current.hitTest(result, position: transformed),
          ) ||
          hit;
      child = data.previousSibling;
    }
    return hit;
  }
}
