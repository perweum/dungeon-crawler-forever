#!/usr/bin/env python3
"""Fill data/manual/boss_display.csv (creature display IDs) for classic-dungeon bosses from CMaNGOS classic-db.

Source: https://github.com/cmangos/classic-db (GPL-3.0) Full_DB/ClassicDB_*.sql.gz, gunzipped to a local file.
creature_template columns used: Entry(0), Name(1), ModelId1(5). Matching is by normalised boss name; bosses that already
have a retail portrait or a display entry are left alone. New (Forever-only) dungeons are skipped: not in a 1.12 database.
Usage: tools/gen_displays_from_cmangos.py <path/to/cdb.sql> [--apply]
"""
import csv, os, re, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
# Forever/retail boss names that differ from the 1.12 database spelling
ALIAS = {"geilhast": "gelihast", "rasfrostwhisperer": "rasfrostwhisper", "kirtonos": "kirtonostheherald",
         "jammalanandogom": "jammalantheprophet"}

def rows_of(line):
    """Yield (entry, name, model1) for each tuple of an INSERT ... VALUES (...),(...); line."""
    s = line[line.index("VALUES") + 6:]
    i, n = 0, len(s)
    while i < n:
        if s[i] != "(":
            i += 1
            continue
        i += 1
        fields, depth_end = [], False
        while len(fields) < 6 and i < n:
            if s[i] == "'":
                j, buf = i + 1, []
                while s[j] != "'":
                    if s[j] == "\\":
                        buf.append(s[j + 1]); j += 2; continue
                    buf.append(s[j]); j += 1
                fields.append("".join(buf)); i = j + 1
            else:
                j = i
                while s[j] not in ",)": j += 1
                fields.append(s[i:j]); i = j
            if s[i] == ",": i += 1
        yield int(fields[0]), fields[1], int(fields[5] or 0)
        # skip the remainder of this tuple (respecting quotes)
        inq = False
        while i < n:
            c = s[i]
            if inq:
                if c == "\\": i += 2; continue
                if c == "'": inq = False
            else:
                if c == "'": inq = True
                elif c == ")": i += 1; break
            i += 1

def main():
    cdb = sys.argv[1]
    names = collections.defaultdict(list)
    for line in open(cdb, encoding="utf-8", errors="replace"):
        if line.startswith("INSERT INTO `creature_template`"):
            for entry, name, model in rows_of(line):
                if model:
                    names[norm(name)].append((entry, model))
    dun = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read()
    have = {}
    live = os.path.join(ROOT, "data/manual/boss_display.csv")
    path = os.path.join(ROOT, "data/draft/boss_display_cmangos.csv")  # staged; copy rows into boss_display.csv to activate
    if os.path.exists(live):
        for r in csv.DictReader(open(live, encoding="utf-8")):
            have[(r["instanceMapID"], r["name"])] = r
    found, missing, ambiguous = [], [], 0
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", raid = (true|false)[^\n]*\n((?:    \{[^\n]*\n)+)', dun):
        inst, dname, raid, body = m.groups()
        if raid == "true" or int(inst) >= 2000:  # skip raids and Forever-new maps
            continue
        seen = set()
        for b in re.finditer(r'name = "([^"]+)"[^\n]*', body):
            bname, line = b.group(1), b.group(0)
            if bname in seen or "portrait =" in line or "display =" in line or (inst, bname) in have:
                continue
            seen.add(bname)
            cands = names.get(norm(bname)) or (names.get(ALIAS[norm(bname)]) if norm(bname) in ALIAS else None)
            if not cands:
                missing.append((dname, bname)); continue
            if len({c[1] for c in cands}) > 1: ambiguous += 1
            found.append((inst, bname, cands[0][1], dname))
    print(f"{len(found)} found, {len(missing)} not matched, {ambiguous} had several different models (first used)")
    for dname, bname in missing: print("  no match:", dname, "-", bname)
    if "--apply" in sys.argv:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["instanceMapID", "name", "displayID"])
            w.writeheader()
            for inst, bname, disp, _ in sorted(found, key=lambda r: (int(r[0]), r[1])):
                w.writerow({"instanceMapID": inst, "name": bname, "displayID": str(disp)})
        print("staged", len(found), "rows ->", path)

main()
