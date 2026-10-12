#!/bin/bash
# Download DB2 tables as CSV from wago.tools for a given build. Usage: tools/fetch_db2.sh [build]
BUILD="${1:-$(cat "$(dirname "$0")/../data/BUILD")}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/data/raw/$BUILD"; mkdir -p "$OUT"
for t in Map LFGDungeons UiMap UiMapAssignment UiMapArt UiMapXMapArt UiMapArtStyleLayer AreaTable WMOMinimapTexture AreaPOI DungeonEncounter MapDifficulty WorldMapOverlay SpellName QuestV2; do
  curl -sf -m 60 "https://wago.tools/db2/$t/csv?build=$BUILD" -o "$OUT/$t.csv" && echo "$t ok" || echo "$t MISSING"
done
