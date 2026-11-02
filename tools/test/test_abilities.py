#!/usr/bin/env python3
"""Offline tests for tools/gen_abilities.py: internal spell-name filter, per-boss selection, alphabetical order, and that
data/manual/abilities_extra.csv spells survive the filter. The check of the committed Data/Abilities.lua order needs the git-ignored
data/raw/<build>/SpellName.csv and is skipped without it (e.g. in CI).
Run alone: tools/.venv/bin/python -B tools/test/test_abilities.py   (tools/test/run.py runs it too)"""
import csv, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import gen_abilities as ga  # noqa: E402
import check_abilities_extra  # noqa: E402

SPELLNAME = os.path.join(ROOT, "data/raw", open(os.path.join(ROOT, "data/BUILD")).read().strip(), "SpellName.csv")

class InternalNames(unittest.TestCase):
    def test_internal_names_dropped(self):
        for nm in ("Disturb Rookery Egg (FAST)", "Hate to Zero", "Kirtonos Gargoyle Passive", "Shade of Eranikus Passive Visual",
                   "Add Lightning Dam - Weap 03", "Green Channeling", "Some Spell (DND)", "Word of Recall (OLD)", "Kill Credit",
                   "Dummy Spell", "Channel Visual"):
            self.assertTrue(ga.internal_name(nm), nm)

    def test_player_facing_names_kept(self):
        for nm in ("Chain Bolt (Rank 1)", "Shadow Bolt", "Hex of Jammal'an", "Poison Proc", "Summoned Urok", "Calm Dragonkin",
                   "Knock Away", "Mind Flay", "Thorns Aura", "Shadow Word: Pain", "Fireball (III)", "Tremor Totem", "Shrink"):
            self.assertFalse(ga.internal_name(nm), nm)

class BossSpells(unittest.TestCase):
    NAMES = {1: "shadow Bolt", 2: "Hate to Zero", 3: "Cleave", 4: "Arcane Explosion", 5: "Shadow Bolt", 6: "Green Channeling",
             7: "cleave", 9: "Bloodlust"}

    def test_alphabetical_case_insensitive_then_id(self):
        ids, added = ga.boss_spells([10], {10: [1, 3, 4, 9]}, self.NAMES)
        self.assertEqual(ids, [4, 9, 3, 1])
        self.assertEqual(added, [])
        self.assertEqual(ga.by_spell_name([5, 7, 3, 1], self.NAMES), [3, 7, 1, 5])  # same name: lower ID first

    def test_filter_dedupe_and_cap_before_extras(self):
        npc_spells = {10: [2, 6, 3, 7, 1], 11: [5, 4]}
        ids, _ = ga.boss_spells([10, 11], npc_spells, self.NAMES)
        self.assertEqual(ids, [4, 3, 1])  # internal 2 and 6 dropped, same-name 7 and 5 dropped
        old = ga.MAX_PER_BOSS
        try:
            ga.MAX_PER_BOSS = 1
            ids, added = ga.boss_spells([10, 11], npc_spells, self.NAMES, [9])
            self.assertEqual((ids, added), ([9, 3], [9]))  # cap applies to the generated part only, then sorted
        finally:
            ga.MAX_PER_BOSS = old

    def test_extra_spells_survive_filter(self):
        ids, added = ga.boss_spells([10], {10: [3]}, self.NAMES, [2, 6, 3])
        self.assertEqual(ids, [3, 6, 2])  # Cleave, Green Channeling, Hate to Zero
        self.assertEqual(added, [2, 6])

class GeneratedData(unittest.TestCase):
    def test_grimlok_order(self):
        ab = check_abilities_extra.load_abilities()
        self.assertEqual(ab[70]["Grimlok"], [6742, 8292, 9532, 11892, 8143])  # Bloodlust, Chain Bolt, Lightning Bolt, Shrink, Tremor Totem

    @unittest.skipUnless(os.path.exists(SPELLNAME), "data/raw/<build>/SpellName.csv not present (git-ignored)")
    def test_every_boss_alphabetical_and_no_internal_names(self):
        names = {int(r["ID"]): r["Name_lang"] for r in csv.DictReader(open(SPELLNAME, encoding="utf-8"))}
        extra = set()
        with open(ga.EXTRA_CSV, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                extra.add((int(r["instanceMapID"]), r["boss"].strip(), int(r["spellID"])))
        for inst, bosses in check_abilities_extra.load_abilities().items():
            for boss, ids in bosses.items():
                self.assertEqual(ids, ga.by_spell_name(ids, names), f"[{inst}][{boss}] not in spell-name order")
                for sp in ids:
                    if (inst, boss, sp) not in extra:
                        self.assertFalse(ga.internal_name(names[sp]), f"[{inst}][{boss}] internal spell {sp} {names[sp]}")

if __name__ == "__main__":
    unittest.main()
