#!/usr/bin/env python3
"""Draw the addon icon (original artwork, no game assets) -> docs/icon/icon-1024.png and icon-512.png (CurseForge avatar).
Run: tools/.venv/bin/python tools/make_icon.py"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs/icon")
N = 2048  # drawn big, scaled down for crisp edges
os.makedirs(OUT, exist_ok=True)
random.seed(7)

def chamfer(box, c):
    x0, y0, x1, y1 = box
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]

def vgrad(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    arr = (np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t) * np.ones((1, w, 1))
    return Image.fromarray(arr.astype("uint8"))

def grain(img, amount):
    a = np.asarray(img).astype("int16")
    noise = np.random.default_rng(3).normal(0, amount, a.shape[:2])[:, :, None]
    return Image.fromarray(np.clip(a + noise, 0, 255).astype("uint8"))

img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# 1 dark rounded background with a warm vertical gradient
bg = vgrad((N, N), (44, 30, 18), (18, 12, 8)).convert("RGBA")
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, N - 1, N - 1), radius=300, fill=255)
img.paste(bg, (0, 0), mask)
d = ImageDraw.Draw(img)

# 2 bronze double border with cut corners (same shape language as the sidebar boxes)
d.polygon(chamfer((70, 70, N - 70, N - 70), 190), outline=(201, 153, 63, 255), width=34)
d.polygon(chamfer((128, 128, N - 128, N - 128), 160), outline=(92, 62, 24, 255), width=12)

# 3 parchment map with grain
inner = chamfer((170, 170, N - 170, N - 170), 140)
parch = grain(vgrad((N, N), (226, 192, 128), (178, 134, 72)), 7)
pm = Image.new("L", (N, N), 0)
ImageDraw.Draw(pm).polygon(inner, fill=255)
img.paste(parch.convert("RGBA"), (0, 0), pm)
d = ImageDraw.Draw(img)

# 4 dungeon layout: one connected silhouette with a single dark outline and lighter floors, like a Blizzard dungeon map
ROOM, EDGE, FLOOR = (143, 98, 52, 255), (80, 50, 20, 255), (170, 120, 64, 255)
rooms = [(300, 300, 800, 700), (1000, 280, 1560, 600), (1120, 760, 1740, 1120), (300, 900, 820, 1320), (760, 1380, 1380, 1720)]
halls = [(780, 420, 1020, 520), (1220, 590, 1340, 780), (800, 980, 1140, 1090), (500, 690, 610, 920), (1040, 1100, 1160, 1400),
         (800, 1250, 880, 1400)]
shapes = rooms + halls
for box in shapes:  # outline first (inflated), so overlapping shapes merge into one silhouette
    d.rounded_rectangle((box[0] - 18, box[1] - 18, box[2] + 18, box[3] + 18), radius=46, fill=EDGE)
for box in shapes:
    d.rounded_rectangle(box, radius=30, fill=ROOM)
for box in rooms:
    d.rounded_rectangle((box[0] + 44, box[1] + 44, box[2] - 44, box[3] - 44), radius=22, fill=FLOOR)

# 5 boss pins: gold ring, dark disc; the big one carries a skull
def pin(cx, cy, r, skull=True):
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((cx - r * 1.5, cy - r * 1.5, cx + r * 1.5, cy + r * 1.5), fill=(255, 205, 90, 120))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(r * 0.45)))
    dd = ImageDraw.Draw(img)
    dd.ellipse((cx - r - 16, cy - r - 16, cx + r + 16, cy + r + 16), fill=(40, 24, 8, 255))
    dd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(224, 176, 70, 255))
    dd.ellipse((cx - r + 22, cy - r + 22, cx + r - 22, cy + r - 22), fill=(30, 20, 14, 255))
    if skull:
        s = r * 0.6
        bone = (236, 226, 204, 255)
        dd.ellipse((cx - s, cy - s * 1.05, cx + s, cy + s * 0.55), fill=bone)           # cranium
        dd.rounded_rectangle((cx - s * 0.58, cy + s * 0.1, cx + s * 0.58, cy + s * 0.95), radius=int(s * 0.18), fill=bone)  # jaw
        for ex in (-0.36, 0.36):                                                          # eye sockets
            dd.ellipse((cx + s * ex - s * 0.24, cy - s * 0.35, cx + s * ex + s * 0.24, cy + s * 0.1), fill=(30, 20, 14, 255))
        dd.polygon([(cx, cy + s * 0.08), (cx - s * 0.12, cy + s * 0.32), (cx + s * 0.12, cy + s * 0.32)], fill=(30, 20, 14, 255))
        for tx in (-0.3, -0.1, 0.1, 0.3):                                                  # teeth
            dd.line((cx + s * tx, cy + s * 0.62, cx + s * tx, cy + s * 0.92), fill=(30, 20, 14, 255), width=8)

pin(1430, 940, 170)
pin(550, 500, 105)
pin(560, 1120, 105)
pin(1070, 1550, 105)
pin(1280, 440, 90)

# 6 infinity sign ("Forever") stamped into the bottom of the parchment: a lemniscate
inf = Image.new("RGBA", (N, N), (0, 0, 0, 0))
di = ImageDraw.Draw(inf)
cx, cy, a = N // 2, N - 232, 100
pts = []
for i in range(0, 361, 2):
    t = math.radians(i)
    dn = 1 + math.sin(t) ** 2
    pts.append((cx + a * 1.9 * math.cos(t) / dn, cy + a * 1.9 * math.sin(t) * math.cos(t) / dn))
di.line(pts + [pts[0]], fill=(86, 54, 22, 255), width=24, joint="curve")
img.alpha_composite(inf)

# inner shadow on the parchment edge for depth
edge = Image.new("L", (N, N), 0)
ImageDraw.Draw(edge).polygon(inner, outline=255, width=26)
shadow = Image.new("RGBA", (N, N), (30, 16, 4, 150))
sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sh.paste(shadow, (0, 0), edge.filter(ImageFilter.GaussianBlur(14)))
img.alpha_composite(sh)

for size in (1024, 512):
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"icon-{size}.png"))
print("wrote", OUT)
