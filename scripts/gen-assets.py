#!/usr/bin/env python3
"""Regenerate the demo's placeholder icon and sounds. Needs Pillow (pip install pillow).

Writes assets/icon.png (1024px, the one source every platform's icon is cut from),
ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png (no alpha: the App Store rejects it),
windows/icon.ico, assets/catch.wav and assets/hit.wav.
"""
import math, pathlib, struct, wave
from PIL import Image, ImageDraw

root = pathlib.Path(__file__).resolve().parent.parent
S = 4  # supersample
N = 1024 * S
img = Image.new("RGB", (N, N))
px = ImageDraw.Draw(img)
top, bot = (13, 16, 38), (70, 38, 120)
for y in range(N):
    t = y / N
    px.line([(0, y), (N, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bot)))
def star(cx, cy, r, col, rot=0.0):
    pts = []
    for i in range(10):
        a = rot + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.sin(a) * rr, cy - math.cos(a) * rr))
    px.polygon(pts, fill=col)
for i in range(40):
    x, y = (i * 0.618 % 1) * N, (i * 0.377 % 1) * N
    r = (2 + i % 3) * S * 1.5
    px.ellipse([x - r, y - r, x + r, y + r], fill=(200, 205, 240))
star(N * 0.5, N * 0.40, N * 0.27, (255, 205, 80), 0.0)
c = N * 0.5
px.polygon([(c, N * 0.60), (c - N * 0.13, N * 0.86), (c + N * 0.13, N * 0.86)], fill=(120, 225, 235))
px.polygon([(c, N * 0.71), (c - N * 0.05, N * 0.82), (c + N * 0.05, N * 0.82)], fill=(13, 16, 38))
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(root / "assets/icon.png")
img.save(root / "ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
img.save(root / "windows/icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

def tone(path, notes, dur, noise=0.0):
    rate, frames, seed = 44100, [], 12345
    n = int(rate * dur)
    for i in range(n):
        t = i / rate
        f = notes[min(len(notes) - 1, int(len(notes) * i / n))]
        env = min(1, t * 80) * (1 - i / n) ** 2
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        v = math.sin(2 * math.pi * f * t) * (1 - noise) + (seed / 0x3FFFFFFF - 1) * noise
        frames.append(struct.pack("<h", int(v * env * 0.5 * 32767)))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(b"".join(frames))
tone(root / "assets/catch.wav", [880, 1320, 1760], 0.22)
tone(root / "assets/hit.wav", [180, 120, 70], 0.40, noise=0.55)
print("wrote icon + sounds")
