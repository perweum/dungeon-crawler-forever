#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/QuestDetails.lua: what a quest asks for and gives, for the reward display in the Quests tab.

  * old quests: CMaNGOS classic-db (GPL-3.0) quest_template: Objectives text, choice rewards, fixed rewards (with counts), money, reputation (faction ids named below).
    (1.12 data has no experience field, so old quests show no XP unless a manual note gives it.)
  * Forever-new quests: the facts the maintainer pasted from Wowhead are in the `note` column of data/manual/dungeon_quests.csv; this reads them back:
    "N xp", "N <Faction> [and N <Faction>] reputation" / "N reputation each with A, B and C", "choose A, B or C [and receive a D]",
    "reward(s) A, B and C", "objective(s): ...". Item names are turned into ids with the client's ItemSparse.csv (exact name).
    Names that are not found are listed on the console (fix the note or add the item to the note spelled as in game).
A note's facts win over classic-db for the same quest.
Output: ns.QuestDetails[questID] = { obj = "text", xp = n, money = copper, rep = { { "Faction", n }, ... }, choose = { { itemID, count }, ... }, get = { ... } }
Reads Data/Quests.lua (run tools/gen_quests.py first). Usage: tools/gen_quest_details.py <path/to/classic-db.sql>
"""
import collections, csv, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_quests as G
from lupa import LuaRuntime

ROOT = G.ROOT
DATA = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data")
OUT = os.path.join(DATA, "QuestDetails.lua")
FACTION = {21: "Booty Bay", 47: "Ironforge", 54: "Gnomeregan Exiles", 59: "Thorium Brotherhood", 67: "Horde", 68: "Undercity", 69: "Darnassus",
           72: "Stormwind", 76: "Orgrimmar", 81: "Thunder Bluff", 87: "Bloodsail Buccaneers", 169: "Steamwheedle Cartel", 349: "Ravenholdt",
           369: "Gadgetzan", 469: "Alliance", 470: "Ratchet", 529: "Argent Dawn", 530: "Darkspear Trolls", 577: "Everlook", 609: "Cenarion Circle",
           809: "Shen'dralar", 910: "Brood of Nozdormu"}
NAME = r"[A-Z][A-Za-z' ]+?"

def num(s):
    return int(s.replace(",", ""))

def clean_text(s):
    s = re.sub(r"\$[Bb]", " ", s or "")
    s = s.replace("$N", "<name>").replace("$n", "<name>").replace("$C", "<class>").replace("$c", "<class>").replace("$R", "<race>").replace("$r", "<race>")
    return re.sub(r"\s+", " ", s).strip()

def parse_note(note, item_id, missing):
    out = {}
    # the notes grow by appending (a later paste corrects an earlier one): the last fact wins
    xps = re.findall(r"([\d,]+)\s*xp", note, re.I)
    if xps:
        out["xp"] = num(xps[-1])
    rep = {}
    for m in re.finditer(r"(\d[\d,]*) reputation each with ([^;.]+)", note):
        for f in re.split(r", | and ", m.group(2)):
            if f.strip():
                rep[f.strip()] = num(m.group(1))
    for m in re.finditer(r"((?:\d[\d,]* %s)(?: and \d[\d,]* %s)*) reputation(?! each)" % (NAME, NAME), note):
        for part in re.split(r" and (?=\d)", m.group(1)):
            mm = re.match(r"(\d[\d,]*) (.+)", part.strip())
            if mm:
                rep[mm.group(2).strip()] = num(mm.group(1))
    if rep:
        out["rep"] = list(rep.items())
    def items(text):
        res = []
        for nm in text:
            nm = nm.strip().rstrip(".")
            mm = re.match(r"(.+?)\s*\((\d+)\)$", nm)
            cnt = 1
            if mm:
                nm, cnt = mm.group(1), int(mm.group(2))
            nm = re.sub(r"^(?:an?|the)\s+", "", nm, flags=re.I)
            if not nm or nm[0].isdigit():
                continue
            i = item_id(nm)
            if i:
                res.append((i, cnt))
            else:
                missing.add(nm)
                res.append((nm, cnt))   # no id known: the display shows the name alone
        return res
    ms = re.findall(r"choose ([^;]+?)(?= and receive|\. |[;]|$)", note, re.I)
    if ms:
        ch = items(re.split(r", | or ", ms[-1]))
        if ch:
            out["choose"] = ch
    ms = re.findall(r"and receive ([^;.]+)", note, re.I)
    got = items([ms[-1]]) if ms else []
    ms = re.findall(r"(?<!money )\brewards?:? ([A-Z][^;]*?)(?:\. |;|$)", note)
    if ms and "choose" not in ms[-1].lower():
        got += items([p for p in re.split(r", | and ", ms[-1]) if p.strip()])
    if got:
        out["get"] = got
    ms = re.findall(r"objectives?:?\s+(?=[A-Z])([^;]+)", note)
    if ms:
        out["obj"] = ms[-1].strip().rstrip(".")
    return out

def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        sys.exit(__doc__)
    build = open(os.path.join(ROOT, "data/BUILD")).read().strip()
    lua = LuaRuntime(); lua.execute("ns = {}")
    lua.eval("function(src) local f = load(src); return f('x', ns) end")(open(os.path.join(DATA, "Quests.lua"), encoding="utf-8").read())
    ns = lua.globals().ns
    ids = set()
    for m, lst in ns.QuestData.items():
        for _, q in lst.items():
            ids.add(int(q["id"]))
    sparse = {}
    for r in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/ItemSparse.csv"), encoding="utf-8")):
        sparse.setdefault(r["Display_lang"], int(r["ID"]))
    T = G.load(sys.argv[1], tables=("quest_template", "item_template"))
    qc, qr = T["quest_template"]
    ic, ir = T["item_template"]
    cname = {}
    for r in ir:
        cname.setdefault(r[ic["name"]], int(r[ic["entry"]]))
    # item names with ids from the installed AtlasLoot Forever data (facts only: "{ 1, 279854 }, -- Twilight Initiate's Belt (waist, leather)")
    atlas = {}
    wow = os.environ.get("WOW_DIR", "/Applications/World of Warcraft/_forever_")
    for rel in ("AtlasLootClassic_DungeonsAndRaids/data.lua", "AtlasLootContinued_DungeonsAndRaids/data-forever.lua"):
        p = os.path.join(wow, "Interface/AddOns", rel)
        if os.path.exists(p):
            for m in re.finditer(r"\{\s*\d+,\s*(\d+)\s*\},?\s*--\s*([^(\n]+?)\s*(?:\(|$)", open(p, encoding="utf-8", errors="replace").read(), re.M):
                atlas.setdefault(m.group(2).strip(), int(m.group(1)))
    item_id = lambda nm: sparse.get(nm) or atlas.get(nm) or cname.get(nm)
    details = {}
    for r in qr:
        e = int(r[qc["entry"]])
        if e not in ids:
            continue
        d = {}
        ob = clean_text(r[qc["Objectives"]])
        if ob:
            d["obj"] = ob
        ch = [(int(r[qc["RewChoiceItemId%d" % i]]), int(r[qc["RewChoiceItemCount%d" % i]] or 1)) for i in range(1, 7) if int(r[qc["RewChoiceItemId%d" % i]] or 0)]
        got = [(int(r[qc["RewItemId%d" % i]]), int(r[qc["RewItemCount%d" % i]] or 1)) for i in range(1, 5) if int(r[qc["RewItemId%d" % i]] or 0)]
        if ch: d["choose"] = ch
        if got: d["get"] = got
        money = int(r[qc["RewOrReqMoney"]] or 0)
        if money > 0: d["money"] = money
        rep = []
        for i in range(1, 6):
            f, v = int(r[qc["RewRepFaction%d" % i]] or 0), int(r[qc["RewRepValue%d" % i]] or 0)
            if f in FACTION and v > 0:
                rep.append((FACTION[f], v))
        if rep: d["rep"] = rep
        details[e] = d
    missing = set()
    for n, r in enumerate(csv.DictReader(open(os.path.join(ROOT, "data/manual/dungeon_quests.csv"), encoding="utf-8")), 2):
        q = int(r["questID"] or 0)
        if not q or q not in ids:
            continue
        p = parse_note(r["note"], item_id, missing)
        if p:
            details.setdefault(q, {}).update(p)
    def item_list(lst):
        def one(i, c):
            v = G.lua_str(i) if isinstance(i, str) else str(i)
            return "{ %s, %d }" % (v, c) if c != 1 else "{ %s }" % v
        return "{ " + ", ".join(one(i, c) for i, c in lst) + " }"
    lines = ["-- GENERATED by tools/gen_quest_details.py from CMaNGOS classic-db (GPL-3.0) + the notes in data/manual/dungeon_quests.csv. Do not edit.",
             "-- ns.QuestDetails[questID] = { obj = objective text, xp, money (copper), rep = { { faction, amount }, ... }, choose = { { itemID, count }, ... }, get = { ... } }",
             "local _, ns = ...", "ns.QuestDetails = {"]
    for q in sorted(details):
        d = details[q]
        f = []
        if d.get("obj"): f.append("obj = " + G.lua_str(d["obj"]))
        if d.get("xp"): f.append("xp = %d" % d["xp"])
        if d.get("money"): f.append("money = %d" % d["money"])
        if d.get("rep"): f.append("rep = { " + ", ".join("{ %s, %d }" % (G.lua_str(n), v) for n, v in d["rep"]) + " }")
        if d.get("choose"): f.append("choose = " + item_list(d["choose"]))
        if d.get("get"): f.append("get = " + item_list(d["get"]))
        if f:
            lines.append(f"  [{q}] = {{ " + ", ".join(f) + " },")
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    c = collections.Counter()
    for d in details.values():
        for k in d: c[k] += 1
    print(f"wrote {OUT}: {len(details)} quests, {os.path.getsize(OUT)} bytes; fields {dict(c)}")
    if missing:
        print("  ? item names in notes that are not in the client's ItemSparse or classic-db:", ", ".join(sorted(missing)))

main()
