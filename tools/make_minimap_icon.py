#!/usr/bin/env python3
"""Make addon/DungeonCrawlerForever/Art/minimap-icon.tga (the minimap button's picture) from assets/banner.jpg: the gem staff of the logo, cropped round.
Usage: tools/.venv/bin/python tools/make_minimap_icon.py"""
import os
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.join(ROOT, "assets/banner-1200.jpg")).convert("RGB")
CX, CY, R, N = 372, 255, 78, 64  # centre and radius in the 1200 px banner; the icon is 64x64 and shown at about 22 px
img = src.crop((CX - R, CY - R, CX + R, CY + R)).resize((N * 4, N * 4), Image.LANCZOS)
mask = Image.new("L", (N * 4, N * 4), 0)
ImageDraw.Draw(mask).ellipse((0, 0, N * 4 - 1, N * 4 - 1), fill=255)
img = img.convert("RGBA"); img.putalpha(mask)
img = img.resize((N, N), Image.LANCZOS)
img.save(os.path.join(ROOT, "addon/DungeonCrawlerForever/Art/minimap-icon.tga"))
