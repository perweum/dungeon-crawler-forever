#!/usr/bin/env python3
"""Print one version's section from CHANGELOG.md (the part under "## [x.y.z] - date" up to the next version heading).

    tools/changelog_section.py v0.1.2        # tag or version; a suffix like -beta1 is ignored when no exact section exists
Exit code 1 (and a message on stderr) when the version has no entry: the release workflow uses this to refuse a release without notes.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def section(version):
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    v = version.lstrip("v")
    for cand in (v, v.split("-")[0]):
        m = re.search(r"^## \[" + re.escape(cand) + r"\][^\n]*\n(.*?)(?=^## \[|\Z)", text, re.M | re.S)
        if m and m.group(1).strip():
            return m.group(1).strip() + "\n"
    return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = section(sys.argv[1])
    if out is None:
        sys.exit(f"CHANGELOG.md has no entry for {sys.argv[1]}: add one before tagging")
    sys.stdout.write(out)
