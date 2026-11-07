"""tools/import_report.py: parsing, validation and conflict handling of a "Share my recordings" report (no files of the repo are changed)."""
import importlib.util, os, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
spec = importlib.util.spec_from_file_location("import_report", os.path.join(ROOT, "tools/import_report.py"))
src = open(spec.origin, encoding="utf-8").read().rsplit("\nmain()", 1)[0]  # the module without its final main() call
mod = type(sys)("import_report")
mod.__file__ = spec.origin
exec(compile(src, spec.origin, "exec"), mod.__dict__)

class ImportReport(unittest.TestCase):
    def run_report(self, text, extra=()):
        d = tempfile.mkdtemp()
        mod.POS, mod.DISP = os.path.join(d, "bosses.csv"), os.path.join(d, "boss_display.csv")
        rp = os.path.join(d, "r.txt")
        open(rp, "w", encoding="utf-8").write(text)
        old = sys.argv
        sys.argv = ["import_report.py", rp, "--no-gen", *extra]
        try:
            mod.main()
        finally:
            sys.argv = old
        return open(mod.POS, encoding="utf-8").read() if os.path.exists(mod.POS) else ""

    def test_position_and_portrait(self):
        names = mod.boss_names()
        inst = next(i for i, b in names.items() if "Zul'Alai" in b)
        out = self.run_report(f"DCF 0.1.19 build 70862\nP|{inst}|829591|Zul'Alai|0.4123|0.2345\nD|{inst}|Zul'Alai|555\n")
        self.assertIn(f"{inst},829591,Zul'Alai,0.4123,0.2345", out)
        self.assertIn("Zul'Alai,555", open(mod.DISP, encoding="utf-8").read())

    def test_bad_lines_are_skipped(self):
        names = mod.boss_names()
        inst = next(i for i, b in names.items() if "Zul'Alai" in b)
        out = self.run_report(f"P|{inst}|829591|Not A Boss|0.4|0.4\nP|{inst}|829591|Zul'Alai|1.4|0.4\nP|99999|1|X|0.1|0.1\nnonsense\n")
        self.assertEqual(out, "")

if __name__ == "__main__":
    unittest.main()
