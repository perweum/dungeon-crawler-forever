"""tools/apply_level_rules.py: the grey formula, the cap, and the rule on a few real cases (D-081)."""
import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import apply_level_rules as R

class LevelRules(unittest.TestCase):
    def test_gray_level(self):
        self.assertEqual(R.gray_level(5), 0)
        self.assertEqual(R.gray_level(28), 21)   # 28 - 2 - 5
        self.assertEqual(R.gray_level(45), 35)   # 45 - 9 - 1
        self.assertEqual(R.gray_level(60), 51)   # 60 - 9

    def test_cap(self):
        self.assertEqual(R.cap_for(20), 26)      # Rethilgore (20) is grey from player level 27 on: Shadowfang Keep ends at 26
        self.assertEqual(R.cap_for(62), 60)

    def test_rule_classic(self):
        # Razorfen Kraul: available 24, bosses 28-33: a level 24 player cannot hit the last boss (33), so it starts at 28
        self.assertEqual(R.rule(24, 28, 33, 24, 33, False, False), (28, 33))
        # Deadmines: available 16, top boss 21: 16 is fine
        self.assertEqual(R.rule(16, 19, 21, 16, 25, False, False), (16, 25))
        # Shadowfang Keep: the lowest boss is level 20 and the old upper bound was 28
        self.assertEqual(R.rule(18, 20, 26, 18, 28, False, False), (21, 26))

    def test_rule_new_and_exempt(self):
        # a new dungeon keeps Blizzard's range, raised only to Available (Excavation Site: 24-29, available 26)
        self.assertEqual(R.rule(26, 28, 31, 24, 29, True, False), (26, 29))
        # Uldaman keeps its recommended range
        self.assertEqual(R.rule(35, 40, 47, 35, 45, False, True), (35, 45))

if __name__ == "__main__":
    unittest.main()
