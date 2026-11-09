import 'package:flutter_test/flutter_test.dart';
import 'package:timer/ui/feed_scroll.dart';

/// Drags [px] at [pxPerMs], one move per 120 Hz frame. Returns the time it ended.
double drag(FeedScroll feed, {required double px, required double pxPerMs, double from = 0}) {
  const frame = 1000 / 120;
  final steps = (px.abs() / (pxPerMs * frame)).round();
  var now = from;
  for (var i = 0; i < steps; i++) {
    now += frame;
    feed.move(px / steps, now);
  }
  return now;
}

void main() {
  test('a slow drag is targeted: one number per 56 px, no boost', () {
    final feed = FeedScroll(25);
    drag(feed, px: pxPerItem * 3, pxPerMs: 0.2);
    expect(feed.mode, ScrollMode.target);
    expect(feed.finger, closeTo(28, 1e-9));
  });

  test('a quick swipe switches to fast mode and boosts travel', () {
    final feed = FeedScroll(25);
    drag(feed, px: -600, pxPerMs: 2.5);
    expect(feed.mode, ScrollMode.fast);
    expect(25 - feed.finger, greaterThan(600 / pxPerItem * 1.5));
  });

  test('holding still after a fast swipe hands control back to targeting', () {
    final feed = FeedScroll(60);
    final end = drag(feed, px: -500, pxPerMs: 2.5);
    ScrollMode? changed;
    for (var t = end; t < end + 300 && changed == null; t += 16) {
      changed = feed.update(t);
      // Brief hesitations keep the fast swipe going.
      if (t < end + 150) expect(feed.mode, ScrollMode.fast);
    }
    expect(changed, ScrollMode.target);
  });

  test('slowing down without stopping also returns to targeting', () {
    final feed = FeedScroll(60);
    final end = drag(feed, px: -500, pxPerMs: 2.5);
    drag(feed, px: -60, pxPerMs: 0.15, from: end);
    expect(feed.mode, ScrollMode.target);
  });

  test('a targeted release lands on the nearest number', () {
    final feed = FeedScroll(24);
    final end = drag(feed, px: pxPerItem * 0.6, pxPerMs: 0.2);
    final landing = feed.release(feed.target, end + 8);
    expect(landing.mode, ScrollMode.target);
    expect(landing.target, 25);
  });

  test('a short flick glides well past where the finger went', () {
    final feed = FeedScroll(40);
    final end = drag(feed, px: -80, pxPerMs: 2.7);
    final landing = feed.release(feed.finger, end + 8);
    expect(landing.mode, ScrollMode.fast);
    expect(feed.finger - landing.target, greaterThan(5));
    expect(landing.target, landing.target.roundToDouble());
  });

  test('a lift event arriving late still glides', () {
    final feed = FeedScroll(40);
    final end = drag(feed, px: -300, pxPerMs: 2.5);
    expect(feed.release(feed.finger, end + 45).mode, ScrollMode.fast);
  });

  test('a finger that rests before lifting lands where it is', () {
    final feed = FeedScroll(40);
    final end = drag(feed, px: -300, pxPerMs: 2.5);
    final landing = feed.release(feed.finger, end + 150);
    expect(landing.velocity, 0);
    expect(landing.target, closeTo(feed.finger, 2.5));
  });

  test('a glide never leaves the range', () {
    final feed = FeedScroll(5);
    final end = drag(feed, px: -200, pxPerMs: 3);
    expect(feed.release(feed.finger, end + 8).target, 0);
  });

  test('fast glides are drawn to nearby checkpoints only', () {
    expect(FeedScroll.magnet(28.2), 30);
    expect(FeedScroll.magnet(46.9), 45);
    expect(FeedScroll.magnet(22.6), 23);
  });

  test('targeting ticks every number; fast mode clicks only on checkpoints', () {
    expect(FeedScroll.detent(24, 25, ScrollMode.target), Detent.number);
    expect(FeedScroll.detent(24, 25, ScrollMode.fast), Detent.none);
    expect(FeedScroll.detent(14, 15, ScrollMode.fast), Detent.checkpoint);
    expect(FeedScroll.detent(13, 17, ScrollMode.fast), Detent.checkpoint);
    // Arriving at a checkpoint clicks; leaving it does not.
    expect(FeedScroll.detent(16, 15, ScrollMode.fast), Detent.checkpoint);
    expect(FeedScroll.detent(15, 14, ScrollMode.fast), Detent.none);
    expect(FeedScroll.detent(15, 16, ScrollMode.fast), Detent.none);
    // Checkpoints are heavier than numbers even while targeting.
    expect(FeedScroll.detent(29, 30, ScrollMode.target), Detent.checkpoint);
  });

  test('the notch is sticky near numbers, continuous and monotonic', () {
    expect(FeedScroll.notch(25), 25);
    expect(FeedScroll.notch(25.1) - 25, lessThan(0.05));
    expect(FeedScroll.notch(25.5 - 1e-9), closeTo(FeedScroll.notch(25.5 + 1e-9), 1e-6));
    var last = FeedScroll.notch(20);
    for (var x = 20.0; x <= 30; x += 0.01) {
      final y = FeedScroll.notch(x);
      expect(y, greaterThanOrEqualTo(last));
      last = y;
    }
  });

  test('dragging past the ends resists', () {
    final feed = FeedScroll(0);
    drag(feed, px: -pxPerItem, pxPerMs: 0.2);
    expect(feed.finger, inExclusiveRange(-0.35, 0));
  });
}
