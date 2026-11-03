import 'package:flutter_test/flutter_test.dart';
import 'package:timer/engine/readout.dart';
import 'package:timer/engine/session.dart';

void main() {
  const t0 = 1000000;
  const minute = 60000;

  test('a timer runs past zero into stopwatch overtime', () {
    final running = const Selecting(25).activate(t0);
    expect(readoutOf(running, t0, use24h: true).hero, '25');
    expect(readoutOf(running, t0 + 1000, use24h: true).label, '24:59');
    expect(readoutOf(running, t0 + 1000, use24h: true).hero, '25');

    final over = readoutOf(running, t0 + 25 * minute + 7000, use24h: true);
    expect(over.day, isTrue);
    expect(over.label, '+00:07');
    expect(over.hero, '+7');
  });

  test('the final minute counts seconds on the hero, starting at 60', () {
    final running = const Selecting(2).activate(t0);
    expect(readoutOf(running, t0 + 58000, use24h: true).hero, '2');
    expect(readoutOf(running, t0 + 60000, use24h: true).hero, '60');
    expect(readoutOf(running, t0 + 61000, use24h: true).hero, '59');
    expect(readoutOf(running, t0 + 119500, use24h: true).hero, '1');
  });

  test('pause freezes and resume continues where it left off', () {
    final running = const Selecting(10).activate(t0);
    final paused = running.activate(t0 + 3 * minute);
    expect(paused, isA<Paused>());
    expect(readoutOf(paused, t0 + 50 * minute, use24h: true).label, '07:00');
    final resumed = paused.activate(t0 + 50 * minute);
    expect(readoutOf(resumed, t0 + 50 * minute + 1000, use24h: true).label, '06:59');
  });

  test('reset lands on the minutes left, or the original value after zero', () {
    expect(const Paused(25, signed: -312000).landingValue, 6);
    expect(const Paused(25, signed: -60000).landingValue, 1);
    expect(const Paused(25, signed: 95000).landingValue, 25);
    expect(const Paused(stopwatchValue, signed: 95000).landingValue, stopwatchValue);
  });

  test('plus starts a stopwatch at zero', () {
    final running = const Selecting(stopwatchValue).activate(t0);
    final r = readoutOf(running, t0 + 61000, use24h: true);
    expect(r.day, isTrue);
    expect(r.hero, '1');
    expect(r.label, '01:01');
  });

  test('sessions survive a JSON round trip', () {
    for (final s in [const Selecting(7), const Running(25, anchor: 42), const Paused(0, signed: 9)]) {
      expect(Session.fromJson(s.toJson()).toJson(), s.toJson());
    }
    expect(Session.fromJson({'kind': 'bogus'}), isA<Selecting>());
  });

  test('long stopwatch labels grow an hour field', () {
    expect(clockDuration(3725), '1:02:05');
  });
}
