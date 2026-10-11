#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Art/glow.tga: a soft round white glow (alpha falls off smoothly to 0 at the edge).
Our own texture, 64x64 32-bit TGA (~16 KB). Tinted in-game with SetVertexColor. Usage: tools/.venv/bin/python tools/make_glow.py"""
import math, os
from PIL import Image
N = 64
img = Image.new("RGBA", (N, N))
px = img.load()
for y in range(N):
    for x in range(N):
        r = math.hypot(x - (N - 1) / 2, y - (N - 1) / 2) / (N / 2)   # 0 centre .. 1 edge
        a = max(0.0, 1.0 - r)
        a = a * a * (3 - 2 * a)            # smoothstep: soft shoulder
        a = a ** 1.6                       # heavier falloff = more blur, less hard core
        px[x, y] = (255, 255, 255, int(255 * a))
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "addon/DungeonCrawlerForever/Art/glow.tga")
img.save(out, rle=False)  # uncompressed: safest for the WoW TGA loader
print("wrote", out, os.path.getsize(out), "bytes")
