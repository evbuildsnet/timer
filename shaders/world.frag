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
uniform float uFlood;   // 0..1 flood rises, 1..2 flood drains (fades under Reduce Motion)
uniform float uRipple;  // decaying per-second pulse
uniform float uDim;     // 0 awake .. 1 paused
uniform float uMode;
uniform float uAlpha;
uniform vec2 uFocus;    // hero center in px, for the light pool
uniform float uStill;   // 1 under Reduce Motion

out vec4 fragColor;

// ÜberCharge palette: a HUD-dark room with a BLU charge draining (timer), a
// HUD-cream room with a RED charge building (stopwatch and overtime), and a
// RED invulnerability flash when time runs out.
const vec3 NIGHT_BG = vec3(0.047, 0.043, 0.040);
const vec3 NIGHT_POOL = vec3(0.112, 0.100, 0.092);
const vec3 NIGHT_TIDE_TOP = vec3(0.070, 0.175, 0.500);
const vec3 NIGHT_TIDE_DEEP = vec3(0.012, 0.030, 0.115);
const vec3 NIGHT_SHEEN = vec3(0.560, 0.790, 1.000);
const vec3 NIGHT_LINE = vec3(0.520, 0.800, 1.000);
const vec3 NIGHT_INK = vec3(0.925, 0.890, 0.800);
const vec3 NIGHT_INK_SUBMERGED = vec3(0.800, 0.900, 1.000);

const vec3 DAY_BG = vec3(0.925, 0.890, 0.812);
const vec3 DAY_POOL = vec3(0.958, 0.932, 0.872);
const vec3 DAY_TIDE_TOP = vec3(0.690, 0.135, 0.105);
const vec3 DAY_TIDE_DEEP = vec3(0.360, 0.035, 0.035);
const vec3 DAY_SHEEN = vec3(1.000, 0.640, 0.540);
const vec3 DAY_LINE = vec3(0.520, 0.060, 0.050);
const vec3 DAY_INK = vec3(0.165, 0.145, 0.135);
const vec3 DAY_INK_SUBMERGED = vec3(0.985, 0.940, 0.860);

const vec3 FLOOD = vec3(0.740, 0.105, 0.085);
const vec3 FLOOD_SHEEN = vec3(1.000, 0.700, 0.600);
const vec3 FLOOD_INK = vec3(1.000, 0.950, 0.880);

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

// The glossy, environment-mapped shine of an invulnerable charge: two drifting
// diagonal streaks bent by a slow warp. Static when time is frozen.
float sheen(vec2 p) {
  vec2 u = p / uSize.y;
  float t = uTime;
  float warp = sin(u.y * 7.0 + t * 0.9) * 0.05 + sin(u.x * 5.0 - t * 0.7) * 0.04;
  float d = u.x * 0.8 + u.y * 0.6 + warp;
  float a = pow(0.5 + 0.5 * sin(d * 6.0 - t * 1.1), 14.0);
  float b = pow(0.5 + 0.5 * sin(d * 2.3 + t * 0.6 + 1.7), 4.0) * 0.6;
  float c = pow(0.5 + 0.5 * sin(d * 17.0 - t * 1.6 + 0.4), 30.0) * 0.5;
  return a + b + c;
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  float present = smoothstep(0.0, 0.015, uTide);
  float level = mix(uSize.y + 24.0, uSize.y * (1.0 - uTide), present);
  float amp = (3.0 + 6.0 * uWave) * present * (1.0 - uDim * 0.8);
  float surface = surfaceAt(p.x, level, amp);
  float under = smoothstep(surface - 0.8, surface + 0.8, p.y);

  // The flood rises over everything, then drains back down into the day tide.
  // Under Reduce Motion it fades in place instead.
  float rise = clamp(uFlood, 0.0, 1.0);
  float drain = uStill > 0.5 ? 0.0 : smoothstep(0.0, 1.0, clamp(uFlood - 1.0, 0.0, 1.0));
  float fade = (uStill > 0.5 ? clamp(2.0 - uFlood, 0.0, 1.0) : 1.0) * step(0.0001, uFlood);
  float floodLevel = mix(mix(uSize.y + 40.0, -60.0, rise), uSize.y + 40.0, drain);
  float floodSurface = surfaceAt(p.x * 1.3 + 40.0, floodLevel, 14.0 * (1.0 - rise * 0.6 * (1.0 - drain)));
  float flooded = smoothstep(floodSurface - 1.0, floodSurface + 1.0, p.y) * fade;
  float shine = sheen(p) * (1.0 - uDim * 0.75);

  if (uMode < 0.5) {
    vec2 q = (p - uFocus) / vec2(uSize.x, uSize.y * 0.7);
    float pool = exp(-dot(q, q) * 2.6);
    vec3 night = mix(NIGHT_BG, NIGHT_POOL, pool * (1.0 - uDim * 0.6));
    vec3 day = mix(DAY_BG, DAY_POOL, pool);

    float depth = clamp((p.y - surface) / (uSize.y * 0.6), 0.0, 1.0);
    // Chrome: a bright horizon just under the surface, streaks below it.
    float horizon = exp(-max(p.y - surface, 0.0) / (uSize.y * 0.08));
    vec3 nightTide = mix(NIGHT_TIDE_TOP, NIGHT_TIDE_DEEP, depth) + NIGHT_SHEEN * (shine * 0.30 + horizon * 0.14);
    vec3 dayTide = mix(DAY_TIDE_TOP, DAY_TIDE_DEEP, depth) + DAY_SHEEN * (shine * 0.24 + horizon * 0.10);
    night = mix(night, nightTide, under * (1.0 - uDim * 0.35));
    day = mix(day, dayTide, under);

    float d = p.y - surface;
    float line = exp(-abs(d) / 1.4) + exp(-max(d, 0.0) / 22.0) * 0.35 * under + exp(-abs(d) / 60.0) * 0.08;
    line *= present * (1.0 - uDim * 0.55);
    night += NIGHT_LINE * line * 0.9;
    day = mix(day, DAY_LINE, clamp(exp(-abs(d) / 1.2) * present, 0.0, 1.0) * 0.85);

    vec3 color = mix(night, day, uDay);
    float floodLine = exp(-abs(p.y - floodSurface) / 3.0) * fade;
    color = mix(color, FLOOD + FLOOD_SHEEN * shine * 0.28, flooded);
    color += FLOOD_SHEEN * floodLine * 0.6;

    vec2 v = (p / uSize) - 0.5;
    color *= 1.0 - dot(v, v) * mix(0.42, 0.05, uDay);
    color += (hash(p + fract(uTime) * 61.0) - 0.5) * 0.018;
    fragColor = vec4(color, 1.0);
    return;
  }

  // Submerged numerals turn to polished metal and catch the same streaks.
  float glint = clamp(shine, 0.0, 1.0) * 0.6;
  vec3 nightInk = mix(NIGHT_INK, mix(NIGHT_INK_SUBMERGED, vec3(1.0), glint), under);
  vec3 dayInk = mix(DAY_INK, mix(DAY_INK_SUBMERGED, vec3(1.0), glint), under);
  nightInk *= 1.0 - uDim * (uMode > 1.5 ? 0.0 : 0.28);
  // A soft top-down light on the night numerals.
  nightInk *= 0.94 + 0.06 * smoothstep(uSize.y, 0.0, p.y);
  // Ink flips (a step, never a fade) where the backdrop crosses mid-grey, so
  // numerals never melt into the backdrop while the world changes rooms.
  vec3 ink = mix(nightInk, dayInk, step(0.5, uDay));
  // Like the room flip, ink switches where the flood is, never fading through grey.
  ink = mix(ink, FLOOD_INK, smoothstep(0.4, 0.6, flooded));

  float alpha = uAlpha * (uMode > 1.5 ? 0.82 : 1.0);
  fragColor = vec4(ink * alpha, alpha);
}
