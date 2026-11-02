#!/usr/bin/env python3
"""Offline tests for tools/fetch_sources.py (no network: git is replaced by a stub, fixtures are tiny files in a temp dir).
Run alone: tools/.venv/bin/python -B tools/test/test_fetch_sources.py   (tools/test/run.py runs it too)"""
import ast, gzip, hashlib, io, json, os, shutil, sys, tempfile, unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import fetch_sources as fs  # noqa: E402

DUMP = """-- MySQL dump 10.13
CREATE TABLE `creature_ai_scripts` (
  `id` int unsigned NOT NULL,
  `creature_id` int unsigned NOT NULL DEFAULT '0',
  `action1_type` tinyint unsigned NOT NULL DEFAULT '0',
  `action1_param1` int NOT NULL DEFAULT '0',
  `comment` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb3;
LOCK TABLES `creature_ai_scripts` WRITE;
INSERT INTO `creature_ai_scripts` VALUES (1,100,11,999,'old row');
UNLOCK TABLES;
CREATE TABLE `creature_ai_summons` (
  `id` int unsigned NOT NULL,
  `comment` text,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM;
INSERT INTO `creature_ai_summons` VALUES (7,'old summon');
CREATE TABLE `db_version` (
  `version` varchar(120) DEFAULT NULL,
  `required_z2815_01_mangos_pursuit` bit(1) DEFAULT NULL,
  `content_4493_VDB-20191006132107_world` bit(1) DEFAULT NULL
) ENGINE=MyISAM;
INSERT INTO `db_version` VALUES ('Classic DB',NULL,NULL);
CREATE TABLE `creature_template_spells` (
  `entry` int NOT NULL,
  `spell1` int NOT NULL
) ENGINE=MyISAM;
INSERT INTO `creature_template_spells` VALUES (100,5),(101,6);
"""

ACID = """/* licence header; with a ; inside */
TRUNCATE creature_ai_scripts;
TRUNCATE creature_ai_summons;
UPDATE db_version SET `creature_ai_version` = 'ACID';
-- a comment with a quote ' and a ;
INSERT INTO `creature_ai_scripts` (`id`,`creature_id`,`comment`,`action1_type`,`action1_param1`) VALUES
('10001','100','Boss - Cast Fireball; then \\'flee\\'','11','133'),
('10002','100','It''s fine','11','0');
INSERT INTO `creature_ai_summons` (`id`,`comment`) VALUES
('8',NULL);
UPDATE creature_template SET AIName='EventAI' WHERE entry=100;
"""


def gen_quests_sql_rows():
    """The real parser the generators use (tools/gen_quests.py runs main() on import, so only this function is taken)."""
    src = read(os.path.join(TOOLS, "gen_quests.py"))
    fn = next(n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "sql_rows")
    ns = {}
    exec(compile(ast.Module(body=[fn], type_ignores=[]), "gen_quests.py", "exec"), ns)
    return ns["sql_rows"]


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class FakeGit:
    """Stands in for fs.run_git: answers ls-remote, and builds a fake upstream checkout for clone."""
    def __init__(self, commit="a" * 40, fail=None):
        self.commit, self.fail, self.calls = commit, fail, []

    def __call__(self, args, timeout, cwd=None):
        self.calls.append(args[0])
        if self.fail:
            raise RuntimeError(self.fail)
        if args[0] == "ls-remote":
            return f"{self.commit}\trefs/heads/master\n"
        if args[0] == "clone":
            d = args[-1]
            os.makedirs(os.path.join(d, "Full_DB")); os.makedirs(os.path.join(d, "ACID"))
            os.makedirs(os.path.join(d, "Updates", "Instances"))
            with gzip.open(os.path.join(d, "Full_DB", "ClassicDB_test.sql.gz"), "wt", encoding="utf-8") as f:
                f.write(DUMP)
            write(os.path.join(d, "ACID", "acid_classic.sql"), ACID)
            for name in ("4490_old.sql", "4494_new.sql", "4500_newer.sql", "9999_Final.sql"):
                write(os.path.join(d, "Updates", name), "UPDATE x SET y=1;\n")
            write(os.path.join(d, "Updates", "Instances", "036_deadmines.sql"), "\n")
            return ""
        if args[0] == "sparse-checkout":
            return ""
        if args[0] == "log":
            return f"{self.commit} 2026-10-25T20:12:03+01:00\n"
        raise AssertionError(f"unexpected git call {args}")


class FetchSourcesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dcf-fetch-test-")
        self.dest = os.path.join(self.tmp, "sources")
        self.wow = os.path.join(self.tmp, "wow")
        inst = os.path.join(self.wow, "Interface", "AddOns", fs.ATLAS_DIR)
        os.makedirs(inst); os.makedirs(os.path.join(self.wow, "Interface", "AddOns", "AtlasLootClassic"))
        write(os.path.join(inst, "data.lua"), "data = 1\n")
        write(os.path.join(inst, "droprate.lua"), "rates = 1\n")
        write(os.path.join(self.wow, "Interface", "AddOns", "AtlasLootClassic", "AtlasLootClassic.toc"), "## Version: Forever 1.60.1\n")
        self.inst = inst
        self._saved = fs.run_git, fs.WOW_DIR
        fs.WOW_DIR = self.wow

    def tearDown(self):
        fs.run_git, fs.WOW_DIR = self._saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_main(self, *args):
        out = io.StringIO()
        with redirect_stdout(out):
            code = fs.main(list(args) + ["--dest", self.dest])
        return code, out.getvalue()

    def sources_line(self, text):
        return [l for l in text.splitlines() if l.startswith("SOURCES ")][-1]

    def test_build_sql_replaces_acid_tables_in_dump_column_order(self):
        os.makedirs(self.dest)
        gz, acid, out = (os.path.join(self.dest, n) for n in ("d.sql.gz", "acid.sql", "out.sql"))
        with gzip.open(gz, "wt", encoding="utf-8") as f:
            f.write(DUMP)
        write(acid, ACID)
        res = fs.build_sql(gz, acid, out, "header line")
        self.assertEqual(res["replaced"], {"creature_ai_scripts": 2, "creature_ai_summons": 1})
        self.assertEqual(res["content_version"], 4493)
        self.assertEqual(len(res["ignored"]), 2)  # the two UPDATE statements
        text = read(out)
        self.assertTrue(text.startswith("-- header line\n"))
        self.assertNotIn("old row", text)
        self.assertNotIn("old summon", text)
        self.assertIn("INSERT INTO `creature_template_spells` VALUES (100,5),(101,6);", text)  # other tables untouched
        sql_rows = gen_quests_sql_rows()
        lines = [l for l in text.splitlines() if l.startswith("INSERT INTO `creature_ai_scripts`")]
        self.assertEqual(len(lines), 1)
        rows = sql_rows(lines[0])
        # dump column order: id, creature_id, action1_type, action1_param1, comment
        self.assertEqual(rows[0], ["10001", "100", "11", "133", "Boss - Cast Fireball; then 'flee'"])
        self.assertEqual(rows[1], ["10002", "100", "11", "0", "It's fine"])
        summons = [l for l in text.splitlines() if l.startswith("INSERT INTO `creature_ai_summons`")]
        self.assertEqual(sql_rows(summons[0]), [["8", None]])
        # the INSERT comes after its CREATE TABLE (gen_abilities reads columns from the CREATE TABLE)
        self.assertLess(text.index("CREATE TABLE `creature_ai_scripts`"), text.index(lines[0]))

    def test_build_sql_refuses_column_mismatch(self):
        os.makedirs(self.dest)
        gz, acid, out = (os.path.join(self.dest, n) for n in ("d.sql.gz", "acid.sql", "out.sql"))
        with gzip.open(gz, "wt", encoding="utf-8") as f:
            f.write(DUMP)
        write(acid, "TRUNCATE creature_ai_summons;\nINSERT INTO `creature_ai_summons` (`id`,`extra`) VALUES (1,2);\n")
        with self.assertRaises(ValueError):
            fs.build_sql(gz, acid, out)
        self.assertFalse(os.path.exists(out))
        self.assertFalse(os.path.exists(out + ".tmp"))

    def test_check_with_empty_cache_reports_missing_and_changes_nothing(self):
        fs.run_git = git = FakeGit()
        code, out = self.run_main("--check")
        self.assertEqual(code, 0)
        self.assertEqual(self.sources_line(out), "SOURCES cdb=missing atlas=missing")
        self.assertEqual(git.calls, ["ls-remote"])  # one request, no download
        self.assertFalse(os.path.exists(self.dest))

    def test_fetch_then_check_newer_and_offline(self):
        fs.run_git = FakeGit("a" * 40)
        code, out = self.run_main("--fetch")
        self.assertEqual(code, 0, out)
        sql = os.path.join(self.dest, "classic-db", fs.SQL_NAME)
        atlas = os.path.join(self.dest, "atlasloot", fs.ATLAS_DIR)
        self.assertIn(f"--cdb {sql}", out)
        self.assertIn(f"--atlas {atlas}", out)
        self.assertTrue(os.path.isfile(os.path.join(atlas, "data.lua")))
        state = json.loads(read(os.path.join(self.dest, "state.json")))
        self.assertEqual(state["cdb"]["commit"], "a" * 40)
        self.assertEqual(state["cdb"]["updates_newer_than_dump"], 3)       # 4494, 4500, 9999 (4490 is in the dump)
        self.assertEqual(state["cdb"]["last_update_file"], "4500_newer.sql")
        self.assertEqual(state["cdb"]["instance_scripts"], 1)
        self.assertEqual(state["atlas"]["sha256"]["data.lua"], hashlib.sha256(b"data = 1\n").hexdigest())
        self.assertEqual(state["atlas"]["toc_version"], "Forever 1.60.1")

        fs.run_git = git = FakeGit("a" * 40)
        code, out = self.run_main("--check")
        self.assertEqual(self.sources_line(out), "SOURCES cdb=ok atlas=ok")
        self.assertEqual(git.calls, ["ls-remote"])

        # a second --fetch with nothing new downloads nothing
        fs.run_git = git = FakeGit("a" * 40)
        code, out = self.run_main("--fetch")
        self.assertEqual(git.calls, ["ls-remote"])
        self.assertIn("nothing downloaded", out)
        self.assertIn("nothing copied", out)

        # upstream moved and the installed AtlasLoot data changed (same TOC version)
        write(os.path.join(self.inst, "droprate.lua"), "rates = 2\n")
        fs.run_git = FakeGit("b" * 40)
        code, out = self.run_main("--check")
        self.assertEqual(self.sources_line(out), "SOURCES cdb=newer atlas=newer")
        self.assertIn("NEWER AVAILABLE commit bbbbbbbbbb", out)
        self.assertIn("droprate.lua", out)
        self.assertEqual(read(os.path.join(self.inst, "droprate.lua")), "rates = 2\n")  # game copy untouched

        # refetch: upstream moved but Full_DB/ACID identical -> .sql kept; atlas recopied
        fs.run_git = FakeGit("b" * 40)
        code, out = self.run_main("--fetch")
        self.assertIn("inputs changed: no", out)
        self.assertIn("content changed", out)
        fs.run_git = FakeGit("b" * 40)
        self.assertEqual(self.sources_line(self.run_main("--check")[1]), "SOURCES cdb=ok atlas=ok")

        # offline: clear error, exit 1, no retry
        fs.run_git = git = FakeGit(fail="git ls-remote timed out after 30s (offline?)")
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertEqual(self.sources_line(out), "SOURCES cdb=error atlas=ok")
        self.assertIn("ERROR git ls-remote timed out", out)
        self.assertEqual(git.calls, ["ls-remote"])

    def test_atlas_missing_install_is_an_error(self):
        fs.run_git = FakeGit()
        shutil.rmtree(self.inst)
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertEqual(self.sources_line(out), "SOURCES cdb=missing atlas=error")

    def test_dest_inside_repo_is_refused(self):
        with self.assertRaises(SystemExit):
            fs.resolve_dest(os.path.join(fs.ROOT, "tools", "cache-x"))
        self.assertEqual(fs.resolve_dest(self.dest), os.path.realpath(self.dest))


if __name__ == "__main__":
    unittest.main()
