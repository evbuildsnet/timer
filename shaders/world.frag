#version 460 core
#include <flutter/runtime_effect.glsl>

// One program paints the whole scene. uMode picks what this draw is:
//   0 = world (background + tide), 1 = numeral, 2 = label.
// Numerals and labels re-evaluate the same tide surface, so whatever sits
// under the waterline changes color in perfect sync with the background.

uniform vec2 uSize;
uniform float uTime;
uniform float uDay;     // 0 night (timer) .. 1 day (stopwatch)
uniform float uTide;    // 0..1 fill height from the bottom
uniform float uWave;    // 0 still .. 1 alive
uniform float uFlood;   // 0..1 flood rises, 1..2 flood fades
uniform float uRipple;  // decaying per-second pulse
uniform float uDim;     // 0 awake .. 1 paused
uniform float uMode;
uniform float uAlpha;
uniform vec2 uFocus;    // hero center in px, for the light pool

out vec4 fragColor;

const vec3 NIGHT_BG = vec3(0.043, 0.039, 0.035);
const vec3 NIGHT_POOL = vec3(0.105, 0.078, 0.060);
const vec3 NIGHT_TIDE_TOP = vec3(0.235, 0.105, 0.043);
const vec3 NIGHT_TIDE_DEEP = vec3(0.105, 0.040, 0.020);
const vec3 NIGHT_LINE = vec3(1.000, 0.690, 0.330);
const vec3 NIGHT_INK = vec3(1.000, 0.945, 0.860);
const vec3 NIGHT_INK_SUBMERGED = vec3(1.000, 0.700, 0.300);

const vec3 DAY_BG = vec3(0.949, 0.925, 0.878);
const vec3 DAY_POOL = vec3(0.970, 0.952, 0.915);
const vec3 DAY_TIDE_TOP = vec3(0.885, 0.895, 0.950);
const vec3 DAY_TIDE_DEEP = vec3(0.830, 0.850, 0.940);
const vec3 DAY_LINE = vec3(0.176, 0.294, 1.000);
const vec3 DAY_INK = vec3(0.078, 0.071, 0.063);
const vec3 DAY_INK_SUBMERGED = vec3(0.090, 0.170, 0.780);

const vec3 FLOOD = vec3(1.000, 0.720, 0.290);
const vec3 FLOOD_INK = vec3(0.090, 0.050, 0.030);

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float surfaceAt(float x, float level, float amp) {
  float t = uTime;
  float w = sin(x * 0.011 + t * 0.70) * 0.55
          + sin(x * 0.027 - t * 1.10) * 0.30
          + sin(x * 0.061 + t * 1.90) * 0.15;
  float cx = x - uSize.x * 0.5;
  float ripple = uRipple * sin(abs(cx) * 0.045 - t * 9.0) * exp(-abs(cx) / (uSize.x * 0.45));
  return level + amp * w + ripple * 5.0;
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  float present = smoothstep(0.0, 0.015, uTide);
  float level = mix(uSize.y + 24.0, uSize.y * (1.0 - uTide), present);
  float amp = (3.0 + 6.0 * uWave) * present * (1.0 - uDim * 0.8);
  float surface = surfaceAt(p.x, level, amp);
  float under = smoothstep(surface - 0.8, surface + 0.8, p.y);

  float rise = clamp(uFlood, 0.0, 1.0);
  float fade = clamp(2.0 - uFlood, 0.0, 1.0) * step(0.0001, uFlood);
  float floodSurface = surfaceAt(p.x * 1.3 + 40.0, mix(uSize.y + 40.0, -60.0, rise), 14.0 * (1.0 - rise * 0.6));
  float flooded = smoothstep(floodSurface - 1.0, floodSurface + 1.0, p.y) * fade;

  if (uMode < 0.5) {
    vec2 q = (p - uFocus) / vec2(uSize.x, uSize.y * 0.7);
    float pool = exp(-dot(q, q) * 2.6);
    vec3 night = mix(NIGHT_BG, NIGHT_POOL, pool * (1.0 - uDim * 0.6));
    vec3 day = mix(DAY_BG, DAY_POOL, pool);

    float depth = clamp((p.y - surface) / (uSize.y * 0.6), 0.0, 1.0);
    vec3 nightTide = mix(NIGHT_TIDE_TOP, NIGHT_TIDE_DEEP, depth);
    vec3 dayTide = mix(DAY_TIDE_TOP, DAY_TIDE_DEEP, depth);
    night = mix(night, nightTide, under * (1.0 - uDim * 0.35));
    day = mix(day, dayTide, under);

    float d = p.y - surface;
    float line = exp(-abs(d) / 1.4) + exp(-max(d, 0.0) / 22.0) * 0.35 * under + exp(-abs(d) / 60.0) * 0.08;
    line *= present * (1.0 - uDim * 0.55);
    night += NIGHT_LINE * line * 0.9;
    day = mix(day, DAY_LINE, clamp(exp(-abs(d) / 1.2) * present, 0.0, 1.0) * 0.85);

    vec3 color = mix(night, day, uDay);
    float floodLine = exp(-abs(p.y - floodSurface) / 3.0) * fade;
    color = mix(color, FLOOD, flooded);
    color += vec3(1.0, 0.85, 0.6) * floodLine * 0.6;

    vec2 v = (p / uSize) - 0.5;
    color *= 1.0 - dot(v, v) * mix(0.42, 0.05, uDay);
    color += (hash(p + fract(uTime) * 61.0) - 0.5) * 0.018;
    fragColor = vec4(color, 1.0);
    return;
  }

  vec3 nightInk = mix(NIGHT_INK, NIGHT_INK_SUBMERGED, under);
  vec3 dayInk = mix(DAY_INK, DAY_INK_SUBMERGED, under);
  nightInk *= 1.0 - uDim * (uMode > 1.5 ? 0.0 : 0.28);
  // A soft top-down light on the night numerals.
  nightInk *= 0.94 + 0.06 * smoothstep(uSize.y, 0.0, p.y);
  // Ink flips (a step, never a fade) where the backdrop crosses mid-grey, so
  // numerals never melt into the backdrop while the world changes rooms.
  vec3 ink = mix(nightInk, dayInk, step(0.5, uDay));
  ink = mix(ink, FLOOD_INK, flooded);

  float alpha = uAlpha * (uMode > 1.5 ? 0.82 : 1.0);
  fragColor = vec4(ink * alpha, alpha);
}
