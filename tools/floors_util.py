"""Shared by import_manual.py and check_recorded.py: which floors of an instance are still shown by the addon.

A dungeon with an overview map (custom art marked `overview = true` in Data/ArtCustom.lua) shows only that map: positions and markers recorded on
the game's older floors of that dungeon are ignored (they are not imported and not reported as missing).
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def overview_floors():
    """{instanceMapID (str): {uiMapID (str), ...}}: for every instance with bundled custom art, the floors that are shown (custom art replaces
    the game's own floors). Positions recorded on other floors of such an instance (the game's old floors, replaced custom maps) are ignored."""
    p = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/ArtCustom.lua")
    out = {}
    if not os.path.exists(p):
        return out
    cur = None
    for line in open(p, encoding="utf-8"):
        m = re.match(r"\s*\[(\d+)\] = \{ -- custom art", line)
        if m:
            cur = m.group(1)
            out[cur] = set()
            continue
        m = re.match(r"\s*\{ uiMapID = (\d+)", line)
        if m and cur:
            out[cur].add(m.group(1))
    return out

def floor_ok(ov, inst, floor):
    """True if a position recorded on `floor` of `inst` is still on a map the addon shows."""
    return str(int(inst)) not in ov or str(int(floor)) in ov[str(int(inst))]
