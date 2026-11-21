"""The loot audit (tools/audit_loot.py) must pass on the shipped data, and must catch a crafted item in a boss's loot."""
import os, shutil, sys, tempfile, unittest, csv
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import audit_loot, gen_loot

class LootAudit(unittest.TestCase):
    def test_shipped_loot_has_no_hard_findings(self):
        hard, soft, _ = audit_loot.audit()
        self.assertEqual(hard, [], "crafted items in Data/Loot.lua: regenerate (tools/build_item_facts.py, then tools/gen_loot.py)")

    def test_catches_a_crafted_item(self):
        d = tempfile.mkdtemp()
        try:
            for sub in ("addon/DungeonCrawlerForever/Data", "data/derived", "data/manual"):
                os.makedirs(os.path.join(d, sub))
            for f in ("addon/DungeonCrawlerForever/Data/Dungeons.lua",):
                shutil.copy(os.path.join(ROOT, f), os.path.join(d, f))
            open(os.path.join(d, "addon/DungeonCrawlerForever/Data/Loot.lua"), "w").write(
                'ns.Loot = {\n  [47] = { -- Razorfen Kraul\n    ["Roogug"] = {{274152,0},{252512,0}},\n  },\n}\n')
            with open(os.path.join(d, "data/derived/item_facts.csv"), "w", newline="") as fh:
                w = csv.writer(fh); w.writerow(["id", "name", "known", "crafted", "quality", "reqlevel", "ilvl", "bonding"])
                w.writerow([274152, "Roogug's Severed Head", 0, 0, "", "", "", ""]); w.writerow([252512, "Brawler's Leather Helm", 1, 1, 3, 25, 30, 1])
            hard, _, _ = audit_loot.audit(d)
            self.assertEqual(len(hard), 1)
            self.assertIn("Brawler's Leather Helm", hard[0])
        finally:
            shutil.rmtree(d)

    def test_generator_drops_crafted_automatically(self):
        self.assertIn(252512, gen_loot.excluded_items())
        self.assertNotIn(18258, gen_loot.excluded_items())  # a classic id is never auto-excluded

if __name__ == "__main__":
    unittest.main()
