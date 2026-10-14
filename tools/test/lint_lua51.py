#!/usr/bin/env python3
"""Fail on syntax the game's Lua 5.1 does not have (the test harness runs a newer Lua and would not notice): integer division //, goto,
bit shifts and the bitwise ~ operator. Checks every addon file except the generated Data/ files. Used by tools/test/run.py."""
import glob, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def problems():
    bad = []
    for p in glob.glob(os.path.join(ROOT, "addon/**/*.lua"), recursive=True):
        if "/Data/" in p:
            continue
        for n, line in enumerate(open(p, encoding="utf-8"), 1):
            code = re.sub(r'"(\\.|[^"\\])*"|\'(\\.|[^\'\\])*\'', '""', line).split("--")[0]
            for pat, why in ((r"//", "integer division //"), (r"\bgoto\b", "goto"), (r"<<|>>", "bit shift"), (r"(?<![~=<>])~(?!=)", "bitwise ~")):
                if re.search(pat, code):
                    bad.append(f"{os.path.relpath(p, ROOT)}:{n}: {why} is not Lua 5.1: {line.strip()[:70]}")
    return bad

if __name__ == "__main__":
    bad = problems()
    for b in bad:
        print(b)
    sys.exit(1 if bad else 0)
