#!/usr/bin/env python3
"""Cross-check our dungeon quests (addon/DungeonCrawlerForever/Data/Quests.lua) against the QuestieDB addon installed in the game. A CHECKER ONLY (D-072).

Questie and QuestieDB are "all rights reserved when in doubt" (their LICENSE.md), so nothing from them is copied: this script reads the installed
addon at run time, prints where it disagrees with us, and writes nothing into addon/ or data/. Settle each difference from a source we may use
(the client's QuestV2.csv, CMaNGOS classic-db, in game), then fix data/manual/ or tools/gen_quests.py.

What it compares, per quest of ours that Questie also has: name, quest level, required level, faction, class, giver and turn-in NPC names, the
prerequisite. And the other way round: quests Questie files under the same dungeon area (the area is worked out from our own quests, never typed in
from their tables) that we do not list.

Usage: tools/.venv/bin/python tools/check_questie.py [path/to/QuestieDB_Forever.toc] [--all]   (--all also lists the harmless differences)
The decoder below is our own: a QuestieDB value is base64 of CBOR, the id list is zlib-compressed first; the field numbers are listed in the addon's
src/meta/*.lua.
"""
import base64, collections, os, re, struct, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_TOC = "/Applications/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc"
QUESTS = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Quests.lua")
REVIEWED = os.path.join(ROOT, "data/manual/quest_crosscheck.csv")  # questID,field,verdict,reason: what we decided about a disagreement (keep | fixed | open)

# quest fields (QuestieDB src/meta/questMeta.lua)
F_NAME, F_STARTED, F_FINISHED, F_REQLEVEL, F_LEVEL, F_RACES, F_CLASSES, F_PREGROUP, F_PRESINGLE, F_ZONE = 1, 2, 3, 4, 5, 6, 7, 12, 13, 17
ALLIANCE, HORDE = 1 | 4 | 8 | 64, 2 | 16 | 32 | 128  # classic race bits


def cbor(b, i=0):
    ib = b[i]; mt, ai = ib >> 5, ib & 31; i += 1
    def arg():
        nonlocal i
        if ai < 24: return ai
        n = {24: 1, 25: 2, 26: 4, 27: 8}[ai]; v = int.from_bytes(b[i:i + n], "big"); i += n; return v
    if mt == 0: return arg(), i
    if mt == 1: return -1 - arg(), i
    if mt in (2, 3):
        n = arg(); s = b[i:i + n]; i += n; return (s.decode("utf-8", "replace") if mt == 3 else s), i
    if mt == 4:
        out = []
        for _ in range(arg()):
            v, i = cbor(b, i); out.append(v)
        return out, i
    if mt == 5:
        out = {}
        for _ in range(arg()):
            k, i = cbor(b, i); v, i = cbor(b, i); out[k] = v
        return out, i
    if mt == 6: arg(); return cbor(b, i)
    if ai == 20: return False, i
    if ai == 21: return True, i
    if ai in (22, 23): return None, i
    if ai == 25: return struct.unpack(">e", b[i:i + 2])[0], i + 2
    if ai == 26: return struct.unpack(">f", b[i:i + 4])[0], i + 4
    if ai == 27: return struct.unpack(">d", b[i:i + 8])[0], i + 8
    raise ValueError("cbor type %d" % ai)


class DB:
    def __init__(self, toc):
        self.meta = {}
        for line in open(toc, encoding="utf-8", errors="replace"):
            m = re.match(r"## X-([A-Za-z]+-[^:]+): (.*)$", line.rstrip("\n"))
            if m: self.meta[m.group(1)] = m.group(2)
        self._rows = {}

    def stored(self, key):
        v = self.meta.get(key)
        if v is not None and v.startswith("~"):
            v = "".join(self.meta[f"{key}-{i}"] for i in range(1, int(v.strip("~")) + 1))
        return v

    def ids(self, kind):
        raw = base64.b64decode(self.stored(kind + "-IDS"))
        for w in (15, -15, 31):
            try: return cbor(zlib.decompress(raw, w))[0]
            except Exception: pass
        raise ValueError("cannot read the id list")

    def row(self, kind, id):
        k = (kind, id)
        if k not in self._rows:
            s = self.stored(f"{kind}-{id}-S")
            r = cbor(base64.b64decode(s))[0] if s else None
            if r is not None and not isinstance(r, dict): r = {}  # an empty row comes back as a list
            if r and isinstance(r.get(1), bytes): r[1] = r[1].decode("utf-8", "replace")  # names are stored as byte strings
            self._rows[k] = r
        return self._rows[k]

    def table(self, kind, id, field):
        s = self.stored(f"{kind}-{id}-{field}")
        return cbor(base64.b64decode(s))[0] if s else None

    def npc_name(self, id):
        r = self.row("Npc", id)
        return r.get(1) if r else None


def parse_ours():
    """{instance: [ {field: value} ]} from Data/Quests.lua"""
    out, inst, names = collections.OrderedDict(), None, {}
    for line in open(QUESTS, encoding="utf-8"):
        m = re.match(r"^  \[(\d+)\] = \{ -- (.*)$", line)
        if m: inst = int(m.group(1)); out[inst] = []; names[inst] = m.group(2); continue
        if inst and line.startswith("    { id = "):
            q = {}
            for k, v in re.findall(r'(\w+) = ("(?:[^"\\]|\\.)*"|\{[^}]*\}|[^,\s}]+)', line):
                q[k] = v[1:-1] if v.startswith('"') else ([int(x) for x in re.findall(r"\d+", v)] if v.startswith("{") else (int(v) if re.fullmatch(r"-?\d+", v) else v))
            out[inst].append(q)
    return out, names


def norm(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_all = "--all" in sys.argv
    toc = args[0] if args else DEFAULT_TOC
    if not os.path.exists(toc): sys.exit("QuestieDB not found at %s (pass the QuestieDB_Forever.toc path)" % toc)
    db = DB(toc)
    qids = set(db.ids("Quest"))
    ours, dnames = parse_ours()
    n_ours = sum(len(v) for v in ours.values())
    print(f"QuestieDB: {len(qids)} quests. Ours: {n_ours} quests in {len(ours)} dungeons.\n")

    reviewed = {}
    if os.path.exists(REVIEWED):
        import csv
        for r in csv.DictReader(open(REVIEWED, encoding="utf-8")): reviewed[(int(r["questID"]), r["field"])] = r["verdict"]
    missing_in_theirs, diffs, notes = [], collections.defaultdict(list), collections.defaultdict(list)
    area_votes = collections.defaultdict(collections.Counter)  # dungeon -> Questie zone of the quests we do inside
    ours_ids = {q["id"] for v in ours.values() for q in v}
    needed_for = collections.defaultdict(set)  # quest -> pre-quests of ours that list it under "unlocks" (a quest has one prereq, "starts with A, B and C" needs three)
    for v in ours.values():
        for q in v:
            for u in q.get("unlocks") or []: needed_for[u].add(q["id"])
    for inst, quests in ours.items():
        for q in quests:
            r = db.row("Quest", q["id"]) if q["id"] in qids else None
            who = f'{dnames[inst]} · {q["id"]} {q["name"]}'
            if not r: missing_in_theirs.append(who); continue
            def add(field, text):
                v = reviewed.get((q["id"], field))
                if v in ("keep", "fixed"): return  # looked at already (data/manual/quest_crosscheck.csv)
                diffs[inst].append(f'{who}: {text}' + (" [still open]" if v == "open" else ""))
            z = r.get(F_ZONE)
            if z and z > 0 and not q.get("pre"): area_votes[inst][z] += 1
            if norm(r.get(F_NAME)) != norm(q["name"]): add("name", f'name is "{r.get(F_NAME)}" there')
            if r.get(F_LEVEL) is not None and "level" in q and r[F_LEVEL] != q["level"]: add("level", f'level {q["level"]} here, {r[F_LEVEL]} there')
            if "min" in q and r.get(F_REQLEVEL) is not None and r[F_REQLEVEL] != q["min"]: add("min", f'required level {q["min"]} here, {r[F_REQLEVEL]} there')
            races = r.get(F_RACES) or 0
            theirs = "A" if (races & ALLIANCE and not races & HORDE) else "H" if (races & HORDE and not races & ALLIANCE) else None
            if theirs != q.get("faction"): add("faction", f'faction {q.get("faction") or "both"} here, {theirs or "both"} there (race mask {races})')
            if (r.get(F_CLASSES) or 0) != (q.get("class") or 0): add("class", f'class mask {q.get("class") or 0} here, {r.get(F_CLASSES) or 0} there')
            for field, key, label in ((F_STARTED, "giver", "giver"), (F_FINISHED, "turnin", "turn-in")):
                t = db.table("Quest", q["id"], field)
                t = t if isinstance(t, dict) else {}
                npcs = [db.npc_name(n) for n in (t.get(1) or [])]
                if key in q and npcs and norm(q[key]) not in {norm(n) for n in npcs}:
                    add(key, f'{label} {q[key]} here, {" / ".join(map(str, npcs))} there')
            pre = set((db.table("Quest", q["id"], F_PRESINGLE) or []) + (db.table("Quest", q["id"], F_PREGROUP) or []))
            ourpre = ({q["prereq"]} if isinstance(q.get("prereq"), int) else set()) | needed_for.get(q["id"], set())
            if ourpre and pre and not ourpre & pre: add("prereq", f'prerequisite {sorted(ourpre)} here, {sorted(pre)} there')
            elif ourpre and not pre: notes[inst].append(f'{who}: prerequisite {sorted(ourpre)} here, none there')
            elif pre and not ourpre: notes[inst].append(f'{who}: no prerequisite here, {sorted(pre)} there')

    # a dungeon's area: the zone most of its in-dungeon quests have there, with at least 3 votes and 60% of them (a hub city's quests vote for the city)
    areas = {inst: c.most_common(1)[0][0] for inst, c in area_votes.items() if c.most_common(1)[0][1] >= 3 and c.most_common(1)[0][1] >= 0.6 * sum(c.values())}
    excluded = set()
    ex_path = os.path.join(ROOT, "data/manual/quest_exclude.csv")
    if os.path.exists(ex_path):
        import csv
        excluded = {int(r["questID"]) for r in csv.DictReader(open(ex_path, encoding="utf-8")) if r["questID"].strip()}
    after_path = os.path.join(ROOT, "data/manual/dungeon_quests.csv")  # role "after": follow-ups done outside the dungeon, recorded but not listed (D-065)
    import csv
    excluded |= {int(r["questID"]) for r in csv.DictReader(open(after_path, encoding="utf-8")) if r["questID"].strip() and (r.get("role") or "").strip() == "after"}
    extra = collections.defaultdict(list)
    shared = collections.Counter(areas.values())
    for qid in sorted(qids):
        if qid in ours_ids or qid in excluded or reviewed.get((qid, "listed")) == "no": continue  # (data/manual/quest_exclude.csv: left out on purpose)
        r = db.row("Quest", qid)
        z = r.get(F_ZONE) if r else None
        for inst, a in areas.items():
            if z == a and shared[a] == 1:
                extra[inst].append(f'{dnames[inst]} · {qid} {r.get(F_NAME)} (level {r.get(F_LEVEL)}, requires {r.get(F_REQLEVEL)})')

    print(f"== Disagreements on quests we have ({sum(map(len, diffs.values()))})")
    for inst in diffs: print("\n".join("  " + d for d in diffs[inst]))
    print(f"\n== Quests of ours that QuestieDB does not have ({len(missing_in_theirs)})")
    print("\n".join("  " + m for m in missing_in_theirs))
    print(f"\n== Quests QuestieDB files under a dungeon's area that we do not list ({sum(map(len, extra.values()))})")
    for inst in extra: print("\n".join("  " + e for e in extra[inst]))
    unmatched = [dnames[i] for i in ours if i not in areas or shared[areas[i]] != 1]
    print(f"\n(dungeon area worked out for {len(areas)} of {len(ours)} dungeons; the 'we do not list' check skipped for: {', '.join(unmatched) or 'none'})")
    if show_all:
        print(f"\n== Prerequisite present on one side only ({sum(map(len, notes.values()))}; often just a different way to write the same chain)")
        for inst in notes: print("\n".join("  " + n for n in notes[inst]))
    print("\nAreas used: " + ", ".join(f"{dnames[i]}={a}" for i, a in areas.items()))


if __name__ == "__main__":
    main()
