import 'dart:ui';

part 'glyph_data.g.dart';

final class _GlyphSource {
  const _GlyphSource({
    required this.ends,
    required this.onCurve,
    required this.advances,
    required this.masters,
  });

  final List<int> ends;
  final List<bool> onCurve;
  final List<num> advances;
  final List<List<num>> masters;
}

/// A point in the font's design space: `wdth` in 25..151, `wght` in 250..1000.
typedef Axes = ({double wdth, double wght});

/// Glyph outlines in em units: x grows right, y grows down, baseline at 0.
final class Run {
  const Run(this.glyphs, this.advance, this.top, this.bottom);

  final List<(Path, double)> glyphs;

  /// Total advance width in em.
  final double advance;

  /// Figure top (negative, above baseline) and bottom, in em.
  final double top;
  final double bottom;

}

const wdthMin = 25.0;

abstract final class Glyphs {
  static final _paths = <(String, int, int), Path>{};

  static Run run(String text, Axes axes) {
    final weights = _weights(axes);
    var x = 0.0;
    final glyphs = <(Path, double)>[];
    for (final char in text.split('')) {
      final source = _glyphs[char];
      if (source == null) continue;
      glyphs.add((_path(char, source, axes, weights), x));
      x += _blend(source.advances, weights) / _upm;
    }
    return Run(
      glyphs,
      x,
      -_blend(_figureTop, weights) / _upm,
      -_blend(_figureBottom, weights) / _upm,
    );
  }

  /// Advance width in em, used for fitting. Tabular figures keep this stable per digit count.
  static double advance(String text, Axes axes) {
    final weights = _weights(axes);
    var x = 0.0;
    for (final char in text.split('')) {
      final source = _glyphs[char];
      if (source != null) x += _blend(source.advances, weights) / _upm;
    }
    return x;
  }

  static double figureHeight(Axes axes) {
    final weights = _weights(axes);
    return (_blend(_figureTop, weights) - _blend(_figureBottom, weights)) / _upm;
  }

  static Path _path(String char, _GlyphSource source, Axes axes, List<(int, double)> weights) {
    final key = (char, (axes.wdth * 2).round(), (axes.wght / 4).round());
    final cached = _paths[key];
    if (cached != null) return cached;
    if (_paths.length > 600) _paths.clear();

    final count = source.masters.first.length;
    final points = List<double>.filled(count, 0);
    for (final (master, weight) in weights) {
      final coords = source.masters[master];
      for (var i = 0; i < count; i++) {
        points[i] += coords[i] * weight;
      }
    }
    return _paths[key] = _outline(points, source.ends, source.onCurve);
  }

  /// Bilinear weights over the width x weight master grid (row-major: weight, then width).
  static List<(int, double)> _weights(Axes axes) {
    final (w0, w1, wt) = _segment(_wdthStops, axes.wdth);
    final (g0, g1, gt) = _segment(_wghtStops, axes.wght);
    final columns = _wdthStops.length;
    return [
      (g0 * columns + w0, (1 - wt) * (1 - gt)),
      (g0 * columns + w1, wt * (1 - gt)),
      (g1 * columns + w0, (1 - wt) * gt),
      (g1 * columns + w1, wt * gt),
    ];
  }

  static (int, int, double) _segment(List<num> stops, double value) {
    final v = value.clamp(stops.first.toDouble(), stops.last.toDouble());
    for (var i = 0; i < stops.length - 1; i++) {
      if (v <= stops[i + 1] || i == stops.length - 2) {
        return (i, i + 1, (v - stops[i]) / (stops[i + 1] - stops[i]));
      }
    }
    return (0, 1, 0);
  }

  static double _blend(List<num> values, List<(int, double)> weights) {
    var sum = 0.0;
    for (final (index, weight) in weights) {
      sum += values[index] * weight;
    }
    return sum;
  }

  /// Converts TrueType quadratic contours (font units, y up) into a Path in em (y down).
  static Path _outline(List<double> coords, List<int> ends, List<bool> onCurve) {
    final path = Path();
    var start = 0;
    for (final end in ends) {
      final n = end - start + 1;
      Offset at(int i) {
        final k = start + (i % n);
        return Offset(coords[k * 2] / _upm, -coords[k * 2 + 1] / _upm);
      }

      bool on(int i) => onCurve[start + (i % n)];

      // Find an on-curve start, or synthesize one between two off-curve points.
      var first = 0;
      while (first < n && !on(first)) {
        first++;
      }
      final Offset origin;
      if (first == n) {
        origin = Offset.lerp(at(0), at(1), 0.5)!;
        first = 0;
      } else {
        origin = at(first);
      }
      path.moveTo(origin.dx, origin.dy);

      Offset? control;
      for (var step = 1; step <= n; step++) {
        final i = first + step;
        final point = at(i);
        if (on(i)) {
          if (control == null) {
            path.lineTo(point.dx, point.dy);
          } else {
            path.quadraticBezierTo(control.dx, control.dy, point.dx, point.dy);
            control = null;
          }
        } else {
          if (control != null) {
            final mid = Offset.lerp(control, point, 0.5)!;
            path.quadraticBezierTo(control.dx, control.dy, mid.dx, mid.dy);
          }
          control = point;
        }
      }
      if (control != null) {
        path.quadraticBezierTo(control.dx, control.dy, origin.dx, origin.dy);
      }
      path.close();
      start = end + 1;
    }
    return path;
  }
}
