import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timer/glyphs/glyph_set.dart';
import 'package:timer/ui/geometry.dart';

void main() {
  test('every hero fits its box on phones and desktops', () {
    for (final size in const [Size(390, 844), Size(844, 390), Size(1440, 900), Size(320, 568)]) {
      final g = Geometry(size, EdgeInsets.zero);
      for (final text in ['+', '1', '9', '25', '88', '125', '+42']) {
        final f = g.fit(text);
        final axes = (wdth: f.wdth, wght: Weight.bold(f.wdth));
        expect(Glyphs.advance(text, axes) * f.scale, lessThanOrEqualTo(g.heroBox.width + 0.01));
        expect(Glyphs.figureHeight(axes) * f.scale, lessThanOrEqualTo(g.heroBox.height + 0.01));
      }
    }
  });

  test('two digits fill the width of a portrait phone', () {
    final g = Geometry(const Size(390, 844), EdgeInsets.zero);
    final f = g.fit('25');
    expect(Glyphs.advance('25', (wdth: f.wdth, wght: Weight.bold(f.wdth))) * f.scale, closeTo(g.heroBox.width, 0.5));
  });
}
