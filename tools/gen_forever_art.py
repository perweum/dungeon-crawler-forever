#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/ArtForever.lua: floor art for Forever-new dungeons from WMO minimap tiles.

The client ships per-group minimap tiles for interior WMOs (Forever DB2 WMOMinimapTexture). Each tile covers a
128x128 yard block. Layout rule (verified visually by research prototypes):
  x_yd = (ymax_all - y1_group) + BlockX*128           (image right = world -y)
  y_yd = (xmax_all - x1_group) + (nBlocksY-1-BlockY)*128   (image down  = world -x)
using the group bounding boxes (MOGI) of the WMO root file. Nothing is shipped but FileDataIDs + offsets.
Only the WMO *root* file is downloaded (small) from wago.tools' public CASC endpoint and cached in tools/cache/.
Usage: tools/gen_forever_art.py
"""
import csv, os, struct, urllib.request, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data/BUILD")).read().strip()
CACHE = os.path.join(ROOT, "tools/cache")
TILE_YD = 128

# instanceMapID -> source. Two kinds:
#   WMO     : interior building tiles (wmoFile = root FileDataID, wmoId = WMOID)           -> yards layout, 128 yd per tile
#             optional orient = "xy": the tiles are placed by their own pixel size (2 px per yard, so a 64x256 tile is 32x128 yd, not a 128 yd square),
#             image right = world +x, image down = world -y, from the corner (min x, max y) of the group box. Checked against the in-game
#             map of the Drowned City's flooded part (the layout rule below, right = -y and down = -x, is the one verified for the Hall of Thanes).
#             optional skipGroups = WMO groups whose tile is not drawn (tiny props, ~2 yd, with 32 px textures that would be blown up to 128 yd)
#   terrain : outdoor ADT minimap tiles from the map's WDT (wdtFile = Map.WdtFileDataID); `crop` = tiles around the centre of the
#             used area, e.g. 1 -> 3x3 tiles   -> yards layout, 533.33 yd per tile (512 px)
SOURCES = {
    3065: {"kind": "wmo", "wmoFile": 7732775, "wmoId": 20708, "floors": [{"name": "The Hall of Thanes"}]},
    # box = (dx0, dx1, dy0, dy1) tile offsets from the centre tile of the used area; the city sits in the upper-left 2x2 tiles
    2959: {"kind": "terrain", "wdtFile": 6982267, "box": (-1, 0, -1, 0), "floors": [{"name": "City of Dalaran"}]},
    # 2026-11-07, build 70862: nobody has been in these dungeons yet, so there is no better map. Preview maps from the outdoor minimap tiles (all tiles of the map).
    # skip = FileDataIDs of flat grey filler tiles that would only draw a grey slab (Blackmaw Hold).
    # extra = more floors of the same dungeon, each its own source (here the flooded interior WMO placed in the terrain, WMOID 20740, 9 minimap tiles)
    2970: {"kind": "terrain", "wdtFile": 6992746, "floors": [{"name": "The Drowned City"}],
           "extra": [{"kind": "wmo", "wmoFile": 7748971, "wmoId": 20740, "orient": "xy", "skipGroups": [8, 9, 10], "floors": [{"name": "Underwater"}]}]},
    2974: {"kind": "terrain", "wdtFile": 7011642, "skip": [7011751, 7011781, 7011811, 7011817, 7011823, 7011829, 7011835, 7011841, 7011847, 7011853, 7011859, 7011865, 7011871], "floors": [{"name": "Blackmaw Hold"}]},
    2994: {"kind": "terrain", "wdtFile": 7244526, "floors": [{"name": "Alcaz Prison"}]},
    3001: {"kind": "terrain", "wdtFile": 7278158, "floors": [{"name": "The Shaper's Terrace"}]},
    3039: {"kind": "terrain", "wdtFile": 7540069, "floors": [{"name": "Krol'dok Stronghold"}]},
}
ADT_YD = 533.33333

def chunks(b):
    i = 0
    while i + 8 <= len(b):
        tag = b[i:i + 4][::-1].decode("latin1")
        n = struct.unpack("<I", b[i + 4:i + 8])[0]
        yield tag, b[i + 8:i + 8 + n]
        i += 8 + n

def download(fid, ext="wmo"):
    os.makedirs(CACHE, exist_ok=True)
    p = os.path.join(CACHE, f"{fid}.{ext}")
    if not os.path.exists(p):
        req = urllib.request.Request(f"https://wago.tools/api/casc/{fid}?download&version={BUILD}", headers={"User-Agent": "dungeon-map-tools/0.1"})
        with urllib.request.urlopen(req, timeout=180) as r, open(p, "wb") as f:
            f.write(r.read())
    return open(p, "rb").read()

def layout(src):
    c = dict(chunks(download(src["wmoFile"])))
    n = struct.unpack("<I", c["MOHD"][4:8])[0]
    wid = struct.unpack("<I", c["MOHD"][32:36])[0]
    assert wid == src["wmoId"], f"WMOID mismatch {wid} != {src['wmoId']}"
    G = {}
    for i in range(n):
        _fl, x0, y0, z0, x1, y1, z1, _no = struct.unpack("<I6fi", c["MOGI"][i * 32:i * 32 + 32])
        G[i] = (x0, y0, z0, x1, y1, z1)
    rows = [r for r in csv.DictReader(open(os.path.join(ROOT, "data/raw", BUILD, "WMOMinimapTexture.csv"), encoding="utf-8")) if r["WMOID"] == str(wid) and int(r["GroupNum"]) not in src.get("skipGroups", ())]
    xmax = max(g[3] for g in G.values())
    ymax = max(g[4] for g in G.values())
    nblocks = collections.defaultdict(int)
    for r in rows:
        nblocks[int(r["GroupNum"])] = max(nblocks[int(r["GroupNum"])], int(r["BlockY"]) + 1)
    if src.get("orient") == "xy":
        xmin = min(g[0] for g in G.values())
        ymax_ = max(g[4] for g in G.values())
        tiles = []
        for r in sorted(rows, key=lambda r: (int(r["GroupNum"]), int(r["BlockX"]), int(r["BlockY"]))):
            g = int(r["GroupNum"])
            x0, y0, z0, x1, y1, z1 = G[g]
            blp = download(int(r["FileDataID"]), "blp")
            assert blp[:4] == b"BLP2", f"tile {r['FileDataID']} is not a BLP2"
            pw, ph = struct.unpack("<II", blp[12:20])
            px = (x0 - xmin) + int(r["BlockX"]) * TILE_YD
            py = (ymax_ - y1) + (nblocks[g] - 1 - int(r["BlockY"])) * TILE_YD
            tiles.append((int(r["FileDataID"]), px, py, g, (z0 + z1) / 2, pw / 2.0, ph / 2.0))
        return tiles
    tiles = []
    for r in sorted(rows, key=lambda r: (int(r["GroupNum"]), int(r["BlockX"]), int(r["BlockY"]))):
        g = int(r["GroupNum"])
        x0, y0, z0, x1, y1, z1 = G[g]
        px = (ymax - y1) + int(r["BlockX"]) * TILE_YD
        py = (xmax - x1) + (nblocks[g] - 1 - int(r["BlockY"])) * TILE_YD
        tiles.append((int(r["FileDataID"]), px, py, g, (z0 + z1) / 2))
    return tiles

def terrain_layout(src):
    """Outdoor minimap tiles: MAIN flags say which ADTs exist, MAID (8 uint32 per tile) holds the minimap FileDataID as value 8."""
    c = dict(chunks(download(src["wdtFile"], "wdt")))
    main, maid = c["MAIN"], c["MAID"]
    found = []
    for i in range(4096):
        if struct.unpack("<I", main[i * 8:i * 8 + 4])[0] & 1:
            v = struct.unpack("<8I", maid[i * 32:i * 32 + 32])
            if v[7]:
                found.append((i % 64, i // 64, v[7]))
    xs, ys = [t[0] for t in found], [t[1] for t in found]
    cx, cy = (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2
    skip = set(src.get("skip", ()))
    found = [t for t in found if t[2] not in skip]
    k, box = src.get("crop"), src.get("box")
    if box:
        keep = [t for t in found if cx + box[0] <= t[0] <= cx + box[1] and cy + box[2] <= t[1] <= cy + box[3]]
    else:
        keep = [t for t in found if k is None or (abs(t[0] - cx) <= k and abs(t[1] - cy) <= k)]
    x0, y0 = min(t[0] for t in keep), min(t[1] for t in keep)
    return [(fid, (x - x0) * ADT_YD, (y - y0) * ADT_YD, ADT_YD) for x, y, fid in sorted(keep, key=lambda t: (t[1], t[0]))]

def main():
    out = ["-- GENERATED by tools/gen_forever_art.py from WMO minimap tiles. Do not edit.",
           "-- [instanceMapID] = floors = { uiMapID (synthetic), name, yards=true, w, h (yards), tiles = { {FileDataID, x, y}, ... } }",
           "-- x/y are yards from the top-left of the floor; a tile is 128 yd square unless it has a 4th value (its size in yards; outdoor ADT tiles = 533.33), or a 4th and 5th (width and height in yards).",
           "local _, ns = ...", "ns.ArtForever = {"]
    for inst, src in SOURCES.items():
        for n, fsrc in enumerate([src] + src.get("extra", []), 1):
            terrain = fsrc.get("kind") == "terrain"
            tiles = terrain_layout(fsrc) if terrain else layout(fsrc)
            sized = (not terrain) and fsrc.get("orient") == "xy"  # tiles with their own width and height (t[5], t[6])
            tw = lambda t: t[3] if terrain else (t[5] if sized else TILE_YD)
            th = lambda t: t[3] if terrain else (t[6] if sized else TILE_YD)
            w = max(t[1] + tw(t) for t in tiles)
            h = max(t[2] + th(t) for t in tiles)
            name = fsrc["floors"][0]["name"]
            if n == 1:
                out.append(f'  [{inst}] = {{ -- {name}')
            def one(t):
                if terrain: return "{%d,%.1f,%.1f,%.1f}" % (t[0], t[1], t[2], t[3])
                if sized: return "{%d,%.1f,%.1f,%.1f,%.1f}" % (t[0], t[1], t[2], t[5], t[6])
                return "{%d,%.1f,%.1f}" % (t[0], t[1], t[2])
            body = ",".join(one(t) for t in tiles)
            out.append(f'    {{ uiMapID = {900000 + inst * 10 + n}, name = "{name}", yards = true, w = {w:.1f}, h = {h:.1f}, tiles = {{{body}}} }},')
            print(f"{inst} floor {n}: {len(tiles)} tiles, canvas {w}x{h} yards")
        out.append("  },")
    out.append("}")
    path = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/ArtForever.lua")
    open(path, "w").write("\n".join(out) + "\n")
    print("wrote", path)

main()
