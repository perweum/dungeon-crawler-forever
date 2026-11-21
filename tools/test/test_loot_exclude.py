"""Items listed in data/manual/loot_exclude.csv (crafted by a profession recipe, not boss drops) must not be in the shipped loot, and gen_loot must skip them."""
import csv, os, re, sys, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_loot

class LootExclude(unittest.TestCase):
    def ids(self):
        return {int(r["itemID"]) for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/loot_exclude.csv"), encoding="utf-8"))}

    def test_not_in_shipped_loot(self):
        s = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Loot.lua"), encoding="utf-8").read()
        have = {int(x) for x in re.findall(r"\{(\d+),\d", s)}
        self.assertEqual(sorted(self.ids() & have), [], "crafted items are in Data/Loot.lua: run tools/gen_loot.py")

    def test_generator_skips_them(self):
        boss = [{"items": [(252512, 0), (6681, 0)], "npc": None}]
        self.assertEqual([i for i, _, _ in gen_loot.boss_items(boss, {}, self.ids())], [6681])
        self.assertEqual([i for i, _, _ in gen_loot.boss_items(boss, {})], [252512, 6681])

if __name__ == "__main__":
    unittest.main()
