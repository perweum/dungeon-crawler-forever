#!/usr/bin/env python3
"""Generate data/manual/entrances_classic.csv: entrance positions of classic dungeons AND raids on their zone maps.

Source: Forever `Map.Corpse_0/1` (world position where a dead player reappears = just outside the entrance) converted with the
zone's `UiMapAssignment` bounds: u=(R4-y)/(R4-R1), v=(R3-x)/(R3-R0). The zone is chosen by game knowledge (candidate list per
instance; first one whose map actually contains the point wins). Accuracy ~3-5% of the map; fix individual ones in
data/manual/overrides.csv (applied last). Run by tools/update.py before gen_dungeons.py.
"""
import csv, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = open(os.path.join(ROOT, "data/BUILD")).read().strip()
F = os.path.join(ROOT, "data/raw", BUILD)
ZONES = {  # instanceMapID -> candidate zone names (game knowledge)
    33: ["Silverpine Forest"], 34: ["Stormwind City"], 36: ["Westfall"], 43: ["The Barrens"], 47: ["The Barrens"],
    48: ["Ashenvale"], 70: ["Badlands"], 90: ["Dun Morogh"], 109: ["Swamp of Sorrows"], 129: ["The Barrens"],
    189: ["Tirisfal Glades"], 209: ["Tanaris"], 229: ["Burning Steppes", "Searing Gorge"], 230: ["Searing Gorge", "Burning Steppes"],
    289: ["Western Plaguelands"], 329: ["Eastern Plaguelands"], 349: ["Desolace"], 389: ["Orgrimmar"], 429: ["Feralas"],
    # raids
    249: ["Dustwallow Marsh"], 309: ["Stranglethorn Vale"], 409: ["Searing Gorge", "Burning Steppes"],
    469: ["Burning Steppes", "Searing Gorge"], 509: ["Silithus"], 531: ["Silithus"],
}

def main():
    maps = {r["ID"]: r for r in csv.DictReader(open(os.path.join(F, "Map.csv"), encoding="utf-8"))}
    ui = {r["ID"]: r for r in csv.DictReader(open(os.path.join(F, "UiMap.csv"), encoding="utf-8"))}
    assign = {}
    for a in csv.DictReader(open(os.path.join(F, "UiMapAssignment.csv"), encoding="utf-8")):
        u = ui.get(a["UiMapID"])
        if u and u["Type"] == "3":
            assign[(a["MapID"], u["Name_lang"])] = (a["UiMapID"], [float(a["Region_%d" % i]) for i in range(6)])
    rows = []
    for inst, cands in ZONES.items():
        m = maps[str(inst)]
        cx, cy, cm = float(m["Corpse_0"]), float(m["Corpse_1"]), m["CorpseMapID"]
        for zone in cands:
            hit = assign.get((cm, zone))
            if not hit:
                continue
            zid, r = hit
            u, v = (r[4] - cy) / (r[4] - r[1]), (r[3] - cx) / (r[3] - r[0])
            if 0 <= u <= 1 and 0 <= v <= 1:
                rows.append((inst, m["MapName_lang"], zid, round(u, 4), round(v, 4), zone))
                break
        else:
            print("no zone contains the entrance of", inst, m["MapName_lang"])
    path = os.path.join(ROOT, "data/manual/entrances_classic.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["instanceMapID", "name", "entranceZoneUiMapID", "entranceX", "entranceY", "source"])
        for inst, name, zid, u, v, zone in sorted(rows):
            w.writerow([inst, name, zid, u, v, f"derived: Map.Corpse -> {zone} UiMapAssignment"])
    print(f"wrote {path}: {len(rows)} entrances")
    for inst, name, zid, u, v, zone in sorted(rows):
        if inst in (249, 309, 409, 469, 509, 531): print(f"  raid {name}: {zone} {u:.3f}, {v:.3f}")

main()
