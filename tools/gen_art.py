#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/Art.lua: per-instance floor art as FileDataID tile grids.

Source: public DB2 tables from wago.tools (retail 'live' build for the art chain, Forever build for the
instance list). Nothing copied from third-party addons. Re-run per build.
Usage: tools/gen_art.py [--refresh]
"""
import csv, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOREVER = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data/BUILD")).read().strip()
LIVE = os.path.join(ROOT, "data/raw/live")
FOREVER_DIR = os.path.join(ROOT, "data/raw", FOREVER)
TABLES = ["UiMapAssignment", "UiMapXMapArt", "UiMapArt", "UiMapArtStyleLayer", "UiMapArtTile", "UiMap", "UiMapGroupMember"]

def fetch(name, refresh):
    os.makedirs(LIVE, exist_ok=True)
    path = os.path.join(LIVE, name + ".csv")
    if refresh or not os.path.exists(path):
        req = urllib.request.Request(f"https://wago.tools/db2/{name}/csv", headers={"User-Agent": "dungeon-map-tools/0.1"})
        with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
            f.write(r.read())
    return list(csv.DictReader(open(path, encoding="utf-8")))

def main():
    refresh = "--refresh" in sys.argv
    D = {t: fetch(t, refresh) for t in TABLES}
    maps = {r["ID"]: r for r in csv.DictReader(open(os.path.join(FOREVER_DIR, "Map.csv"), encoding="utf-8"))}
    ui = {r["ID"]: r for r in D["UiMap"]}
    xart = {}
    for r in D["UiMapXMapArt"]:
        xart.setdefault(r["UiMapID"], r["UiMapArtID"])
    artstyle = {r["ID"]: r["UiMapArtStyleID"] for r in D["UiMapArt"]}
    layer = {}
    for r in D["UiMapArtStyleLayer"]:
        if r["LayerIndex"] == "0":
            layer[r["UiMapArtStyleID"]] = r
    tiles = {}
    for r in D["UiMapArtTile"]:
        if r["LayerIndex"] == "0":
            tiles.setdefault(r["UiMapArtID"], {})[(int(r["RowIndex"]), int(r["ColIndex"]))] = r["FileDataID"]
    group, gname = {}, {}  # uiMapID -> floor index within its group / floor name
    for r in D["UiMapGroupMember"]:
        group[r["UiMapID"]] = int(r["FloorIndex"]) if "FloorIndex" in r else 0
        if r.get("Name_lang"):
            gname[r["UiMapID"]] = r["Name_lang"]

    # extra floors from other retail maps attached to an instance (e.g. the Legion Upper Blackrock Spire maps for map 229)
    extras = {}
    ep = os.path.join(ROOT, "data/manual/art_extra.csv")
    if os.path.exists(ep):
        for r in csv.DictReader(open(ep, encoding="utf-8")):
            extras.setdefault(r["instanceMapID"], []).append(r["uiMapID"])

    by_instance = {}
    bounds = {}  # uiMapID -> world bounds of the floor image (Region_0, Region_1, Region_3, Region_4): used by the edit-mode floor overlay
    for r in D["UiMapAssignment"]:
        by_instance.setdefault(r["MapID"], set()).add(r["UiMapID"])
        if r["UiMapID"] not in bounds:
            bounds[r["UiMapID"]] = [float(r["Region_%d" % i]) for i in (0, 1, 3, 4)]

    # legacy world map textures (Interface/WorldMap/<Name>/<Name><floor>_<1..12>.blp): 12 consecutive FileDataIDs per floor, named
    # in string order (_1, _10, _11, _12, _2 ... _9), laid out 4 columns x 3 rows by their number. Listed in data/manual/art_legacy.csv.
    legacy = {}
    lp = os.path.join(ROOT, "data/manual/art_legacy.csv")
    ORDER = ["1", "10", "11", "12", "2", "3", "4", "5", "6", "7", "8", "9"]
    if os.path.exists(lp):
        for r in csv.DictReader(open(lp, encoding="utf-8")):
            first = int(r["firstFileDataID"])
            ids = {int(n): first + ORDER.index(n) for n in ORDER}
            grid = "{" + ",".join("{" + ",".join(str(ids[row * 4 + col + 1]) for col in range(4)) + "}" for row in range(3)) + "}"
            uid = 600000 + int(r["instanceMapID"]) * 10 + int(r["floor"])
            legacy.setdefault(r["instanceMapID"], []).append(
                f'    {{ uiMapID = {uid}, name = "{r["name"]}", legacy = true, w = 1002, h = 668, tile = 256, tiles = {grid} }},')

    forder = {}  # hand-set floor order per instance (the game's order is not always the order you walk through a dungeon)
    fp = os.path.join(ROOT, "data/manual/floor_order.csv")
    if os.path.exists(fp):
        for r in csv.DictReader(open(fp, encoding="utf-8")):
            forder[r["instanceMapID"]] = r["order"].split(";")
    out, missing = [], []
    for mid, m in sorted(maps.items(), key=lambda kv: int(kv[0])):
        if m["InstanceType"] not in ("1", "2"):
            continue
        cands = [u for u in by_instance.get(mid, ()) if ui.get(u, {}).get("Type") in ("4", "6") and u in xart]
        if not cands:
            missing.append((mid, m["MapName_lang"]))
            continue
        floors = sorted(cands, key=lambda u: (group.get(u, 0), int(u))) + [u for u in extras.get(mid, []) if u in xart and u not in cands]
        if mid in forder:  # data/manual/floor_order.csv: listed floors first, in that order; the rest keep the game's order
            first = [u for u in forder[mid] if u in floors]
            floors = first + [u for u in floors if u not in first]
        entries = []
        for u in floors:
            art = xart[u]
            g = tiles.get(art)
            if not g:
                continue
            lay = layer.get(artstyle.get(art, ""), {})
            rows = max(k[0] for k in g) + 1
            cols = max(k[1] for k in g) + 1
            grid = "{" + ",".join("{" + ",".join(g.get((r, c), "0") for c in range(cols)) + "}" for r in range(rows)) + "}"
            nm = gname.get(u, "")
            nm = ', name = "' + nm.replace('"', "'") + '"' if nm else ""
            bd = bounds.get(u)
            bd = ", bounds = {" + ",".join("%g" % round(v, 1) for v in bd) + "}" if bd else ""
            entries.append(f'    {{ uiMapID = {u}{nm}{bd}, artID = {art}, w = {lay.get("LayerWidth", 0)}, h = {lay.get("LayerHeight", 0)}, tile = {lay.get("TileWidth", 256)}, tiles = {grid} }},')
        entries += legacy.pop(mid, [])
        out.append(f'  [{mid}] = {{ -- {m["MapName_lang"]}\n' + "\n".join(entries) + "\n  },")
    path = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Art.lua")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("-- GENERATED by tools/gen_art.py from public DB2 (wago.tools). Do not edit.\n")
        f.write("-- [instanceMapID] = floors = { uiMapID, artID, w, h, tile, tiles[row][col] = FileDataID }\n")
        f.write("local _, ns = ...\nns.ArtData = {\n" + "\n".join(out) + "\n}\n")
    print(f"wrote {path}: {len(out)} instances with art")
    print("no retail art for:", ", ".join(f"{i} {n}" for i, n in missing))

main()
