#!/usr/bin/env python3
"""Check data/manual/dungeon_quests.csv: every quest id exists in the Forever client's quest list (data/raw/<build>/QuestV2.csv),
faction / where values are valid, and the dungeon is a known instance. Exit code 1 on problems.
Columns: instanceMapID,questID,name,level,minLevel,faction,races,where,giver,giverZone,coords,turnin,turninZone,prereq,chain,step,note
  races = names separated by ";" (empty = all races of the faction)
  where = outside (picked up before the dungeon) | inside | item (started by an item) | attune (key / attunement)
  faction = Horde | Alliance | empty (both); instanceMapID 0 = not assigned to a dungeon yet."""
import csv, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
build = open(os.path.join(ROOT, "data/BUILD")).read().strip()
client = {int(r["ID"]) for r in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/QuestV2.csv"), encoding="utf-8"))}
dungeons = {int(m.group(1)) for m in re.finditer(r"^  \[(\d+)\] = \{ name =", open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read(), re.M)}
problems, seen = [], set()
for n, r in enumerate(csv.DictReader(open(os.path.join(ROOT, "data/manual/dungeon_quests.csv"), encoding="utf-8")), 2):
    where = f"line {n} ({r['name'] or r['questID']})"
    inst = int(r["instanceMapID"] or 0)
    if inst and inst not in dungeons: problems.append(f"{where}: unknown dungeon {inst}")
    if r["questID"]:
        q = int(r["questID"])
        if q not in client: problems.append(f"{where}: quest id {q} is not in the Forever client's quest list (typo?)")
        if (inst, q) in seen: problems.append(f"{where}: duplicate")
        seen.add((inst, q))
    if r["where"] not in ("outside", "inside", "item", "attune", ""): problems.append(f"{where}: where must be outside / inside / item / attune")
    if r["faction"] not in ("Horde", "Alliance", ""): problems.append(f"{where}: faction must be Horde, Alliance or empty")
print("\n".join(problems) if problems else f"dungeon_quests.csv ok ({len(seen)} quests with ids)")
sys.exit(1 if problems else 0)
