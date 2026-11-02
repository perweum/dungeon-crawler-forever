#!/usr/bin/env python3
"""Offline tests for tools/gen_abilities.py: internal spell-name filter, per-boss selection, alphabetical order, that
data/manual/abilities_extra.csv spells survive the filter, and that data/manual/abilities_verified.csv lists replace everything else. The check of the committed Data/Abilities.lua order needs the git-ignored
data/raw/<build>/SpellName.csv and is skipped without it (e.g. in CI).
Run alone: tools/.venv/bin/python -B tools/test/test_abilities.py   (tools/test/run.py runs it too)"""
import csv, os, sys, tempfile, unittest

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

class Verified(unittest.TestCase):
    NAMES = BossSpells.NAMES
    OURS = {70: ("Uldaman", ["Grimlok", "Archaedas"]), 34: ("Stormwind Stockade", ["Bruegal Ironknuckle"])}

    def test_verified_replaces_generated_and_extra(self):
        npc_spells, extra = {10: [3, 1, 4]}, {(70, "Grimlok"): [9]}
        verified = {(70, "Grimlok"): [2, 6, 5, 7]}  # internal names and same-name spells kept, no cap
        old = ga.MAX_PER_BOSS
        try:
            ga.MAX_PER_BOSS = 1
            ids, tags = ga.select_spells((70, "Grimlok"), [10], npc_spells, self.NAMES, extra, verified)
        finally:
            ga.MAX_PER_BOSS = old
        self.assertEqual(ids, [7, 6, 2, 5])  # cleave, Green Channeling, Hate to Zero, Shadow Bolt: by name, none dropped
        self.assertEqual(set(tags.values()), {"verified"})

    def test_empty_verified_means_no_entry(self):
        ids, tags = ga.select_spells((70, "Grimlok"), [10], {10: [3, 1]}, self.NAMES, {(70, "Grimlok"): [9]}, {(70, "Grimlok"): []})
        self.assertEqual((ids, tags), ([], {}))

    def test_unverified_boss_unchanged(self):
        ids, tags = ga.select_spells((70, "Archaedas"), [10], {10: [3]}, self.NAMES, {(70, "Archaedas"): [9]}, {(70, "Grimlok"): []})
        self.assertEqual((ids, tags), ([9, 3], {9: "manual"}))

    def load(self, rows):
        with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8") as f:
            f.write("instanceMapID,boss,spellID,note\n" + "".join(r + ',"Wowhead, checked 2026-11-02"\n' for r in rows))
        self.addCleanup(os.unlink, f.name)
        return ga.load_verified(f.name, self.OURS, self.NAMES)

    def assertFails(self, rows, *fragments):
        with self.assertRaises(SystemExit) as cm:
            self.load(rows)
        for frag in fragments:
            self.assertIn(frag, str(cm.exception))

    def test_loader(self):
        self.assertEqual(self.load(["70,Grimlok,3", "70,Grimlok,1", "70,Grimlok,3", "34,Bruegal Ironknuckle,"]),
                         {(70, "Grimlok"): [3, 1], (34, "Bruegal Ironknuckle"): []})
        self.assertEqual(ga.load_verified("/nonexistent/abilities_verified.csv", self.OURS, self.NAMES), {})

    def test_loader_errors(self):
        self.assertFails(["70,Grimlok,3", "70,Nobody,3"], ".csv:3:", "unknown boss 'Nobody'")
        self.assertFails(["34,Grimlok,3"], ".csv:2:", "unknown boss")  # right name, wrong instance
        self.assertFails(["70,Grimlok,3", "70,Grimlok,8"], ".csv:3:", "spell 8 is not in")
        self.assertFails(["70,Grimlok,", "70,Grimlok,3"], ".csv:3:", "line 2 says it has no abilities")
        self.assertFails(["70,Grimlok,3", "70,Grimlok,"], ".csv:3:", "line 2 lists a spell")

    def test_dates(self):
        with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8") as f:
            f.write('instanceMapID,boss,spellID,note\n70,Grimlok,3,"x 2026-11-02"\n70,Grimlok,1,"y 2026-12-01"\n34,Bruegal Ironknuckle,,none\n')
        self.addCleanup(os.unlink, f.name)
        self.assertEqual(ga.verified_dates(f.name), {(70, "Grimlok"): "2026-12-01", (34, "Bruegal Ironknuckle"): ""})

class GeneratedData(unittest.TestCase):
    def test_grimlok_order(self):
        ab = check_abilities_extra.load_abilities()
        self.assertEqual(ab[70]["Grimlok"], [6742, 8292, 9532, 11892, 8143])  # Bloodlust, Chain Bolt, Lightning Bolt, Shrink, Tremor Totem

    def test_verified_bosses(self):
        ab = check_abilities_extra.load_abilities()
        self.assertEqual(ab[189]["Interrogator Vishas"], [9034, 2767])  # Immolate, Shadow Word: Pain (was the generated {8981})
        self.assertEqual(ab[70]["Archaedas"], [10252, 10258, 8269, 6524])
        for inst, boss in ((34, "Bruegal Ironknuckle"), (43, "Kresh"), (43, "Deviate Faerie Dragon"), (90, "Viscous Fallout"),
                           (90, "Grubbis"), (349, "Maraudos")):
            self.assertNotIn(boss, ab.get(inst, {}), "verified as no abilities: must have no entry")
        self.assertEqual(check_abilities_extra.problems(), [])

    @unittest.skipUnless(os.path.exists(SPELLNAME), "data/raw/<build>/SpellName.csv not present (git-ignored)")
    def test_every_boss_alphabetical_and_no_internal_names(self):
        names = {int(r["ID"]): r["Name_lang"] for r in csv.DictReader(open(SPELLNAME, encoding="utf-8"))}
        extra = set()
        for path in (ga.EXTRA_CSV, ga.VERIFIED_CSV):  # manual and verified spells are never name-filtered
            with open(path, encoding="utf-8") as f:
                for r in csv.DictReader(f):
                    if (r["spellID"] or "").strip():
                        extra.add((int(r["instanceMapID"]), r["boss"].strip(), int(r["spellID"])))
        for inst, bosses in check_abilities_extra.load_abilities().items():
            for boss, ids in bosses.items():
                self.assertEqual(ids, ga.by_spell_name(ids, names), f"[{inst}][{boss}] not in spell-name order")
                for sp in ids:
                    if (inst, boss, sp) not in extra:
                        self.assertFalse(ga.internal_name(names[sp]), f"[{inst}][{boss}] internal spell {sp} {names[sp]}")

if __name__ == "__main__":
    unittest.main()
