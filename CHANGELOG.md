# Changelog

Written for players: what you get, not what changed in the code. One entry per release, newest first.

## [0.1.7] - 2026-10-14

### New
- **Sunken Temple on one map.** All five floors on a single overview map, like Gnomeregan, Shadowfang Keep and Blackrock Spire.
- **Activation markers.** Statues, braziers, postboxes and other things you have to use to start a boss now have a marker on the map. Select a boss and its markers are highlighted; hover for what to do. Added for Sunken Temple (Atal'alarion and Jammal'an), Blackfathom Deeps (Aku'mai), Uldaman (Ironaya) and Stratholme (Postmaster Malown).
- **Summoned bosses are marked.** Bosses that need an item or a quest from outside the dungeon, such as Gahz'rilla (the mallet), Kirtonos, Kormok, Death Knight Darkreaver, the Tier 0.5 bosses and the Dreadsteed boss, get a purple tag and ring. Event bosses like Aku'mai and Archaedas show a one-line hint on how to start the fight.
- **Missing bosses added:** Ogom the Wretched in Sunken Temple, Mor Grayhoof, Isalien, Death Knight Darkreaver, Gyth and Watchman Doomgrip, with their loot.

### Improved
- More linked stairs and doors recorded across the dungeons.
- More boss positions on the overview maps.

### Fixed
- "The Vault" in Blackrock Depths is no longer listed as a boss. It is the event that releases Watchman Doomgrip, who now has the pin.

## [0.1.6] - 2026-10-13

### New
- **One overview map for the maze-like dungeons.** Gnomeregan, Shadowfang Keep and both halves of Blackrock Spire now open on a single big map of the whole dungeon instead of separate floors. It fills your window, opens zoomed on the entrance, and has boss pins and markers on it. Select a boss in the list and the map moves to it if it is out of view.
- **Stairs and doors that tell you where they lead.** Linked stairs, doors and arrows share a letter at both ends (A, B, C and so on, starting again in each wing). Hover one to see where it goes, click it to jump to the other end. Linked dungeons so far: Shadowfang Keep, Gnomeregan, Blackrock Spire, Scholomance, Blackfathom Deeps, Uldaman, Maraudon and the City of Dalaran. The All floors view draws a coloured line between each pair.
- **Trash loot.** Every dungeon and raid with a trash loot table now has a "Trash" entry at the end of the boss list with the items that drop from the regular monsters.
- **City of Dalaran loot** for all eight bosses, from the latest AtlasLoot Forever.
- **Two missing Upper Blackrock Spire bosses:** Solakar Flamewreath (the Rookery event) and the rare Jed Runewatcher, with their loot.

### Improved
- A quest chain is now named after the quest that starts it, not a generic name. The City of Dalaran key quest is Heart of Disruption, for both factions.
- An Ancient Grudge in the Hall of Thanes now shows who takes it in.
- Quest tooltips are bigger and easier to read.

### Fixed
- Boss portraits are back in the dungeons that now use an overview map.

### For contributors
- New edit-mode buttons: **Link markers** (join any two markers, even on the same map), **Landmarks** (known bosses, doors and vendors from the game data) and **Overlay** (shows another floor faintly, to find where stairs connect).

## [0.1.5] - 2026-10-12

### New
- **Quest tooltips with real facts.** Hovering a quest shows its status (completed, in your log, available or why it is locked), level, required level, who starts it and who ends it, with the zone and map coordinates, and the quest it requires. Chains list their steps with the next step marked. The text is larger and easier to read.
- **Where to pick quests up.** Most quests now show the zone and map coordinates of the quest giver and the hand-in NPC.

### Fixed
- **City of Dalaran key quest.** Heart of Disruption (both factions) is now marked as the quest that gives the dungeon key, instead of Blood in the Streets.
- An Ancient Grudge (Hall of Thanes) now shows its hand-in, the Ghostly Attendant inside the dungeon.
- The Ruins of Lordaeron marker on the Eastern Kingdoms map no longer hides under the Undercity marker.

## [0.1.4] - 2026-10-12

### New
- **Quests for Ruins of Lordaeron and Excavation Site: Wetlands.** Both dungeons now have their quests on the Quests tab, for Horde and Alliance: the pick-ups outside and inside the dungeon, the quests started by items you loot, and the chains between them (Elder Knowledge and Earthen Echo, Lost in the Thicket Things and Heartwoven, Dragonmaw Rumors and Open the Maw, and more). Only the quests that belong to the dungeon are listed, not the long storylines behind them.

## [0.1.3] - 2026-10-12

### New
- **Quests tab.** Dungeons with known quests get a **Bosses | Quests** switch in the sidebar. It lists the attunement and key quests, the pre-quests that lead to the dungeon, and the quests you pick up outside or inside it, for all 19 classic dungeons plus the City of Dalaran and the Hall of Thanes.
- **It knows where you are in each quest.** Completed quests are checked off and folded away, quests in your log are marked, and quests you cannot take yet say why: "Requires: <quest>" or "Requires level 24". Quests for the other faction or another class are hidden.
- **Quest chains are one row.** Open a chain to see its steps (for example "Step 2 of 3"), so long chains like the Scholomance key do not crowd the list. Finishing a later step also counts the earlier ones as done.
- In the wide view the quests have a detail pane with level, where to pick the quest up and where to hand it in.

### Notes
- Classic quest data comes from the CMaNGOS classic database, filtered by the quests Forever actually has. Levels of quests Forever has changed may be off; the Forever-only dungeons were entered by hand. Report anything that looks wrong.
- The quest list is text only: quest givers are not marked on the dungeon maps, the game's own map markers still work outside.

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
