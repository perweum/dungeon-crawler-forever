#!/usr/bin/env python3
"""Check that every row of data/manual/abilities_extra.csv made it into the generated Data/Abilities.lua (under its instance and boss),
that every boss in data/manual/abilities_verified.csv has exactly its verified spells (no entry when verified as none; extra rows for
such a boss are ignored, as the generator does), and that no boss lists a spell ID twice. Used by tools/test/run.py."""
import csv, os, sys
from lupa import LuaRuntime
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXTRA = os.path.join(ROOT, "data/manual/abilities_extra.csv")
VERIFIED = os.path.join(ROOT, "data/manual/abilities_verified.csv")
DATA = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Abilities.lua")

def load_abilities(path=DATA):
    """Run the generated file the way the game does (addon name, ns) and return {instanceMapID: {boss: [spellID, ...]}}."""
    L = LuaRuntime()
    ns = L.table()
    chunk = L.eval("load")(open(path, encoding="utf-8").read(), "@Abilities.lua")
    chunk("DungeonCrawlerForever", ns)
    return {int(inst): {boss: [int(s) for s in ids.values()] for boss, ids in bosses.items()} for inst, bosses in ns.Abilities.items()}

def load_verified(path=VERIFIED):
    """{(instanceMapID, boss): set of spellIDs} (empty set = verified: no abilities)."""
    out = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                ids = out.setdefault((int(r["instanceMapID"]), r["boss"].strip()), set())
                if (r["spellID"] or "").strip():
                    ids.add(int(r["spellID"]))
    return out

def problems(extra_path=EXTRA, data_path=DATA, verified_path=VERIFIED):
    bad, ab, verified = [], load_abilities(data_path), load_verified(verified_path)
    for (inst, boss), want in sorted(verified.items()):
        have = ab.get(inst, {}).get(boss)
        if not want and have is not None:
            bad.append(f"Abilities.lua [{inst}][{boss}]: verified as no abilities, but has {have}")
        elif want and set(have or []) != want:
            bad.append(f"Abilities.lua [{inst}][{boss}]: {have} differs from the verified list {sorted(want)}")
    for inst, bosses in ab.items():
        for boss, ids in bosses.items():
            if len(ids) != len(set(ids)):
                bad.append(f"Abilities.lua [{inst}][{boss}]: duplicate spell IDs {ids}")
    if os.path.exists(extra_path):
        with open(extra_path, encoding="utf-8") as f:
            for n, r in enumerate(csv.DictReader(f), start=2):
                inst, boss, sp = int(r["instanceMapID"]), r["boss"].strip(), int(r["spellID"])
                if (inst, boss) in verified:
                    continue  # a verified list replaces the extra rows
                if sp not in ab.get(inst, {}).get(boss, []):
                    bad.append(f"{os.path.relpath(extra_path, ROOT)}:{n}: spell {sp} for [{inst}][{boss}] is missing from Abilities.lua")
    return bad

if __name__ == "__main__":
    bad = problems()
    for b in bad:
        print(b)
    sys.exit(1 if bad else 0)
