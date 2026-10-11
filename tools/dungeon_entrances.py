#!/usr/bin/env python3
"""Convert Map.csv Corpse_0/Corpse_1/CorpseMapID (dungeon entrance world x,y) to normalized UiMap positions.

World coords: x = north(+)/south(-), y = west(+)/east(-). UiMapAssignment.Region_0/1 = world (x,y) of one corner,
Region_3/4 = the opposite one; on the map image the LEFT edge is max world y and the TOP edge is max world x:
    u = (y_max - y) / (y_max - y_min)    v = (x_max - x) / (x_max - x_min)       (then UiMin + u*(UiMax-UiMin) ...)
Zone boxes overlap (they are bounding boxes, not polygons), so pick the containing box where the point is farthest from the
box edge (score = -min(u,1-u,v,1-v)); this resolves Wailing Caverns/Zul'Farrak/Scholomance correctly.
Caveat: Map.Corpse_* is the ghost/entrance anchor and can be tens of yards off the portal; use as a +-1% hint. Usage: tools/dungeon_entrances.py [csv-out]
"""
import csv, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data/raw/1.60.1.70291")
ui = {r["ID"]: r for r in csv.DictReader(open(os.path.join(D, "UiMap.csv"), encoding="utf-8"))}
assign = list(csv.DictReader(open(os.path.join(D, "UiMapAssignment.csv"), encoding="utf-8")))

def to_ui(uimap, x, y, a):
    x0, y0, x1, y1 = (float(a[k]) for k in ("Region_0", "Region_1", "Region_3", "Region_4"))
    xmin, xmax, ymin, ymax = min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1)
    if not (xmin <= x <= xmax and ymin <= y <= ymax):
        return None
    u = (ymax - y) / (ymax - ymin); v = (xmax - x) / (xmax - xmin)
    u0, v0, u1, v1 = (float(a[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
    return u0 + u * (u1 - u0), v0 + v * (v1 - v0), -min(u, 1 - u, v, 1 - v)

# Zone boxes overlap, so the zone is disambiguated by the zone name published for each dungeon (zockify/foreverdb tables).
ZONE_HINT = {"33": "Silverpine Forest", "34": "Stormwind City", "36": "Westfall", "43": "The Barrens", "47": "The Barrens",
             "48": "Ashenvale", "70": "Badlands", "90": "Dun Morogh", "109": "Swamp of Sorrows", "129": "The Barrens",
             "189": "Tirisfal Glades", "209": "Tanaris", "229": "Burning Steppes", "230": "Searing Gorge",
             "289": "Western Plaguelands", "329": "Eastern Plaguelands", "349": "Desolace", "389": "Orgrimmar", "429": "Feralas"}
CONTINENT = {"0": "1415", "1": "1414"}  # canonical continent uiMaps (1463/1464 are alternate classic continents)

def locate(mapid, x, y, types, hint=None):
    best = None
    for a in assign:
        if a["MapID"] != str(mapid) or ui.get(a["UiMapID"], {}).get("Type") not in types:
            continue
        if hint and ui[a["UiMapID"]]["Name_lang"] != hint:
            continue
        if types == ("2",) and a["UiMapID"] != CONTINENT[str(mapid)]:
            continue
        r = to_ui(a["UiMapID"], x, y, a)
        if r and (best is None or r[2] < best[3]):
            best = (a["UiMapID"], round(r[0], 4), round(r[1], 4), r[2])
    return best

def main():
    rows = []
    for m in csv.DictReader(open(os.path.join(D, "Map.csv"), encoding="utf-8")):
        if m["InstanceType"] != "1" or float(m["Corpse_0"]) == 0 and float(m["Corpse_1"]) == 0:
            continue
        cm = m["CorpseMapID"]; x, y = float(m["Corpse_0"]), float(m["Corpse_1"])
        z = locate(cm, x, y, ("3",), ZONE_HINT.get(m["ID"])) or locate(cm, x, y, ("3",)); c = locate(cm, x, y, ("2",))
        rows.append((m["ID"], m["MapName_lang"], cm, x, y, z, c))
    out = ["instanceMapID,name,corpseMapID,worldX,worldY,zoneUiMapID,zoneU,zoneV,continentUiMapID,contU,contV"]
    for i, n, cm, x, y, z, c in rows:
        out.append(",".join(map(str, [i, '"%s"' % n, cm, x, y, *(z[:3] if z else ("", "", "")), *(c[:3] if c else ("", "", ""))])))
    text = "\n".join(out) + "\n"
    if len(sys.argv) > 1: open(sys.argv[1], "w").write(text)
    print(text)
main()
