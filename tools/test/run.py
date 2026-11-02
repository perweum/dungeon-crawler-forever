#!/usr/bin/env python3
"""Run the Lua smoke test against the WoW mock: tools/.venv/bin/python tools/test/run.py"""
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
    print("ABILITIES: data/manual/abilities_extra.csv and Data/Abilities.lua disagree (re-run tools/gen_abilities.py):")
    for b in bad:
        print("  ", b)
    sys.exit(1)
print("ok - abilities_extra.csv rows are in Data/Abilities.lua")
L = LuaRuntime()
try:
    L.execute(open("tools/test/smoke.lua").read())
except Exception as e:
    print("HARNESS ERROR:", str(e)[:1500])
    sys.exit(1)
