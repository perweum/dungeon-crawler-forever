"""The release zip must not contain developer-only files (Dev.lua) or their TOC lines (D-078)."""
import os, re, subprocess, sys, tempfile, unittest, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class PackageDev(unittest.TestCase):
    def test_dev_lua_not_shipped(self):
        toc = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/DungeonCrawlerForever.toc"), encoding="utf-8").read()
        version = re.search(r"^## Version: (\S+)", toc, re.M).group(1)
        out = os.path.join(ROOT, "dist", f"DungeonCrawlerForever-{version}.zip")
        had = os.path.exists(out)
        subprocess.run([sys.executable, os.path.join(ROOT, "tools/package.py"), "--skip-tests", "--skip-recorded-check"], check=True, stdout=subprocess.DEVNULL)
        try:
            with zipfile.ZipFile(out) as z:
                names = z.namelist()
                self.assertFalse([n for n in names if n.endswith("Dev.lua")], "Dev.lua is in the zip")
                ztoc = z.read("DungeonCrawlerForever/DungeonCrawlerForever.toc").decode("utf-8")
                self.assertNotIn("Dev.lua", ztoc)
                self.assertIn("Commands.lua", ztoc)
        finally:
            if not had:
                os.remove(out)

if __name__ == "__main__":
    unittest.main()
