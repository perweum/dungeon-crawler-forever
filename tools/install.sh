#!/bin/zsh
# Symlink dev addons into the Forever beta AddOns folder. Usage: tools/install.sh [probe|main|all]
set -e
DEST="/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
SRC="$(cd "$(dirname "$0")/../addon" && pwd)"
case "${1:-all}" in probe) L=(DungeonMapProbe);; main) L=(DungeonCrawlerForever);; *) L=(DungeonMapProbe DungeonCrawlerForever);; esac
for a in $L; do ln -sfn "$SRC/$a" "$DEST/$a"; echo "linked $a"; done
