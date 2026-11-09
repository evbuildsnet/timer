import 'dart:math' as math;

/// A damped spring with unit mass. Everything that moves on screen is one of these.
final class Spring {
  Spring(this.value, {this.stiffness = 260, double dampingRatio = 0.8})
    : target = value,
      damping = 2 * dampingRatio * math.sqrt(stiffness);

  double value;
  double target;
  double velocity = 0;
  double stiffness;
  double damping;

  /// Changes how the spring feels without disturbing its motion.
  void tune(double stiffness, double dampingRatio) {
    this.stiffness = stiffness;
    damping = 2 * dampingRatio * math.sqrt(stiffness);
  }

  bool get settled => (value - target).abs() < 5e-4 && velocity.abs() < 5e-3;

  void snap(double v) {
    value = target = v;
    velocity = 0;
  }

  /// Advances the simulation. Returns true while still moving.
  bool step(double dt) {
    if (settled) {
      value = target;
      velocity = 0;
      return false;
    }
    var remaining = dt;
    while (remaining > 0) {
      final h = math.min(remaining, 1 / 240);
      final force = -stiffness * (value - target) - damping * velocity;
      velocity += force * h;
      value += velocity * h;
      remaining -= h;
    }
    return true;
  }
}
