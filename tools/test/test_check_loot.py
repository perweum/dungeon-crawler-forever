#!/usr/bin/env python3
"""tools/check_loot.py against the made-up fixture in tools/test/loot_check/ (see its README.md). Used by tools/test/run.py;
run alone: tools/.venv/bin/python -B tools/test/test_check_loot.py"""
import hashlib, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FIX = os.path.join(ROOT, "tools/test/loot_check")

def check_loot(*extra, root=FIX):
    args = [sys.executable, "-B", os.path.join(ROOT, "tools/check_loot.py"), "--root", root, "--atlas", os.path.join(FIX, "atlas"), *extra]
    return subprocess.run(args, capture_output=True, text=True, cwd=ROOT)

def fixture_hashes():
    out = {}
    for d, _, files in os.walk(FIX):
        for f in files:
            p = os.path.join(d, f)
            out[p] = hashlib.sha256(open(p, "rb").read()).hexdigest()
    return out

def section(text, title):
    """lines of one report section ('== TITLE (n)' up to the next blank line)"""
    lines, on = [], False
    for l in text.splitlines():
        if l.startswith("== "):
            on = l.startswith(f"== {title}")
            continue
        if on:
            if not l.strip():
                break
            lines.append(l.strip())
    return lines

def run():
    fails = []
    def expect(cond, what):
        if not cond:
            fails.append(what)
    before = fixture_hashes()

    r = check_loot()
    out = r.stdout
    expect(r.returncode == 0, f"exit {r.returncode} without --cdb (stderr: {r.stderr[-500:]})")
    last = out.strip().splitlines()[-1] if out.strip() else ""
    expect(last == "LOOTCHECK missing=2 new=2 removed=2 stale=2 allowlisted=1 unmapped=1 unreleased=2 crosscheck=skipped", f"summary line without --cdb: {last!r}")
    missing, new, removed = section(out, "MISSING"), section(out, "NEW IN ATLASLOOT"), section(out, "REMOVED FROM ATLASLOOT")
    allowed, stale = section(out, "ALLOWLISTED"), section(out, "STALE ALLOWLIST")
    expect(any("Epsilon Boss" in l for l in missing), "Epsilon Boss (no loot, not allowlisted) should be MISSING")
    expect(any("Theta Lone" in l for l in missing), "Theta Lone (instance without AtlasLoot data) should be MISSING")
    expect(not any("Gamma Event" in l for l in missing), "allowlisted Gamma Event must not be MISSING")
    expect(any("Gamma Event" in l and "event" in l for l in allowed), "Gamma Event should be ALLOWLISTED")
    expect(any("Delta Add" in l and "stale" in l for l in stale), "allowlisted Delta Add has loot: STALE ALLOWLIST")
    expect(any("Omega Gone" in l for l in stale), "allowlist row for a boss not in Dungeons.lua: STALE ALLOWLIST")
    expect(any("Beta Boss" in l and "2003" in l for l in new), "Beta Boss +2003 should be NEW IN ATLASLOOT")
    expect(any("Zeta Newcomer" in l and "new boss" in l for l in new), "Zeta Newcomer should be new boss loot")
    expect(any("FixtureUnmapped" in l for l in new), "FixtureUnmapped should be listed as an unmapped AtlasLoot dungeon")
    expect(any("Beta Boss" in l and "2002" in l for l in removed), "Beta Boss -2002 should be REMOVED FROM ATLASLOOT")
    expect(any("Eta Retired" in l for l in removed), "Eta Retired should be REMOVED FROM ATLASLOOT")
    expect(not any("Alpha Boss" in l or "Trash" in l for l in missing + new + removed), "Alpha Boss and Trash are unchanged")
    expect(sum("skipped" in l for l in section(out, "CROSS-CHECK")) == 1, "without --cdb the cross-check is skipped in one line")
    notrel = section(out, "NOT RELEASED")
    expect("== NOT RELEASED (2)" in out, "NOT RELEASED section with a count of 2")
    expect(any("Iota Unreleased" in l and "classic" in l for l in notrel), "Iota Unreleased (status classic) should be NOT RELEASED")
    expect(any("Kappa Hidden" in l and "hidden" in l for l in notrel), "Kappa Hidden (status hidden) should be NOT RELEASED")
    expect(not any("Iota" in l or "Kappa" in l for l in missing), "bosses of unreleased instances must not be MISSING")
    expect(not any("Theta Lone" in l or "Epsilon Boss" in l for l in notrel), "bosses of released instances are not NOT RELEASED")

    # the instance is released: drop its status row (on a copy of the fixture) and its boss is MISSING again
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, "loot_check")
        shutil.copytree(FIX, copy)
        st = os.path.join(copy, "data/manual/dungeon_status.csv")
        rows = open(st, encoding="utf-8").read().splitlines(keepends=True)
        open(st, "w", encoding="utf-8").writelines(l for l in rows if not l.startswith("9003,"))
        r2 = check_loot(root=copy)
        out2 = r2.stdout
        last2 = out2.strip().splitlines()[-1] if out2.strip() else ""
        expect(r2.returncode == 0, f"exit {r2.returncode} with 9003 released (stderr: {r2.stderr[-500:]})")
        expect(" missing=3 " in last2 and " unreleased=1 " in last2, f"9003 released: summary line {last2!r}")
        expect(any("Iota Unreleased" in l for l in section(out2, "MISSING")), "Iota Unreleased should be MISSING once 9003 has no status row")
        expect(not any("Iota" in l for l in section(out2, "NOT RELEASED")), "Iota Unreleased must leave NOT RELEASED once released")

    r = check_loot("--cdb", os.path.join(FIX, "classic-db-fixture.sql.txt"))
    out = r.stdout
    expect(r.returncode == 0, f"exit {r.returncode} with --cdb (stderr: {r.stderr[-500:]})")
    last = out.strip().splitlines()[-1] if out.strip() else ""
    expect(last.endswith(" crosscheck=1-mismatch"), f"summary line with --cdb: {last!r}")
    cross = section(out, "CROSS-CHECK")
    mism = [l for l in cross if l.startswith("MISMATCH")]
    expect(len(mism) == 1 and "Beta Boss" in mism[0] and "only CMaNGOS [2099]" in mism[0], f"one mismatch, Beta Boss 2099 via a reference: {mism}")
    expect(any("quest drops [3999]" in l for l in mism), "CMaNGOS quest drop 3999 listed apart")
    expect(any("Forever" in l and "Alpha Boss" in l and "270001" in l for l in cross), "Forever item 270001 listed apart, not a mismatch")
    expect(any("no CMaNGOS loot" in l and "Delta Add" in l for l in cross), "Delta Add (LootId 0) has no CMaNGOS loot")
    expect(not any("Trash" in l for l in cross), "Trash entries are not cross-checked")

    r = check_loot("--cdb", os.path.join(FIX, "does-not-exist.sql"))
    expect(r.returncode == 2, f"unreadable --cdb should exit 2, got {r.returncode}")
    expect(fixture_hashes() == before, "check_loot.py must not write any file")
    return fails

if __name__ == "__main__":
    f = run()
    print("\n".join(f) if f else "check_loot: ok")
    sys.exit(1 if f else 0)
