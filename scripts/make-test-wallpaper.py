#!/usr/bin/env python3
"""Directional test wallpaper for scripts/kwin-nested-test.sh.

Draws ONE asymmetric pattern at the nested session's resolution: a solid
background, a fine 100 px grid with coordinate labels every 400 px, big
edge labels (IZQ / DER / ARR / ABA), a fat arrow from the centre toward
ARR (top) and a magenta square pinned to the TOP-LEFT corner. Nothing in
it is symmetric, so a mirrored or rotated face (cube side or cap, ADR-027)
betrays itself at a glance and the hull edges stay findable.

Why one image for all desktops: Plasma 6.8.3 cannot assign a different
wallpaper per virtual desktop (measured 2026-11-27: no per-desktop keys in
/usr/share/plasma/wallpapers/org.kde.image/contents/config/main.xml, no
per-desktop logic in the plugin, and the upstream request is still open:
KDE bug 155150). The harness labels each desktop instead with a maximised
E<n> window (scripts/test-wallpaper-label.py).

The PNG is generated at run time inside the harness' private root and is
never committed, so the repo carries no binary asset to license.

Usage: make-test-wallpaper.py --output PATH [--width 1600] [--height 900]
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GRID_PX = 100  # fine grid: the user measures stretching on cube faces
LABEL_EVERY = 400  # coordinate labels only every N px to keep it readable

BACKGROUND = (32, 60, 108)  # steel blue, far from magenta/yellow/white
GRID = (128, 140, 160)  # low-contrast so labels and arrow pop
TEXT = (255, 255, 255)
STROKE = (10, 10, 10)  # outline so white text survives any background
ACCENT = (255, 205, 0)  # arrow: yellow, distinct from every label colour
CORNER = (255, 0, 255)  # magenta quadrant: the unique corner marker

FONT_CANDIDATES = (
  "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",  # Arch
  "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",  # Debian/Flatpak-ish
)


def load_font(px: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
  """Biggest-capable bold font; PIL's built-in scaler font as fallback."""
  for path in FONT_CANDIDATES:
    try:
      return ImageFont.truetype(path, px)
    except OSError:
      continue
  try:
    return ImageFont.load_default(size=px)
  except TypeError:  # Pillow < 10.1 has no size argument
    return ImageFont.load_default()


def draw_centered(
  draw: ImageDraw.ImageDraw,
  cx: int,
  cy: int,
  text: str,
  font,
  stroke: int = 0,
) -> None:
  """Centred text without relying on anchor support of the font backend."""
  box = draw.textbbox((0, 0), text, font=font, stroke_width=stroke)
  draw.text(
    (cx - (box[0] + box[2]) // 2, cy - (box[1] + box[3]) // 2),
    text,
    font=font,
    fill=TEXT,
    stroke_width=stroke,
    stroke_fill=STROKE,
  )


def draw_arrow(draw: ImageDraw.ImageDraw, w: int, h: int) -> None:
  """Fat shaft + solid head, centre to the TOP edge: a lone mirror maps
  it onto itself, but the magenta corner does not, and together they
  separate mirror from rotation."""
  cx, cy = w // 2, h // 2
  # Tip kept below the ARR edge label so neither one hides the other.
  tip_y = int(h * 0.18)
  head_h = max(40, h // 12)
  head_w = max(60, w // 22)
  shaft_w = max(10, w // 70)
  draw.line([(cx, cy), (cx, tip_y + head_h - shaft_w)], fill=ACCENT, width=shaft_w)
  draw.polygon(
    [
      (cx, tip_y),
      (cx - head_w // 2, tip_y + head_h),
      (cx + head_w // 2, tip_y + head_h),
    ],
    fill=ACCENT,
  )
  # Centre marker: the image origin the cube maps onto.
  ring = max(6, w // 120)
  draw.ellipse(
    [cx - ring, cy - ring, cx + ring, cy + ring], fill=TEXT, outline=STROKE, width=3
  )


def generate(path: Path, width: int, height: int) -> None:
  img = Image.new("RGB", (width, height), BACKGROUND)
  draw = ImageDraw.Draw(img)

  for x in range(GRID_PX, width, GRID_PX):
    draw.line([(x, 0), (x, height)], fill=GRID, width=1)
  for y in range(GRID_PX, height, GRID_PX):
    draw.line([(0, y), (width, y)], fill=GRID, width=1)

  f_small = load_font(max(14, height // 45))
  for x in range(LABEL_EVERY, width, LABEL_EVERY):
    draw.text((x + 4, 4), str(x), fill=TEXT, font=f_small)
  for y in range(LABEL_EVERY, height, LABEL_EVERY):
    draw.text((4, y + 4), str(y), fill=TEXT, font=f_small)

  # Unique corner marker: top-left quadrant-sized magenta square.
  draw.rectangle([0, 0, width // 4, height // 4], fill=CORNER)
  f_mid = load_font(max(24, height // 14))
  draw.text(
    (16, 16), "ARR-IZQ", fill=TEXT, font=f_mid, stroke_width=2, stroke_fill=STROKE
  )

  # Big labels on the four edges (ASCII on purpose: no accent glyph can
  # fail on a minimal font).
  f_big = load_font(max(40, height // 7))
  pad = max(30, height // 14)
  draw_centered(draw, width // 2, pad, "ARR", f_big, stroke=3)
  draw_centered(draw, width // 2, height - pad, "ABA", f_big, stroke=3)
  draw_centered(draw, pad, height // 2, "IZQ", f_big, stroke=3)
  draw_centered(draw, width - pad, height // 2, "DER", f_big, stroke=3)

  draw_arrow(draw, width, height)

  path.parent.mkdir(parents=True, exist_ok=True)
  img.save(path, "PNG")


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--output", required=True, type=Path, help="PNG to write")
  ap.add_argument("--width", type=int, default=1600)
  ap.add_argument("--height", type=int, default=900)
  args = ap.parse_args()

  if args.width < 2 * GRID_PX or args.height < 2 * GRID_PX:
    print(f"error: min size is {2 * GRID_PX}x{2 * GRID_PX}", file=sys.stderr)
    return 2

  generate(args.output, args.width, args.height)
  print(args.output)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
