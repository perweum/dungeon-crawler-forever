#!/usr/bin/env python3
"""Offline tests for tools/gen_clear_times.py: the committed Data/ClearTimes.lua matches the committed draft, every released dungeon has a
full-clear range, ranges are sane, and a row in data/manual/clear_times.csv overrides the computed range.
Run alone: tools/.venv/bin/python -B tools/test/test_clear_times.py   (tools/test/run.py runs it too)"""
import csv, os, re, shutil, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))
import gen_clear_times as gct  # noqa: E402


def ranges(text):
    out = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"  \[(\d+)\] = \{", line)
        if m:
            cur = int(m.group(1))
        m = re.match(r'    \{ wing = (\d+), kind = "(\w+)", label = "[^"]*", min = (\d+), max = (\d+), basis = "(\w+)" \},', line)
        if m:
            out[(cur, int(m.group(1)), m.group(2))] = (int(m.group(3)), int(m.group(4)), m.group(5))
    return out


class ClearTimes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.saved = (gct.OUT, gct.MANUAL)
        gct.OUT = os.path.join(self.tmp, "ClearTimes.lua")
        self.rows = list(csv.DictReader(open(gct.DRAFT, encoding="utf-8")))

    def tearDown(self):
        gct.OUT, gct.MANUAL = self.saved
        shutil.rmtree(self.tmp)

    def test_committed_lua_is_current(self):
        gct.build(self.rows)
        self.assertEqual(open(gct.OUT, encoding="utf-8").read(), open(self.saved[0], encoding="utf-8").read(),
                         "Data/ClearTimes.lua is out of date: run tools/gen_clear_times.py")

    def test_every_dungeon_has_a_full_clear(self):
        gct.build(self.rows)
        r = ranges(open(gct.OUT, encoding="utf-8").read())
        for inst, d in gct.dungeons().items():
            if not d["raid"]:
                self.assertTrue(any(k[0] == inst and k[2] == "full" for k in r), "no full clear for %s" % d["name"])
        for k, (lo, hi, _) in r.items():
            self.assertTrue(5 <= lo < hi <= 600, "range %s: %d-%d" % (k, lo, hi))

    def test_manual_row_wins(self):
        gct.MANUAL = os.path.join(self.tmp, "clear_times.csv")
        with open(gct.MANUAL, "w", encoding="utf-8") as f:
            f.write("instanceMapID,wing,kind,min,max,source\n33,0,full,20,25,test\n")
        gct.build(self.rows)
        r = ranges(open(gct.OUT, encoding="utf-8").read())
        self.assertEqual(r[(33, 0, "full")], (20, 25, "manual"))


if __name__ == "__main__":
    unittest.main()
