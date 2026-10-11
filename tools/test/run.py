#!/usr/bin/env python3
"""Run the Lua smoke test against the WoW mock: tools/.venv/bin/python tools/test/run.py"""
import os, sys
from lupa import LuaRuntime
os.chdir(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
L = LuaRuntime()
try:
    L.execute(open("tools/test/smoke.lua").read())
except Exception as e:
    print("HARNESS ERROR:", str(e)[:1500])
    sys.exit(1)
