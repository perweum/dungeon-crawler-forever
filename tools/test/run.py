#!/usr/bin/env python3
"""Run the Lua 5.1 lint, the Lua smoke test against the WoW mock and the offline Python tool tests: tools/.venv/bin/python tools/test/run.py"""
import os, sys
from lupa import LuaRuntime
os.chdir(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(os.getcwd(), "tools/test"))
import lint_lua51
bad = lint_lua51.problems()
if bad:
    print("LINT: syntax the game's Lua 5.1 does not have:")
    for b in bad:
        print("  ", b)
    sys.exit(1)
import check_abilities_extra
bad = check_abilities_extra.problems()
if bad:
    print("ABILITIES: data/manual/abilities_extra.csv or abilities_verified.csv and Data/Abilities.lua disagree (re-run tools/gen_abilities.py):")
    for b in bad:
        print("  ", b)
    sys.exit(1)
print("ok - abilities_extra.csv rows and abilities_verified.csv lists are in Data/Abilities.lua")
L = LuaRuntime()
import csv  # the game's own encounter list (tools/test/fixtures/encounters.csv, refreshed with tools/snapshot_encounters.py): the data-consistency test reads it
_enc = L.eval("{}")
for _r in csv.DictReader(open("tools/test/fixtures/encounters.csv", encoding="utf-8")):
    _row = L.eval("{}"); _row["id"] = int(_r["id"]); _row["name"] = _r["name"]
    _m = int(_r["map"])
    if _enc[_m] is None: _enc[_m] = L.eval("{}")
    _t = _enc[_m]; _t[len(_t) + 1] = _row
L.globals().REAL_ENCOUNTERS = _enc
L.globals().SNAPSHOT_ROUTES = os.environ.get("SNAPSHOT_ROUTES") == "1"  # D-073: add the current route versions to tools/test/fixtures/route_versions.csv
try:
    L.execute(open("tools/test/smoke.lua").read())
    LuaRuntime().execute(open("tools/test/controller.lua").read())
except Exception as e:
    print("HARNESS ERROR:", str(e)[:1500])
    sys.exit(1)
import test_check_loot  # tools/check_loot.py against the made-up fixture in tools/test/loot_check/
fails = test_check_loot.run()
for f in fails:
    print("LOOT CHECK TEST FAILED:", f)
if fails:
    sys.exit(1)
print("ok   check_loot.py (fixture: allowlisted, stale allowlist, not released, sub-header split, cross-check mismatch)")
# offline Python tests for the tools: every tools/test/test_*.py (no network)
import unittest
result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.discover("tools/test", pattern="test_*.py"))
if not result.wasSuccessful():
    sys.exit(1)
