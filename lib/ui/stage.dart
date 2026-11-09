import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/readout.dart';
import '../engine/session.dart';
import '../engine/store.dart';
import 'geometry.dart';
import 'scene.dart';
import 'spring.dart';

const _pxPerItem = 56.0;
const _wheelPxPerItem = 48.0;
const _slop = 9.0;
const _resetDistance = 72.0;
const _wheelResetDistance = 140.0;
const _floodRise = 0.9;
const _floodHold = 1.5;
const _floodEnd = 2.7;

/// A finished timer replays its silent alarm when you come back within this window.
const _replayWindowMs = 15 * 60000;

/// Overtime keeps the screen awake this long, then lets the phone sleep.
const _overtimeWakeMs = 10 * 60000;

/// Countries that read clocks in 12-hour time, for web (iOS reports the setting).
const _twelveHourCountries = {'US', 'CA', 'AU', 'NZ', 'IN', 'PH', 'PK', 'EG', 'SA', 'CO', 'MX'};

class Stage extends StatefulWidget {
  const Stage({super.key, required this.store, required this.program});

  final Store store;
  final ui.FragmentProgram program;

  @override
  State<Stage> createState() => _StageState();
}

class _StageState extends State<Stage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final scene = Scene();
  late final ScenePainter painter = ScenePainter(scene, widget.program);
  late final Ticker ticker = createTicker((_) => _frame());
  final focusNode = FocusNode();
  final _clock = Stopwatch()..start();

  late Session session = widget.store.session;
  late bool onboarded = widget.store.onboarded;
  bool _still = false;
  bool _use24h = true;

  // Motion.
  final dial = Spring(Session.defaultMinutes.toDouble(), stiffness: 190, dampingRatio: 0.84);
  final day = Spring(0, stiffness: 70, dampingRatio: 1);
  final tide = Spring(0, stiffness: 42, dampingRatio: 0.62);
  final wave = Spring(1, stiffness: 30, dampingRatio: 1);
  final dim = Spring(0, stiffness: 120, dampingRatio: 1);
  final spread = Spring(0, stiffness: 200, dampingRatio: 0.9);
  final body = Spring(Body.selecting, stiffness: 240, dampingRatio: 0.78);
  final press = Spring(0, stiffness: 900, dampingRatio: 0.5);
  final nudge = Spring(0, stiffness: 320, dampingRatio: 0.7);
  final enter = Spring(1, stiffness: 260, dampingRatio: 0.72);
  final caption = Spring(0, stiffness: 80, dampingRatio: 1);
  final rest = Spring(1, stiffness: 160, dampingRatio: 1);
  late final _springs = [day, tide, wave, dim, spread, body, press, nudge, enter, caption, rest];

  double _lastFrameAt = 0;
  Timer? _idle;
  bool _dialHeld = false;
  int _lastWheelAt = 0;
  int _lastFeedInputAt = 0;
  double _pausedWheel = 0;
  int _lastClick = -1;
  int? _lastSigned;
  double? _floodClock;
  String _lastLabel = '';
  bool _dayUi = false;
  bool _awake = false;
  String _announced = '';

  // Pointer.
  int? _pointer;
  Offset _downAt = Offset.zero;
  Offset _lastAt = Offset.zero;
  Duration _lastMoveTime = Duration.zero;
  double _speed = 0;
  bool _dragging = false;
  bool _caught = false;
  VelocityTracker? _velocity;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Monotonic ms for input timing: immune to the wall clock stepping. Never 0.
  int get _mono => _clock.elapsedMilliseconds + 1;

  int get _selected => dial.target.round().clamp(stopwatchValue, maxMinutes);

  Readout _readout(Session s, int now) => s is Selecting
      ? selectionReadout(s.value, now, use24h: _use24h)
      : readoutOf(s, now, use24h: _use24h);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = _now;
    final signed = session.signedAt(now);
    // A timer that finished while the app was closed still gets its moment.
    _lastSigned = session.isTimer && signed != null && signed >= 0 && signed < _replayWindowMs ? -1 : signed;
    _settleFor(session, now, immediate: true);
    _wake();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _use24h = kIsWeb
        ? !_twelveHourCountries.contains(View.of(context).platformDispatcher.locale.countryCode)
        : MediaQuery.alwaysUse24HourFormatOf(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    ticker.dispose();
    focusNode.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _awake = false;
      _wake();
    }
  }

  // ───────────────────────────── Session changes

  void _commit(Session next) {
    setState(() => session = next);
    widget.store.session = next;
    _pausedWheel = 0;
    _lastWheelAt = 0;
  }

  /// Points every spring at where the session wants it to be.
  void _settleFor(Session s, int now, {bool immediate = false}) {
    final readout = _readout(s, now);
    final targets = switch (s) {
      Selecting() => (spread: 0.0, body: Body.selecting, dim: 0.0, wave: 0.45),
      Running() => (spread: 1.0, body: Body.running, dim: 0.0, wave: 1.0),
      Paused() => (spread: 1.0, body: Body.paused, dim: 1.0, wave: 0.0),
    };
    spread.target = targets.spread;
    body.target = targets.body;
    dim.target = targets.dim;
    wave.target = targets.wave;
    if (immediate) {
      dial.snap(s.value.toDouble());
      for (final spring in [spread, body, dim, wave]) {
        spring.snap(spring.target);
      }
      day.snap(readout.day ? 1 : 0);
      tide.snap(readout.tide);
      scene.hero = readout.hero;
    }
  }

  void _activate() {
    _wake();
    final now = _now;
    final current = session;
    if (current is Selecting) {
      final value = _selected;
      dial.snap(value.toDouble());
      _commit(Selecting(value).activate(now));
      scene
        ..hero = feedText(value)
        ..entering = null;
      enter.snap(1);
      press.velocity -= 9;
      tide.velocity += 1.2;
      if (!onboarded) widget.store.onboarded = onboarded = true;
      HapticFeedback.mediumImpact();
    } else {
      _commit(current.activate(now));
      HapticFeedback.lightImpact();
    }
    _lastSigned = session.signedAt(now);
    _settleFor(session, now);
  }

  void _reset() {
    final current = session;
    if (current is! Paused) return;
    _wake();
    final landing = current.landingValue;
    final g = scene.geometry;
    if (g != null) {
      scene.ghosts.add(
        Ghost(text: scene.hero, fit: g.fit(scene.hero), body: body.value, direction: 1, offset: nudge.value),
      );
    }
    _commit(Selecting(landing));
    dial.snap(landing.toDouble());
    _lastFeedInputAt = _mono;
    _lastClick = landing;
    enter
      ..snap(0)
      ..target = 1;
    nudge.snap(0);
    _settleFor(session, _now);
    HapticFeedback.heavyImpact();
  }

  void _moveDial(int steps) {
    if (session is Paused) _reset();
    if (session is! Selecting) return;
    _wake();
    dial.target = (_selected + steps).clamp(stopwatchValue, maxMinutes).toDouble();
  }

  // ───────────────────────────── Frame loop
  //
  // The ticker runs only while something moves. At rest a timer wakes the
  // scene at ~20 fps for the breathing tide, or once per second when the
  // water is still (paused, reduced motion).

  void _wake() {
    _idle?.cancel();
    _idle = null;
    if (!ticker.isActive) ticker.start();
  }

  void _frame() {
    final t = _clock.elapsedMicroseconds / 1e6;
    final dt = (t - _lastFrameAt).clamp(0.0, 0.05);
    _lastFrameAt = t;
    final active = _update(dt, t);
    scene.repaint();
    if (active) {
      if (!ticker.isActive) _wake();
      return;
    }
    if (ticker.isActive) ticker.stop();
    _idle?.cancel();
    // A paused scene has nothing to update until the next input wakes it.
    if (session is Paused) return;
    final breathing = !_still && wave.value > 0.05;
    // When still, wake right after the session's next whole second so labels never lag.
    final phase = session.signedAt(_now) ?? _now;
    _idle = Timer(
      breathing ? const Duration(milliseconds: 50) : Duration(milliseconds: 1004 - phase % 1000),
      _frame,
    );
  }

  /// Advances the world by [dt]. Returns true while anything is in motion.
  bool _update(double dt, double t) {
    final now = _now;
    final g = scene.geometry;
    var moving = _dialHeld || _dragging || _pointer != null;

    if (session is Selecting) {
      if (!_dialHeld && _lastWheelAt != 0 && _mono - _lastWheelAt > 140) {
        _lastWheelAt = 0;
        dial.target = dial.value.round().clamp(stopwatchValue, maxMinutes).toDouble();
      }
      moving |= _lastWheelAt != 0;
      if (!_dialHeld) moving |= _advance(dial, dt);
      // Remember where the feed came to rest, so a reload lands on the same value.
      final landed = dial.target.round().clamp(stopwatchValue, maxMinutes);
      if (_pointer == null && !_dialHeld && _lastWheelAt == 0 && dial.settled && landed != session.value) {
        _commit(Selecting(landed));
      }
      final clicked = dial.value.round().clamp(stopwatchValue, maxMinutes);
      if (clicked != _lastClick) {
        if (_lastClick != -1) HapticFeedback.selectionClick();
        _lastClick = clicked;
      }
    }

    final current = session;
    final readout = current is Selecting
        ? selectionReadout(dial.value.round().clamp(stopwatchValue, maxMinutes), now, use24h: _use24h)
        : readoutOf(current, now, use24h: _use24h);

    // Crossing zero: the silent alarm.
    final signed = current.signedAt(now);
    if (current case Running(isTimer: true) when signed != null) {
      final last = _lastSigned;
      if (last != null && last < 0 && signed >= 0 && signed < _replayWindowMs) _celebrate();
    }
    _lastSigned = signed;
    _syncWakelock(current, signed);

    // Hero ticks and the per-second ripple.
    if (current is! Selecting && readout.hero != scene.hero && g != null) {
      _tickHero(scene.hero, readout.hero, g, counting: readout.day ? 1 : -1);
    }
    if (current is Running && readout.label != _lastLabel && _lastLabel.isNotEmpty && !_still) {
      scene.ripple = 1;
    }
    _lastLabel = readout.label;

    // The feed is at rest once input has paused and the dial has landed on a value.
    final atRest = current is! Selecting ||
        (!_dialHeld && _mono - _lastFeedInputAt > 120 && _lastWheelAt == 0 && (dial.value - dial.target).abs() < 0.02);
    if (!atRest) rest.snap(0);
    moving |= !atRest;
    rest.target = atRest ? 1 : 0;

    // World targets.
    final floodClock = _floodClock;
    final flooding = floodClock != null && floodClock < _floodRise;
    if (current is Selecting) {
      final position = dial.value.clamp(0.0, maxMinutes.toDouble());
      // Crossing toward `+` flips rooms in one animated move; a held drag never parks on grey.
      // Hysteresis keeps a resting, trembling finger near the boundary from strobing.
      day.target = position < 0.4 ? 1 : position > 0.6 ? 0 : day.target;
      // Preview the amount of time as water, kept below the label so the
      // glowing waterline never runs through text.
      final reach = g == null ? 0.3 : (g.size.height - g.labelBottom) / g.size.height;
      tide.target = position <= 1 ? 0 : position / maxMinutes * reach;
    } else {
      day.target = readout.day && !flooding ? 1 : 0;
      tide.target = readout.tide;
      // The tide creeps continuously; let the spring animate only real jumps
      // (the start surge, the minute wrap) so a resting scene stays idle.
      final pixel = g == null ? 0.001 : 1 / g.size.height;
      if ((tide.value - tide.target).abs() < pixel && tide.velocity.abs() < 0.05) tide.snap(tide.target);
    }
    caption.target = switch (current) {
      Selecting() when !onboarded => 1,
      Paused() => 1,
      _ => 0,
    };
    // Keep the old words while a caption fades out, so it never flashes the wrong hint.
    if (caption.target > 0) {
      scene.caption = current is Paused ? 'tap to resume  ·  swipe to reset' : 'swipe to choose  ·  tap to start';
    }

    for (final spring in _springs) {
      // Reduced motion still crossfades the room change instead of a hard full-screen cut.
      moving |= _still && spring == day ? _ramp(day, dt / 0.25) : _advance(spring, dt);
    }

    if (floodClock != null) {
      final next = floodClock + dt;
      _floodClock = next >= _floodEnd ? null : next;
      scene.flood = switch (next) {
        _ when next >= _floodEnd => 0,
        // Reduced motion: no rising wave and no hard flash; the flood fades in, holds, fades out.
        _ when _still && next < 0.3 => 2 - next / 0.3,
        _ when _still => next < _floodHold ? 1 : 1 + (next - _floodHold) / (_floodEnd - _floodHold),
        _ when next < _floodRise => 1 - math.pow(1 - next / _floodRise, 3).toDouble(),
        _ when next < _floodHold => 1,
        _ => 1 + (next - _floodHold) / (_floodEnd - _floodHold),
      };
      moving = true;
    }

    for (final ghost in scene.ghosts) {
      ghost.progress += dt / (_still ? 0.12 : 0.32);
    }
    scene.ghosts.removeWhere((ghost) => ghost.progress >= 1);
    moving |= scene.ghosts.isNotEmpty;
    if (scene.enter >= 0.999 && enter.settled) scene.entering = null;
    scene.ripple *= math.exp(-dt * 7);
    if (scene.ripple < 0.2) scene.ripple = 0;
    moving |= scene.ripple > 0;

    scene
      ..time = _still ? 0 : t
      ..selecting = current is Selecting
      ..feedRest = rest.value
      ..dial = dial.value
      ..day = day.value
      ..tide = tide.value.clamp(0.0, 1.0)
      ..still = _still
      ..wave = _still ? 0 : wave.value
      ..dim = dim.value
      ..spread = spread.value
      ..body = body.value
      ..press = press.value
      ..nudge = nudge.value
      ..enter = enter.value
      ..captionAlpha = caption.value
      ..label = readout.label;

    // Dark status-bar text whenever the backdrop is light: the day room, unless the
    // red flood covers the top (it drains from the top down, or fades under Reduce Motion).
    final flood = scene.flood;
    final dayUi = scene.day > 0.5 && !(flood >= 0.93 && flood <= (_still ? 1.5 : 1.12));
    final announced = current is Selecting
        ? selectionReadout(_selected, now, use24h: _use24h).announcement
        : readout.announcement;
    if (dayUi != _dayUi || announced != _announced) {
      setState(() {
        _dayUi = dayUi;
        _announced = announced;
      });
    }
    return moving;
  }

  bool _advance(Spring spring, double dt) {
    if (!_still) return spring.step(dt);
    final moving = !spring.settled;
    spring.snap(spring.target);
    return moving;
  }

  /// Moves linearly toward the target; used where reduced motion still wants a fade.
  bool _ramp(Spring spring, double step) {
    final gap = spring.target - spring.value;
    if (gap == 0) return false;
    spring
      ..value = gap.abs() <= step ? spring.target : spring.value + step * gap.sign
      ..velocity = 0;
    return true;
  }

  void _syncWakelock(Session s, int? signed) {
    final awake = s is Running && !(s.isTimer && signed != null && signed > _overtimeWakeMs);
    if (awake == _awake) return;
    _awake = awake;
    WakelockPlus.toggle(enable: awake).ignore();
  }

  void _tickHero(String from, String to, Geometry g, {required double counting}) {
    final sameShape = from.length == to.length;
    final changed = sameShape ? [for (var i = 0; i < to.length; i++) from[i] != to[i]] : null;
    scene.ghosts.add(
      Ghost(text: from, fit: g.fit(from), body: body.value, direction: -counting, offset: nudge.value, changed: changed),
    );
    scene
      ..hero = to
      ..entering = changed ?? List.filled(to.length, true)
      ..enterDirection = -counting;
    enter
      ..snap(0)
      ..target = 1;
  }

  void _celebrate() {
    _floodClock = 0;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 140), HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 280), HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 900), HapticFeedback.mediumImpact);
  }

  // ───────────────────────────── Input

  double _gain() => 1 + 1.8 * ((_speed - 0.4) / 1.4).clamp(0.0, 1.0);

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryButton) return;
    _wake();
    focusNode.requestFocus();
    _pointer = event.pointer;
    _downAt = _lastAt = event.position;
    _lastMoveTime = event.timeStamp;
    _speed = 0;
    _dragging = false;
    _velocity = VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.position);
    // Touching a spinning feed stops it, like any iOS list. That touch never starts a timer.
    _caught = session is Selecting && (dial.velocity.abs() > 1.5 || (dial.target - dial.value).abs() > 0.3);
    if (_caught) {
      // A caught feed is held: no label until the finger lifts and the dial lands.
      dial.snap(dial.value);
      _dialHeld = true;
    } else {
      press.target = 1;
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    final dy = event.position.dy - _lastAt.dy;
    final ms = math.max(1, (event.timeStamp - _lastMoveTime).inMicroseconds / 1000);
    _speed += (dy.abs() / ms - _speed) * (1 - math.exp(-ms / 80));
    _lastAt = event.position;
    _lastMoveTime = event.timeStamp;

    final total = event.position - _downAt;
    if (!_dragging) {
      if (total.distance < _slop) return;
      _dragging = true;
      press.target = 0;
    }

    switch (session) {
      case Selecting():
        _dialHeld = true;
        var delta = dy / _pxPerItem * _gain();
        final p = dial.value;
        if (p < 0 || p > maxMinutes) delta *= 0.3;
        dial.snap(p + delta);
        _lastFeedInputAt = _mono;
      case Paused():
        if (total.dy.abs() > _resetDistance) {
          _reset();
          _dialHeld = true;
        } else {
          nudge.snap(total.dy * 0.55);
        }
      case Running():
        nudge.snap(14 * _tanh(total.dy / 90));
    }
  }

  void _onUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    press.target = 0;
    nudge.target = 0;

    if (_dragging) {
      _dragging = false;
      if (session is Selecting && _dialHeld) {
        final pxPerSecond = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
        final itemsPerSecond = (pxPerSecond / _pxPerItem * _gain()).clamp(-90.0, 90.0);
        final projected = dial.value + itemsPerSecond * 0.16;
        dial
          ..velocity = itemsPerSecond
          ..target = projected.round().clamp(stopwatchValue, maxMinutes).toDouble();
      }
      _dialHeld = false;
      return;
    }
    _dialHeld = false;
    if (_caught) {
      dial.target = dial.value.round().clamp(stopwatchValue, maxMinutes).toDouble();
      return;
    }
    if (event is PointerCancelEvent) return;
    _tap(event.localPosition);
  }

  void _tap(Offset position) {
    final g = scene.geometry;
    if (session is Selecting && g != null) {
      for (final item in feedItems(dial.value, g, spread: 0, caption: scene.captionAlpha)) {
        final a = item.distance.abs();
        if (a < 0.5 || a > 1.6 || item.alpha < 0.05) continue;
        final halfHeight = g.inkHeight((wdth: item.wdth, scale: item.scale)) / 2 + 24;
        if ((position.dy - item.center.dy).abs() < halfHeight) {
          dial.target = item.value.toDouble();
          return;
        }
      }
    }
    _activate();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) => _scroll(event.scrollDelta.dy));
  }

  /// Wheel and trackpad. A paused session only resets after a deliberate scroll.
  void _scroll(double dy) {
    _wake();
    if (session is Paused) {
      if (_mono - _lastWheelAt > 300) _pausedWheel = 0;
      _lastWheelAt = _mono;
      _pausedWheel += dy;
      if (_pausedWheel.abs() > _wheelResetDistance) _reset();
      return;
    }
    if (session is! Selecting) return;
    _lastFeedInputAt = _mono;
    final next = dial.value - dy / _wheelPxPerItem;
    dial.snap(next.clamp(stopwatchValue - 0.4, maxMinutes + 0.4));
    _lastWheelAt = _mono;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final pressed = event is KeyDownEvent;
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveDial(1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveDial(-1);
    } else if (pressed && (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter)) {
      _activate();
    } else if (pressed && (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace)) {
      if (session is Selecting) return KeyEventResult.ignored;
      _escape();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Esc and the VoiceOver scrub: pause a run, reset a pause.
  void _escape() {
    switch (session) {
      case Running():
        _activate();
      case Paused():
        _reset();
      case Selecting():
        break;
    }
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  // ───────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final g = scene.geometry;
    if (g == null || g.size != media.size || g.safe != media.padding.deflateRect(Offset.zero & media.size)) {
      scene.geometry = Geometry(media.size, media.padding);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _dayUi ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          onPointerSignal: _onSignal,
          onPointerPanZoomUpdate: (event) => _scroll(-event.panDelta.dy),
          child: Semantics(
            label: _announced,
            value: session is Selecting ? feedText(_selected) : null,
            increasedValue: session is Selecting && _selected < maxMinutes ? feedText(_selected + 1) : null,
            decreasedValue: session is Selecting && _selected > stopwatchValue ? feedText(_selected - 1) : null,
            hint: switch (session) {
              Selecting() => 'Activate to start',
              Running() => 'Activate to pause',
              Paused() => 'Activate to resume',
            },
            onTap: _activate,
            // VoiceOver owns swipes, so reset needs its own doors: a custom
            // action and the two-finger scrub (same as Esc).
            onDismiss: session is Selecting ? null : _escape,
            customSemanticsActions: session is Paused ? {const CustomSemanticsAction(label: 'Reset'): _reset} : null,
            onIncrease: session is Selecting ? () => _moveDial(1) : null,
            onDecrease: session is Selecting ? () => _moveDial(-1) : null,
            child: CustomPaint(painter: painter, size: Size.infinite),
          ),
        ),
      ),
    );
  }
}
