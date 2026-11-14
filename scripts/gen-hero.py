#!/usr/bin/env python3
"""Draw docs/hero.png, the README banner and social card (1280x640). Needs Pillow.

Composes the title, the platform list and the real demo screenshot (docs/screenshot.png),
so re-run it after re-taking the screenshot. Fonts: macOS system fonts, with a fallback.
"""
import math, pathlib
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = pathlib.Path(__file__).resolve().parent.parent
W, H, S = 1280, 640, 2  # drawn at 2x, saved at 1x
NAVY, PURPLE, GOLD, CYAN, RED, INK = (13, 16, 38), (58, 32, 104), (255, 205, 80), (120, 225, 235), (240, 84, 104), (236, 240, 255)

def font(size, bold=True):
    for path, idx in (("/System/Library/Fonts/SFNSRounded.ttf", 0), ("/System/Library/Fonts/SFNS.ttf", 0),
                      ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
                      ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 0)):
        try:
            f = ImageFont.truetype(path, size * S, index=idx)
            if bold:
                try: f.set_variation_by_name("Bold")
                except Exception: pass
            return f
        except Exception:
            continue
    return ImageFont.load_default()

img = Image.new("RGB", (W * S, H * S))
d = ImageDraw.Draw(img)
for y in range(H * S):  # diagonal-ish gradient
    t = y / (H * S)
    d.line([(0, y), (W * S, y)], fill=tuple(int(a + (b - a) * t ** 1.3) for a, b in zip(NAVY, PURPLE)))
for i in range(140):  # star field
    x, y = (i * 0.6180339 % 1) * W * S, (i * 0.3819660 * 7 % 1) * H * S
    r = (1 + i % 3) * S * 0.9
    d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * (0.35 + 0.5 * ((i * 37) % 10) / 10)) for c in INK))

def star(cx, cy, r, col, rot=0.0):
    pts = []
    for i in range(10):
        a = rot + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.sin(a) * rr, cy - math.cos(a) * rr))
    d.polygon(pts, fill=col)

# the screenshot, tilted card on the right with a soft shadow
shot = Image.open(root / "docs/screenshot.png").convert("RGB")
cw = 540 * S
card = shot.resize((cw, int(cw * shot.height / shot.width)), Image.LANCZOS)
mask = Image.new("L", card.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, card.width - 1, card.height - 1], radius=18 * S, fill=255)
frame = Image.new("RGBA", (card.width + 8 * S, card.height + 8 * S), (0, 0, 0, 0))
ImageDraw.Draw(frame).rounded_rectangle([0, 0, frame.width - 1, frame.height - 1], radius=22 * S, fill=(255, 255, 255, 46))
frame.paste(card, (4 * S, 4 * S), mask)
frame = frame.rotate(-5, resample=Image.BICUBIC, expand=True)
pad = 80 * S  # room for the blur, or the shadow shows a hard edge
shadow = Image.new("RGBA", (frame.width + 2 * pad, frame.height + 2 * pad), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 150), (pad, pad), mask=frame.split()[3])
shadow = shadow.filter(ImageFilter.GaussianBlur(22 * S))
px, py = 700 * S, 160 * S
img.paste(shadow, (px + 6 * S - pad, py + 22 * S - pad), shadow)
img.paste(frame, (px, py), frame)

# title block
x0 = 72 * S
star(x0 + 22 * S, 96 * S, 24 * S, GOLD, 0.2)
d.text((x0 + 58 * S, 74 * S), "open source  ·  MIT  ·  plain C", font=font(22, False), fill=(159, 182, 214))
d.text((x0, 140 * S), "raylib", font=font(92), fill=INK)
d.text((x0, 236 * S), "ship kit", font=font(92), fill=GOLD)
d.text((x0, 362 * S), "One C codebase. Six platforms.", font=font(30), fill=INK)
d.text((x0, 404 * S), "One command each, all the way to App Store review.", font=font(21, False), fill=(190, 200, 232))

# platform chips
chips = [("macOS", CYAN), ("Windows", CYAN), ("Linux", CYAN), ("Web", GOLD), ("iPhone", GOLD), ("iPad", GOLD)]
f = font(20)
x, y = x0, 476 * S
for label, col in chips:
    w = d.textlength(label, font=f) + 32 * S
    d.rounded_rectangle([x, y, x + w, y + 42 * S], radius=21 * S, fill=NAVY, outline=col, width=2 * S)
    d.text((x + 16 * S, y + 8 * S), label, font=f, fill=col)
    x += w + 12 * S
d.text((x0, 548 * S), "$ scripts/ios-appstore.sh && scripts/asc-submit.py", font=ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 18 * S) if pathlib.Path("/System/Library/Fonts/Menlo.ttc").exists() else font(18, False), fill=(150, 165, 205))

img = img.resize((W, H), Image.LANCZOS)
img.save(root / "docs/hero.png", optimize=True)
print("wrote docs/hero.png")
