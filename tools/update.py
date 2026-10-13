#!/usr/bin/env python3
"""One command to refresh all generated data after a game patch.

    tools/update.py --check            show the newest Forever build wago.tools knows and whether data/BUILD is behind
    tools/update.py --latest           switch data/BUILD to the newest build, then regenerate everything
    tools/update.py [--build X.Y.Z.N]  regenerate for a given build (default: data/BUILD)
    add  --atlas <AtlasLoot DungeonsAndRaids folder>  to refresh loot from a different AtlasLoot copy
    add  --cdb <CMaNGOS classic-db .sql>  to also regenerate boss abilities (Data/Abilities.lua) and dungeon quests (Data/Quests.lua)

Steps: fetch DB2 tables -> art (retail tiles, stitched WMO tiles, bundled community art) -> entrances -> dungeons/bosses ->
loot (from AtlasLoot) -> coverage report (data/STATUS.md). Prints what is NEW since the last run: new dungeons and new bosses are
what a human then has to look at (positions, portraits, art). Also keeps the TOC '## Interface' in step with the build.
Run with the venv python: tools/.venv/bin/python tools/update.py ...
"""
import json, os, re, subprocess, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
DUNGEONS = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua")
DEFAULT_ATLAS = "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids"

def run(*args):
    print("\n$", " ".join(a.replace(ROOT + "/", "") for a in args), flush=True)
    subprocess.run(list(args), check=True, cwd=ROOT)

def newest_builds():
    """Newest build per product among Forever builds (version 1.60+; Classic Era is 1.15.x, MoP Classic 5.x)."""
    req = urllib.request.Request("https://wago.tools/api/builds", headers={"User-Agent": "dungeon-map-tools/0.1"})
    data = json.load(urllib.request.urlopen(req, timeout=60))
    out = {}
    for product, builds in data.items():
        forever = [b for b in builds if re.match(r"^1\.(6\d|[7-9]\d)\.", b["version"])]
        if forever:
            b = max(forever, key=lambda b: b["created_at"])
            out[product] = (b["version"], b["created_at"])
    return out

def set_toc_interface(build):
    """Forever build 1.60.1.x -> interface 16001. Keeps the previous two values so players on an older client still load it."""
    major, minor, patch = (int(x) for x in build.split(".")[:3])
    new = major * 10000 + minor * 100 + patch
    toc = os.path.join(ROOT, "addon/DungeonCrawlerForever/DungeonMap.toc")
    text = open(toc, encoding="utf-8").read()
    m = re.search(r"^## Interface: ([0-9, ]+)$", text, re.M)
    old = [int(x) for x in m.group(1).replace(" ", "").split(",") if x] if m else []
    vals = ([new] + [v for v in old if v != new])[:3]
    line = "## Interface: " + ", ".join(str(v) for v in vals)
    text = re.sub(r"^## Interface: .*$", line, text, count=1, flags=re.M)
    open(toc, "w", encoding="utf-8").write(text)
    print(f"TOC {line}")

def snapshot():
    if not os.path.exists(DUNGEONS):
        return {}
    text = open(DUNGEONS, encoding="utf-8").read()
    res = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)".*?bosses = \{\n((?:    \{[^\n]*\n)+)', text):
        res[m.group(2)] = {b for b in re.findall(r'name = "([^"]+)"', m.group(3))}
    return res

def main():
    argv = sys.argv[1:]
    build_file = os.path.join(ROOT, "data/BUILD")
    current = open(build_file).read().strip()
    if "--check" in argv or "--latest" in argv:
        nb = newest_builds()
        for p, (v, t) in nb.items():
            print(f"{p}: newest {v} ({t})")
        print(f"data/BUILD: {current}")
        newest = max((v for v, _ in nb.values()), key=lambda v: [int(x) for x in v.split(".")], default=current)  # product names may change at launch: look at all products
        print("up to date" if newest == current else f"NEWER BUILD AVAILABLE: {newest}")
        if "--latest" not in argv:
            return
        current = newest
    if "--build" in argv:
        current = argv[argv.index("--build") + 1]
    open(build_file, "w").write(current + "\n")
    set_toc_interface(current)
    before = snapshot()
    run("/bin/bash", os.path.join(ROOT, "tools/fetch_db2.sh"), current)
    run(PY, os.path.join(ROOT, "tools/gen_art.py"))
    run(PY, os.path.join(ROOT, "tools/gen_combined.py"))
    run(PY, os.path.join(ROOT, "tools/gen_forever_art.py"))
    run(PY, os.path.join(ROOT, "tools/gen_custom_art.py"))
    run(PY, os.path.join(ROOT, "tools/gen_entrances.py"))
    run(PY, os.path.join(ROOT, "tools/gen_dungeons.py"))
    atlas = argv[argv.index("--atlas") + 1] if "--atlas" in argv else (DEFAULT_ATLAS if os.path.isdir(DEFAULT_ATLAS) else None)
    run(PY, os.path.join(ROOT, "tools/gen_loot.py"), *([atlas] if atlas else []))
    if "--cdb" in argv:  # boss abilities need the CMaNGOS classic-db SQL dump (a large download, so optional)
        run(PY, os.path.join(ROOT, "tools/gen_abilities.py"), argv[argv.index("--cdb") + 1], *([atlas] if atlas else []))
        run(PY, os.path.join(ROOT, "tools/check_dungeon_quests.py"))  # validates data/manual/dungeon_quests.csv before it is merged
        run(PY, os.path.join(ROOT, "tools/gen_quests.py"), argv[argv.index("--cdb") + 1])
    else:
        print("\n(boss abilities and dungeon quests not regenerated: pass --cdb <classic-db.sql> to refresh Data/Abilities.lua and Data/Quests.lua)")
    run(PY, os.path.join(ROOT, "tools/coverage.py"))
    after = snapshot()
    print("\n===== WHAT CHANGED (needs a human) =====")
    new_d = [d for d in after if d not in before]
    for d in new_d:
        print(f"NEW DUNGEON: {d} ({len(after[d])} bosses) -> needs map art, positions, portraits")
    for d in after:
        if d in before and after[d] - before[d]:
            print(f"NEW BOSSES in {d}: {', '.join(sorted(after[d] - before[d]))}")
    gone = [d for d in before if d not in after]
    for d in gone:
        print(f"REMOVED DUNGEON: {d}")
    if not (new_d or gone or any(after[d] - before.get(d, set()) for d in after)):
        print("no new dungeons or bosses")
    print("see data/STATUS.md for the full coverage table")

main()
