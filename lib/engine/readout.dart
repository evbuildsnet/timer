import 'session.dart';

/// Everything the screen needs to show for a session at a moment in time.
final class Readout {
  const Readout({
    required this.hero,
    required this.label,
    required this.day,
    required this.tide,
    required this.announcement,
  });

  /// The massive number: minutes, or seconds within the final/first minute.
  final String hero;

  /// The small line under the hero.
  final String label;

  /// Stopwatch world (light) when true, timer world (dark) when false.
  final bool day;

  /// Fill level 0..1: time left for timers, the current minute for stopwatches.
  final double tide;

  final String announcement;
}

Readout readoutOf(Session session, int now, {required bool use24h}) {
  final signed = session.signedAt(now);
  if (signed == null) return _selection(session.value, now, use24h);
  if (signed < 0) return _countdown(session, -signed);
  return _countup(session, signed);
}

Readout selectionReadout(int value, int now, {required bool use24h}) =>
    _selection(value, now, use24h);

Readout _selection(int value, int now, bool use24h) {
  if (value == stopwatchValue) {
    return const Readout(
      hero: '+',
      label: 'stopwatch',
      day: true,
      tide: 0,
      announcement: 'Stopwatch',
    );
  }
  final end = DateTime.fromMillisecondsSinceEpoch(now + value * 60000);
  final clock = clockTime(end, use24h: use24h);
  return Readout(
    hero: '$value',
    label: 'until $clock',
    day: false,
    tide: value / maxMinutes,
    announcement: '$value ${value == 1 ? 'minute' : 'minutes'}, until $clock',
  );
}

Readout _countdown(Session session, int remainingMs) {
  final seconds = (remainingMs / 1000).ceil();
  final label = clockDuration(seconds);
  return Readout(
    hero: seconds <= 60 ? '$seconds' : '${(seconds / 60).ceil()}',
    label: label,
    day: false,
    tide: (remainingMs / (session.value * 60000)).clamp(0.0, 1.0),
    announcement: '$label left',
  );
}

Readout _countup(Session session, int elapsedMs) {
  final seconds = elapsedMs ~/ 1000;
  final overtime = session.isTimer;
  final sign = overtime ? '+' : '';
  final label = '$sign${clockDuration(seconds)}';
  return Readout(
    hero: '$sign${seconds < 60 ? seconds : seconds ~/ 60}',
    label: label,
    day: true,
    tide: (elapsedMs % 60000) / 60000,
    announcement: overtime ? '$label over' : '$label elapsed',
  );
}

String clockDuration(int totalSeconds) {
  final s = totalSeconds.abs();
  final hours = s ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  final seconds = (s % 60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  return '${minutes.toString().padLeft(2, '0')}:$seconds';
}

String clockTime(DateTime time, {required bool use24h}) {
  final minutes = time.minute.toString().padLeft(2, '0');
  if (use24h) return '${time.hour.toString().padLeft(2, '0')}:$minutes';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:$minutes ${time.hour < 12 ? 'am' : 'pm'}';
}
