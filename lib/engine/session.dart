/// One time axis: a signed clock where negative means "time left" and positive
/// means "time counted". A timer starts below zero and simply keeps going past
/// it, which turns it into a stopwatch. `+` (value 0) starts right at zero.
library;

const stopwatchValue = 0;
const maxMinutes = 90;
const _minute = 60000;

sealed class Session {
  const Session(this.value);

  /// Selected feed value: 0 is the stopwatch, 1..90 are minutes.
  final int value;

  bool get isTimer => value > stopwatchValue;

  Map<String, Object> toJson() => switch (this) {
    Selecting() => {'kind': 'selecting', 'value': value},
    Running(:final anchor) => {'kind': 'running', 'value': value, 'anchor': anchor},
    Paused(:final signed) => {'kind': 'paused', 'value': value, 'signed': signed},
  };

  static Session fromJson(Object? json) {
    if (json case {'kind': final String kind, 'value': final int value}) {
      final v = value.clamp(stopwatchValue, maxMinutes);
      return switch ((kind, json)) {
        ('running', {'anchor': final int anchor}) => Running(v, anchor: anchor),
        ('paused', {'signed': final int signed}) => Paused(v, signed: signed),
        _ => Selecting(v),
      };
    }
    return const Selecting(defaultMinutes);
  }

  static const defaultMinutes = 25;
}

final class Selecting extends Session {
  const Selecting(super.value);
}

final class Running extends Session {
  const Running(super.value, {required this.anchor});

  /// Epoch ms at which the signed clock reads zero.
  final int anchor;
}

final class Paused extends Session {
  const Paused(super.value, {required this.signed});

  /// Frozen signed clock in ms.
  final int signed;
}

extension SessionClock on Session {
  /// Signed clock in ms, or null while selecting.
  int? signedAt(int now) => switch (this) {
    Selecting() => null,
    Running(:final anchor) => now - anchor,
    Paused(:final signed) => signed,
  };

  /// Primary action: start the selection, pause a run, resume a pause.
  Session activate(int now) => switch (this) {
    Selecting(:final value) => Running(value, anchor: now + value * _minute),
    Running(:final value, :final anchor) => Paused(value, signed: now - anchor),
    Paused(:final value, :final signed) => Running(value, anchor: now - signed),
  };

  /// Where the feed lands after resetting: the minutes that were left, or the
  /// original value once the timer has run past zero.
  int get landingValue => switch (this) {
    Paused(:final signed) when signed < 0 => (-signed / _minute).ceil().clamp(1, maxMinutes),
    _ => value,
  };
}
