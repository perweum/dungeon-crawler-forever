#!/usr/bin/env python3
"""Convert a map image into 256x256 BLP2 (DXT1) tiles for addon/DungeonCrawlerForever/Art/.

Usage: tools/.venv/bin/python tools/jpg2blp.py <image> <instanceMapID> [floor=1] [--size 1536x1024]
Writes <instanceMapID>_<floor>_<row>_<col>.blp (1-based) with a full mipmap chain, then run
tools/gen_custom_art.py && tools/gen_dungeons.py. DXT1 = 4 bits/pixel, so a 6x4 grid is ~0.8 MB.
Source images are NOT kept in the repo (see data/SOURCES.md for licence/credit).
"""
import os, struct, sys
import numpy as np
import etcpak
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "addon/DungeonCrawlerForever/Art")
TILE = 256

def dxt1(img):
    """img: PIL RGB(A) of any size >=1 -> DXT1 bytes (pads to multiples of 4 by edge replication)."""
    w, h = img.size
    pw, ph = max(4, (w + 3) // 4 * 4), max(4, (h + 3) // 4 * 4)
    if (pw, ph) != (w, h):
        canvas = Image.new("RGBA", (pw, ph))
        canvas.paste(img.convert("RGBA"), (0, 0))
        for x in range(w, pw): canvas.paste(canvas.crop((w - 1, 0, w, ph)), (x, 0))
        for y in range(h, ph): canvas.paste(canvas.crop((0, h - 1, pw, h)), (0, y))
        img = canvas
    rgba = img.convert("RGBA").tobytes()
    return bytes(etcpak.compress_bc1(rgba, pw, ph))

def blp2(tile):
    mips = []
    img = tile.convert("RGB")
    w = h = TILE
    while True:
        mips.append(dxt1(img.resize((w, h), Image.LANCZOS) if (w, h) != img.size else img))
        if w == 1 and h == 1: break
        w, h = max(1, w // 2), max(1, h // 2)
    header_len = 4 + 4 + 4 + 8 + 64 + 64 + 1024
    offsets, sizes, pos = [0] * 16, [0] * 16, header_len
    for i, m in enumerate(mips):
        offsets[i], sizes[i] = pos, len(m)
        pos += len(m)
    # magic, type=1, encoding=2 (DXT), alphaDepth=0, alphaEncoding=0 (DXT1), hasMips=1, width, height
    head = b"BLP2" + struct.pack("<I", 1) + bytes([2, 0, 0, 1]) + struct.pack("<II", TILE, TILE)
    head += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + b"\0" * 1024
    assert len(head) == header_len
    return head + b"".join(mips)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    size = (1536, 1024)
    if "--size" in sys.argv:
        size = tuple(int(v) for v in sys.argv[sys.argv.index("--size") + 1].split("x"))
        args = [a for a in args if a != sys.argv[sys.argv.index("--size") + 1]]
    src, inst = args[0], int(args[1])
    floor = int(args[2]) if len(args) > 2 else 1
    assert size[0] % TILE == 0 and size[1] % TILE == 0, "size must be a multiple of 256"
    im = Image.open(src).convert("RGB").resize(size, Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for r in range(size[1] // TILE):
        for c in range(size[0] // TILE):
            tile = im.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE))
            data = blp2(tile)
            path = os.path.join(OUT, f"{inst}_{floor}_{r + 1}_{c + 1}.blp")
            open(path, "wb").write(data)
            total += len(data)
    print(f"{size[0] // TILE * (size[1] // TILE)} tiles, {total / 1024:.0f} KB -> {OUT}")

main()
