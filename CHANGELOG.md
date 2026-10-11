# Changelog

Written for players: what you get, not what changed in the code. One entry per release, newest first.

## [0.1.2] - 2026-10-11

### New
- **Floor markers.** Entrances, exits, stairs up, stairs down and left / right arrows are marked on the maps of 18 dungeons, so you can see how the floors connect. They use the game's own door icons, and they are larger and easier to spot.
- **Blackrock Depths: the Ring of Law.** One entry in the boss list that opens to show its six champions (Gorosh, Grizzle, Eviscerator, Ok'thor, Anub'shiah, Hedrum) with their loot, portraits and abilities. Click it to open or close the list.
- **More boss locations**, among them all nine Lower Blackrock Spire bosses, more of Blackrock Depths (the tavern bosses, the Vault) and Roogug in Razorfen Kraul.

### Improved
- **Floors in the order you walk through the dungeon.** Lower Blackrock Spire now starts at the Hall of Blackhand, and in Shadowfang Keep the Wall Walk is the fourth floor.

### Fixed
- The navigation bar now fits the dungeon name and shows the floor drop-down only for dungeons with several floors, including when you switch between Lower and Upper Blackrock Spire.

### For contributors
- Edit mode has one button per marker type, explains why a click did nothing, and shift-click removes any marker. Contributor commands tell you to type `/dm dev` first.

## [0.1.1] - 2026-10-11

### Fixed
- **Missing boss locations** in Shadowfang Keep (6 bosses), Razorfen Downs (2) and Stormwind Stockade (2). They were not included in the first release.
- The navigation bar width and floor drop-down when switching between Lower and Upper Blackrock Spire.
- Small corrections to the boss locations in the City of Dalaran.

## [0.1.0] - 2026-10-10

First release.

### New
- Dungeon and raid maps inside the world map, with every floor, a navigation bar and floor selector, and entrance pins on the zone and continent maps.
- Clickable boss portraits on the map: click for the sidebar, double-click for the wide view (Bosses, Abilities and Loot side by side).
- Loot with drop chances and item tooltips (from AtlasLoot Forever), and boss abilities from the game's own spell data.
- Defeated bosses are checked off for the current run, rare bosses have a silver ring and a one-click Find button.
- Lower / Upper Blackrock Spire, Dire Maul and Scarlet Monastery are listed as the separate dungeons you queue for.
- Maps for the new Forever dungeons: Hall of Thanes, Ruins of Lordaeron, Excavation Site and City of Dalaran.
- Level ranges taken from the game's own dungeon finder. A small options page (`/dm config`).
