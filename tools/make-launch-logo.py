#!/usr/bin/env python3
"""Makes the launch screen's logo: the platter from the app icon, with the name under it.

The launch screen shows one image at its own size, in the middle of the screen, so it's all in one picture.
Needs Pillow. Run it again if the icon or the name changes: python3 tools/make-launch-logo.py
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PLATTER = 180  # points across
RADIUS = 442 / 1024  # the icon's platter, out to its dark outer ring, as a share of the icon's width
GAP = 18  # points between the platter and the name
TEXT = 24  # points
TRACKING = 3  # points between letters
FONT = "/System/Library/Fonts/Supplemental/DIN Alternate Bold.ttf"  # the same as the app's control lettering
WHITE = (236, 238, 242, 255)
BLUE = (33, 133, 255, 255)  # the icon's spindle
NAME = [("SEGUE", WHITE), (" ", WHITE), ("DJ", BLUE)]
SCALE = 3  # the largest size it's drawn at

assets = Path(__file__).resolve().parent.parent / "Cheeks" / "Assets.xcassets"
icon = Image.open(assets / "AppIcon.appiconset" / "AppIcon.png").convert("RGB")
side = icon.width
radius = side * RADIUS
platter = icon.crop((round(side / 2 - radius), round(side / 2 - radius), round(side / 2 + radius), round(side / 2 + radius)))

# Drawn large and scaled down, for a clean edge.
mask = Image.new("L", (platter.width * 4, platter.height * 4), 0)
ImageDraw.Draw(mask).ellipse((0, 0, mask.width - 1, mask.height - 1), fill=255)
platter.putalpha(mask.resize(platter.size, Image.LANCZOS))
platter = platter.resize((PLATTER * SCALE, PLATTER * SCALE), Image.LANCZOS)

font = ImageFont.truetype(FONT, TEXT * SCALE)
letters = [(letter, color) for word, color in NAME for letter in word]
tracking = TRACKING * SCALE
text_width = round(sum(font.getlength(letter) for letter, _ in letters) + tracking * (len(letters) - 1))
ascent, descent = font.getmetrics()

width = max(platter.width, text_width)
height = platter.height + GAP * SCALE + ascent + descent
width += width % SCALE and SCALE - width % SCALE  # whole points, so it lands on the same pixels at every scale
height += height % SCALE and SCALE - height % SCALE
logo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
logo.paste(platter, ((width - platter.width) // 2, 0), platter)
draw = ImageDraw.Draw(logo)
x = (width - text_width) / 2
for letter, color in letters:
    draw.text((x, platter.height + GAP * SCALE), letter, font=font, fill=color)
    x += font.getlength(letter) + tracking

folder = assets / "LaunchLogo.imageset"
folder.mkdir(exist_ok=True)
images = []
for scale in (1, 2, 3):
    name = f"LaunchLogo@{scale}x.png"
    logo.resize((width * scale // SCALE, height * scale // SCALE), Image.LANCZOS).save(folder / name, optimize=True)
    images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
(folder / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print(f"{width // SCALE}x{height // SCALE} points")
