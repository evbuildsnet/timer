import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../engine/session.dart';
import '../glyphs/glyph_set.dart';

/// Numeral weight (wght axis). Narrow widths run lighter so counters stay open.
abstract final class Weight {
  static const thin = 270.0;

  static double bold(double wdth) => 790 + 150 * ((wdth - wdthMin) / 75).clamp(0.0, 1.0);

  /// [body] 0 is the paused hairline, 1 the full numeral.
  static double at(double wdth, double body) => thin + (bold(wdth) - thin) * body;
}

/// Body (0..1) of a numeral in each role.
abstract final class Body {
  static const paused = 0.0;
  static const neighbor = 0.72;
  static const selecting = 0.9;
  static const running = 1.0;
}

/// How a piece of text fills a box: the width axis it needs and pixels per em.
typedef Fit = ({double wdth, double scale});

/// Screen layout: where the hero lives and how big everything is.
final class Geometry {
  Geometry(this.size, EdgeInsets padding)
    : safe = padding.deflateRect(Offset.zero & size) {
    final landscape = safe.width > safe.height * 1.15;
    final w = safe.width * (landscape ? 0.82 : 0.94);
    // Landscape leaves room above and below so the feed stays visible on desktops.
    final h = safe.height * (landscape ? 0.52 : 0.6);
    final center = Offset(safe.center.dx, safe.top + safe.height * (landscape ? 0.45 : 0.43));
    heroBox = Rect.fromCenter(center: center, width: w, height: h);
    labelSize = (math.min(size.width, size.height) * 0.052).clamp(15.0, 30.0);
    captionSize = (labelSize * 0.66).clamp(12.0, 18.0);
    referenceHeight = inkHeight(fit(_reference));
  }

  final Size size;
  final Rect safe;
  late final Rect heroBox;
  late final double labelSize;
  late final double captionSize;

  /// Vertical room the label (and optional caption) take under the hero.
  double labelBlock(double caption) => labelSize * 2.1 + captionSize * 1.9 * caption;

  /// Ink height of a two-digit hero, used to space the feed.
  late final double referenceHeight;

  final _fits = <String, Fit>{};

  Offset get heroCenter => heroBox.center;

  double inkHeight(Fit f) => f.scale * Glyphs.figureHeight((wdth: f.wdth, wght: Weight.bold(f.wdth)));

  Fit fit(String text) => _fits[text] ??= _fit(text);

  /// The widest two-digit value: its ink height is shared by every value.
  static const _reference = '88';

  /// Past this the tabular `1` turns into a flag; single digits stay elegant.
  static const _widest = 100.0;

  Fit _fit(String text) {
    double aspect(double wdth) {
      final axes = (wdth: wdth, wght: Weight.bold(wdth));
      return Glyphs.advance(text, axes) / Glyphs.figureHeight(axes);
    }

    // Every value shares the ink height of a two-digit number, so the hero
    // never jumps in size as it ticks from 10 to 9.
    final boxHeight = text == _reference ? heroBox.height : math.min(heroBox.height, referenceHeight);
    final target = heroBox.width / boxHeight;
    double wdth;
    if (aspect(wdthMin) >= target) {
      wdth = wdthMin;
    } else if (aspect(_widest) <= target) {
      wdth = _widest;
    } else {
      var lo = wdthMin, hi = _widest;
      for (var i = 0; i < 18; i++) {
        final mid = (lo + hi) / 2;
        aspect(mid) < target ? lo = mid : hi = mid;
      }
      wdth = (lo + hi) / 2;
    }
    final axes = (wdth: wdth, wght: Weight.bold(wdth));
    final scale = math.min(
      heroBox.width / Glyphs.advance(text, axes),
      boxHeight / Glyphs.figureHeight(axes),
    );
    // A lone plus at full figure height reads as a medical cross; let it breathe.
    return (wdth: wdth, scale: text == '+' ? scale * 0.62 : scale);
  }

  /// Lowest point of the hero's label block (label plus caption), with breathing room.
  double get labelBottom => heroCenter.dy + referenceHeight / 2 + labelBlock(1) + labelSize;

  /// Baseline of the label line, tucked under the hero's ink.
  double labelTop(String hero) {
    final ink = inkHeight(fit(hero));
    return math.min(heroCenter.dy + ink / 2 + labelSize * 0.9, safe.bottom - labelSize * 3.2);
  }
}

/// A value on the selection feed, placed for the current dial position.
typedef FeedItem = ({int value, String text, Offset center, double scale, double alpha, double wdth, double distance});

String feedText(int value) => value == stopwatchValue ? '+' : '$value';

/// Lays out the feed around a fractional dial position. Larger values sit above;
/// values below leave room for the label block under the hero.
List<FeedItem> feedItems(double position, Geometry g, {required double spread, double caption = 0}) {
  final h = g.referenceHeight;
  const small = 0.2;
  final gap = h * 0.1;
  final first = h * 0.5 + gap + h * small * 0.5;
  final rest = h * small + gap * 0.9;
  final below = g.labelBlock(caption);

  double offset(double a, bool down) {
    final reach = first + (down ? below * math.min(a, 1) : 0);
    return a <= 1 ? a * (first + (down ? below : 0)) : reach + (a - 1) * rest;
  }

  double relative(double a) {
    if (a >= 1) return small - 0.04 * math.min(a - 1, 1);
    final t = a * a * (3 - 2 * a);
    return 1 - (1 - small) * t;
  }

  double alphaAt(double a) => a <= 1 ? 1 - 0.62 * a : 0.38 * math.max(0, 1 - (a - 1) * 0.7);

  final items = <FeedItem>[];
  final from = math.max(stopwatchValue, position.floor() - 3);
  final to = math.min(maxMinutes, position.ceil() + 3);
  for (var value = from; value <= to; value++) {
    final d = value - position;
    final a = d.abs();
    final text = feedText(value);
    final f = g.fit(text);
    final push = a > 0.5 ? spread * h * 0.5 : 0.0;
    final y = g.heroCenter.dy - d.sign * (offset(a, d < 0) + push);
    final scale = f.scale * relative(a);
    final halfInk = g.inkHeight(f) * relative(a) / 2;
    // Fade out before touching the status bar or the home indicator.
    final room = math.min(y - halfInk - g.safe.top, g.safe.bottom - (y + halfInk));
    final edge = (room / (h * 0.12) + 1).clamp(0.0, 1.0);
    items.add((
      value: value,
      text: text,
      center: Offset(g.heroCenter.dx, y),
      scale: scale,
      alpha: alphaAt(a) * edge,
      wdth: f.wdth,
      distance: d,
    ));
  }
  return items;
}
