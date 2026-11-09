import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../engine/session.dart';
import '../glyphs/glyph_set.dart';
import 'geometry.dart';

/// A numeral leaving the screen: the old hero during a tick or a reset.
final class Ghost {
  Ghost({
    required this.text,
    required this.fit,
    required this.body,
    required this.direction,
    this.offset = 0,
    this.changed,
  });

  final String text;
  final Fit fit;
  final double body;

  /// Vertical offset the hero had when it left, so it departs from where it was.
  final double offset;

  /// -1 drifts up, +1 drifts down.
  final double direction;

  /// Glyph indices that changed. Null means the whole run leaves.
  final List<bool>? changed;
  double progress = 0;
}

/// Everything the painter needs for one frame. Mutated by the stage, then repainted.
final class Scene extends ChangeNotifier {
  Geometry? geometry;
  double time = 0;

  double day = 0;
  double tide = 0;
  double wave = 1;
  double flood = 0;
  double ripple = 0;
  double dim = 0;

  /// Reduce Motion: the flood fades in place instead of rising and draining.
  bool still = false;

  bool selecting = true;
  double dial = 25;

  /// 1 when the feed is at rest, 0 while it moves. The label only shows at rest,
  /// because moving numerals sweep through its line.
  double feedRest = 1;
  double spread = 0;

  String hero = '25';
  double body = Body.selecting;
  double press = 0;
  double nudge = 0;
  double enter = 1;
  double enterDirection = -1;
  List<bool>? entering;
  final ghosts = <Ghost>[];

  String label = '';
  String caption = '';
  double captionAlpha = 0;

  void repaint() => notifyListeners();
}

final class ScenePainter extends CustomPainter {
  ScenePainter(this.scene, this.program) : super(repaint: scene);

  final Scene scene;
  final ui.FragmentProgram program;
  final _pool = <ui.FragmentShader>[];
  var _used = 0;
  final _labels = <(String, double, double), TextPainter>{};
  final _placed = <(Path, double, double, double, double), Path>{};

  @override
  void paint(Canvas canvas, Size size) {
    final g = scene.geometry;
    if (g == null) return;
    _used = 0;
    final s = scene;

    canvas.drawRect(Offset.zero & size, Paint()..shader = _shader(size, g, 0, 1));

    final feedAlpha = s.selecting ? 1.0 : 1 - s.spread;
    if (feedAlpha > 0.01) {
      for (final item in feedItems(s.dial, g, spread: s.selecting ? 0 : s.spread, caption: s.captionAlpha)) {
        final isCenter = item.distance.abs() < 0.5;
        if (!s.selecting && isCenter) continue;
        final alpha = item.alpha * (isCenter ? s.enter : feedAlpha);
        if (alpha < 0.01) continue;
        final t = (1 - item.distance.abs()).clamp(0.0, 1.0);
        _glyphs(
          canvas,
          item.text,
          center: item.center,
          scale: item.scale,
          wdth: item.wdth,
          body: Body.neighbor + (Body.selecting - Body.neighbor) * t,
          paint: Paint()..shader = _shader(size, g, 1, alpha),
        );
      }
    }

    if (!s.selecting) _hero(canvas, size, g);
    _ghosts(canvas, size, g);
    _texts(canvas, size, g);
  }

  void _hero(Canvas canvas, Size size, Geometry g) {
    final s = scene;
    final fit = g.fit(s.hero);
    final squashX = 1 + 0.035 * s.press;
    final squashY = 1 - 0.07 * s.press;
    final center = g.heroCenter.translate(0, s.nudge);
    final travel = g.referenceHeight * 0.32;
    final entering = s.entering;

    final steady = Paint()..shader = _shader(size, g, 1, 1);
    final incoming = Paint()..shader = _shader(size, g, 1, s.enter.clamp(0.0, 1.0));
    _glyphs(
      canvas,
      s.hero,
      center: center,
      scale: fit.scale,
      wdth: fit.wdth,
      body: s.body,
      sx: squashX,
      sy: squashY,
      paint: steady,
      include: entering == null ? null : (i) => i >= entering.length || !entering[i],
    );
    if (entering != null) {
      _glyphs(
        canvas,
        s.hero,
        center: center.translate(0, -s.enterDirection * (1 - s.enter) * travel),
        scale: fit.scale * (0.9 + 0.1 * s.enter),
        wdth: fit.wdth,
        body: s.body,
        sx: squashX,
        sy: squashY,
        paint: incoming,
        include: (i) => i < entering.length && entering[i],
        slotScale: fit.scale,
      );
    }
  }

  void _ghosts(Canvas canvas, Size size, Geometry g) {
    final travel = g.referenceHeight * 0.32;
    for (final ghost in scene.ghosts) {
      final p = ghost.progress.clamp(0.0, 1.0);
      final alpha = (1 - p) * (1 - p) * (1 - p);
      if (alpha < 0.01) continue;
      final changed = ghost.changed;
      final center = g.heroCenter.translate(0, ghost.offset);
      _glyphs(
        canvas,
        ghost.text,
        center: center.translate(0, ghost.direction * p * travel),
        scale: ghost.fit.scale * (1 - 0.12 * p),
        wdth: ghost.fit.wdth,
        body: ghost.body,
        paint: Paint()..shader = _shader(size, g, 1, alpha),
        include: changed == null ? null : (i) => i < changed.length && changed[i],
        slotScale: ghost.fit.scale,
      );
    }
  }

  void _texts(Canvas canvas, Size size, Geometry g) {
    final s = scene;
    final top = s.selecting ? _feedLabelTop(g) : g.labelTop(s.hero);
    // Between values the feed's numerals sweep through the label's line, so the
    // label steps aside while the feed moves and returns as it settles.
    final settled = s.selecting ? s.feedRest : 1.0;
    if (s.label.isNotEmpty && settled > 0.01) {
      _label(canvas, size, g, s.label, g.labelSize, 600, top + s.nudge * 0.6, settled);
    }
    if (s.captionAlpha * settled > 0.01 && s.caption.isNotEmpty) {
      _label(canvas, size, g, s.caption, g.captionSize, 520, top + g.labelSize * 1.7 + s.nudge * 0.6, s.captionAlpha * settled);
    }
  }

  /// Glides between neighbors' label positions so the line never jumps mid-scroll.
  double _feedLabelTop(Geometry g) {
    final p = scene.dial.clamp(stopwatchValue.toDouble(), maxMinutes.toDouble());
    final below = g.labelTop(feedText(p.floor()));
    final above = g.labelTop(feedText(p.ceil()));
    return below + (above - below) * (p - p.floor());
  }

  void _label(Canvas canvas, Size size, Geometry g, String text, double fontSize, double weight, double top, double alpha) {
    final painter = _labels[(text, fontSize, weight)] ??= _layoutLabel(text, fontSize, weight);
    final offset = Offset(g.heroCenter.dx - painter.width / 2, top);
    final bounds = (offset & painter.size).inflate(2);
    canvas.saveLayer(bounds, Paint());
    painter.paint(canvas, offset);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = _shader(size, g, 2, alpha),
    );
    canvas.restore();
  }

  TextPainter _layoutLabel(String text, double fontSize, double weight) {
    if (_labels.length > 8) {
      for (final painter in _labels.values) {
        painter.dispose();
      }
      _labels.clear();
    }
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Label',
          fontSize: fontSize,
          color: const Color(0xFFFFFFFF),
          letterSpacing: fontSize * 0.04,
          fontVariations: [FontVariation('wght', weight)],
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Draws a numeral run centered on [center]. Glyph slots are laid out at
  /// [slotScale] (defaults to [scale]) so a subset drawn at another scale stays
  /// in its slot.
  void _glyphs(
    Canvas canvas,
    String text, {
    required Offset center,
    required double scale,
    required double wdth,
    required double body,
    required Paint paint,
    double sx = 1,
    double sy = 1,
    double? slotScale,
    bool Function(int index)? include,
  }) {
    final run = Glyphs.run(text, (wdth: wdth, wght: Weight.at(wdth, body.clamp(0.0, 1.03))));
    final kx = scale * sx;
    final ky = scale * sy;
    final slot = (slotScale ?? scale) * sx;
    final left = center.dx - run.advance * slot / 2;
    final baseline = center.dy - (run.top + run.bottom) / 2 * ky;
    for (var i = 0; i < run.glyphs.length; i++) {
      if (include != null && !include(i)) continue;
      final (path, x) = run.glyphs[i];
      final next = i + 1 < run.glyphs.length ? run.glyphs[i + 1].$2 : run.advance;
      final half = (next - x) / 2;
      canvas.drawPath(_place(path, kx, ky, left + (x + half) * slot - half * kx, baseline), paint);
    }
  }

  /// Bakes the transform into the path (the shader reads local coordinates,
  /// so the canvas itself stays untransformed). Cached while the hero is still.
  Path _place(Path path, double kx, double ky, double tx, double ty) {
    final key = (path, kx, ky, tx, ty);
    final cached = _placed[key];
    if (cached != null) return cached;
    if (_placed.length > 48) _placed.clear();
    final matrix = Float64List(16)
      ..[0] = kx
      ..[5] = ky
      ..[10] = 1
      ..[12] = tx
      ..[13] = ty
      ..[15] = 1;
    return _placed[key] = path.transform(matrix);
  }

  ui.FragmentShader _shader(Size size, Geometry g, double mode, double alpha) {
    if (_used == _pool.length) _pool.add(program.fragmentShader());
    final shader = _pool[_used++];
    final s = scene;
    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, s.time)
      ..setFloat(i++, s.day)
      ..setFloat(i++, s.tide)
      ..setFloat(i++, s.wave)
      ..setFloat(i++, s.flood)
      ..setFloat(i++, s.ripple)
      ..setFloat(i++, s.dim)
      ..setFloat(i++, mode)
      ..setFloat(i++, alpha)
      ..setFloat(i++, g.heroCenter.dx)
      ..setFloat(i++, g.heroCenter.dy)
      ..setFloat(i++, s.still ? 1 : 0);
    return shader;
  }

  @override
  bool shouldRepaint(ScenePainter oldDelegate) => oldDelegate.scene != scene;
}
