#!/usr/bin/env python3
"""Draw the disk image window background: a warm wash, an arrow from Ember to Applications,
and a one-line hint. Writes scripts/dmg/background.png (540x320) and background@2x.png.

The icon centres match release.sh: Ember at (140, 150), Applications at (400, 150).
Run: python3 scripts/make-dmg-background.py [path/to/font.otf]
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 540, 320
S = 2  # draw at 2x, then downscale for the 1x copy
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dmg")

def font(size):
    for path in sys.argv[1:] + [
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
    ]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

img = Image.new("RGB", (W * S, H * S))
d = ImageDraw.Draw(img)

# Vertical wash: soft cream at the top to a warm peach at the bottom.
top, bottom = (252, 246, 238), (247, 226, 206)
for y in range(H * S):
    t = y / (H * S - 1)
    d.line([(0, y), (W * S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

# Arrow between the two icons, in Ember's amber.
amber = (226, 122, 46)
y = 150 * S
x0, x1 = 215 * S, 322 * S
d.rounded_rectangle([x0, y - 4 * S, x1 - 14 * S, y + 4 * S], radius=4 * S, fill=amber)
d.polygon([(x1 - 22 * S, y - 16 * S), (x1 + 4 * S, y), (x1 - 22 * S, y + 16 * S)], fill=amber)

# Hint under the icons (Finder draws the icon labels at about y = 225).
text = "Drag Ember into Applications"
f = font(15 * S)
tw = d.textlength(text, font=f)
d.text(((W * S - tw) / 2, 262 * S), text, font=f, fill=(120, 84, 60))

os.makedirs(OUT, exist_ok=True)
img.save(os.path.join(OUT, "background@2x.png"), optimize=True)
img.resize((W, H), Image.LANCZOS).save(os.path.join(OUT, "background.png"), optimize=True)
print("wrote", OUT)
