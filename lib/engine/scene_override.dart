import 'session.dart';

/// Parses `kind,value,signedSeconds` into a session, for previews and QA.
/// Examples: `selecting,25` · `running,25,-754` · `paused,25,-312` · `running,0,42`.
Session? parseScene(String? spec, int now) {
  if (spec == null || spec.isEmpty) return null;
  final parts = spec.split(',');
  final value = int.tryParse(parts.elementAtOrNull(1) ?? '')?.clamp(stopwatchValue, maxMinutes);
  if (value == null) return null;
  final signed = (num.tryParse(parts.elementAtOrNull(2) ?? '') ?? -value * 60) * 1000;
  return switch (parts.first) {
    'selecting' => Selecting(value),
    'running' => Running(value, anchor: now - signed.round()),
    'paused' => Paused(value, signed: signed.round()),
    _ => null,
  };
}
