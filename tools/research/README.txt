Throw-away research prototypes (2026-10-09).
Run from a scratch dir containing lf.csv (community-listfile, "id;path"), wdt/, tiles/, obj/, wmot/ subdirs; needs Pillow.
Files are fetched from https://wago.tools/api/casc/<FileDataID>?download&version=1.60.1.70291 (public, no key).
wdt.py/maid.py: parse WDT MAIN+MAID (minimap FileDataID = 8th uint32). stitch.py: terrain minimap stitcher.
obj.py/wmoid.py: list WMOs placed in a map (MODF nameId == FileDataID) and their WMOID. wmostitch.py: WMO minimap stitcher.
