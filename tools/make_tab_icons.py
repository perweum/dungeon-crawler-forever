#!/usr/bin/env python3
"""Generate the sidebar tab icons: addon/DungeonCrawlerForever/Art/tab_bosses.tga (skull), tab_quests.tga (exclamation mark), tab_highscore.tga (trophy).
Our own artwork: plain white shapes on transparent, 64x64 32-bit TGA, drawn 4x larger and scaled down for smooth edges. The addon tints them with
SetVertexColor, so they stay one colour. Usage: tools/.venv/bin/python tools/make_tab_icons.py"""
import os
from PIL import Image, ImageDraw
K, N = 4, 64
S = N * K
W = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

def canvas():
    img = Image.new("RGBA", (S, S), CLEAR)
    return img, ImageDraw.Draw(img)

def p(v): return v * K

def skull():
    img, d = canvas()
    d.ellipse([p(10), p(5), p(54), p(46)], fill=W)            # cranium
    d.rounded_rectangle([p(19), p(36), p(45), p(58)], radius=p(5), fill=W)   # jaw
    for x in (27, 32, 37):                                    # teeth gaps
        d.rectangle([p(x) - K // 2, p(48), p(x) + K // 2, p(58)], fill=CLEAR)
    d.ellipse([p(15), p(20), p(29), p(36)], fill=CLEAR)       # eyes
    d.ellipse([p(35), p(20), p(49), p(36)], fill=CLEAR)
    d.polygon([(p(32), p(37)), (p(28), p(46)), (p(36), p(46))], fill=CLEAR)  # nose
    return img

def exclaim():
    img, d = canvas()
    d.polygon([(p(22), p(4)), (p(42), p(4)), (p(37), p(40)), (p(27), p(40))], fill=W)
    d.rounded_rectangle([p(22), p(4), p(42), p(14)], radius=p(5), fill=W)
    d.ellipse([p(23), p(46), p(41), p(62)], fill=W)
    return img

def trophy():
    img, d = canvas()
    d.pieslice([p(14), p(-6), p(50), p(40)], 0, 180, fill=W)  # cup
    d.rectangle([p(14), p(8), p(50), p(18)], fill=W)
    d.rectangle([p(14), p(8), p(50), p(18)], fill=W)
    d.arc([p(2), p(8), p(22), p(30)], 90, 270, fill=W, width=p(4))   # handles
    d.arc([p(42), p(8), p(62), p(30)], 270, 90, fill=W, width=p(4))
    d.rectangle([p(28), p(38), p(36), p(48)], fill=W)         # stem
    d.rounded_rectangle([p(18), p(48), p(46), p(58)], radius=p(3), fill=W)   # base
    return img

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for name, fn in (("tab_bosses", skull), ("tab_quests", exclaim), ("tab_highscore", trophy)):
    out = os.path.join(here, "addon/DungeonCrawlerForever/Art", name + ".tga")
    fn().resize((N, N), Image.LANCZOS).save(out, rle=False)
    print("wrote", out, os.path.getsize(out), "bytes")
