# Contributing

The addon's code is GPL-3.0-or-later (see `LICENSE`). Most useful contributions are **observations from the game** that no database has:

## Record boss positions (new dungeons or dungeons with gaps)
1. Open the dungeon map (`/dm`, pick the dungeon), type `/dm dev` once (switches the developer commands on, they are hidden from players), then `/dm edit`.
2. Select a boss in the right-hand list, then click its position on the map. Repeat.
3. `/reload`, then from a checkout of this repository run
   `tools/.venv/bin/python tools/import_manual.py` (needs `python3 -m venv tools/.venv && tools/.venv/bin/pip install lupa`).
   Or use `/dm export` in game and paste the lines into `data/manual/bosses.csv` yourself.
4. Open a pull request with the changed `data/manual/*.csv`. `data/STATUS.md` shows what is still missing (regenerate it with `python3 tools/coverage.py`).

## Floor markers (entrances, exits, stairs, portals)
In edit mode (`/dm edit`) click one of the buttons at the top of the map to choose what a click places: Boss / Entrance / Exit / Stairs up / Stairs down / Portal, then click the map. Shift-click a marker to remove it. `/reload`, then `tools/import_manual.py` writes `data/manual/markers.csv`.

## Portraits, names, entrances
- Boss portrait: `/dm display <displayID>` with the boss selected (look the ID up on a database site by hand; please do not scrape one) -> `data/manual/boss_display.csv`.
- A boss shows under a working/internal name, or an entry is not a boss: `data/manual/boss_names.csv`, `data/manual/boss_hide.csv`.
- An entrance is in the wrong spot: `data/manual/overrides.csv` (zone uiMapID, x, y as fractions 0-1).

## Art
Painted map art must come with the author's permission and a licence we can ship; credit goes in `data/manual/art_credits.csv`
and `data/SOURCES.md`. Convert with `tools/jpg2blp.py`. Do not add Blizzard art files; the addon references the game's own files by ID.

## Data that regenerates
Do not edit `addon/DungeonCrawlerForever/Data/*.lua` by hand; they are generated. To refresh the generated data after a game patch run `tools/update.py --latest` (needs the venv python; add `--cdb <classic-db.sql>` to regenerate boss abilities); see the docstring of `tools/update.py`.

## Policy
The addon follows Blizzard's UI add-on policy: no donation requests or advertising inside the game. Put donation links on the distribution page only.

## Releasing (maintainer)
1. Record or fix data in game, then `tools/.venv/bin/python tools/import_manual.py` so it is in `data/manual/*.csv` (packaging refuses to build while recorded data is missing: `tools/check_recorded.py`).
2. Bump `## Version` in `addon/DungeonCrawlerForever/DungeonCrawlerForever.toc`, run the tests (`tools/.venv/bin/python tools/test/run.py`), commit and push.
3. Tag the commit `vX.Y.Z` (the tag must match the TOC version) and push the tag. The `Release` workflow builds the zip, attaches it to a GitHub release and uploads it to CurseForge.
   Use a tag like `v0.2.0-beta1` for a beta, `-alpha1` for an alpha; otherwise `CF_RELEASE_TYPE` (default beta) decides.
   One-time setup: secret `CF_API_KEY`, variables `CF_PROJECT_ID` and `CF_GAME_VERSION_IDS` (see the header of `.github/workflows/release.yml`).

## Testing like a player (maintainer)
The dev symlink reads the source and your own recorded data, which hides missing data (see D-055). Before a release: close the game,
run `tools/player_test.sh on` (installs the newest zip from `dist/` and moves your saved variables aside), test, close the game and run
`tools/player_test.sh off` to get the dev symlink and your saved variables back.

## Floor order
The floors of a dungeon follow the game's own order. To change it, add a row to `data/manual/floor_order.csv` (`instanceMapID,order,note`, `order` = the floor ids in the order you want, separated by `;`; floors you leave out keep the game's order after them), then run `python3 tools/gen_art.py` and `python3 tools/gen_dungeons.py`. Wings (Blackrock Spire, Dire Maul, Scarlet Monastery) set their floor order in `data/manual/wings.csv` instead.
