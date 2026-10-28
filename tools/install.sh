#!/bin/zsh
# Symlink dev addons into a WoW client's AddOns folder.
# Usage: tools/install.sh [probe|main|all] [forever|beta]   (default: all forever)
set -e
case "${2:-forever}" in
  beta) CLIENT="_classic_beta_";;
  forever) CLIENT="_forever_";;
  *) echo "unknown client '$2' (forever|beta)"; exit 1;;
esac
DEST="/Applications/World of Warcraft/$CLIENT/Interface/AddOns"
SRC="$(cd "$(dirname "$0")/../addon" && pwd)"
mkdir -p "$DEST"
case "${1:-all}" in probe) L=(DungeonMapProbe);; main) L=(DungeonCrawlerForever);; *) L=(DungeonMapProbe DungeonCrawlerForever);; esac
for a in $L; do
  if [ -e "$DEST/$a" ] && [ ! -L "$DEST/$a" ]; then echo "skipped $a: $DEST/$a is a real folder (move it away first)"; continue; fi
  ln -sfn "$SRC/$a" "$DEST/$a"; echo "linked $a -> $CLIENT"
done
