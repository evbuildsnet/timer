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
  <radialGradient id="pool" cx="50%" cy="42%" r="65%"><stop offset="0" stop-color="#1D1612"/><stop offset="1" stop-color="#0B0A09"/></radialGradient>
  <linearGradient id="tide" x1="0" y1="{tide}" x2="0" y2="{size}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#3C1B0B"/><stop offset="1" stop-color="#1A0905"/></linearGradient>
  <clipPath id="under"><path d="{wave}"/></clipPath>
  <filter id="glow" x="-10%" y="-200%" width="120%" height="500%"><feGaussianBlur stdDeviation="9"/></filter>
</defs>
<rect width="{size}" height="{size}" fill="url(#pool)"/>
<path d="{wave}" fill="url(#tide)"/>
<g fill="#FFF1DB">{numerals}</g>
<g fill="#FFB24C" clip-path="url(#under)">{numerals}</g>
<path d="{wave.split(' V')[0]}" fill="none" stroke="#FFB04F" stroke-width="16" opacity="0.55" filter="url(#glow)"/>
<path d="{wave.split(' V')[0]}" fill="none" stroke="#FFD08A" stroke-width="4"/>
</svg>'''
Path(sys.argv[1]).write_text(svg)
