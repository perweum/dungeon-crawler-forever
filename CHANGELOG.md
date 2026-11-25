# Changelog

Written for players: what you get, not what changed in the code. One entry per release, newest first.

## [Unreleased]

### Added
- **New instances this hour:** the game refuses you with "You have entered too many instances lately" after 5 new instances in an hour, and never says how many you have used. The sidebar now counts them and shows "3 of 5 new instances this hour"; walking back into an instance you have not reset does not count. At the limit it turns red and says how many minutes until the next slot frees up.
- **Dungeon lockouts:** under the typical clear time the sidebar now says "Locked" with how many bosses are defeated and how long until the lockout resets (counting down while the map is open), or "Not locked". The addon asks the game for your saved instances when a map opens, which the old line never did.

### Added
- **Quest markers inside the older dungeons:** a blue "!" where an NPC or object inside the dungeon hands out a quest, and a yellow "?" where you hand one in (Blackrock Depths, Dire Maul, Blackrock Spire, Uldaman, Stratholme, Razorfen Kraul and Downs, Blackfathom Deeps, Sunken Temple, Ragefire Chasm, Scarlet Monastery, Shadowfang Keep). They show only for the quests that are yours, the start until you have the quest and the hand-in while you have it.

### Added
- **Quest rewards in the Quests tab:** click a quest and the details show what it asks for and gives, laid out like the game's own quest reward frame: the objective, "choose one of these rewards" and "you will receive" with the item icons and tooltips, experience, reputation and money. In the wide view it sits beside the list; in the narrow view it opens under the list (click the quest again to close it). Old quests have no experience figure.

### Added
- **Alcaz Prison: the end of both quest lines:** Bad News for Folkar and Thrall Needs to Know (Horde) and Somber News (Alliance) are listed after the dungeon quests, and the journey no longer sends you out of the dungeon for a hand-in that happens inside it.

### Added
- **Quest items on bosses:** a boss that drops an item a quest needs, an item that starts a quest, or that a quest wants killed gets a blue quest marker on its card and map pin, and the item gets the marker in the loot pane (with the quest's name). It disappears once you have done the quest, and it is not shown for quests of the other faction, class or race.

### Added
- **More quest data:** the Horde quests that open Krol'dok Stronghold (A Message in Blood to Clugfist's Decree), A Small Favor for the Alliance, the Alcaz Prison chains with their rewards, Thrall Needs to Know, the Paladin chain from Diplomatic Incident to A Moon-Kissed Blade (Horde Paladins, shown in the Deadmines and Shadowfang Keep, with what to do in each),, and positions for Gorn One Eye, Unele, Mithera, Zaruk, Einar, Jacques, Voidglare and the Rebel Camp quests.

### Fixed
- **Chains you joined later:** a quest in your log now counts as proof that the steps before it are done (for example Scarab Shells in the log makes Tran'rek count as done).

### Fixed
- **Quests for one race only:** a quest that only some races of your faction can take (for example Compendium of the Fallen in Scarlet Monastery, which an Undead cannot) is no longer listed for the others. `/dm questfilter` shows what is hidden in the dungeon you have open.

## [0.3.9] - 2026-11-24

### Changed
- **Syncing is one go instead of a few boards at a time:** between players on this version a sync now moves every board (up to 60 boards and 150 runs per request) instead of a handful per 15 minutes. Older versions keep working, at their old pace.

### Added
- **`/dm icons`:** a browser for the game's own icons (search by name, hover for the name, click to copy it).

### Fixed
- **Quests: the Journey tab's line and icons:** the line between steps is continuous with evenly spaced dots, and the List and Journey buttons have icons that follow the button colours.
- **Runs shared with you reach your guildmates:** a run can now be passed on any number of times (it was twice), so the highscores of people who only hear from you fill up. `/dm comms` also says why a request got nothing back.
- **Unreadable shared runs are said out loud:** when someone shares a run your addon cannot read because the route or dungeon data differs, you get one line in chat.

## [0.3.8] - 2026-11-24

### Changed
- **Runs recorded while private are shared when you switch sharing on:** the best of each board goes to your guild and friends (the rest when someone asks), so changing your mind does not lose the runs you already did.
- **Don't share now keeps only your own runs private:** you still pass on the runs other people shared with you to your guild and friends (never your own), so the best times reach everyone. Choosing "Don't share my own" is still a full opt-out of your own times. Until you answer the sharing question your own runs are private too, and the question comes back at every login until you choose.
- **Quests: journey view, now the first tab.** The Quests tab opens on a Journey (List is the button next to it) that lists the quests step by step (where to pick them up, the dungeon, where to hand them in) with a stepper down the left side. The current step is open.

### Fixed
- **Blue quest markers staying on an open map:** the markers of quests you track no longer disappear while the map is open (seen with OpenMap).
- **Warning before earlier private runs are shared:** switching sharing on shows how many runs become shareable, and you can keep them private.

## [0.3.7] - 2026-11-23

### Added
- **Quests for Blackmaw Hold and The Shaper's Terrace:** the Blackmaw Reclamation series (Master Feardred through Blackmaw Counter-Offensive), Blackmaw Magic, Get to the Roots of It and the other quests for Blackmaw Hold, with levels, rewards and who gives them, and the Alliance and Horde quests for The Shaper's Terrace.

### Fixed
- **Guild sync with an older addon:** when another player's highscore boards cannot be read because their addon (or yours) has different route data, the sync report now says so and asks you to update, instead of "nothing new". Routes can now be changed without wiping the highscores recorded on the old version.
- **The Platinum Discs (Uldaman)** now shows its whole chain: the second step is a quest you pick up inside the dungeon by touching the Discs of Norgannon, and the third step, the reward voucher to Bena Winterhoof in Thunder Bluff (Horde) or Dinita Stonemantle in Ironforge (Alliance), is listed.

## [0.3.6] - 2026-11-22

### Added
- **A minimap button for the journal.** Left click opens the dungeon journal, right click the options, and you can drag it around the minimap. New players get it with the welcome window, which has a box to switch it off. If you already had the addon it is off: switch it on under Esc > Options > AddOns > Dungeon Crawler Forever > Map and entrances.
- **New dungeon quests:** Destruction in Deadmines, the two Coldbringer's Eye quests (Razorfen Downs), Past Due (Scarlet Monastery), Word of the Woods, Rot and Regret and An'she's Radiance (Maraudon), Ever After and Fragment of the Firelands (Blackrock Depths), Blood and Thunder (Blackrock Spire) and Fallen in the Fen (Excavation Site: Wetlands). The Krol'dok Stronghold quests Break Their Chains, Carving a Path, It Is Time, Brother..., both Bring Me His Head and An Acquaintance in Southshore (The Drowned City) are listed too.

### Fixed
- **Bossman Toof (Krol'dok Stronghold) no longer shows as skipped.** The game never reports his bridge event, so the time window marked him "skipped" once Overlord Mugg was down, and the route on the map could point back at him. He now shows as "event" in the time window and counts as passed on the route. The run itself was always saved and counts him when it finishes.
- **Necklace Recovery in Uldaman** is a Horde quest and is no longer shown to the Alliance.
- **Required levels and classes:** The Dark Iron War (22), Knowledge in the Deeps (18), Find the Gems (37), Hot Fiery Death (55) and both Shadowshard Fragments (39) now show the level the game asks for. The Forging of Quel'Serrar chain (Dire Maul) is shown to Warriors and Paladins only.
- **Krol'dok Stronghold, Horde:** Bring Me His Head and It Is Time, Brother... are listed, and A Token of Vengeance, Tome of Twilight and Eye of Mugg now follow them in the right order.
- **The Drowned City:** An Acquaintance in Southshore is listed, and Take Two With Water and Magics of the Drowned City follow it (they followed Troll Witchery directly).
- **Quest chains:** the Blackrock Depths chain with Kharan Mighthammer now runs Kharan Mighthammer, Kharan's Tale, The Bearer of Bad News (it skipped Kharan's Tale). The Horde quests A Little Payback and Blood Red Bandanas (Alcaz Prison) and the Alliance quest A Bit of Wet Work now follow the last step of their pre-quest chain, not the first.

## [0.3.5] - 2026-11-21

### Fixed
- **Crafted leather helms are no longer listed as boss drops.** Razorfen Kraul, Blackfathom Deeps, the Stormwind Stockade and Scarlet Monastery showed Brawler's, Trapper's, Defender's, Wisdom's, Totemic and Stormrider's Leather Helm under almost every boss. Those are made by Leatherworkers; the patterns and plans (which do drop) stay.

## [0.3.4] - 2026-11-20

### Added
- **Copy / paste your runs.** The Highscore tab has a new **Copy / paste runs** button (also `/dm runs`). It shows your runs as text: copy it with Ctrl+C, paste it into the same window on your other computer and press Import. Your runs there count as yours, runs you already have are skipped, and it also works to hand runs to a friend. Nothing is sent anywhere by itself.

### Fixed
- **Runs in dungeons with renamed bosses were never recorded.** The game lists some bosses under another name than the one you see (in the Drowned City the third boss is called "Deathless Guardians" internally, but it is Deathless Marrow). The run timer counted that kill under the wrong name, so the route never finished and no highscore run was saved. This affected the Drowned City and every other dungeon with a renamed boss (Magmatus, the Baron, Arcanic Enigma, Izha'Rel and Tor'Rel, Overlord Mugg, War Handler Ashka, Zarla Ober). Runs there now finish and are saved.
- **Routes that waited for a boss the game never reports.** A few routes include a boss that has no fight of its own in the game's data (Ogom in Sunken Temple, Ruuzlu in Zul'Farrak, Gyth in Upper Blackrock Spire, Watchman Doomgrip in Blackrock Depths, Maraudos in Maraudon, Bossman Toof in Krol'dok). The timer waited for them forever and no run was saved. They no longer hold the run open: it finishes when the last boss the game reports falls, and they count as down at that moment.
- **Bosses that share a fight are counted with it.** Ogom (with Jammal'an), Ruuzlu (with Chief Ukorz), Gyth (with Rend) and Watchman Doomgrip (with the Vault) are marked down at the moment the fight they belong to ends, so the run records their real time and not just the finish.
- **You are told when a run is not saved.** If you leave a dungeon one or two bosses short of finishing the route, the chat now says which bosses were not seen. A boss the game reports under a name the addon does not know is mentioned once, so a missing run is noticed the same day.
- **A run is no longer lost to a name that did not match.** If you leave a dungeon one boss short of the route and exactly one boss was heard under a name the addon does not know, the run is saved anyway, marked "not ranked" with the reason (it is not shared and stays off the board). `/dm recover` tries the same on the dungeon visit still stored, so a run lost earlier can be rescued after an update.
- The kill message, the boss list and the map now use the boss's real name too (the same renamed bosses showed the game's internal name before).

### Changed
- **Runs are asked for more often.** While the game is open, the addon now asks your guild, online friends and your group for runs every 15 minutes, so a guildmate who logged in after you is no longer missed until your next login.

## [0.3.3] - 2026-11-19

### Added
- **New loot** from AtlasLoot: 3 new items in Razorfen Downs (Plaguemaw the Rotting, Glutton, Amnennar the Coldbringer) and 17 in Zul'Farrak (Hydromancer Velratha, Gahz'rilla, Theka the Martyr, Witch Doctor Zum'rah, Nekrum Gutchewer, Chief Ukorz Sandscalp, Sandarr Dunereaver, Zerillis).
- **The Shaper's Terrace** has a suggested route through its ten bosses, new boss positions, and the three crystal consoles that start Snowtalon, Cinder and Bolt are marked on the map. Highscore for it now follows this route, so earlier runs there are not compared with new ones.

### Changed
- **"Sync with guild" now tells you what came back.** Guildmates answer with quiet addon messages, so a working sync used to look like nothing happened. Under a minute after you press it, the chat says how many players with the addon answered and how many new runs arrived. If nobody answered it says so, and if the game refused the message it says that too.
- **King Op** (The Shaper's Terrace) is left out of the boss list until his place is found.

## [0.3.2] - 2026-11-18

### Changed
- **The journal and the dungeon maps no longer switch the world map to full size.** They open in the size your map already has, small or full. If you liked the old behaviour, it is now an option: Esc > Options > AddOns > Dungeon Crawler Forever > Map and entrances > "Open the journal and dungeon maps in the full-size map" (off by default).

## [0.3.1] - 2026-11-18

### Added
- **Routes for Blackrock Depths, Lower and Upper Blackrock Spire, Dire Maul and Stratholme**, so 25 dungeons now have a suggested route. Dire Maul has one route per wing, and Dire Maul North also has a short **Tribute** route (Cho'Rush and King Gordok). Stratholme has a **Living** and an **Undead** route.
- **Highscore:** these dungeons are now timed and ranked on their route, through its boss stops in route order, instead of on every regular boss. A run counts for every route whose bosses it has killed, so Stratholme has a Living side board, an Undead side board and a Full run board, and Dire Maul North has one for the main route and one for the Tribute run. Runs recorded before this update are not compared with new ones for these dungeons.
- **Optional bosses.** A boss you do not have to kill gets a green ring and an "(optional)" tag in the boss list, and does not count for the Highscore route. In Blackrock Depths these are Ribbly Screwspigot and Plugger Spazzring in the Grim Guzzler, Warder Stilgiss and Princess Moira Bronzebeard. Phalanx and Hurley Blackbreath, the two Grim Guzzler bosses you need, now say so.
- **Lower and Upper Blackrock Spire, and the three Dire Maul wings, are cards of their own in the journal**, with their own levels and boss counts. The search finds them by short names too: `lbrs`, `ubrs`, `dme`, `dmw`, `dmn`.
- **Naxxramas loot** (the classic loot lists; the raid is still marked "classic data").
- Trigger markers for Pyroguard Emberseer's doors and Immol'thar's pylons, and stair links in Blackrock Depths.
- `/dm route first` puts the route you are looking at first in the route list (your own routes only), so the dungeon opens on it.

### Changed
- You can now rename the **Main route** of a dungeon: it takes the name you type (the route that ships with the addon is not changed).
- **Postmaster Malown** in Stratholme is now marked as a summoned boss (purple ring), because it only appears once the postboxes are opened.
- Blackmaw Hold and The Shaper's Terrace open on a view of their own that shows the middle of the dungeon, not only the entrance.
- The route picker is the addon's own list now, so it can never open behind the route editor.

### Fixed
- Opening the route editor no longer gives a Lua error.
- The route list in the route editor was drawn behind the editor, so its text could not be read.
- Delete route / Reset to Default is available in the developer route editor too.
- One more item for the Relic Guardian in the Wetlands excavation, from the game update.

## [0.3.0] - 2026-11-17

### Added
- **Controller support.** The dungeon map and the journal now work with a gamepad, with the game's own controller UI turned on.
  - **Journal:** open it and the D-pad moves between the dungeon cards and the tabs straight away; A opens a card, B goes back.
  - **Dungeon map:** the left stick moves a crosshair over the map and the right stick zooms where the crosshair is. Push the crosshair into the edge of a zoomed map to scroll it. D-pad Left and Right switch between the map and the sidebar; in the sidebar, Up and Down choose, A selects (a boss, floor, loot item or quest) and X hides or shows the sidebar.
  - **Entrances:** on the world map, move the game's cursor onto a dungeon entrance and press A.
  - **A key guide** at the bottom shows what each button does right now, drawn with the same button icons as the game's own guides (Xbox or PlayStation, following your controller).
  - **Route button:** with a controller each press switches to the next route, as the game's menu cannot be used from the pad.
  - The map's own controls stay the game's: Back closes the map, and the D-pad Down / Up toggle between the small and full map.
- **Controller macros.** `/dm macros` creates three account macros, **DM Map**, **DM Journal** and **DM World Map**, that you can put on your controller layout (Game Menu > Macros, then the controller settings). They open the map cleanly, so the game does not block other controller actions afterwards. Use them instead of `/dm` or `/dm list` in your own macros: a typed command opens the map in a way that makes the game block some controller actions once the map closes, and `/dm macros` points out any of your macros that do this.
- **Controller buttons for our keys.** `/dm keys` and **Set key** accept a controller button as well as a key.
- **Several routes per dungeon.** When a dungeon has more than one route, a **Route** button on the map picks which one is drawn (the map switches by itself when you kill a boss that belongs to only one route), and **Full run** shows them all together. You can make your own routes, and rename or delete them. The route editor can be folded up to free the map and dragged by its title.
- **Routes for Scholomance and Stratholme**, so 23 dungeons now have a suggested route. Their Highscore runs are now timed and ranked on that route, through its boss stops in route order, where before they used every regular boss.
- **Blackmaw Hold has its seven bosses, stairs and floor links on the map.** It and The Shaper's Terrace now open on the game's own map tiles, zoomed in on the entrance.

### Fixed
- The game no longer says "action blocked" when you open the radial menu or chat, or close the map, after using the dungeon map or the journal, when you open them from the map or radial menu, a key, or the new macros (typing `/dm` still opens the map the old way, see above). The quest panel is also no longer touched while the map closes.
- A door or stair on a route no longer shows its link letter twice.
- Hearthsinger Forresten and Timmy the Cruel in Stratholme are now in the right place.
- Setting a key no longer removes your old key if the new one cannot be used.
- The welcome window closes with Esc or B without interfering with the game's own cancel button.

## [0.2.1] - 2026-11-16

### Changed
- **Runs swap between players more completely.** When you meet someone with the addon (your guild, friends or a new group), you each send a short summary of the boards you hold, and then only the runs the other side lacks are sent, best first. Before, only the top three runs per board were passed on. Players still on 0.2.0 keep working: they just don't take part in the summary swap.
- The same run is no longer stored twice if two players call its route by different names.

## [0.2.0] - 2026-11-16

### Added
- **Highscore.** Every dungeon run is now timed, from the first fight to the death of the last boss of the dungeon's route. The new **Highscore** tab ranks runs like a leaderboard: click a row to see who was in the group, the time at every boss, deaths and wipes. Your own best is always shown, with its true rank, even if you are outside the top ten. Pick the level bracket from the menu at the top of the tab.
- **Run summary.** When you set a personal best, a first time or a top three place, a window shows your time, your rank and the time at each boss against your previous best. Choose when it appears in the options.
- **Sharing.** Finished runs are shared automatically with your group, your guild and friends who have the addon, so the highscores fill up. Pick who gets them the first time, or any time with `/dm sharing`: everyone with the addon, guild and friends only, or don't share (your runs stay on your computer). Nothing is sent until you choose. A **Sync with guild** button on the Highscore tab fetches your guild's runs.
- **Boss levels** on the map pins, the boss list and the boss header.
- **Better time window.** It shows from the moment you come in, starts at the first fight, shows +/- against your best at each boss (green faster, red slower, yellow equal) and a pace line. One button hides the numbers for a relaxed run.
- **Tab icons** on Bosses, Quests and Highscore.

### Changed
- **Options are on pages:** map and entrances, dungeons and loot, runs and highscore.
- A run goes on until you stop it: leaving and coming back does not end it.

### Fixed
- Entering a dungeon while already in combat no longer starts the run clock.
- A second wing of a shared dungeon (Scarlet Monastery Graveyard, then Library) is recorded as its own run without pressing Reset.

## [0.1.25] - 2026-11-14

### Added
- **Loot for Blackmaw Hold and The Shaper's Terrace.** Seven bosses in Blackmaw Hold and ten of the Shaper's Terrace now show what they drop. Shadetooth and Relic Guardian in Excavation Site: Wetlands each have one more item.
- **A Pre-quests section in the Quests tab.** The quests you must finish before a dungeon's own quests now sit under their own "Pre-quests" heading, tagged Pre, and each one says which quest it is needed for. They no longer bury the quests you do in the dungeon, and quests that only come after a dungeon quest are not listed.
- **Move stop in the route editor.** Pick up a stop, click the dot it should follow, and put it down there, to reorder a route without starting over.

### Changed
- **The dungeon map works in combat.** You can open and close the map and the journal during a fight. The "Find this rare" button is gone for this: it is what stopped the map from opening or closing in combat. Rare bosses keep their silver ring.
- **The quest log steps aside on the small map.** Opening a dungeon on the small map closes the game's quest panel, which was squeezing the map, and opens it again when you leave. The full-size map is unchanged.
- **Bigger arrows for hiding and showing the sidebar.**
- **Re-recorded routes for City of Dalaran and Maraudon.** Fel Ancient in Dalaran and Tinkerer Gizlock in Maraudon no longer have two numbers each.

### Fixed
- **Clicking a boss in the route editor no longer adds it a second time.** A boss already on the route is selected instead, or joins the route if you cut it just before, which used to give one boss two numbers.

## [0.1.24] - 2026-11-13

### Added
- **New hand-drawn maps for The Drowned City, Krol'dok Stronghold and Alcaz Prison**, by Santiago Reyes (Atlas de Azeroth: Forever). They replace the maps made from the game's map tiles. The Drowned City has the island and the Underwater floor.
- **Alcaz Prison is mapped.** Both floors are there, the Main Unit and the Maximum Security Unit, with all five bosses numbered in the order of the run, a route, the stairs between the floors, and loot for four of the bosses. Its last boss is **Zarla Ober** (the game's own list calls her Blazeroar).
- **Nine more dungeon quests.** The Drowned City gets The Web of Magic, Findings for the Explorer's League, The Second Rebellion, Enemies in the Water and Ancient Gurubashi Idol. Krol'dok Stronghold gets the Horde Eye of Mugg. City of Dalaran gets Prison Break In and Dalaran Patrols. Excavation Site: Wetlands gets Seeking Caitlin, which now starts the Lost in the Thicket Things chain.

### Changed
- **The Drowned City and Krol'dok Stronghold are re-placed on the new maps.** Boss pins, routes, entrances, stairs and the two pearl markers all follow the new art.
- **More quest givers are on the map.** Quests that start in Rog'mar, the Krol'dok Stronghold outskirts, Orgrimmar and Arathi Highlands now show where to find the giver.

## [0.1.23] - 2026-11-11

### Added
- **Krol'dok Stronghold is filled in.** Every boss now shows what it drops, and the dungeon has a Trash entry with the drops of the regular mobs. Bossman Toof, who starts a boss event on the bridge, is listed and on the map and the route.
- **Quests for Krol'dok Stronghold.** All 18 quests are listed for both factions, including the Alliance starter quests in Farholde Keep (Saving Sunnyglade, Scraps of Knowledge, Curious Trinkets), the Horde chain that begins with Clugfist's Decree, and the key quests (Krol'dok Moulding and Key Ingredients).
- **The Shaper's Terrace has boss positions.** Titanosaur, Izha'Rel and Tor'Rel, Thunderhoof, Venomridge, Direhorn Matriarch, Snowtalon, Bolt, Vitrix and Nanaya are on the map, together with the entrance. The panels that start the Snowtalon and Vitrix fights are marked "Activate panel to start fight".

### Changed
- **Boss names match the game.** Shaper's Terrace boss 2 is Izha'Rel and Tor'Rel (it was listed as Ravasaur Hunters), and in Krol'dok Stronghold the bosses are War Handler Ashka and Overlord Mugg.

### Fixed
- **The Krol'dok Stronghold route now ends at Overlord Mugg.** It used to double back and finish with a second stop at him.

## [0.1.22] - 2026-11-10

### Added
- **Loot for The Drowned City.** Every boss now shows what it drops. Gill, a rare that patrols the centre of the dungeon, is listed too, with a silver outline.

## [0.1.21] - 2026-11-09

### Added
- **Quests for The Drowned City.** The dungeon now lists its quests, including the Horde chain (The Vile Reef, The Gurubashi Legends of Old, Locating the Lost City) and the Alliance chain (Bad Medicine, Kurzen's Mystery, Troll Witchery), with who gives them and where.
- **The doors in The Drowned City are linked.** Click a door on the map to jump to the floor it leads to, and Zul'Alai's pin is a little more accurate.
- **A route for Krol'dok Stronghold**, from the entrance through the dungeon, and all five bosses are now at their correct positions on the map.

## [0.1.20] - 2026-11-08

### Added
- **A journal for every dungeon and raid.** Every dungeon and raid is a card with its loading-screen picture and level range, sorted by level, with a Dungeons and a Raids tab. Type in the search box to find a dungeon by its name or by a boss: "VanCleef" shows the Deadmines. Click a card to open its map. New dungeons get a "New" tag for a few releases, and dungeons without boss positions yet are marked "Preview map".
- **The journal is one click away.** There is a **Journal** button at the right end of the world map's top bar, on every map. Inside a dungeon the top bar reads World > Eastern Kingdoms > Wetlands > Dungeon Journal > Excavation Site: Wetlands, and clicking "Dungeon Journal" takes you back to the same place in the list. You can also type `/dm list`, or use "Browse all dungeons and raids..." in the dungeon picker. The button can be turned off in the options.
- **Keys for the dungeon map and the journal.** Both are in Esc > Options > Keybindings under AddOns. The options also have a **Set key** button: press the key you want for the journal, and it is set without leaving the page (`/dm key` does the same). The Toggle dungeon map key was missing from the keybindings before and is there now.
- **A short welcome the first time.** One small window with the logo says how to open the maps and the journal, with buttons for "Open the journal" and "Set a key". Open it again from the options ("Show welcome") or with `/dm welcome`.
- **Share what you recorded.** The options have a new "Share my recordings" button (also `/dm report`). It shows a few short lines with the boss positions and portraits you recorded in game, already selected: press Ctrl+C and paste them into an issue on GitHub (the window has a button that copies the link), and they can be added to the maps for everyone.
- **The Drowned City is mapped.** All seven bosses are on the map, with the entrance, a route through the dungeon and the stairs between the two floors. The flooded part of the dungeon is its own floor, "Underwater", laid out from the game's map tiles: the long corridor, the rooms, the round chamber and the three-walkway hall. The two pearls that open the way to Deathless Marrow are marked ("Activate Pearl 1/2" and "2/2"), and the optional Primeval Elemental is on the Underwater floor.
- **A route for Excavation Site: Wetlands**, from the entrance through the dungeon, and a small correction to the Maraudon route near Tinkerer Gizlock.

### Changed
- **Maps made from the game's map tiles show whole.** The Drowned City, the other new dungeons and City of Dalaran now start with the whole map in view and can be zoomed out, instead of being cropped to fill the window.
- **The journal's search box has a magnifying glass** and a clear button, so it is easy to see.

### Fixed
- **New dungeons now work with OpenMap.** A dungeon that OpenMap has no icon for (such as the newest Forever dungeons) now gets an entrance icon from Dungeon Crawler on OpenMap's map, and clicking it opens the dungeon map. Icons that OpenMap makes from the game's own list are recognised by name too.
- **The quest log stays visible next to the dungeon map.** The dungeon map used to be drawn over the game's quest log whenever the log was open, for example on a full-screen map with OpenMap's quest log. It now stops at the log's edge, so you see both.

## [0.1.19] - 2026-11-07

### Added
- **Five new dungeons.** The Drowned City (35-40), Krol'dok Stronghold (40-45), Alcaz Prison (48-53), Blackmaw Hold (55-60, entrances in Azshara and Winterspring) and The Shaper's Terrace (58-60) are in the list, with their bosses, an entrance on the world map and a preview map made from the game's own map tiles. Boss positions, portraits and loot are not known yet: nobody has been there, and the loot lists are not out. They will follow as they are found.

## [0.1.18] - 2026-11-07

### Changed
- **The Quests list shows how far you are, like the game's quest log.** A quest you have not started has the "!" mark, a quest you are on has "...", a quest ready to hand in has "?", and a finished one has a check mark. Under a quest you are on you see what is left to do (for example "Tablet of Will: 1/2"); hover it, or open the wide view, for every objective.
- **The quest log key works in dungeons.** It opens the game's own quest log instead of the dungeon map. There is also an "All quests" button in the Quests list for the same thing; press the world map key to come back to the dungeon map.

## [0.1.17] - 2026-11-06

### Changed
- **Dungeon routes are shown by default.** The suggested route through the bosses is now on when you open a dungeon's map. Turn it off with Hide route in the map's bottom-left corner, and it stays off. You can also change it in the options under "Show the dungeon route by default".

## [0.1.16] - 2026-11-06

### Added
- **Track quests on the world map.** In a dungeon's Quests list, quests you don't have yet get a Track button ("Track all" for every one of them). Each tracked quest gets a blue quest marker on the world map where it starts. Click the marker for a map pin that shows the way, or right-click it to stop tracking. A marker goes away by itself once you pick up the quest.

## [0.1.15] - 2026-11-06

### Added
- **Share quests with your party.** In a group, quests from your quest log get a Share button in the dungeon's Quests list, and "Share all" offers every one of them at once.
- **Typical clear times.** Under each dungeon's level you now see how long a full clear usually takes, for example "Full clear: usually 35-55 min". Hover it for every kind of run: the quest run for your faction, and Stratholme's Living and Undead sides. The time also shows on dungeon entrances. For now these are estimates from each dungeon's size, monsters and bosses, for a group at the recommended level. Turn them off in the options under Timers.

### Changed
- **The split timer is now "Time in dungeon".** It counts from the moment you come in, so buffing, waiting for people and corpse runs are part of it: it shows how long you really spent there, with the time at each boss compared with your best visit. A /reload or a short trip outside (up to half an hour) keeps the clock going; the Reset button starts it again. The "start when I enter a dungeon" option and the Start button are gone, since it always starts at the door. Turn the window on with /dm timer (or /dm splits) or in the options.

## [0.1.14] - 2026-11-05

### Changed
- **Ready for the launch of World of Warcraft: Forever** (live build 1.60.1.70790).
- **Boss order follows the live game.** Shade of the Archmage (City of Dalaran) and Rath'mael (Ruins of Lordaeron) are now listed last, as in the game.
- **Boss abilities checked by hand.** Boss ability lists were checked against Wowhead and internal spell names are filtered out. Abilities are now listed in name order.
- **More loot in Blackrock Depths.** Hurley Blackbreath, Ribbly Screwspigot and Plugger Spazzring (the Grim Guzzler) now show their loot.

## [0.1.13] - 2026-10-28

### Changed
- **Updated for the latest Forever client** (build 1.60.1.70658).
- **Loot lists refreshed** for the dungeon bosses. The Stormwind Stockade now shows all its loot.

## [0.1.12] - 2026-10-20

### New
- **Works with OpenMap.** If you use the OpenMap addon, a click on one of its dungeon icons now opens the Dungeon Crawler dungeon map, with bosses, loot, quests and routes. Several dungeons at one icon, such as the Scarlet Monastery wings, show a small list to pick from. OpenMap's own buttons step aside while our map is open, and our map sits above its frames. You can turn this off in the options ("Open this addon's map from OpenMap's dungeon icons").
- **Level range under the entrance icons.** Each dungeon entrance on the zone maps shows its recommended levels, coloured for your level like quests: orange when you are in the range. Where several dungeons share an entrance, one combined range.
- **One icon per entrance.** Dungeons and wings that share a door (Scarlet Monastery, Dire Maul, Blackrock) are now one icon with a list, instead of a cluster of icons.
- **A new route editor bar.** Edit route now opens a toolbar over the map in the same style as the sidebar. It has tiles for Previous, Next, To the end, Cut here, Join here, Delete, Undo and Start over, plus Save route and Reset to Default. It also shows the stops of the route as numbered badges (click one to select it; hover for your best time), the split timer switches, and a close button in the corner.
- **Route buttons in the corner.** A red **Hide route** or **Show route** button sits above the red **Edit route** button, bottom left on the map.

### Improved
- The map covers Blizzard's quest panel when it is open, instead of showing the quest list next to ours.
- Tooltips on the route buttons open under the editor bar or beside the corner buttons, so they no longer cover the button.
- Gnomeregan: Grubbis has a second Forever item, the Skullduggery Belt, from the latest AtlasLoot.

### Fixed
- Boss pictures are no longer squeezed. The pictures that come from the Encounter Journal are twice as wide as high and were being pressed into a square; the middle of the picture is used now.

## [0.1.11] - 2026-10-15

### New
- **Sunken Temple route.** A built-in route through the whole temple, with its stops, stairs and triggers. Tick Show route to see it.
- **Cutting a route is much clearer.** The **Cut here** button is always in the bar while you draw (greyed until you select a dot), with a tooltip that walks you through it. After a cut the old part turns dark grey, a red ring marks the cut, and a new **Join here** button joins your new section to any point of the grey part, including stops and steps that the mouse cannot click.

### Improved
- Route stops now always sit on their boss's pin, so a route never drifts away from a boss whose position was refined. Removing a stairs or door marker also removes its route steps.
- Better positions for Hazzas, Morphaz, Jammal'an and Ogom in Sunken Temple.

### Fixed
- Rare bosses now get the silver ring in the boss list and the boss header, not only on the map pins.

## [0.1.10] - 2026-10-15

### New
- **Draw your own route.** Under the Show route box there is now an **Edit route** button. Click the map to add points, a boss to add a stop, and stairs or doors to add a step. Click a dot to select it and drag it to move it, or Ctrl-click a line to add a point on it. Cut the route at a point to draw a new section; the rest turns grey until you join it up again. **Undo** takes back the last thing you did, whatever it was. **Save route** keeps it, and **Reset to Default** brings back the built-in route.
- **Routes for more dungeons.** Built-in routes now cover Ragefire Chasm, Deadmines, Shadowfang Keep, Stockade, Wailing Caverns, Razorfen Kraul, Razorfen Downs, Blackfathom Deeps, Uldaman, Gnomeregan, all four Scarlet Monastery wings, Zul'Farrak, Maraudon, City of Dalaran and Ruins of Lordaeron. Routes stay hidden until you tick Show route.
- **Options at a glance.** The options page is split into sections (Map, World map entrances, Dungeons and raids, Bosses and loot, Routes, Timers), and there is an **Options** button with a gear at the top of the map's side panel.
- **Missing bosses and rares added:**
  - Scarlet Monastery: Azshir the Sleepless, Fallen Champion and Ironspine in the Graveyard, and Scarlet Commander Mograine with Whitemane in the Cathedral.
  - Zul'Farrak: Sandarr Dunereaver, Dustwraith, Zerillis and Ruuzlu.
  - Maraudon: Maraudos and Veng, two of the five Khans.
- **City of Dalaran:** Lyn the Ignored is marked as a summoned boss and names the item you need, the Tome of Dalaran. A marker shows where to talk to Grindle Firespark to free the Fel Ancient.

### Improved
- More boss positions and activation markers recorded, for example in Razorfen Downs and Zul'Farrak.
- The route colours are easier to tell apart: the purple leg is now darker.

### Fixed
- No more "blocked from an action" popup if the map redraws during combat while a rare is selected.
- Start over on a dungeon that only has the built-in route now gives you an empty route to draw.

## [0.1.9] - 2026-10-14

### New
- **The split timer can start by itself.** It now starts when you enter a dungeon, and there is a Start button on the timer window. If you prefer the old behaviour, turn off "Start the split timer when I enter a dungeon" in the options and it starts with the first fight.

### Fixed
- **"Blocked from an action only available to the Blizzard UI" popup when pressing Escape.** The addon no longer touches the game's own popup list, so Escape works normally again.
- **Lua error when opening the world map (M) a second time**, and a game crash when opening a dropdown on the map's top bar. The addon no longer hooks into the world map; it follows the map with its own light-weight watcher instead.
- **The dungeon map's top bar** now looks and behaves like the game's own: same spacing, colours and arrows. Clicking a place name leaves the dungeon and opens that map.

## [0.1.8] - 2026-10-14

### New
- **Boss kill times.** When a boss dies, the time of the fight is shown in chat together with your personal best for that boss. The best time is also shown in the boss header. You can turn the chat message off in the options.
- **Split timer (optional).** A run timer with a split at every boss, compared with your best run. Tick "Split timer" at the bottom left of the map to use it.
- **Dungeon routes.** Suggested routes through six dungeons, drawn on the map with a colour for each leg, numbered stops at the bosses, and steps at the stairs, doors and triggers you have to use. Skip a boss and the route notices when you kill a later one. Routes are hidden at first: tick "Show route" at the bottom left of the map, or turn on "Show the dungeon route by default" in the options.
- **New Wailing Caverns map** that matches the dungeon, replacing the game's map.
- **Missing bosses added:** the Deviate Faerie Dragon in Wailing Caverns and Bruegal Ironknuckle in The Stockade.

### Fixed
- Only Bruegal Ironknuckle is marked as a rare in The Stockade; the other bosses are no longer wrongly tagged.
- Lordaeron Captain in Ruins of Lordaeron is marked as a rare.
- The current leg of the route is always drawn on top of the others.

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
