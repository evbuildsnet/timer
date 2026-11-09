import 'dart:math' as math;

import '../engine/session.dart';

/// How a finger on the feed is read. Like the iPhone home bar, one gesture
/// means different things depending on how it moves:
/// - [target]: slow or resting finger. 1:1, notched, a haptic tick per number.
/// - [fast]: a quick swipe or flick. Boosted, long glide, haptics only at [checkpoints].
enum ScrollMode { target, fast }

/// Values that click in fast mode, and that a fast glide is drawn to.
const checkpoints = [5, 10, 15, 30, 45, 60];

/// What crossing between two values should feel like.
enum Detent { none, number, checkpoint }

typedef Landing = ({double target, double velocity, ScrollMode mode});

const pxPerItem = 56.0;

/// Finger speed (px/ms) that switches to fast mode.
const _fastSpeed = 1.1;

/// A fast finger must stay below this speed for [_dwellMs] to return to target mode.
const _slowSpeed = 0.3;
const _dwellMs = 120.0;

/// Speed is measured over this trailing window, so a resting finger reads as 0.
const _windowMs = 60.0;

/// A release this fast (px/ms) glides even if the drag itself was slow.
const _flickSpeed = 1.6;

/// A finger that rested this long before lifting lands where it is.
const _liftGapMs = 80.0;

/// How far a glide may be pulled to reach a checkpoint.
const _magnetReach = 2.5;

final class FeedScroll {
  FeedScroll(this.finger);

  /// Dial position the finger points at (before notching).
  double finger;
  ScrollMode mode = ScrollMode.target;

  final _moves = <({double at, double dy, double dt})>[];
  double? _lastMoveAt;
  double? _slowSince;

  /// The finger's recent motion: net and total px over the ms they took.
  ({double net, double travel, double ms}) _window(double end) {
    var net = 0.0, travel = 0.0, ms = 0.0;
    for (final m in _moves) {
      if (m.at > end || end - m.at > _windowMs) continue;
      net += m.dy;
      travel += m.dy.abs();
      ms += m.dt;
    }
    return (net: net, travel: travel, ms: ms);
  }

  /// Finger speed in px/ms at [now]; a resting finger reads 0.
  double speedAt(double now) {
    final w = _window(now);
    return w.ms == 0 ? 0 : w.travel / w.ms;
  }

  /// Signed finger velocity (px/ms) as it lifted at [now]; 0 if it rested first.
  double liftVelocity(double now) {
    final last = _lastMoveAt;
    if (last == null || now - last > _liftGapMs) return 0;
    final w = _window(last);
    return w.ms == 0 ? 0 : w.net / w.ms;
  }

  /// Fast mode boosts travel smoothly from 1x at the threshold to 4x.
  double gain(double speed) => mode == ScrollMode.fast ? 1 + 3 * ((speed - _fastSpeed) / 1.6).clamp(0.0, 1.0) : 1;

  /// A finger moved by [dy] px at [now] ms.
  void move(double dy, double now) {
    final dt = (now - (_lastMoveAt ?? now - 8)).clamp(1.0, 50.0);
    _lastMoveAt = now;
    _moves
      ..removeWhere((m) => now - m.at > _windowMs)
      ..add((at: now, dy: dy, dt: dt));
    update(now);
    var delta = dy / pxPerItem * gain(speedAt(now));
    if (finger < stopwatchValue || finger > maxMinutes) delta *= 0.3;
    finger += delta;
  }

  /// Re-reads the mode at [now]. Returns the new mode when it changed.
  ScrollMode? update(double now) {
    final speed = speedAt(now);
    switch (mode) {
      case ScrollMode.target when speed > _fastSpeed:
        _slowSince = null;
        return mode = ScrollMode.fast;
      case ScrollMode.fast when speed < _slowSpeed:
        final since = _slowSince ??= now;
        if (now - since >= _dwellMs) {
          _slowSince = null;
          return mode = ScrollMode.target;
        }
      case ScrollMode.fast:
        _slowSince = null;
      case ScrollMode.target:
        break;
    }
    return null;
  }

  /// Where the dial should be while the finger is down.
  double get target => mode == ScrollMode.fast ? finger : notch(finger);

  /// The finger lifted at [now]; [position] is where the dial is.
  Landing release(double position, double now) {
    final lift = liftVelocity(now);
    final fast = mode == ScrollMode.fast || lift.abs() > _flickSpeed;
    // The boost lives in the drag; the glide carries the finger's real speed.
    final velocity = (lift * 1000 / pxPerItem).clamp(-90.0, 90.0);
    final landing = fast ? magnet(position + velocity * 0.32) : (position + velocity * 0.08).roundToDouble();
    return (
      target: landing.clamp(stopwatchValue.toDouble(), maxMinutes.toDouble()),
      velocity: velocity,
      mode: fast ? ScrollMode.fast : ScrollMode.target,
    );
  }

  /// Sticky near whole numbers, quick between them: a knob with notches.
  static double notch(double x) {
    final n = x.roundToDouble();
    final r = x - n;
    return n + 0.5 * r.sign * math.pow((2 * r).abs(), 2.4);
  }

  /// A glide ending near a checkpoint lands on it.
  static double magnet(double projected) {
    for (final c in checkpoints) {
      if ((projected - c).abs() <= _magnetReach) return c.toDouble();
    }
    return projected.roundToDouble();
  }

  /// The feel of the shown value changing from [from] to [to].
  static Detent detent(int from, int to, ScrollMode mode) {
    if (from == to) return Detent.none;
    final lo = math.min(from, to), hi = math.max(from, to);
    // Moving up crosses (from, to]; moving down crosses [to, from).
    final crossed = checkpoints.any((c) => to > from ? c > lo && c <= hi : c >= lo && c < hi);
    if (crossed) return Detent.checkpoint;
    return mode == ScrollMode.target ? Detent.number : Detent.none;
  }
}
