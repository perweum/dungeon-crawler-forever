#!/usr/bin/env python3
"""Make addon/DungeonCrawlerForever/Art/welcome-banner.blp (the header of the welcome window) from assets/banner.jpg.

The game wants power-of-two textures: the 2000x661 banner is scaled to 1024x338 and put at the top of a 1024x512 BLP2 (DXT1, with mipmaps, ~350 KB);
the window shows only that part (texture coordinates 0..1 x 0..BANNER_V, see UI/Welcome.lua).
Usage: tools/.venv/bin/python tools/make_banner.py
"""
import os, struct
import etcpak
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/banner.jpg")
OUT = os.path.join(ROOT, "addon/DungeonCrawlerForever/Art/welcome-banner.blp")
W, H = 1024, 512

def blp2(img):
    mips, w, h = [], W, H
    while True:
        level = img if (w, h) == img.size else img.resize((w, h), Image.LANCZOS)
        pw, ph = max(4, w), max(4, h)
        if (pw, ph) != (w, h):  # mip levels smaller than a DXT block are padded
            canvas = Image.new("RGBA", (pw, ph)); canvas.paste(level.convert("RGBA"), (0, 0)); level = canvas
        mips.append(bytes(etcpak.compress_bc1(level.convert("RGBA").tobytes(), pw, ph)))
        if w == 1 and h == 1: break
        w, h = max(1, w // 2), max(1, h // 2)
    header_len = 4 + 4 + 4 + 8 + 64 + 64 + 1024
    offsets, sizes, pos = [0] * 16, [0] * 16, header_len
    for i, m in enumerate(mips):
        offsets[i], sizes[i] = pos, len(m)
        pos += len(m)
    head = b"BLP2" + struct.pack("<I", 1) + bytes([2, 0, 0, 1]) + struct.pack("<II", W, H)
    head += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + b"\0" * 1024
    return head + b"".join(mips)

src = Image.open(SRC).convert("RGB")
bh = round(W * src.size[1] / src.size[0])
canvas = Image.new("RGB", (W, H), (14, 8, 28))
canvas.paste(src.resize((W, bh), Image.LANCZOS), (0, 0))
data = blp2(canvas)
open(OUT, "wb").write(data)
print(f"{OUT}: {len(data) / 1024:.0f} KB, banner is {W}x{bh} of {W}x{H}: BANNER_V = {bh / H:.4f}")
