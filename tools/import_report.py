#!/usr/bin/env python3
"""Import a "Share my recordings" report (the short text players copy from the addon, /dm report) into data/manual/.

    tools/import_report.py report.txt        (or: pbpaste | tools/import_report.py -)   [--replace] [--no-gen]

Lines (see addon UI/Report.lua):  DCF <version> build <n>  |  P|instance|floor|boss|x|y  |  D|instance|boss|displayID
Every line is checked: known dungeon, boss name exactly as in Data/Dungeons.lua, coordinates 0..1, floor still shown (not replaced by an overview map).
Positions: a boss that already has a recorded position is NOT changed unless --replace (it is listed as a conflict, for the maintainer to decide).
Writes data/manual/bosses.csv and boss_display.csv, then regenerates Data/Dungeons.lua (tools/gen_dungeons.py) unless --no-gen. Prints a summary of every change.
"""
import csv, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from floors_util import overview_floors, floor_ok

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUNGEONS = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua")
POS = os.path.join(ROOT, "data/manual/bosses.csv")
DISP = os.path.join(ROOT, "data/manual/boss_display.csv")

def boss_names():
    """{instanceMapID (str): {boss name, ...}} from the generated Dungeons.lua."""
    out, cur = {}, None
    for line in open(DUNGEONS, encoding="utf-8"):
        m = re.match(r'  \[(\d+)\] = \{ name = ', line)
        if m:
            cur = m.group(1)
            out[cur] = set()
            continue
        m = re.match(r'    \{ id = \d+, name = "((?:[^"\\]|\\.)*)"', line)
        if m and cur:
            out[cur].add(m.group(1).replace('\\"', '"'))
    return out

def read_rows(path, keys):
    rows = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, encoding="utf-8")):
            rows[tuple(r[k] for k in keys)] = r
    return rows

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--") or a == "-"]
    if not args:
        sys.exit(__doc__)
    text = sys.stdin.read() if args[0] == "-" else open(args[0], encoding="utf-8").read()
    replace = "--replace" in sys.argv
    names, ov = boss_names(), overview_floors()
    pos = read_rows(POS, ("instanceMapID", "name"))
    disp = read_rows(DISP, ("instanceMapID", "name"))
    added, same, conflicts, bad = [], 0, [], []
    head = None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip().strip("`")
        if not line:
            continue
        if line.startswith("DCF "):
            head = line
            continue
        parts = line.split("|")
        kind = parts[0]
        try:
            if kind == "P" and len(parts) == 6:
                inst, floor, name, x, y = parts[1], parts[2], parts[3], float(parts[4]), float(parts[5])
                int(inst); int(floor)
                if inst not in names or name not in names[inst]:
                    raise ValueError("unknown dungeon or boss")
                if not (0 <= x <= 1 and 0 <= y <= 1):
                    raise ValueError("coordinates outside 0..1")
                if not floor_ok(ov, inst, floor):
                    raise ValueError("floor is replaced by an overview map")
                row = {"instanceMapID": inst, "uiMapID": floor, "name": name, "x": f"{x:.4f}", "y": f"{y:.4f}"}
                old = pos.get((inst, name))
                if old and (old["uiMapID"], old["x"], old["y"]) == (row["uiMapID"], row["x"], row["y"]):
                    same += 1
                elif old and not replace:
                    conflicts.append(f"{name} ({inst}): have {old['x']},{old['y']} on {old['uiMapID']}, report says {row['x']},{row['y']} on {floor}")
                else:
                    pos[(inst, name)] = row
                    added.append(f"position  {name} ({inst}) {row['x']},{row['y']} floor {floor}" + (" [replaced]" if old else ""))
            elif kind == "D" and len(parts) == 4:
                inst, name, did = parts[1], parts[2], int(parts[3])
                int(inst)
                if inst not in names or name not in names[inst]:
                    raise ValueError("unknown dungeon or boss")
                old = disp.get((inst, name))
                if old and old["displayID"] == str(did):
                    same += 1
                elif old and not replace:
                    conflicts.append(f"{name} ({inst}) portrait: have {old['displayID']}, report says {did}")
                else:
                    disp[(inst, name)] = {"instanceMapID": inst, "name": name, "displayID": str(did)}
                    added.append(f"portrait  {name} ({inst}) display {did}" + (" [replaced]" if old else ""))
            else:
                raise ValueError("not a P| or D| line")
        except (ValueError, IndexError) as e:
            bad.append(f"line {n}: {e}: {raw.strip()[:80]}")
    print(head or "(no DCF header line)")
    for a in added: print("  +", a)
    if same: print(f"  = {same} already in the data")
    for c in conflicts: print("  ! conflict (not changed, use --replace):", c)
    for b in bad: print("  ? skipped,", b)
    if added:
        with open(POS, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["instanceMapID", "uiMapID", "name", "x", "y"])
            w.writeheader()
            for k in sorted(pos, key=lambda k: (int(k[0]), k[1])): w.writerow(pos[k])
        with open(DISP, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["instanceMapID", "name", "displayID"])
            w.writeheader()
            for k in sorted(disp, key=lambda k: (int(k[0]), k[1])): w.writerow(disp[k])
        if "--no-gen" not in sys.argv:
            subprocess.run([sys.executable, os.path.join(ROOT, "tools/gen_dungeons.py")], check=True)
    print(f"{len(added)} added, {same} unchanged, {len(conflicts)} conflicts, {len(bad)} skipped")

main()
