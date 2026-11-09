"""Renders the app icon SVG from the same Roboto Flex numerals the app uses.

Run: uv run --with fonttools python -I tool/build_icon.py <out.svg>
"""

import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
font = instancer.instantiateVariableFont(
    TTFont(ROOT / "tool/fonts/RobotoFlex.ttf"),
    {"opsz": 144, "YTFI": 788, "wdth": 25, "wght": 940, "GRAD": 0, "slnt": 0},
)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()

paths, x = [], 0
for ch in "25":
    name = cmap[ord(ch)]
    pen = SVGPathPen(glyphs)
    glyphs[name].draw(pen)
    paths.append((pen.getCommands(), x))
    x += font["hmtx"][name][0]
bounds = BoundsPen(glyphs)
glyphs[cmap[ord("8")]].draw(bounds)
top = bounds.bounds[3]

size = 1024
ink_w = x
scale = size * 0.80 / ink_w
height = top * scale
ox = (size - ink_w * scale) / 2
baseline = size * 0.5 + height / 2
tide = size * 0.60
numerals = "".join(
    f'<path transform="translate({ox + gx * scale:.1f},{baseline:.1f}) scale({scale:.4f},{-scale:.4f})" d="{d}"/>'
    for d, gx in paths
)
wave = f"M0 {tide} C {size*0.25} {tide-22}, {size*0.5} {tide+20}, {size*0.75} {tide-8} S {size} {tide+6}, {size} {tide} V {size} H 0 Z"

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">
<defs>
  <radialGradient id="pool" cx="50%" cy="42%" r="65%"><stop offset="0" stop-color="#1D1A17"/><stop offset="1" stop-color="#0C0B0A"/></radialGradient>
  <linearGradient id="tide" x1="0" y1="{tide}" x2="0" y2="{size}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#173A9C"/><stop offset="1" stop-color="#030A24"/></linearGradient>
  <clipPath id="under"><path d="{wave}"/></clipPath>
  <linearGradient id="sheen" x1="0" y1="{size}" x2="{size}" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0.36" stop-color="#FFF" stop-opacity="0"/><stop offset="0.45" stop-color="#FFF" stop-opacity="0.30"/><stop offset="0.5" stop-color="#FFF" stop-opacity="0"/><stop offset="0.63" stop-color="#FFF" stop-opacity="0"/><stop offset="0.66" stop-color="#FFF" stop-opacity="0.20"/><stop offset="0.69" stop-color="#FFF" stop-opacity="0"/></linearGradient>
  <filter id="glow" x="-10%" y="-200%" width="120%" height="500%"><feGaussianBlur stdDeviation="9"/></filter>
</defs>
<rect width="{size}" height="{size}" fill="url(#pool)"/>
<path d="{wave}" fill="url(#tide)"/>
<g fill="#ECE3CC">{numerals}</g>
<g fill="#CCE5FF" clip-path="url(#under)">{numerals}</g>
<rect width="{size}" height="{size}" fill="url(#sheen)" clip-path="url(#under)"/>
<path d="{wave.split(' V')[0]}" fill="none" stroke="#5FA8FF" stroke-width="16" opacity="0.6" filter="url(#glow)"/>
<path d="{wave.split(' V')[0]}" fill="none" stroke="#CDE8FF" stroke-width="4"/>
</svg>'''
Path(sys.argv[1]).write_text(svg)
