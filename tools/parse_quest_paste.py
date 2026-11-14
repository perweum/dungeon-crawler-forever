#!/usr/bin/env python3
"""Turn quest pages you copied from a quest database site (pasted as plain text) into draft rows for data/manual/dungeon_quests.csv.

You read the pages and paste them; this script only reads the text file you give it, it never fetches anything. It keeps facts only
(ids, names, levels, NPCs, series, reward item names, xp, reputation) and does not copy descriptions or story text.

The paste can hold, in one file:
  * optionally the dungeon's overview table ("Quest  Level  Side  Effort  Share?  Starts"): gives each quest's start zone and /way coordinates
  * any number of quest pages, each starting at its "Quick Facts" block and ending at the "/run print(C_QuestLog.IsQuestFlaggedCompleted(<id>))" line
Pages are matched to overview rows by quest name and required level (two quests can share a name).

Usage: tools/parse_quest_paste.py --instance <instanceMapID> <paste.txt> [more.txt ...] [--source "Wowhead quest page"] [--apply]
  default: writes data/draft/quests_pasted.csv and prints what it found; --apply appends the new rows to data/manual/dungeon_quests.csv
  (skipping quest ids already there) and runs tools/check_dungeon_quests.py. Then run tools/gen_quests.py.
Whatever the script could not read is listed under "check by hand"; side icons are lost in a text paste, so the side comes from "Side:" only.
"""
import csv, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_MAIN = os.path.join(ROOT, "data/manual/dungeon_quests.csv")
OUT = os.path.join(ROOT, "data/draft/quests_pasted.csv")
FIELDS = ["instanceMapID", "questID", "name", "level", "minLevel", "faction", "races", "where", "giver", "giverZone", "coords", "turnin",
          "turninZone", "prereq", "chain", "step", "note", "role", "unlocks"]
WAY = r"/way\s+(?P<x>\d+(?:\.\d+)?)\s+(?P<y>\d+(?:\.\d+)?)"


def undouble(s):
    """'The Grave Knight The Grave Knight' -> 'The Grave Knight' (the site prints a quest name twice in the overview)."""
    s = s.strip()
    w = s.split()
    if len(w) >= 2 and len(w) % 2 == 0 and w[:len(w) // 2] == w[len(w) // 2:]:
        return " ".join(w[:len(w) // 2])
    return s


def lines_of(text):
    return [l.rstrip() for l in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]


def parse_starts(raw):
    """The overview's Starts cell -> dict(kind, npc, zone, x, y, pre, inside)."""
    s = raw.strip()
    m = re.match(r"^Inside Dungeon\s*-\s*(?P<npc>.+?)(?:\s+on entry)?\.?$", s, re.I)
    if m:
        return {"inside": True, "npc": m.group("npc").strip()}
    m = re.match(r"^Starts with\s+(?P<pre>.+?)\s+from\s+(?P<npc>.+?)\s+in\s+(?P<zone>.+?)\s*" + WAY + r"\.?$", s, re.I)
    if m:
        return {"pre": undouble(m.group("pre")), "npc": m.group("npc").strip(), "zone": m.group("zone").strip(), "x": m.group("x"), "y": m.group("y")}
    m = re.match(r"^(?P<zone>.+?)\s+-\s+(?P<npc>.+?)\s*" + WAY + r"\.?$", s)
    if m:
        return {"npc": m.group("npc").strip(), "zone": m.group("zone").strip(), "x": m.group("x"), "y": m.group("y")}
    return {"unparsed": s}


def parse_overview(chunk):
    """[{name, minLevel, starts(raw), parsed, leads, note}] from the overview table, [] when there is none.
    Two layouts: one line per quest, or the quest name on its own line with the level row below it starting "(leads to X)"; lines after a row that
    start with "Starts with ..." are kept as a note on that row."""
    rows, on, prev_name = [], False, None
    for l in chunk:
        if re.match(r"^Quest\t+Level", l):
            on = True
            continue
        if not on or not l.strip():
            continue
        if "\t" not in l:
            if rows and re.match(r"^Starts with\b", l.strip(), re.I):
                rows[-1]["note"] = (rows[-1]["note"] + " " if rows[-1]["note"] else "") + l.strip()
            else:
                prev_name = undouble(l)
            continue
        cells = l.split("\t")
        if len(cells) < 3 or not cells[1].strip().isdigit():
            continue
        first = cells[0].strip()
        leads = None
        if first.startswith("(leads to"):
            leads = undouble(first[len("(leads to"):].rstrip(") ").strip())
            name = prev_name or ""
        else:
            name = undouble(first)
        prev_name = None
        starts = cells[-1].strip()
        rows.append({"name": name, "minLevel": int(cells[1]), "starts": starts, "parsed": parse_starts(starts), "leads": leads, "note": "",
                     "pre": any(c.strip() == "Pre" for c in cells[2:-1])})
    return rows


def parse_page(chunk):
    """One quest page (lines from 'Quick Facts' to the /run line) -> dict, or None when it has no quest id."""
    text = "\n".join(chunk)
    m = re.search(r"IsQuestFlaggedCompleted\((\d+)\)", text)
    if not m:
        return None
    p = {"id": int(m.group(1)), "problems": []}
    facts_end = len(chunk)
    for i, l in enumerate(chunk):
        if re.match(r"^(Series|Screenshots?|Videos?)\b", l.strip()):
            facts_end = i
            break
    for l in chunk[:facts_end]:
        l = l.strip()
        for key, rx in (("level", r"^Level:\s*(\d+)"), ("minLevel", r"^Requires level\s+(\d+)"), ("type", r"^Type:\s*(.+)"), ("side", r"^Side:\s*(.+)"),
                        ("start", r"^Start:\s*(.+)"), ("end", r"^End:\s*(.+)"), ("patch", r"^Added in patch\s+(\S+)")):
            mm = re.match(rx, l)
            if mm:
                p[key] = int(mm.group(1)) if key in ("level", "minLevel") else mm.group(1).strip()
        if re.match(r"^Not sharable", l, re.I):
            p["sharable"] = False
        elif re.match(r"^Sharable", l, re.I):
            p["sharable"] = True
    # series: "1. Krol'dok Moulding" on one line, or the number and the name on separate lines ("1." then the name); a step can list several
    # quests (alternatives) on the following lines until the next number
    steps = []
    for i, l in enumerate(chunk):
        if l.strip() == "Series":
            j = i + 1
            while j < len(chunk):
                t = chunk[j].strip()
                if re.match(r"^(Screenshots?|Videos?)\b", t):
                    break
                mm = re.match(r"^\d+\.\s*(.*)$", t)
                if mm:
                    steps.append([mm.group(1).strip()] if mm.group(1).strip() else [])
                elif t and steps:
                    steps[-1].append(t)
                elif t:
                    break
                j += 1
            break
    p["steps"] = [st for st in steps if st]
    p["series"] = [n for st in p["steps"] for n in st]
    # title: the first real line after the Screenshots / Videos lines
    idx = None
    for i, l in enumerate(chunk):
        if re.match(r"^Videos?\b", l.strip()):
            idx = i
    if idx is None:
        for i, l in enumerate(chunk):
            if re.match(r"^Added in patch", l.strip()):
                idx = i
    j = (idx or 0) + 1
    while j < len(chunk) and (not chunk[j].strip() or chunk[j].strip().startswith("None yet")):
        j += 1
    p["title"] = chunk[j].strip() if j < len(chunk) else ""
    # objectives: bullet lines between the objective sentence and "Relevant Locations" (the sentence itself is not kept)
    p["objectives"], p["provided"] = [], None
    k = j + 1
    while k < len(chunk) and chunk[k].strip() == "":
        k += 1
    k += 1  # skip the objective sentence
    while k < len(chunk) and not chunk[k].startswith("Relevant Locations") and not chunk[k].startswith("Description"):
        t = chunk[k].strip()
        if t.lower().startswith("provided item"):
            nxt = chunk[k + 1].strip() if k + 1 < len(chunk) else ""
            p["provided"] = t.split(":", 1)[1].strip() or nxt
            k += 1
        elif t and not t.lower().startswith("provided") and not t.isdigit():
            p["objectives"].append(t)
        k += 1
    # zones named under "Relevant Locations"
    zone_text = ""
    for l in chunk:
        mm = re.match(r"^(This quest starts and ends in|The entirety of this quest happens in|Part of this quest happens in)\s+(.+?)\.?$", l.strip())
        if mm:
            zone_text = mm.group(2)
            p["zoneKind"] = mm.group(1)
            break
    zone_text = re.sub(r"\s+and has objectives in\s+.+$", "", zone_text)  # "starts and ends in X and has objectives in Y" -> X
    p["zones"] = zone_text
    # rewards
    p["choices"], p["rewards"], p["money_raw"] = [], [], None
    try:
        r0 = next(i for i, l in enumerate(chunk) if l.strip() == "Rewards")
        r1 = next(i for i, l in enumerate(chunk) if i > r0 and l.strip() == "Gains")
    except StopIteration:
        r0 = r1 = None
    if r0 is not None:
        mode = None
        for l in chunk[r0 + 1:r1]:
            t = l.strip()
            if not t:
                continue
            if t.lower().startswith("you will be able to choose"):
                mode = "choices"
            elif t.lower().startswith("you will also receive") or t.lower().startswith("you will receive"):
                mode = "rewards"
                rest = t.split(":", 1)[1].strip() if ":" in t else ""
                if rest:
                    p["money_raw"] = rest
            elif mode:
                p[mode].append(t)
    xp = re.search(r"([\d,]+)\s+experience", text)
    p["xp"] = int(xp.group(1).replace(",", "")) if xp else None
    p["rep"] = [(int(a.replace(",", "")), b.strip()) for a, b in re.findall(r"(\d[\d,]*)\s+reputation with\s+(.+)", text)]
    return p


def split_text(text):
    """(overview lines, [page lines]). A page ends at its "/run print(C_QuestLog.IsQuestFlaggedCompleted(<id>))" line and starts after the
    previous one, so a paste works with or without the "Quick Facts" heading. In the first segment, whatever comes before the heading (or, without
    a heading, before the first "Level:" line) is the overview table."""
    ls = lines_of(text)
    ends = [i for i, l in enumerate(ls) if "IsQuestFlaggedCompleted(" in l]
    if not ends:
        return ls, []
    first = next((i for i, l in enumerate(ls[:ends[0] + 1]) if l.strip() == "Quick Facts" or re.match(r"^Level:\s*\d+", l.strip())), 0)
    overview = ls[:first]
    pages, start = [], first
    for e in ends:
        pages.append(ls[start:e + 1])
        start = e + 1
    return overview, pages


def side_of(p):
    s = (p.get("side") or "").strip().lower()
    return "Horde" if s == "horde" else "Alliance" if s == "alliance" else ""


def build(instance, texts, source, today):
    overview, pages, problems = [], [], []
    for t in texts:
        ov, pg = split_text(t)
        overview += parse_overview(ov)
        for chunk in pg:
            p = parse_page(chunk)
            if p:
                pages.append(p)
            else:
                problems.append("a page without a quest id (no IsQuestFlaggedCompleted line) was skipped")
    by_title = {}
    for p in pages:
        by_title.setdefault(p["title"], []).append(p)
    rows = []
    for p in pages:
        ov = next((o for o in overview if o["name"] == p["title"] and o["minLevel"] == p.get("minLevel")), None)
        if not p["title"]:
            problems.append(f"quest {p['id']}: title not found")
        if "level" not in p:
            problems.append(f"quest {p['id']} {p['title']}: level not found")
        giver = p.get("start", "")
        zone, coords, where, extra = "", "", "outside", []
        if ov:
            po = ov["parsed"]
            if po.get("unparsed"):
                problems.append(f"quest {p['id']} {p['title']}: start text not understood: {po['unparsed']!r}")
            elif po.get("inside"):
                where = "inside"
                giver = giver or po["npc"]
            elif po.get("pre"):
                extra.append(f"guide table: starts with {po['pre']} from {po['npc']} in {po['zone']} ({po['x']} {po['y']})")
            else:
                giver = giver or po["npc"]
                zone = po["zone"]
                coords = f"{po['x']} {po['y']}"
        if ov and ov.get("note"):
            extra.append("guide table: " + ov["note"])
        if ov and ov.get("leads"):
            extra.append(f"leads to {ov['leads']}")
        if not zone and p.get("zoneKind", "").startswith("This quest starts"):
            zone = p["zones"]
        if not p.get("start") and not (ov and ov["parsed"].get("inside")):
            where = "item"
            problems.append(f"quest {p['id']} {p['title']}: no start NPC, so 'where' is set to item; it may be given inside the dungeon (set inside) if an NPC there offers it")
        # series -> chain, step, prereq
        chain, step, prereq = "", "", ""
        if p["series"] and p["title"] in p["series"]:
            pos = next(i for i, st in enumerate(p["steps"]) if p["title"] in st)
            chain, step = p["steps"][-1][-1], pos + 1
            if pos > 0:
                prevs = p["steps"][pos - 1]
                cand = [q for n in prevs for q in by_title.get(n, []) if q["id"] != p["id"]]
                cand = [q for q in cand if not side_of(q) or not side_of(p) or side_of(q) == side_of(p)] or cand
                if cand:
                    prereq = cand[0]["id"]
                else:
                    extra.append(f"prerequisite is '{' or '.join(prevs)}' (id not pasted yet)")
        elif p["series"]:
            problems.append(f"quest {p['id']} {p['title']}: not found in its own series {p['series']}")
        facts = []
        if p.get("level") is not None:
            facts.append(f"level {p['level']}")
        if p.get("minLevel") is not None:
            facts.append(f"requires level {p['minLevel']}")
        if p.get("type"):
            facts.append(f"type {p['type']}")
        if side_of(p):
            facts.append(side_of(p))
        else:
            facts.append("no side")
        if "sharable" in p:
            facts.append("sharable" if p["sharable"] else "NOT sharable")
        if p.get("patch"):
            facts.append(f"patch {p['patch']}")
        if p["objectives"]:
            facts.append("objective: " + ", ".join(p["objectives"]))
        if p["provided"]:
            facts.append(f"provided item {p['provided']}")
        if p["choices"]:
            facts.append("choose " + " or ".join(p["choices"]))
        if p["rewards"]:
            facts.append("reward " + ", ".join(p["rewards"]))
        if p["money_raw"]:
            facts.append(f"money '{p['money_raw']}' (coin units are lost in a text paste)")
        if p["xp"]:
            facts.append(f"{p['xp']:,} xp")
        for amount, fac in p["rep"]:
            facts.append(f"{amount} {fac} reputation")
        if p["series"]:
            facts.append("series " + " then ".join(p["series"]))
        facts += extra
        note = f"{source} (user paste, {today}): " + "; ".join(facts)
        rows.append({
            "instanceMapID": instance, "questID": p["id"], "name": p["title"], "level": p.get("level", ""), "minLevel": p.get("minLevel", ""),
            "faction": side_of(p), "races": "", "where": where, "giver": giver, "giverZone": zone, "coords": coords,
            "turnin": p.get("end", ""), "turninZone": zone if p.get("end") == giver else "", "prereq": prereq, "chain": chain, "step": step, "note": note, "role": "", "unlocks": "",
        })
        if not ov and overview:
            problems.append(f"quest {p['id']} {p['title']}: not in the pasted overview table (name + required level), start zone unknown")
    # the overview's "(leads to X)": quest X comes after this one, so its prerequisite is the quest whose page was pasted under that name
    for r, p in zip(rows, pages):
        if r["prereq"]:
            continue
        for o in overview:
            if o.get("leads") and o["leads"] == p["title"]:
                src = next((q for q in pages if q["title"] == o["name"] and q.get("minLevel") == o["minLevel"]), None)
                if src and src["id"] != p["id"]:
                    r["prereq"] = src["id"]
                    r["note"] += f"; follows {o['name']} (the guide table says it leads to this quest)"
                else:
                    r["note"] += f"; follows {o['name']} per the guide table (id not pasted)"
                break
    # role suggestion from the overview, as a hint in the draft (the maintainer confirms it): a quest the overview names after "Starts with" /
    # "Follow-up from" / "must complete ... first" / "requires" is a PRE-quest; a quest the overview names in a dungeon quest's "(leads to ...)" comes AFTER it.
    import re as _re
    needs = " || ".join(o["note"] + " " + o["starts"] for o in overview if _re.search(r"starts with|follow[- ]?up from|must complete|requires", o["note"] + " " + o["starts"], _re.I))
    leads = {o["leads"] for o in overview if o.get("leads") and not o["parsed"].get("pre")}
    listed = {(o["name"], o["minLevel"]) for o in overview}
    for r, p in zip(rows, pages):
        t = p["title"]
        if (t, p.get("minLevel")) not in listed and (t + " " + t) in needs:
            r["role"] = "pre"
            r["note"] += "; suggested role pre (the overview names it as needed first)"
        elif t in leads and (t, p.get("minLevel")) not in listed:
            r["role"] = "after"
            r["note"] += "; suggested role after (the overview says a dungeon quest leads to it): it is left out of the list"
    for o in overview:
        if not any(p["title"] == o["name"] and p.get("minLevel") == o["minLevel"] for p in pages):
            problems.append(f"overview lists '{o['name']}' (requires {o['minLevel']}) but its page was not pasted")
    return rows, problems


def main():
    argv = sys.argv[1:]
    arg = lambda n, d=None: argv[argv.index(n) + 1] if n in argv and argv.index(n) + 1 < len(argv) else d
    inst = arg("--instance")
    skip = {inst, arg("--source")}
    files = [a for a in argv if not a.startswith("--") and a not in skip]
    if not inst or not inst.isdigit() or not files:
        sys.exit("usage: tools/parse_quest_paste.py --instance <instanceMapID> <paste.txt> [more.txt ...] [--source TEXT] [--apply]")
    texts = [open(f, encoding="utf-8").read() for f in files]
    rows, problems = build(int(inst), texts, arg("--source", "Wowhead quest page"), time.strftime("%Y-%m-%d"))
    have = set()
    if os.path.exists(CSV_MAIN):
        have = {(r["instanceMapID"], r["questID"]) for r in csv.DictReader(open(CSV_MAIN, encoding="utf-8"))}
    new = [r for r in rows if (str(r["instanceMapID"]), str(r["questID"])) not in have]
    print(f"{len(rows)} quest page(s) read, {len(new)} new, {len(rows) - len(new)} already in dungeon_quests.csv")
    for r in rows:
        tag = "NEW  " if r in new else "known"
        print(f"  {tag} [{r['questID']}] {r['name']}  L{r['level']} min {r['minLevel']}  {r['faction'] or 'no side'}  {r['where']}  "
              f"giver={r['giver'] or '-'} @ {r['giverZone'] or '?'} {r['coords']}"
              + (f"  prereq {r['prereq']}" if r["prereq"] else "") + (f"  chain '{r['chain']}' step {r['step']}" if r["chain"] else "")
              + (f"  ROLE {r['role'].upper()} (suggested)" if r["role"] else ""))
    if problems:
        print("check by hand:")
        for p in dict.fromkeys(problems):
            print("  -", p)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(new)
    print(f"draft: {OUT}")
    if "--apply" in argv and new:
        raw = open(CSV_MAIN, "rb").read()
        nl = "\r\n" if b"\r\n" in raw else "\n"
        with open(CSV_MAIN, "a", newline="", encoding="utf-8") as f:
            if not raw.endswith(b"\n"):
                f.write(nl)
            csv.DictWriter(f, fieldnames=FIELDS, lineterminator=nl).writerows(new)
        print(f"appended {len(new)} rows to {CSV_MAIN}; checking:")
        subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools/check_dungeon_quests.py")])


if __name__ == "__main__":
    main()
