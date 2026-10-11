# Data sources & provenance
Record every source used in shipped data: what, URL, date, licence/ToS, how used.

| Source | Used for | Licence/ToS | Status |
|---|---|---|---|
| wago.tools DB2 CSV (build 1.60.1.70291) | maps, boss lists, LFG dungeons | game data extracted from client; public CSV | in use (raw only, not shipped verbatim) |
| MapUtils (D4KiR) | **not used** — studied only | All Rights Reserved, no redistribution | excluded (D-012) |

Licence of this project: GPL-3.0-or-later. Add one row per third-party source actually used (name, URL, licence, what, date).
| wago.tools DB2 JournalEncounter/JournalInstance, MoP Classic 5.5.4.70032 and retail live | boss pins (Map_0/Map_1, UiMapID), portrait FileDataIDs | Blizzard game data via public CSV; IDs/numbers only | in use (2026-10-09) |
| Forever Map.Corpse_0/1 + UiMapAssignment (client DB2) | classic dungeon entrance pin positions | game data; derived by us | in use; approximate (±0.05), correctable |
| foreverdb.net (levels, floors, entrance facts), icy-veins/warcrafttavern/classicwow.gg (levels/entrances) | recommended level ranges, a few entrance positions | facts only (numbers); no text/images copied | in use via data/manual/dungeon_info.csv; per-row source URLs there |
| CMaNGOS classic-db (https://github.com/cmangos/classic-db, GPL-3.0) | creature spawn positions of 7 bosses (Stormwind Stockade, Sunken Temple, Razorfen Downs) converted to map coords | GPL-3.0 (compatible with our GPL-3.0-or-later); coordinates only | in data/draft/bosses_draft.csv, shown as 'approximate' (2026-10-09) |
| Santiago Reyes, Atlas de Azeroth: Forever — Hall of Thanes, Excavation Site: Wetlands, Ruins of Lordaeron and City of Dalaran (2 floors) maps | bundled low-res map textures (tiles in addon/DungeonCrawlerForever/Art/) | free for the community per his site disclaimer; no explicit redistribution licence → courtesy confirmation before release | pending files; credit + link shown in-game |
(Santiago Reyes site: https://asguevara433.wixsite.com/srmaps — referenced in README only, never in-game; see D-026.)
| AtlasLoot Forever (AtlasLootClassic_DungeonsAndRaids data.lua + droprate.lua; GPL-3.0, author sliccer) | boss loot item IDs, Forever-addition flags, drop rates (facts only), snapshot in Data/Loot.lua | GPL-3.0, compatible | in use via tools/gen_loot.py (2026-10-09) |

| Upper Blackrock Spire map images (3 floors: Dragonspire Hall, Hall of Binding / The Rookery, Blackrock Stadium) | map art for the Upper Blackrock Spire wing, converted to bundled BLP tiles (Art/229_*) | supplied by the project maintainer; Blizzard Entertainment game art. Origin of the files to be recorded here before release | in use (2026-10-10) |
| CMaNGOS classic-db (https://github.com/cmangos/classic-db, GPL-3.0): `creature_template_spells`, `creature_ai_scripts` | boss ability spell IDs (IDs only; text comes from the game client), via tools/gen_abilities.py | GPL-3.0, compatible with our GPL-3.0-or-later; facts only | in use (2026-10-10) |
| Forever client dungeon-finder levels (`GetLFGDungeonInfo`, read with `/dmprobe lfg` on build 1.60.1.70338) | start of each classic dungeon's level range (data/manual/lfg_levels.csv) | game data read in game by the maintainer | in use (2026-10-11) |
