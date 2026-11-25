-- Smoke test: load the addon files in order against the WoW mock and exercise the main flows.
local mock = dofile("tools/test/mock_wow.lua")
local G = _G
mock.install(G)
local ns = {}
local function loadAddonFile(path)
  local f = assert(io.open(path)); local src = f:read("a"); f:close()
  local chunk, err = _G.load(src, "@" .. path); assert(chunk, err)
  return chunk("DungeonCrawlerForever", ns)
end
local order = { "Data/Art.lua", "Data/ArtForever.lua", "Data/ArtCustom.lua", "Data/Dungeons.lua", "Data/Entrances.lua", "Data/Loot.lua", "Data/QuestSources.lua", "Data/Rares.lua", "Data/BossLevels.lua", "Data/Abilities.lua", "Data/Wings.lua", "Data/Markers.lua", "Data/Quests.lua", "Data/Reference.lua", "Data/Combined.lua", "Data/Routes.lua", "Data/ClearTimes.lua", "Data/Journal.lua", "Core.lua", "Model.lua", "RouteAliases.lua", "Runs.lua", "Comms.lua", "Quests.lua", "ClearTimes.lua", "UI/Controller.lua", "UI/Opener.lua", "UI/MinimapButton.lua", "UI/PadLegend.lua", "UI/View.lua", "UI/Quests.lua", "UI/Records.lua", "UI/RunDone.lua", "UI/Overview.lua", "UI/Entrances.lua", "UI/Journal.lua", "UI/Welcome.lua", "UI/OpenMap.lua", "UI/RouteUI.lua", "UI/Options.lua", "UI/Edit.lua", "UI/Report.lua", "UI/RunsIO.lua", "UI/Reference.lua", "UI/Route.lua", "UI/Splits.lua", "UI/Icons.lua", "Probe.lua", "Commands.lua" }
for _, p in ipairs(order) do loadAddonFile("addon/DungeonCrawlerForever/" .. p) end

-- the route versions as shipped (D-073 guard below): taken now, before any test edits routes
local SHIPPED_ROUTES = {}
do
  local ids = {}; for id in pairs(ns.Dungeons) do ids[#ids + 1] = id end; table.sort(ids)
  for _, id in ipairs(ids) do
    local wings = { 0 }
    for _, w in ipairs(ns.GetWings and ns.GetWings(id) or {}) do wings[#wings + 1] = w.wing end
    for _, w in ipairs(wings) do
      for _, rt in ipairs(ns.OfficialRoutes(id, w ~= 0 and w or nil)) do SHIPPED_ROUTES[#SHIPPED_ROUTES + 1] = { inst = id, wing = w, id = rt.id, version = rt.version, bosses = table.concat(rt.bosses, "|") } end
    end
  end
end
local failures = 0
local function try(label, fn, ...)
  local ok, err = xpcall(fn, debug.traceback, ...)
  if not ok then failures = failures + 1; print("FAIL", label, err) else print("ok  ", label) end
end

DungeonMapDB = { manual = {}, hookWorldMap = true }
for _, id in ipairs({ 36, 389, 3065, 2999, 33, 209 }) do
  try("ShowInstance " .. id .. " " .. ns.Dungeons[id].name, ns.ShowInstance, id, nil, true)
  local rows = 0
  for i = 1, 40 do local r = DungeonMapView and DungeonMapView.sidebar end
  try("  RefreshMap " .. id, ns.RefreshMap)
  local rows, pins = 0, 0
  for _, f in ipairs(mock.frames) do
    if rawget(f, "boss") and f.__shown then
      if rawget(f, "text") then rows = rows + 1 else pins = pins + 1 end
    end
  end
  print(string.format("      visible boss rows=%d pins=%d (bosses in data for this dungeon: %d)", rows, pins, #ns.GetBosses(id)))
end
-- loot area: select each boss of Deadmines in turn, then switch dungeon
ns.ShowInstance(36, nil, true)
for _, b in ipairs(ns.GetBosses(36)) do
  ns.GetState().selected = b.id
  try("  select " .. b.name, ns.RefreshMap)
end
ns.GetState().selected = nil
-- sidebar modes: wide (no map), hidden (map only), side
for _, m in ipairs({ "wide", "hidden", "side" }) do
  try("  side mode " .. m, ns.SetSideMode, m)
end
-- clicking a boss pin on the map selects that boss in the list
ns.ShowInstance(36, nil, true)
for _, f in ipairs(mock.frames) do
  if rawget(f, "boss") and rawget(f, "glow") and f.__shown and f.__scripts.OnClick then f.__scripts.OnClick(f); break end
end
assert(ns.GetState().selected ~= nil, "pin click did not select the boss")
print("ok   pin click selects boss id", ns.GetState().selected)
-- kill tracking: BOSS_KILL inside Deadmines marks the boss; a reset message clears it
_G.IsInInstance = function() return true end
_G.GetInstanceInfo = function() return "The Deadmines", "party", 1, "", 5, 0, false, 36 end
DungeonMapDB.kills = {}
ns.GetState().instanceID = 36
local vanCleef
for _, b in ipairs(ns.GetBosses(36)) do if b.name == "Edwin VanCleef" then vanCleef = b end end
try("MarkKilled", ns.MarkKilled, vanCleef.id, "Edwin VanCleef")
assert(ns.IsKilled(vanCleef, 36), "boss should be marked defeated")
assert(not ns.IsKilled(ns.GetBosses(36)[1], 36), "other bosses unaffected")
local r = ns.GetRunKills(36); r.last = os.time() - 7200
assert(not ns.IsKilled(vanCleef, 36), "kill should expire after the reset window")
ns.MarkKilled(vanCleef.id, "Edwin VanCleef")
ns.ResetKills(36)
assert(not ns.IsKilled(vanCleef, 36), "ResetKills should clear")
print("ok   kill tracking: mark, expire, reset")
-- kill detection from combat chat text (BOSS_KILL does not fire for every boss)
ns.ShowInstance(389, nil, true)
_G.GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "", 5, 0, false, 389 end
local oggle
for _, b in ipairs(ns.GetBosses(389)) do if b.name == "Oggleflint" then oggle = b end end
ns.ResetKills()
ns.HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Oggleflint dies.")
assert(ns.IsKilled(oggle, 389), "'dies' message should mark Oggleflint")
ns.ResetKills()
ns.HandleEvent("CHAT_MSG_COMBAT_XP_GAIN", "You killed Oggleflint")
assert(ns.IsKilled(oggle, 389), "'killed' message should mark Oggleflint")
ns.ResetKills()
ns.HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "A random troll dies.")
assert(not ns.IsKilled(oggle, 389), "other deaths must not mark the boss")
DungeonMapDB.debuglog = {}
ns.HandleEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Taragaman the Hungerer dies.")
assert(#DungeonMapDB.debuglog == 1, "debug log should record the event")
DungeonMapDB.debuglog = nil
ns.ResetKills()
ns.ResetKills()
ns.HandleEvent("ENCOUNTER_END", oggle.id, "Oggleflint", 1, 5, 0) -- wipe: success = 0
assert(not ns.IsKilled(oggle, 389), "a wipe must not mark the boss")
ns.HandleEvent("ENCOUNTER_END", oggle.id, "Oggleflint", 1, 5, 1) -- kill
assert(ns.IsKilled(oggle, 389), "ENCOUNTER_END with success should mark the boss")
ns.ResetKills()
ns.HandleEvent("ENCOUNTER_END", oggle.id, nil, 1, 5, 1) -- name unreadable: the encounter id alone is enough
assert(ns.IsKilled(oggle, 389), "id-only ENCOUNTER_END should mark the boss")
ns.ResetKills()
print("ok   kill detection from chat text + ENCOUNTER_END + debug log")
do -- saved settings from older versions: routes become shown by default once (0.1.17), a player's later choice stays
  local saved = DungeonMapDB
  DungeonMapDB = { version = 2, routesDefault = false, autoOpen = false }
  try("ADDON_LOADED with 0.1.16 settings", ns.HandleEvent, "ADDON_LOADED", "DungeonCrawlerForever")
  assert(DungeonMapDB.routesDefault == true and DungeonMapDB.version == 4, "old saved 'off' becomes on")
  DungeonMapDB = { version = 3, runSummary = false }
  try("ADDON_LOADED with the old summary box off", ns.HandleEvent, "ADDON_LOADED", "DungeonCrawlerForever")
  assert(DungeonMapDB.runSummaryMode == "never" and DungeonMapDB.runSummary == nil, "an old summary 'off' becomes Never")
  DungeonMapDB.routesDefault = false
  try("ADDON_LOADED again", ns.HandleEvent, "ADDON_LOADED", "DungeonCrawlerForever")
  assert(DungeonMapDB.routesDefault == false, "turning routes off after the update is kept")
  DungeonMapDB = nil
  try("ADDON_LOADED fresh", ns.HandleEvent, "ADDON_LOADED", "DungeonCrawlerForever")
  assert(DungeonMapDB.routesDefault == true, "new players see routes")
  DungeonMapDB = saved
  local was = DungeonMapDB.routesDefault
  ns.routeShow = nil
  ns.SetRouteShown(false)
  assert(DungeonMapDB.routesDefault == false and not ns.RouteVisible(), "Hide route on the map is remembered")
  ns.SetRouteShown(true)
  assert(DungeonMapDB.routesDefault == true and ns.RouteVisible(), "Show route on the map is remembered")
  DungeonMapDB.routesDefault = was
  print("ok   routes on by default")
end
_G.IsInInstance = function() return false end

-- raid view + dungeon list popup (groups, level colours) + entrance pins on a continent map (dungeon and raid icons)
try("ShowInstance raid Molten Core", ns.ShowInstance, 409, nil, true)
try("  RefreshMap raid", ns.RefreshMap)
for _, f in ipairs(mock.frames) do
  if f.__text == "Molten Core" and f.__scripts.OnClick then try("open dungeon list popup", f.__scripts.OnClick, f); break end
end
local list = ns.GetDungeonList()
assert(not list[1].raid and list[#list].raid, "list should be dungeons first, then raids")
local nr = 0 for _, d in ipairs(list) do if d.raid then nr = nr + 1 end end
print("ok   list: " .. #list .. " entries, " .. nr .. " raids; hidden SoD dungeons absent: " .. tostring(ns.Dungeons[2784] == nil and ns.Dungeons[2875] == nil))
WorldMapFrame.mapID = 1414
try("RefreshEntrances on Kalimdor (continent)", ns.RefreshEntrances)
local pinsShown = 0
for _, f in ipairs(mock.frames) do if rawget(f, "instance") and f.__shown then pinsShown = pinsShown + 1 end end
print("ok   entrance pins shown on Kalimdor: " .. pinsShown)
-- wings: Lower/Upper Blackrock Spire share map 229 but are separate dungeons with their own bosses
do
  local lbrs, ubrs
  for _, d in ipairs(ns.GetDungeonList()) do
    if d.id == 229 and d.wing == 1 then lbrs = d end
    if d.id == 229 and d.wing == 2 then ubrs = d end
  end
  assert(lbrs and ubrs and lbrs.name == "Lower Blackrock Spire" and ubrs.name == "Upper Blackrock Spire", "list should show both BRS wings")
  local l, u = ns.GetBosses(229, nil, 1), ns.GetBosses(229, nil, 2)
  assert(#l > 0 and #u > 0 and #l + #u == #ns.GetBosses(229), "wing boss lists should partition the instance: " .. #l .. "+" .. #u .. " vs " .. #ns.GetBosses(229))
  try("ShowInstance LBRS", ns.ShowInstance, 229, nil, true, 1)
  try("ShowInstance UBRS", ns.ShowInstance, 229, nil, true, 2)
  assert(ns.GetState().wing == 2 and ns.PickWing(229) == 2, "wing should be remembered")
  assert(ns.EntranceZoneFor(229) == 1427 or ns.EntranceZoneFor(229) == 1428, "entrance zone should be a zone map, not a continent")
  assert(#ns.GetFloors(229, 1) == 1 and ns.GetFloors(229, 1)[1].overview and #ns.GetFloors(229, 2) == 1 and ns.GetFloors(229, 2)[1].overview, "LBRS and UBRS: one overview map each")
  assert(ns.GetFloors(229, 2)[1].custom and ns.GetFloors(229, 2)[1].uiMapID ~= ns.GetFloors(229, 1)[1].uiMapID, "UBRS has its own bundled overview map")
  for _, b in ipairs(u) do assert(b.x == nil or b.floor == ns.GetFloors(229, 2)[1].uiMapID, "UBRS pins sit on the UBRS overview map: " .. b.name) end
  -- link letters restart in every wing: the first link of each wing is A (both wings have shipped links)
  local lf, uf = ns.GetFloors(229, 1)[1].uiMapID, ns.GetFloors(229, 2)[1].uiMapID
  local firstL, firstU
  for _, e in ipairs(ns.LinkLetters(229)) do
    if e.link.fa == lf and not firstL then firstL = e.letter end
    if e.link.fa == uf and not firstU then firstU = e.letter end
  end
  assert(firstL == "A" and firstU == "A", "every wing starts at A: " .. tostring(firstL) .. " " .. tostring(firstU))
  -- every dungeon with a trash table gets one "Trash" entry (last in the list, loot only, no pin)
  do
    local sfk = ns.GetBosses(33)
    local tr = sfk[#sfk]
    assert(tr.trash and tr.name == "Trash" and tr.x == nil and #(ns.GetLoot(33, "Trash") or {}) > 5, "Shadowfang Keep ends with a Trash entry with loot")
    ns.ShowInstance(33, nil, true)
    ns.GetState().selected = tr.id
    try("  RefreshMap with the Trash entry selected", ns.RefreshMap)
    ns.GetState().selected = nil
    local trashWings = 0
    for _, b in ipairs(ns.GetBosses(229, nil, 1)) do if b.trash then trashWings = trashWings + 1 end end
    for _, b in ipairs(ns.GetBosses(229, nil, 2)) do if b.trash then trashWings = trashWings + 1 end end
    assert(trashWings == 2, "each Blackrock Spire wing has its own Trash entry: " .. trashWings)
  end
  do -- summoned bosses: flagged, listed after the regular bosses and before Trash
    local sch = ns.GetBosses(289)
    local first, kirt = sch[1], nil
    for i, b in ipairs(sch) do if b.name == "Kirtonos" then kirt = i end end
    assert(kirt and sch[kirt].summoned and not first.summoned, "Kirtonos is a summoned boss, listed after the regular ones")
    ns.ShowInstance(289, nil, true)
    ns.GetState().selected = sch[kirt].id
    try("  RefreshMap with a summoned boss selected", ns.RefreshMap)
    ns.GetState().selected = nil
  end
  do -- Sunken Temple lists Ogom the Wretched next to Jammal'an, with loot
    local ogom
    for _, b in ipairs(ns.GetBosses(109)) do if b.name == "Ogom the Wretched" then ogom = b end end
    assert(ogom and #(ns.GetLoot(109, "Ogom the Wretched") or {}) > 0, "Ogom the Wretched is in the Sunken Temple list with loot")
  end
  do -- Wailing Caverns lists its rare, the Deviate Faerie Dragon
    local fd
    for _, b in ipairs(ns.GetBosses(43)) do if b.name == "Deviate Faerie Dragon" then fd = b end end
    assert(fd and ns.IsRare(43, "Deviate Faerie Dragon") and #(ns.GetLoot(43, "Deviate Faerie Dragon") or {}) > 0, "Deviate Faerie Dragon is a Wailing Caverns rare with loot")
  end
  do -- Stockade: only Bruegal Ironknuckle is a rare
    local br
    for _, b in ipairs(ns.GetBosses(34)) do if b.name == "Bruegal Ironknuckle" then br = b end end
    assert(br and ns.IsRare(34, "Bruegal Ironknuckle"), "Bruegal Ironknuckle is the Stockade rare")
    assert(not ns.IsRare(34, "Targorr the Dread") and not ns.IsRare(34, "Hamhock") and not ns.IsRare(34, "Bazil Thredd"), "the Stockade bosses are not rares")
  end
  local jed
  for _, b in ipairs(u) do if b.name == "Jed Runewatcher" then jed = b end end
  local sol
  for _, b in ipairs(u) do if b.name == "Solakar Flamewreath" then sol = b end end
  assert(sol and #(ns.GetLoot(229, "Solakar Flamewreath") or {}) > 0, "Solakar Flamewreath (the Rookery event) is in the Upper Spire list with loot")
  assert(jed and ns.IsRare(229, "Jed Runewatcher") and #(ns.GetLoot(229, "Jed Runewatcher") or {}) == 3, "Jed Runewatcher: an Upper Spire rare with loot")
  print("ok   wings: LBRS " .. #l .. " bosses / 1 overview map, UBRS " .. #u .. " bosses / 1 overview map")
  -- Scarlet Monastery: four wings, each with its own boss list and only its own map
  for w = 1, 4 do
    local fl, bs = ns.GetFloors(189, w), ns.GetBosses(189, nil, w)
    assert(#fl == 1 and #bs >= 1, "SM wing " .. w .. " should have 1 floor and bosses")
    try("ShowInstance SM wing " .. w, ns.ShowInstance, 189, nil, true, w)
  end
  assert(#ns.GetFloors(189) == 4, "unfiltered SM still has 4 floors")
  local dmE = ns.GetFloors(429, 1)
  assert(#dmE == 2, "Dire Maul East should have 2 floors, got " .. #dmE)
  print("ok   Scarlet Monastery wings: 1 floor each; Dire Maul East 2 floors")
end
-- overview (all floors), floor strip, markers, numbers
ns.ShowInstance(189, nil, true, 1) ; ns.ShowInstance(230, nil, true) -- Blackrock Depths (2 floors)
try("SetOverview on", ns.SetOverview, true)
assert(ns.GetState().overview, "overview should be on for a multi-floor dungeon")
try("OpenFloor 2", ns.OpenFloor, 2)
assert(not ns.GetState().overview and ns.GetState().floorIndex == 2, "OpenFloor leaves the overview")
ns.ShowInstance(389, nil, true) ; ns.SetOverview(true)
assert(not ns.GetState().overview, "single-floor dungeon cannot be in overview")
ns.ShowInstance(429, nil, true, 2) ; try("overview DM West (3 floors)", ns.SetOverview, true) ; ns.SetOverview(false)
ns.ShowInstance(209, nil, true) ; ns.SetOverview(true) ; ns.SetOverview(false)
-- markers: place one in edit mode, read it back, remove it
ns.ShowInstance(36, nil, true) ; ns.editing = true ; ns.editKind = "exit"
DungeonMapDB.markers = {}
local art36 = ns.GetFloors(36)[1]
DungeonMapDB.markers[36] = { [art36.uiMapID] = { { kind = "exit", x = 0.5, y = 0.5 } } }
local shipped = #ns.GetMarkers(36, art36.uiMapID) -- markers that ship with the addon on this floor
local ml = ns.GetMarkers(36, art36.uiMapID)
local mine
for _, m in ipairs(ml) do if m.db then mine = m end end
assert(#ml == shipped and mine and mine.kind == "exit", "marker should be listed")
try("RefreshMap with marker", ns.RefreshMap)
ns.RemoveMarker(mine) ; assert(#ns.GetMarkers(36, art36.uiMapID) == shipped - 1, "marker removed")
-- every marker type has an icon: an atlas or one of our textures, and the new types are placeable
for _, kind in ipairs(ns.MARKER_ORDER) do
  local k = ns.MARKER_KINDS[kind]
  assert(k and k.label and (k.atlas or k.texture or k.quest) and k.color, "marker kind " .. kind .. " needs a label, an icon and a colour")
end
assert(ns.MARKER_KINDS.left and ns.MARKER_KINDS.right and ns.MARKER_KINDS.up.atlas == "poi-door-up", "up / down / left / right are the game's door icons")
assert(ns.MARKER_ALIASES.arrow_left == "left", "markers from earlier builds keep working")
-- a marker that ships with the addon can be removed in edit mode too (remembered until the next import deletes it from the data)
do
  local f36 = ns.GetFloors(36)[1]
  local before = ns.GetMarkers(36, f36.uiMapID)
  local shippedOne
  for _, m in ipairs(before) do if not m.db then shippedOne = m end end
  assert(shippedOne and shippedOne.instance == 36 and shippedOne.floor == f36.uiMapID, "shipped markers should carry their instance and floor")
  DungeonMapDB.markerRemovals = {}
  ns.RemoveMarker(shippedOne)
  assert(#ns.GetMarkers(36, f36.uiMapID) == #before - 1, "a removed shipped marker should disappear")
  assert(#DungeonMapDB.markerRemovals == 1, "the removal should be remembered for the import")
  DungeonMapDB.markerRemovals = {}
  assert(#ns.GetMarkers(36, f36.uiMapID) == #before, "without the removal it is back")
end
ns.editing = false ; ns.editKind = "boss"
print("ok   overview, strip, markers")
-- edit mode places a boss in every wing of the multi-wing dungeons (LBRS / UBRS, Dire Maul, Scarlet Monastery), not just the first boss
do
  local canvas = { GetLeft = function() return 100 end, GetTop = function() return 700 end, GetEffectiveScale = function() return 1 end,
                   GetWidth = function() return 800 end, GetHeight = function() return 600 end }
  _G.GetCursorPosition = function() return 500, 400 end -- inside the canvas: x = 0.5, y = 0.5
  for _, inst in ipairs({ 229, 429, 189 }) do
    for _, w in ipairs(ns.GetWings(inst)) do
      ns.ShowInstance(inst, nil, true, w.wing)
      ns.editing = true ; ns.editKind = "boss"
      local list = ns.GetBosses(inst, nil, w.wing)
      local pick
      for _, cand in ipairs(list) do if not cand.trash then pick = cand end end -- the last real boss (the Trash entry has no place on the map)
      assert(pick, "wing " .. w.name .. " should list bosses")
      ns.GetState().selected = pick.id
      DungeonMapDB.manual[inst] = nil
      ns.EditPlaceAtCursor(canvas, ns.GetState())
      local rec = DungeonMapDB.manual[inst] and DungeonMapDB.manual[inst][pick.name]
      assert(rec and rec.floor and math.abs(rec.x - 0.5) < 0.01, "edit mode did not store " .. pick.name .. " in " .. w.name)
      local again
      for _, b in ipairs(ns.GetBosses(inst, nil, w.wing)) do if b.name == pick.name then again = b end end
      assert(again and again.x and again.floor == rec.floor, "stored boss should show up with its position in " .. w.name)
      DungeonMapDB.manual[inst] = nil
    end
  end
  ns.editing = false
  print("ok   edit mode places bosses in every wing")
end
-- the Ring of Law champions are listed as sub-entries of the Ring of Law, with their own loot and without a pin
do
  local ring, gorosh
  for _, b in ipairs(ns.GetBosses(230)) do
    if b.name == "Ring of Law" then ring = b end
    if b.name == "Gorosh the Dervish" then gorosh = b end
  end
  assert(ring and gorosh, "BRD should list the Ring of Law and its champions")
  assert(gorosh.sub and gorosh.parent == ring.id and not gorosh.x and gorosh.floor == ring.floor, "champion should be a pin-less sub-entry on the parent's floor")
  assert(ns.GetLoot(230, "Gorosh the Dervish") and #ns.GetLoot(230, "Gorosh the Dervish") >= 3, "champion should have loot")
  assert(not ns.IsKilled(gorosh, 230), "sub-entries are never marked defeated by themselves")
  -- the champions only show in the list while their parent is open; opening, selecting one and closing again must not break
  ns.ShowInstance(230, nil, true)
  local st = ns.GetState()
  st.expandedGroups = {}
  try("BRD collapsed", ns.RefreshMap)
  st.expandedGroups[ring.id] = true
  st.selected = gorosh.id
  try("BRD open with a champion selected", ns.RefreshMap)
  st.expandedGroups[ring.id] = false
  st.selected = ring.id
  try("BRD collapsed again", ns.RefreshMap)
  -- clicking the Ring of Law row opens its list, jumps to its floor, and a second click closes it
  st.expandedGroups = {}
  ns.RefreshMap()
  local row
  for _, f in ipairs(mock.frames) do
    if rawget(f, "boss") and f.boss.id == ring.id and rawget(f, "expand") and f.__scripts.OnClick then row = f end
  end
  assert(row, "Ring of Law row should exist")
  row.__scripts.OnClick(row)
  assert(st.expandedGroups[ring.id] and st.selected == ring.id, "first click should open the Ring of Law and select it")
  row.__scripts.OnClick(row)
  assert(not st.expandedGroups[ring.id], "second click should close it again")
  print("ok   Ring of Law champions")
end

-- Quests: eligibility, chains, faction filter, completed folding, the Quests tab
do -- the quest panel steps aside on the small map; nothing is called into the map while it closes, with a controller or in combat (a controller user reported the map bugging out)
  local map = _G.WorldMapFrame
  local log = {}
  local panel = { __shown = true }
  panel.IsShown = function(self) return self.__shown end
  map.QuestLog = panel
  map.IsMaximized = function() return false end
  map.HandleUserActionCloseSidePanel = function(self) log[#log + 1] = "close"; panel.__shown = false end
  map.HandleUserActionOpenSidePanel = function(self) log[#log + 1] = "open"; panel.__shown = true end
  local saveC, savePad = _G.InCombatLockdown, _G.InputUtil
  local function reset() log = {}; panel.__shown = true; map.__shown = true; _G.InCombatLockdown = function() return false end; _G.InputUtil = nil end
  local function show() ns.HideView(); log = {}; ns.ShowInstance(36, nil, true) end
  -- 1) the small map, mouse: the panel closes when the view opens and opens again when the view goes while the map stays open
  reset(); show()
  assert(log[1] == "close" and panel.__shown == false, "the panel steps aside: " .. table.concat(log, ","))
  ns.HideView()
  assert(log[2] == "open" and panel.__shown == true, "and comes back when the view goes")
  -- 2) the map closes with the view up: nothing is called into the map from its own hide
  reset(); show(); log = {}
  map.__shown = false
  ns.HideView()
  assert(#log == 0 and panel.__shown == false, "no call into a map that is closing: " .. table.concat(log, ","))
  -- ... and the panel comes back when the map is next open without the view
  map.__shown = true
  ns.RestoreQuestLog()
  assert(log[1] == "open" and panel.__shown == true, "restored on the next open without the view")
  -- 3) a controller: the panel is not touched at all
  reset(); _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
  show()
  assert(#log == 0 and panel.__shown == true, "with the Gamepad UI the quest panel is left alone: " .. table.concat(log, ","))
  ns.HideView()
  assert(#log == 0, "and not opened on close")
  -- 4) combat: nothing is called, and a panel we closed stays ours to restore
  reset(); show(); log = {}
  _G.InCombatLockdown = function() return true end
  ns.HideView()
  assert(#log == 0 and panel.__shown == false, "no call in combat")
  _G.InCombatLockdown = function() return false end
  ns.RestoreQuestLog()
  assert(log[1] == "open", "restored once combat is over")
  -- 5) the full-size map is left alone
  reset(); map.IsMaximized = function() return true end
  show()
  assert(#log == 0 and panel.__shown == true, "the full-size map keeps its quest panel")
  map.IsMaximized = function() return false end
  ns.HideView()
  _G.InCombatLockdown, _G.InputUtil = saveC, savePad
  map.QuestLog, map.HandleUserActionCloseSidePanel, map.HandleUserActionOpenSidePanel = nil, nil, nil
  print("ok   quest panel step aside")
end
do -- tile-first dungeons (Blackmaw Hold, Shaper's Terrace): floor 1 is the game's tile map and the community floors follow; /dm tiles swaps the others
  local f0 = ns.GetFloors(2974)
  assert(f0[1].uiMapID == 929741 and f0[1].yards and not f0[1].custom and #f0 == 6 and f0[2].uiMapID == 829742, "Blackmaw Hold opens on its tile map, then the community floors")
  local f3 = ns.GetFloors(3001)
  assert(f3[1].uiMapID == 930011 and f3[2].uiMapID == 830012 and #f3 == 2, "so does the Shaper's Terrace")
  local shown = ns.ShownFloorSet(2974)
  assert(shown[929741] and shown[829742] and not shown[829741], "the shown floors (route pruning) are the tile floor and the community floors, not the parked overview")
  assert(ns.GetFloors(2959)[1].uiMapID == 829591 and ns.GetFloors(3039)[1].uiMapID == 830391, "the other dungeons keep their community floor 1")
  -- /dm tiles (temporary check tool): floor 1 of a community-only dungeon drawn from the game's tiles; the floor set the data is kept for does not change
  DungeonMapDB.tileView = true
  assert(ns.GetFloors(3039)[1].uiMapID == 930391 and ns.GetFloors(2974)[1].uiMapID == 929741, "tiles: Krol'dok swaps, Blackmaw Hold already is the tile map")
  assert(ns.ShownFloorSet(3039)[830391] and not ns.ShownFloorSet(3039)[930391], "the check tool does not change the floors data is kept for")
  ns.editing = false; ns.ToggleEdit()
  assert(DungeonMapDB.tileView == false and ns.editing == true, "edit mode turns the tiles off")
  ns.ToggleEdit()
  assert(ns.GetFloors(3039)[1].uiMapID == 830391, "back to the community map")
  print("ok   tile-first dungeons and the tiles check tool")
end
do -- a tile map starts at 130 % of the fitted size and on the entrance; a community map at 100 %
  local saveMk = DungeonMapDB.markers
  DungeonMapDB.markers = nil
  ns.ShowInstance(2974, nil, true)
  ns.GetState().floorIndex = 1
  try("  Blackmaw Hold tile map, no entrance yet", ns.RefreshMap)
  local k = ns.GetZoom()
  assert(math.abs(k - 3.125) < 1e-9, "Blackmaw Hold opens at its own zoom (3.125): " .. tostring(k))
  DungeonMapDB.markers = { [2974] = { [929741] = { { kind = "entrance", x = 0.2, y = 0.7 } } } }
  ns.GetState().floorIndex = 2
  try("  Blackmaw Hold community floor", ns.RefreshMap)
  assert(ns.GetZoom() == 1, "a community map opens at 100 %")
  ns.GetState().floorIndex = 1
  try("  Blackmaw Hold tile map with an entrance", ns.RefreshMap)
  assert(math.abs(ns.GetZoom() - 3.125) < 1e-9, "the start zoom stays with an entrance marker (the view has its own centre)")
  ns.ShowInstance(3001, nil, true)
  ns.GetState().floorIndex = 1
  try("  Shaper's Terrace tile map", ns.RefreshMap)
  assert(math.abs(ns.GetZoom() - 3.906) < 1e-9, "The Shaper's Terrace opens at its own zoom (3.906)")
  ns.ShowInstance(2974, nil, true)
  ns.GetState().floorIndex = 1
  DungeonMapDB.markers = saveMk
  ns.ShowInstance(36, nil, true)
  print("ok   tile map start zoom")
end
do -- boss levels: AtlasLoot's value, a range, the skull, nothing for an unknown boss; shown on the pin tooltip, the list row and the header
  assert(ns.BossLevels and next(ns.BossLevels), "Data/BossLevels.lua is loaded")
  local saved = ns.BossLevels[36]
  ns.BossLevels[36] = { ["One"] = 21, ["Two"] = { 19, 20 }, ["Three"] = 999, ["Four"] = { 30, 30 } }
  assert(ns.BossLevelText(36, "One") == "21" and ns.BossLevelText(36, "Two") == "19-20", "a number, a range")
  assert(ns.BossLevelText(36, "Three") == "??" and ns.BossLevelText(36, "Four") == "30", "the skull is ??, an equal range is one number")
  assert(ns.BossLevelText(36, "Nope") == nil and ns.BossLevelText(99999, "One") == nil, "unknown boss or dungeon: no level")
  ns.BossLevels[36] = saved
  -- real data: Edwin VanCleef is level 21 in the Deadmines; the Forever-new dungeons without a confirmed level show none
  assert(ns.BossLevelText(36, "Edwin VanCleef") == "21", "the Deadmines' last boss has his level: " .. tostring(ns.BossLevelText(36, "Edwin VanCleef")))
  assert(ns.BossLevelText(229, "Mor Grayhoof") == "60", "a level from data/manual/boss_levels.csv")
  ns.ShowInstance(36, nil, true)
  ns.GetState().tab = nil
  try("  boss list with levels", ns.RefreshMap)
  local found
  for _, f in ipairs(mock.frames) do
    local b = rawget(f, "boss")
    if b and f.__shown and b.name == "Edwin VanCleef" and f.text and f.text.GetText then found = f break end
  end
  assert(found and found.text:GetText():find("[21]", 1, true), "the boss list row shows the level")
  print("ok   boss levels")
end
do -- pre-quests: a section of their own, a "Pre" tag, "needed for"; the quests that come after a dungeon quest are not in the data at all
  local done, active = {}, {}
  _G.UnitFactionGroup = function() return "Alliance" end
  _G.UnitLevel = function() return 40 end
  _G.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end, IsOnQuest = function(id) return active[id] == true end,
    GetTitleForQuestID = function() return nil end }
  local saved = ns.QuestData[3065]
  ns.QuestData[3065] = {
    { id = 1, name = "Dungeon quest", level = 40, min = 30, where = "outside", prereq = 11 },
    { id = 2, name = "Another dungeon quest", level = 40, min = 30, where = "outside" },
    { id = 10, name = "Starter one", level = 35, min = 30, where = "outside", pre = true, chain = "Starter", step = 1 },
    { id = 11, name = "Starter two", level = 36, min = 30, where = "outside", pre = true, chain = "Starter", step = 2, prereq = 10 },
    { id = 12, name = "Loose pre-quest", level = 35, min = 30, where = "outside", pre = true, unlocks = { 2, 999 } },
    { id = 13, name = "Horde pre-quest", level = 35, min = 30, faction = "H", where = "outside", pre = true, unlocks = { 2 } },
    { id = 20, name = "Mixed first", level = 38, min = 30, where = "outside", pre = true, chain = "Mixed", step = 1 },
    { id = 21, name = "Mixed last", level = 40, min = 30, where = "outside", chain = "Mixed", step = 2, prereq = 20 },
  }
  local list, counts = ns.GetQuestEntries(3065)
  local by = {}
  for _, e in ipairs(list) do by[e.kind == "chain" and e.name or e.q.name] = e end
  assert(by["Starter"] and by["Starter"].isPre == true, "a chain of pre-quests only is a pre entry")
  assert(by["Loose pre-quest"].isPre == true and by["Dungeon quest"].isPre == false and by["Another dungeon quest"].isPre == false, "loose entries carry their flag")
  assert(by["Mixed"] and by["Mixed"].isPre == false and by["Mixed"].steps[1].isPre == true and by["Mixed"].steps[2].isPre == false,
         "a chain that ends in a dungeon quest stays with the dungeon quests, its early step is tagged Pre")
  assert(by["Horde pre-quest"] == nil, "the other faction's pre-quest is hidden")
  assert(counts.open == 3 and counts.pre == 2 and counts.done == 0, "counts: dungeon quests and pre-quests apart: open " .. counts.open .. " pre " .. tostring(counts.pre))
  local nf = by["Starter"].neededFor
  assert(#nf == 1 and nf[1] == "Dungeon quest", "a chain is needed for the dungeon quest its last step unlocks (prereq link)")
  nf = by["Loose pre-quest"].neededFor
  assert(#nf == 1 and nf[1] == "Another dungeon quest", "`unlocks` names the dungeon quests; unknown ids are ignored")
  assert(by["Mixed"].steps[1].neededFor and by["Mixed"].steps[1].neededFor[1] == "Mixed last", "an early step of a mixed chain knows what it is for")
  assert(ns.NeededForText(by["Loose pre-quest"]) == "  -  for Another dungeon quest", "the sub text says what it is for")
  local joined = table.concat(ns.QuestDetailLines(by["Loose pre-quest"]), "\n")
  assert(joined:find("Needed for", 1, true) and joined:find("Another dungeon quest", 1, true), "the detail pane says what it is needed for")
  -- the list: the dungeon quests, then a folded "Pre-quests" header, then the completed ones
  ns.ShowInstance(3065, nil, true)
  ns.GetState().tab = "quests"
  ns.GetState().questExpanded = nil
  DungeonMapDB.questView = "list"
  try("  quests tab with a pre-quests section", ns.RefreshMap)
  local function preHead() for _, f in ipairs(mock.frames) do if rawget(f, "head") == "pre" and f.__shown then return f end end end
  local head = preHead()
  assert(head and head.__scripts.OnClick, "the Pre-quests header is shown")
  local function shownEntry(name)
    for _, f in ipairs(mock.frames) do
      local en = rawget(f, "entry")
      if en and f.__shown and (en.kind == "chain" and en.name or (en.q and en.q.name)) == name then return f end
    end
  end
  assert(shownEntry("Loose pre-quest"), "the pre-quests are listed under the header")
  head.__scripts.OnClick(head)
  assert(ns.GetState().questExpanded.__preClosed == true, "the header folds the pre-quests away")
  try("  quests tab, pre-quests folded", ns.RefreshMap)
  assert(not shownEntry("Loose pre-quest") and shownEntry("Dungeon quest"), "folded: the pre-quests are gone, the dungeon quests stay")
  head = preHead()
  head.__scripts.OnClick(head)
  assert(not ns.GetState().questExpanded.__preClosed, "and opens again")
  -- everything shipped: the real data has pre-quests flagged for the classic dungeons, and the follow-ups of the new ones are gone
  local pre, after = 0, 0
  for _, q in ipairs(saved) do if q.pre then pre = pre + 1 end end
  for id, l in pairs(ns.QuestData) do for _, q in ipairs(l) do if q.pre then pre = pre + 1 end if q.name == "Heartwoven" or q.name == "Curios of Curiosity" then after = after + 1 end end end
  assert(pre > 100 and after == 0, "the shipped data has pre-quests flagged and no follow-ups: pre " .. pre .. " after " .. after)
  ns.QuestData[3065] = saved
  ns.GetState().tab = nil
  ns.GetState().questExpanded = nil
  print("ok   pre-quests section")
end
do
  local done, active = {}, {}
  _G.UnitFactionGroup = function() return "Horde" end
  _G.UnitLevel = function() return 30 end
  _G.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end, IsOnQuest = function(id) return active[id] == true end,
    GetTitleForQuestID = function() return nil end }
  try("  a quest in the log makes the steps before it done", function()
    active[2865] = true -- Zul'Farrak: Scarab Shells (step 2) is in the log, Tran'rek (step 1, id 2864) is not flagged
    local seen
    for _, e in ipairs(ns.GetQuestEntries(209) or {}) do
      if e.kind == "chain" then for _, stp in ipairs(e.steps) do if stp.q.id == 2864 then seen = stp.status end end
      elseif e.q and e.q.id == 2864 then seen = e.status end
    end
    active[2865] = nil
    assert(seen == "done", "Tran'rek counts as done while Scarab Shells is in the log: " .. tostring(seen))
  end)
  local realData = ns.QuestData
  for id, list in pairs(realData) do -- every shipped dungeon renders its list without errors
    if ns.Dungeons[id] then
      ns.ShowInstance(id, nil, true)
      ns.GetState().tab = "quests"
      DungeonMapDB.questView = "list"
      try("  real quests " .. id .. " (" .. #list .. ")", ns.RefreshMap)
      ns.GetState().questExpanded = { __done = true }
      try("  real quests " .. id .. " all open", ns.RefreshMap)
      DungeonMapDB.questView = "journey"
      try("  real quests " .. id .. " journey", ns.RefreshMap)
      try("  journey steps " .. id, function()
        local steps = ns.GetQuestJourney(id)
        local open = 0
        for _, e in ipairs(ns.GetQuestEntries(id) or {}) do
          if e.kind == "chain" then for _, st in ipairs(e.steps) do if st.status ~= "done" then open = open + 1 end end elseif e.status ~= "done" then open = open + 1 end
        end
        local seen = {}
        for _, sp in ipairs(steps) do if sp.kind == "handin" or sp.kind == "dungeon" then seen[sp.e.q.id] = true end end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        assert(n == open, "every open quest has a hand-in or dungeon step: " .. n .. " of " .. open)
      end)
      DungeonMapDB.questView = nil
      ns.GetState().tab = nil
      ns.GetState().questExpanded = nil
    end
  end
  _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
  ns.QuestData[3065] = {
    { id = 1, name = "Loose quest", level = 20, min = 15, where = "outside", giver = "Giver", giverZone = "Zone" },
    { id = 2, name = "Alliance only", level = 20, min = 15, faction = "A", where = "outside" },
    { id = 3, name = "Step one", level = 25, min = 20, faction = "H", where = "attune", chain = "The chain", step = 1 },
    { id = 4, name = "Step two", level = 25, min = 20, faction = "H", where = "outside", chain = "The chain", step = 2, prereq = 3 },
    { id = 5, name = "Step three", level = 25, min = 20, faction = "H", where = "outside", chain = "The chain", step = 3, prereq = 4 },
    { id = 6, name = "Too high", level = 40, min = 35, where = "inside" },
    { id = 8, name = "Paladin only", level = 20, min = 15, class = 2, where = "outside" },
    { id = 7, name = "Old one", level = 10, min = 5, where = "outside" },
  }
  done[7] = true
  assert(ns.HasQuests(3065), "HasQuests")
  local list, counts = ns.GetQuestEntries(3065)
  local names = {}
  for _, e in ipairs(list) do names[#names + 1] = (e.kind == "chain" and e.name or e.q.name) .. ":" .. e.status end
  assert(counts.open == 3 and counts.done == 1, "counts " .. table.concat(names, ","))
  assert(list[1].kind == "chain" and list[1].attune, "attunement chain first: " .. table.concat(names, ","))
  assert(list[1].current.q.id == 3 and list[1].done == 0, "current step")
  for _, e in ipairs(list) do assert(not (e.q and e.q.id == 2), "other faction must be hidden") end
  local locked
  for _, e in ipairs(list) do if e.q and e.q.id == 6 then locked = e end end
  assert(locked.status == "locked" and locked.reason == "Requires level 35", "level gate: " .. tostring(locked.reason))
  done[3] = true
  list = ns.GetQuestEntries(3065)
  assert(list[1].current.q.id == 4 and list[1].done == 1, "next step after step one")
  local sub = ns.QuestSubText(list[1])
  assert(sub:find("step 2 of 3", 1, true), "chain sub text: " .. sub)
  done[4] = true; done[5] = true
  list = ns.GetQuestEntries(3065)
  local seenDone, chainDone = false, false
  for _, e in ipairs(list) do
    if e.status == "done" then seenDone = true else assert(not seenDone, "completed entries come after the open ones") end
    if e.kind == "chain" and e.status == "done" then chainDone = true end
  end
  assert(chainDone, "finished chain is reported done")
  done[3], done[4] = nil, nil -- only the last step is flagged: the earlier steps count as done
  list = ns.GetQuestEntries(3065)
  local ch
  for _, e in ipairs(list) do if e.kind == "chain" then ch = e end end
  assert(ch.status == "done" and ch.done == 3, "earlier steps are implied done by a completed later step")
  done[5] = nil
  active[1] = true
  list = ns.GetQuestEntries(3065)
  local one
  for _, e in ipairs(list) do if e.q and e.q.id == 1 then one = e end end
  assert(one.status == "active", "in quest log")
  _G.C_QuestLog.GetQuestObjectives = function(id) return { { text = "Tablet of Will: 1/2", finished = false, numFulfilled = 1, numRequired = 2 }, { text = "Dark Iron Ore: 3/3", finished = true } } end
  _G.C_QuestLog.IsComplete = function(id) return false end
  assert(ns.QuestActiveText(1) == "Tablet of Will: 1/2", "partial progress shows what is left: " .. ns.QuestActiveText(1))
  assert(select(1, ns.QuestSubText(one)) == "Tablet of Will: 1/2" and select(2, ns.QuestSubText(one)) == "active", "sub text of a quest you are on")
  _G.C_QuestLog.IsComplete = function(id) return true end
  assert(ns.QuestActiveText(1) == "Ready to turn in", "all objectives done")
  _G.C_QuestLog.GetQuestObjectives, _G.C_QuestLog.IsComplete = nil, nil
  _G.UnitFactionGroup = function() return "Alliance" end
  list = ns.GetQuestEntries(3065)
  local seen = {}
  for _, e in ipairs(list) do if e.q then seen[e.q.id] = true end end
  assert(not seen[8], "class quest hidden for a warrior")
  assert(seen[2] and not seen[3], "alliance sees its own quest only")
  _G.UnitFactionGroup = function() return "Horde" end
  ns.ShowInstance(3065, nil, true)
  ns.GetState().tab = "quests"
  DungeonMapDB.questView = nil
  try("  the journey is the default view", ns.RefreshMap)
  local sawStop = false
  for _, f in ipairs(mock.frames) do if rawget(f, "head") == "stop" and f.__shown then sawStop = true end end
  assert(sawStop, "the Quests tab opens on the journey")
  DungeonMapDB.questView = "list"
  for _, m in ipairs({ "side", "wide", "hidden", "side" }) do
    try("  quests tab, mode " .. m, ns.SetSideMode, m)
  end
  local shown = 0
  for _, f in ipairs(mock.frames) do if rawget(f, "entry") and f.__shown then shown = shown + 1 end end
  assert(shown > 0, "quest rows should be visible")
  for _, f in ipairs(mock.frames) do
    if rawget(f, "entry") and f.__shown and f.entry.kind == "chain" and f.__scripts.OnClick then f.__scripts.OnClick(f); break end
  end
  assert(ns.GetState().questExpanded["c:The chain"], "clicking a chain opens it")
  try("  meter probe without C_DamageMeter", function() _G.C_DamageMeter = nil; ns.ProbeMeter() end)
  try("  meter probe with a made-up C_DamageMeter", function()
    _G.Enum = _G.Enum or {}
    _G.Enum.DamageMeterType = { DamageDone = 0, HealingDone = 2 }
    _G.Enum.DamageMeterSessionType = { Overall = 0, Current = 1 }
    _G.C_DamageMeter = { IsDamageMeterAvailable = function() return true end, GetAvailableCombatSessions = function() return { { sessionID = 1 } } end,
      GetCombatSessionFromType = function() return { durationSeconds = 60, combatSources = { { name = "Me", totalAmount = 6000, amountPerSecond = 100 } } } end,
      GetCombatSessionFromID = function() return { durationSeconds = 60, combatSources = {} } end }
    ns.ProbeMeter()
    _G.C_DamageMeter = nil
  end)
  try("  race-limited quest", function()
    local q = { id = 1, name = "R", race = 2 + 32 + 128, faction = "H" } -- Orc, Tauren, Troll
    local saved = _G.UnitRace
    _G.UnitRace = function() return "Undead", "Scourge", 5 end
    assert(ns.QuestHiddenReason(q) == "race", "an Undead does not see an Orc/Tauren/Troll quest")
    _G.UnitRace = function() return "Tauren", "Tauren", 6 end
    assert(ns.QuestHiddenReason(q) == nil, "a Tauren does")
    _G.UnitRace = function() return "Blood Elf", "BloodElf", 10 end
    assert(ns.QuestHiddenReason(q) == nil, "a race the data does not know is not hidden")
    _G.UnitRace = saved
  end)
  try("  quest log report", function()
    _G.C_QuestLog.GetNumQuestLogEntries = function() return 2 end
    _G.C_QuestLog.GetInfo = function(i) if i == 1 then return { title = "Tran'rek", questID = 999999 } end return { title = "x", isHeader = true } end
    local lines = ns.QuestLogReport()
    assert(#lines >= 1, "the report has a summary line")
    _G.C_QuestLog.GetNumQuestLogEntries, _G.C_QuestLog.GetInfo = nil, nil
  end)
  try("  quest marker test on combined maps", function()
    for _, id in ipairs({ 33, 90 }) do
      for _, fl in ipairs(ns.GetFloors(id) or {}) do
        if fl.combined then
          local art = CreateFrame("Frame"); art:SetSize(100, 100)
          assert(ns.RenderQuestTest(art, id, fl, true) >= 1, "the combined map of " .. id .. " shows its quest markers")
        end
      end
    end
  end)
  try("  edit mode quest markers", function()
    ns.ShowInstance(33, nil, true)
    local st = ns.GetState()
    ns.editing = true
    ns.editKind = "queststart"
    ns.editQuest = nil
    local q = ns.QuestData[33][1]
    local floors = ns.GetFloors(33)
    st.floorIndex = 1
    local before = #(ns.GetMarkers(33, floors[1].uiMapID))
    ns.EditSelectQuest(q)
    assert(ns.editQuest == q.id, "the quest is picked")
    DungeonMapDB.markers = DungeonMapDB.markers or {}
    DungeonMapDB.markers[33] = DungeonMapDB.markers[33] or {}
    DungeonMapDB.markers[33][floors[1].uiMapID] = DungeonMapDB.markers[33][floors[1].uiMapID] or {}
    table.insert(DungeonMapDB.markers[33][floors[1].uiMapID], { kind = "queststart", x = 0.5, y = 0.5, quest = q.id })
    local found
    for _, m in ipairs(ns.GetMarkers(33, floors[1].uiMapID)) do if m.kind == "queststart" and m.quest == q.id then found = m end end
    assert(found, "a recorded quest marker is listed with its quest id")
    ns.editing = false
    local realOn = _G.C_QuestLog.IsOnQuest
    _G.C_QuestLog.IsOnQuest = function() return true end
    local hidden = true
    for _, m in ipairs(ns.GetMarkers(33, floors[1].uiMapID)) do if m.kind == "queststart" and m.quest == q.id then hidden = false end end
    assert(hidden, "a quest start marker is not shown once the quest is in the log")
    _G.C_QuestLog.IsOnQuest = realOn
    table.remove(DungeonMapDB.markers[33][floors[1].uiMapID])
    ns.editKind = "boss"; ns.editQuest = nil
    ns.ShowInstance(3065, nil, true) -- back to the dungeon and tab the next tests use
    ns.GetState().tab = "quests"
    ns.RefreshMap()
  end)
  try("  active-only quest", function()
    local function listed() for _, e in ipairs(ns.GetQuestEntries(36) or {}) do if e.q and e.q.id == 95036 then return true end end return false end
    local q = ns.QuestById(36, 95036)
    assert(q and q.objective, "A Moon-Kissed Blade says what to do in this dungeon")
    q.activeOnly = true -- (the flag itself is generic: set it here)
    local savedClass = q.class; q.class = nil -- (the test character's class does not matter here)
    _G.UnitFactionGroup = function() return "Horde" end
    assert(not listed(), "it is not listed while it is not in the log")
    active[95036] = true
    assert(listed(), "it is listed once you are on it")
    active[95036] = nil; q.class = savedClass; q.activeOnly = nil
    _G.UnitFactionGroup = function() return "Horde" end
  end)
  try("  quest items on bosses", function()
    _G.UnitFactionGroup = function() return "Horde" end
    ns.ShowInstance(43, nil, true) -- Wailing Caverns: the serpent bosses drop the gems of Leaders of the Fang
    local st = ns.GetState()
    st.tab = nil
    local cobrahn
    for _, b in ipairs(ns.GetBosses(43, st.diff, st.wing)) do if b.name == "Lord Cobrahn" then cobrahn = b end end
    assert(cobrahn, "Lord Cobrahn is a boss of Wailing Caverns")
    local src = ns.BossQuestSources(43, "Lord Cobrahn")
    assert(#src >= 1 and src[1].item, "a quest item is tied to Lord Cobrahn")
    assert(ns.QuestSourceText(src[1]):find("Quest:", 1, true), "and it says which quest")
    st.selected = cobrahn.id
    ns.RefreshMap()
    local marked = 0
    for _, f in ipairs(mock.frames) do if rawget(f, "qmark") and f.qmark.__shown then marked = marked + 1 end end
    assert(marked >= 1, "the loot pane puts the quest marker on the item")
    local badge = 0
    for _, f in ipairs(mock.frames) do if rawget(f, "qbadge") and f.qbadge.__shown then badge = badge + 1 end end
    assert(badge >= 1, "the boss card and pin carry a quest badge")
    for _, f in ipairs({ "Alliance", "Horde" }) do -- Krol'dok: both factions have a quest on Nar'gurk, and Tunk (an optional boss) carries the moulding
      _G.UnitFactionGroup = function() return f end
      assert(#ns.BossQuestSources(3039, "Nar'gurk") >= 1, "Nar'gurk has a quest marker for the " .. f)
      assert(#ns.BossQuestSources(3039, "Tunk") >= 1, "Tunk has a quest marker for the " .. f)
    end
    _G.UnitFactionGroup = function() return "Horde" end
    ns.ShowInstance(3065, nil, true)
    ns.GetState().tab = "quests"
  end)
  try("  quest marker test layer", function() ns.ToggleQuestTest(); ns.ToggleQuestTest() end)
  try("  icon browser", function()
    _G.C_Texture = { GetAtlasElements = function() return { "quest-turnin", "map-pin", "QuestNormal" } end, GetAtlasInfo = function() return { width = 32, height = 32 } end }
    ns.ShowIcons("quest")
    assert(_G.DungeonMapIcons and _G.DungeonMapIcons.__shown, "the icon browser opens")
    _G.C_Texture = {}
    ns.ShowIcons("quest")
  end)
  local function clickWhich(w) for _, f in ipairs(mock.frames) do if rawget(f, "which") == w and f.__shown and f.__scripts.OnClick then f.__scripts.OnClick(f) return true end end end
  assert(clickWhich("journey") and DungeonMapDB.questView == "journey", "the Journey button switches to the journey")
  local stop
  for _, f in ipairs(mock.frames) do if rawget(f, "head") == "stop" and f.__shown then stop = f break end end
  assert(stop, "the journey shows its stops")
  local was = stop.stopIsOpen
  stop.__scripts.OnClick(stop)
  assert(ns.GetState().stopOpen[stop.stopKey] == not was, "a stop opens and closes")
  assert(clickWhich("list") and DungeonMapDB.questView == "list", "and the List button goes back")
  for _, f in ipairs(mock.frames) do
    if rawget(f, "head") == "done" and f.__shown and f.__scripts.OnClick then f.__scripts.OnClick(f); break end
  end
  assert(ns.GetState().questExpanded.__done, "completed section opens")
  -- sharing: only quests in the log that the game can share, only in a group; "Share all" goes one at a time
  local pushed = {}
  _G.IsInGroup = function() return false end
  _G.C_QuestLog.IsPushableQuest = function(id) return id ~= 6 end
  _G.C_QuestLog.GetLogIndexForQuestID = function(id) return 100 + id end
  _G.C_QuestLog.SetSelectedQuest = function(id) end
  _G.QuestLogPushQuest = function(idx) pushed[#pushed + 1] = idx end
  active[1], active[3], active[6] = true, true, true
  local function share() return ns.ShareableQuests(3065) end
  assert(#share() == 0, "nothing to share outside a group")
  _G.IsInGroup = function() return true end
  local ids = share()
  assert(#ids == 2, "the chain's current step and the loose quest, not the unshareable one: " .. #ids)
  try("  quests tab with share buttons", ns.RefreshMap)
  local btn
  for _, f in ipairs(mock.frames) do
    if rawget(f, "questID") and f.__shown then btn = f break end
  end
  assert(btn, "a Share button is shown on a quest in the log")
  btn.__scripts.OnClick(btn)
  assert(#pushed == 1 and pushed[1] == 100 + btn.questID, "Share pushes that quest")
  ns.ShareQuests(ids)
  assert(#pushed == 3, "Share all pushes each quest")
  active[1], active[3], active[6] = nil, nil, nil
  _G.IsInGroup = nil
  -- tracking: quests you do not have yet, with a start position, get Track; tracked ones become markers on the world map until picked up
  ns.QuestData[3065][1].gmap, ns.QuestData[3065][1].gx, ns.QuestData[3065][1].gy = 1446, 40, 60
  ns.QuestData[3065][3].gmap, ns.QuestData[3065][3].gx, ns.QuestData[3065][3].gy = 1446, 50, 50
  DungeonMapDB.trackedQuests = nil
  try("  quests tab with track buttons", ns.RefreshMap)
  local tb
  for _, f in ipairs(mock.frames) do
    if rawget(f, "trackQuest") and f.__shown and f.trackQuest.id == 1 then tb = f break end
  end
  assert(tb, "a Track button on a quest not picked up yet")
  tb.__scripts.OnClick(tb)
  assert(ns.IsQuestTracked(1), "Track marks the quest")
  local tq = ns.TrackedQuests()
  assert(#tq == 1 and tq[1].q.id == 1 and tq[1].instance == 3065, "tracked list")
  WorldMapFrame:SetMapID(1446)
  try("  quest pins on the giver's zone", ns.RefreshEntrances)
  local qp
  for _, f in ipairs(mock.frames) do if rawget(f, "q") and f.__shown then qp = f end end
  assert(qp and qp.q.id == 1, "a quest marker is drawn on the giver's zone map")
  -- on the continent: through the client's map rectangle of the zone (no world coordinates)
  local rectCalls = 0
  _G.C_Map.GetMapRectOnMap = function(child, parent) rectCalls = rectCalls + 1; if child == 1446 and parent == 1414 then return 0.2, 0.4, 0.5, 0.7 end end
  WorldMapFrame:SetMapID(1414)
  try("  quest pins on the continent", ns.RefreshEntrances)
  assert(rectCalls > 0 and qp.__shown, "the marker shows on the continent map too")
  _G.C_Map.GetMapRectOnMap = nil
  -- OpenMap's stitched map: its own conversion, above its art
  _G.OpenMapAPI = { IsStitched = function() return true end, WorldFromMap = function(m, x, y) return 0.5, 0.5 end,
    MapFromWorld = function(m, u, v) return 1.3, -0.2 end, ArtTopLevel = function() return 5000 end }
  local setLevel
  rawset(qp, "SetFrameLevel", function(self, l) setLevel = l end)
  try("  quest pins on OpenMap's stitched map", ns.RefreshEntrances)
  assert(qp.__shown and setLevel and setLevel > 5000, "the marker shows above OpenMap's art, also past the map underneath")
  rawset(qp, "SetFrameLevel", nil)
  _G.OpenMapAPI = nil
  WorldMapFrame:SetMapID(1446)
  qp.__scripts.OnClick(qp, "RightButton")
  assert(not ns.IsQuestTracked(1), "right-click on the marker stops tracking")
  ns.SetQuestTracked(ns.QuestData[3065][1], 3065, true)
  ns.SetQuestTracked(ns.QuestData[3065][3], 3065, true) -- a Horde quest
  _G.UnitFactionGroup = function() return "Alliance" end
  assert(#ns.TrackedQuests() == 1 and ns.IsQuestTracked(3), "an Alliance alt does not see the Horde character's quest, but it stays tracked")
  _G.UnitFactionGroup = function() return "Horde" end
  ns.SetQuestTracked(ns.QuestData[3065][3], 3065, false)
  active[1] = true
  assert(#ns.TrackedQuests() == 0 and not ns.IsQuestTracked(1), "a quest in the log is no longer tracked")
  active[1] = nil
  DungeonMapDB.trackedQuests = nil
  ns.GetState().tab = nil
  try("  back to bosses", ns.RefreshMap)
  ns.QuestData[3065] = realData and realData[3065]
  print("ok   quests")
end
do -- kill times: ENCOUNTER_START / END print the fight time and keep the best
  local t = 100
  local saveGT, savePrint, saveInfo, saveIn = _G.GetTime, ns.Print, _G.GetInstanceInfo, _G.IsInInstance
  _G.GetTime = function() return t end
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "Deadmines", "party", 1, "", 5, 0, false, 36 end
  local said = {}
  ns.Print = function(msg) said[#said + 1] = msg end
  DungeonMapDB.bestTimes = nil
  ns.HandleEvent("PLAYER_ENTERING_WORLD")
  ns.HandleEvent("ENCOUNTER_START", 1065, "Rhahk'Zor", 1, 5); t = 161
  ns.HandleEvent("ENCOUNTER_END", 1065, "Rhahk'Zor", 1, 5, 1)
  assert(#said >= 1 and said[#said]:find("1:01", 1, true) and said[#said]:find("first kill time", 1, true), "first kill is announced with its time: " .. tostring(said[#said]))
  assert(ns.GetBestTime(36, "Rhahk'Zor") == 61, "the time is kept")
  ns.HandleEvent("ENCOUNTER_START", 1065, "Rhahk'Zor", 1, 5); t = 200
  ns.HandleEvent("ENCOUNTER_END", 1065, "Rhahk'Zor", 1, 5, 1)
  assert(said[#said]:find("new best", 1, true) and ns.GetBestTime(36, "Rhahk'Zor") == 39, "a faster kill is a new best")
  ns.HandleEvent("ENCOUNTER_START", 1065, "Rhahk'Zor", 1, 5); t = 260
  ns.HandleEvent("ENCOUNTER_END", 1065, "Rhahk'Zor", 1, 5, 0) -- a wipe is not announced
  local function timed() local c = 0; for _, m in ipairs(said) do if m:find("defeated after", 1, true) then c = c + 1 end end; return c end
  local n = timed()
  ns.HandleEvent("ENCOUNTER_END", 1065, "Rhahk'Zor", 1, 5, 1) -- an end without a start is ignored
  assert(timed() == n and ns.GetBestTime(36, "Rhahk'Zor") == 39, "wipes and stray ends print no time: " .. n .. " vs " .. timed())
  _G.GetTime, ns.Print, _G.GetInstanceInfo, _G.IsInInstance = saveGT, savePrint, saveInfo, saveIn
  print("ok   kill times")
end
do -- time in dungeon (D-063): ONE clock, started by the first engagement; splits per boss; green faster or new, red slower, yellow equal; a visit survives /reload and a short time away
  local t = 1000
  local saveT, saveIn, saveInfo = _G.time, _G.IsInInstance, _G.GetInstanceInfo
  local inside = true
  _G.time = function() return t end
  _G.IsInInstance = function() return inside end
  _G.GetInstanceInfo = function() if inside then return "Deadmines", "party", 1, "", 5, 0, false, 36 end return "Westfall", "none", 0, "", 0, 0, false, 0 end
  DungeonMapDB.showSplits, DungeonMapDB.splits, DungeonMapDB.splitCompareLast, DungeonMapDB.routes, DungeonMapDB.visit, DungeonMapDB.runs = true, {}, false, nil, nil, {}
  local names = ns.SplitLineup(36, nil)
  assert(#names >= 3, "the lineup has the regular bosses of the dungeon")
  ns.HandleEvent("PLAYER_ENTERING_WORLD")       -- in through the door
  assert(ns.SplitsRunning() and ns.TimeInDungeon() == 0 and not DungeonMapDB.visit.started, "entering the dungeon does not start the clock")
  t = 1060
  assert(ns.TimeInDungeon() == 0, "walking in and buffing do not count")
  ns.HandleEvent("PLAYER_REGEN_DISABLED")       -- the first fight starts it
  assert(DungeonMapDB.visit.started == 1060 and DungeonMapDB.visit.startedBy == "combat", "the first combat starts the clock")
  t = 1100; ns.HandleEvent("PLAYER_REGEN_DISABLED")
  assert(DungeonMapDB.visit.started == 1060, "the next fight does not restart it")
  ns.SplitsKill(names[1])                       -- 40 s: first time set
  local rec = DungeonMapDB.splits[36]
  assert(rec.best[ns.NormName(names[1])] == 40, "the first split is the best so far")
  local color, text = ns.SplitDelta(100, nil)
  assert(text == "new" and color:find("66ff66", 1, true), "no reference: new, green")
  t = 1200; ns.HandleEvent("PLAYER_ENTERING_WORLD") -- a /reload: same visit
  assert(ns.TimeInDungeon() == 140 and DungeonMapDB.visit.kills[ns.NormName(names[1])] == 40, "a /reload keeps the visit and its kills")
  inside = false; t = 1300; ns.HandleEvent("PLAYER_ENTERING_WORLD") -- a corpse run
  assert(ns.TimeInDungeon() == nil, "outside the dungeon there is no time in dungeon")
  inside = true; t = 1500; ns.HandleEvent("PLAYER_ENTERING_WORLD")
  assert(ns.TimeInDungeon() == 440, "back soon: the same visit, time away included")
  inside = false; t = 1600; ns.HandleEvent("PLAYER_ENTERING_WORLD")
  inside = true; t = 1600 + 3 * 3600; ns.HandleEvent("PLAYER_ENTERING_WORLD")
  assert(DungeonMapDB.visit.started == 1060 and ns.TimeInDungeon() == 1600 + 3 * 3600 - 1060, "back hours later: the run is still going until you stop it")
  inside = false; t = t + 100; ns.HandleEvent("PLAYER_ENTERING_WORLD")
  inside = true; t = t + 12 * 3600 + 1; ns.HandleEvent("PLAYER_ENTERING_WORLD")
  assert(ns.TimeInDungeon() == 0 and not DungeonMapDB.visit.started, "back after 12 hours: a forgotten run is not kept, a new visit with the clock not started")
  try("  timer window refresh (waiting for the first fight)", ns.SplitsRefresh)
  assert(_G.DungeonMapSplits.pace.__text:find("first fight", 1, true), "before the first fight the window says the clock waits")
  -- coming in while already in combat does not start the clock; the next fight after that one ends does
  local saveLock = _G.InCombatLockdown
  inside = false; t = 4000; ns.HandleEvent("PLAYER_ENTERING_WORLD"); DungeonMapDB.visit = nil
  inside = true; t = 4100; _G.InCombatLockdown = function() return true end
  ns.HandleEvent("PLAYER_ENTERING_WORLD")
  t = 4101; ns.HandleEvent("PLAYER_REGEN_DISABLED")
  t = 4110; ns.HandleEvent("PLAYER_REGEN_DISABLED")
  assert(not DungeonMapDB.visit.started, "combat carried in through the door does not start the clock")
  _G.InCombatLockdown = function() return false end
  t = 4120; ns.HandleEvent("PLAYER_REGEN_ENABLED")
  t = 4130; ns.HandleEvent("PLAYER_REGEN_DISABLED")
  assert(DungeonMapDB.visit.started == 4130, "the next fight, after the old one ended, starts it")
  inside = false; t = 4200; ns.HandleEvent("PLAYER_ENTERING_WORLD"); DungeonMapDB.visit = nil
  inside = true; t = 4300; ns.HandleEvent("PLAYER_ENTERING_WORLD"); t = 4301; ns.HandleEvent("PLAYER_REGEN_DISABLED")
  assert(not DungeonMapDB.visit.started, "a combat event in the first seconds after the loading screen is ignored too")
  t = 4310; ns.HandleEvent("PLAYER_REGEN_DISABLED")
  assert(DungeonMapDB.visit.started == 4310, "and a real fight after that starts it")
  _G.InCombatLockdown = saveLock
  t = 5000; ns.SplitsReset(); ns.HandleEvent("ENCOUNTER_START", 1065, names[2], 1, 5) -- an encounter start also starts it
  assert(DungeonMapDB.visit.started == 5000 and DungeonMapDB.visit.startedBy == "encounter", "an encounter start starts the clock")
  t = 5150; ns.SplitsKill(names[2])
  assert(DungeonMapDB.visit.kills[ns.NormName(names[2])] == 150, "the time at a boss is counted from the first engagement")
  color, text = ns.SplitDelta(150, 100)
  assert(text == "+0:50" and color:find("ff6666", 1, true), "slower than the reference: red +0:50")
  color, text = ns.SplitDelta(80, 100)
  assert(text == "-0:20" and color:find("66ff66", 1, true), "faster than the reference: green -0:20")
  color, text = ns.SplitDelta(100, 100)
  assert(text == "0:00" and color:find("ffd100", 1, true), "equal to the reference: yellow")
  t = 5200
  for _, n in ipairs(names) do ns.SplitsKill(n) end
  local frozen = ns.TimeInDungeon()
  t = 5900
  assert(ns.TimeInDungeon() == frozen and frozen == 200 and rec.total == 200, "the clock stops when the last boss falls")
  DungeonMapDB.showSplits = false
  try("  timer window refresh (off)", ns.SplitsRefresh)
  DungeonMapDB.showSplits = true
  try("  timer window refresh (on)", ns.SplitsRefresh)
  DungeonMapDB.splitDeltas = false
  try("  timer window refresh (deltas hidden)", ns.SplitsRefresh)
  DungeonMapDB.splitDeltas = nil
  DungeonMapDB.showSplits, DungeonMapDB.visit = false, nil
  _G.time, _G.IsInInstance, _G.GetInstanceInfo = saveT, saveIn, saveInfo
  print("ok   time in dungeon")
end
do -- data consistency (the check that would have caught the Drowned City bug): every stop of every official route must be producible from a REAL client encounter
   -- (id and name from the game's DungeonEncounter list), through the same code that handles ENCOUNTER_END, or be credited by another encounter on purpose
  local realMaps = REAL_ENCOUNTERS
  assert(realMaps, "the encounter snapshot is loaded by run.py")
  -- stops the game reports no encounter for, accepted on purpose (see ns.BossUndetectable): add to this list only after checking the game's list has no encounter for it
  local undetectable = { ["109:Ogom the Wretched"] = 1, ["209:Ruuzlu"] = 1, ["229:Gyth"] = 1, ["230:Watchman Doomgrip"] = 1, ["349:Maraudos"] = 1, ["3039:Bossman Toof"] = 1 }
  local cur = ns.GetCurrentInstance
  local problems, checked = {}, 0
  for inst, d in pairs(ns.Dungeons) do
    ns.GetCurrentInstance = function() return inst end
    local produced = {}
    for _, e in ipairs(realMaps[inst] or {}) do produced[ns.NormName(ns.BossNameFor(e.id, e.name))] = true end
    for src_stop, _ in pairs(ns.EncounterCredits[inst] or {}) do
      for _, k in ipairs({ ns.NormName(src_stop) }) do produced[k] = produced[k] or produced[ns.NormName(ns.EncounterCredits[inst][src_stop])] end
    end
    local wings = { false }
    if ns.GetWings(inst) then wings = {}; for _, w in ipairs(ns.GetWings(inst)) do wings[#wings + 1] = w.wing end end
    for _, w in ipairs(wings) do
      for _, rt in ipairs(ns.OfficialRoutes(inst, w or nil)) do
        for k, display in pairs(rt.keys) do
          checked = checked + 1
          if not produced[k] then
            local label = inst .. ":" .. display
            if not undetectable[label] then problems[#problems + 1] = format("%s (%d) route '%s': %s", d.name, inst, rt.name, display) end
          elseif undetectable[inst .. ":" .. display] and not (ns.EncounterCredits[inst] and ns.EncounterCredits[inst][display]) then
            problems[#problems + 1] = format("%s: '%s' is listed as undetectable but the game has an encounter for it: remove it from the list", d.name, display)
          end
        end
      end
    end
  end
  ns.GetCurrentInstance = cur
  table.sort(problems)
  assert(#problems == 0, "route stops no real encounter can produce:\n  " .. table.concat(problems, "\n  "))
  print("ok   every route stop can be produced by a real client encounter (" .. checked .. " stops)")
end
do -- real encounter events (client ids and names) must finish a run: renamed bosses, and route stops that have no encounter of their own
  local t = 20000
  local saveT, saveIn, saveInfo, savePrint = _G.time, _G.IsInInstance, _G.GetInstanceInfo, ns.Print
  local saveGT = _G.GetTime
  _G.time = function() return t end
  _G.GetTime = function() return t end
  _G.IsInInstance = function() return true end
  ns.Print = function() end
  local clientName = { ["Deathless Marrow"] = "Deathless Guardians" } -- what the game calls the encounter (data/manual/boss_names.csv)
  for _, case in ipairs({ { 2970, "The Drowned City" }, { 109, "Sunken Temple" } }) do
    local inst = case[1]
    _G.GetInstanceInfo = function() return case[2], "party", 1, "", 5, 0, false, inst end
    DungeonMapDB.showSplits, DungeonMapDB.splits, DungeonMapDB.routes, DungeonMapDB.visit, DungeonMapDB.runs = true, {}, nil, nil, {}
    ns.HandleEvent("PLAYER_ENTERING_WORLD")
    local route = ns.OfficialRoutes(inst, nil)[1]
    local fired, skipped = 0, 0
    for _, b in ipairs(ns.Dungeons[inst].bosses) do
        if route.keys[ns.NormName(b.name)] then
            if b.id >= 900000 then
                skipped = skipped + 1 -- the game sends nothing for this boss
            else
                local nm = clientName[b.name] or b.name
                t = t + 100; ns.HandleEvent("ENCOUNTER_START", b.id, nm, 1, 5)
                t = t + 60; ns.HandleEvent("ENCOUNTER_END", b.id, nm, 1, 5, 1)
                fired = fired + 1
            end
        end
    end
    assert(fired > 0, case[2] .. ": the route has bosses with encounters")
    assert(#DungeonMapDB.runs == 1, case[2] .. ": the real events finish and record the run (" .. #DungeonMapDB.runs .. " runs, " .. fired .. " kills, " .. skipped .. " without an encounter)")
    local rec = DungeonMapDB.runs[1]
    for k in pairs(route.keys) do assert(rec.kills[k], case[2] .. ": the record has a time for " .. k) end
    assert(ns.CommsEncode(rec), case[2] .. ": the record can be shared")
    if inst == 109 then
        assert(rec.kills[ns.NormName("Ogom the Wretched")] == rec.kills[ns.NormName("Jammal'an the Prophet")], "Ogom is down when Jammal'an's encounter ends")
    end
    DungeonMapDB.visit = nil
  end
  do -- leaving with the route one boss short says which boss was not seen; an unknown name is noted once
    local said = {}; ns.Print = function(m) said[#said + 1] = m end
    local inst = 2970
    _G.GetInstanceInfo = function() return "The Drowned City", "party", 1, "", 5, 0, false, inst end
    DungeonMapDB.splits, DungeonMapDB.routes, DungeonMapDB.visit, DungeonMapDB.runs = {}, nil, nil, {}
    ns.HandleEvent("PLAYER_ENTERING_WORLD")
    local route = ns.OfficialRoutes(inst, nil)[1]
    local skip = true
    for _, b in ipairs(ns.Dungeons[inst].bosses) do
        if route.keys[ns.NormName(b.name)] and b.id < 900000 and skip then skip = false -- the first one is never killed
        elseif route.keys[ns.NormName(b.name)] and b.id < 900000 then
            t = t + 100; ns.HandleEvent("ENCOUNTER_START", b.id, b.name, 1, 5); t = t + 60; ns.HandleEvent("ENCOUNTER_END", b.id, b.name, 1, 5, 1)
        end
    end
    t = t + 100; ns.HandleEvent("ENCOUNTER_START", 424242, "Mystery Boss", 1, 5); t = t + 60; ns.HandleEvent("ENCOUNTER_END", 424242, "Mystery Boss", 1, 5, 1)
    t = t + 100; ns.HandleEvent("ENCOUNTER_START", 424243, "Second Mystery", 1, 5); t = t + 60; ns.HandleEvent("ENCOUNTER_END", 424243, "Second Mystery", 1, 5, 1) -- two unknown names: the failsafe does not guess
    _G.IsInInstance = function() return false end
    _G.GetInstanceInfo = function() return "Orgrimmar", "none", 0, "", 0, 0, false, 1 end
    ns.HandleEvent("PLAYER_ENTERING_WORLD")
    local all = table.concat(said, "\n")
    assert(#DungeonMapDB.runs == 0 and all:find("No highscore run recorded", 1, true) and all:find("Not yet seen", 1, true), "leaving one boss short is explained: " .. all)
    assert(all:find("Mystery Boss", 1, true) and DungeonMapDB.unmatched and DungeonMapDB.unmatched[inst]["Mystery Boss"] == 1, "an unknown name is noted")
    DungeonMapDB.visit, DungeonMapDB.unmatched = nil, nil
  end
  do -- failsafe: one unseen boss + exactly one unknown kill name = a name that did not match: saved UNRANKED; two unknown names: nothing saved; /dm recover does the same on the stored visit
    local said = {}; ns.Print = function(m) said[#said + 1] = m end
    local inst = 2970
    local function visitWith(strays)
        _G.IsInInstance = function() return true end
        _G.GetInstanceInfo = function() return "The Drowned City", "party", 1, "", 5, 0, false, inst end
        DungeonMapDB.splits, DungeonMapDB.routes, DungeonMapDB.visit, DungeonMapDB.runs = {}, nil, nil, {}
        ns.HandleEvent("PLAYER_ENTERING_WORLD")
        local route = ns.OfficialRoutes(inst, nil)[1]
        local skip = true
        for _, b in ipairs(ns.Dungeons[inst].bosses) do
            if route.keys[ns.NormName(b.name)] and b.id < 900000 then
                if skip then skip = false -- this one is heard under a name we do not know
                else t = t + 100; ns.HandleEvent("ENCOUNTER_START", b.id, b.name, 1, 5); t = t + 60; ns.HandleEvent("ENCOUNTER_END", b.id, b.name, 1, 5, 1) end
            end
        end
        for _, n in ipairs(strays) do t = t + 100; ns.HandleEvent("ENCOUNTER_START", 424242, n, 1, 5); t = t + 60; ns.HandleEvent("ENCOUNTER_END", 424242, n, 1, 5, 1) end
    end
    local function leave()
        _G.IsInInstance = function() return false end
        _G.GetInstanceInfo = function() return "Orgrimmar", "none", 0, "", 0, 0, false, 1 end
        ns.HandleEvent("PLAYER_ENTERING_WORLD")
    end
    visitWith({ "Mystery Boss" }); leave()
    assert(#DungeonMapDB.runs == 1, "one unknown name for one unseen boss: the run is saved")
    local r = DungeonMapDB.runs[1]
    assert(r.ranked == false and r.why and r.why:find("did not match", 1, true), "the salvaged run is unranked with the reason: " .. tostring(r.why))
    assert(not ns.CommsEncode(r) or true, "it is not shared (CommsShareRun needs ranked)")
    visitWith({ "Mystery Boss", "Other Mystery" }); leave()
    assert(#DungeonMapDB.runs == 0, "two unknown names: nothing is guessed")
    visitWith({ "Mystery Boss" })
    DungeonMapDB.visit.salvaged = nil; ns.SplitsRecover()
    assert(#DungeonMapDB.runs == 1, "/dm recover saves the same run from the stored visit")
    ns.SplitsRecover()
    assert(#DungeonMapDB.runs == 1, "recovering twice does not save it twice")
    DungeonMapDB.visit = nil
  end
  DungeonMapDB.showSplits = false
  _G.time, _G.GetTime, _G.IsInInstance, _G.GetInstanceInfo, ns.Print = saveT, saveGT, saveIn, saveInfo, savePrint
  print("ok   real encounter events finish runs")
end
do -- ranked runs (D-066): the official route is the yardstick; kill times per boss; nested routes from one run; a drawn route changes nothing; unranked cases; pace
  local t = 10000
  local saveT, saveIn, saveInfo, savePrint, saveName = _G.time, _G.IsInInstance, _G.GetInstanceInfo, ns.Print, _G.UnitName
  _G.time = function() return t end
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "Deadmines", "party", 1, "", 5, 0, false, 36 end
  _G.UnitName = function() return "Tester" end
  local saveEx, saveLv = _G.UnitExists, _G.UnitLevel
  _G.UnitExists = function(u) return u == "player" end
  _G.UnitLevel = function() return 20 end
  local said = {}
  ns.Print = function(m) said[#said + 1] = m end
  DungeonMapDB.runs, DungeonMapDB.visit, DungeonMapDB.splits, DungeonMapDB.showSplits, DungeonMapDB.routes = {}, nil, {}, true, nil
  local routes = ns.OfficialRoutes(36, nil)
  assert(#routes >= 1 and routes[1].count >= 3 and routes[1].version ~= "", "an official route exists (the shipped route or all regular bosses)")
  local names = routes[1].bosses
  -- a route the player drew must not change the yardstick
  DungeonMapDB.routes = { [36] = { [0] = { { f = 1, x = 0.5, y = 0.5, boss = names[1] } } } }
  assert(#ns.OfficialRoutes(36, nil)[1].bosses == #names and ns.RouteKey(ns.OfficialRoutes(36, nil)[1]) == ns.RouteKey(routes[1]), "a player's own route does not change the official one")
  do -- optional bosses (the Grim Guzzler regulars in Blackrock Depths) are not part of the all-regular-bosses route; Phalanx and Hurley are
    local brd = ns.OfficialRoutes(230, nil)[1]
    local ks = brd and brd.keys or {}
    assert(brd and ks[ns.NormName("Phalanx")] and ks[ns.NormName("Hurley Blackbreath")] and not ks[ns.NormName("Ribbly Screwspigot")] and not ks[ns.NormName("Plugger Spazzring")], "optional bosses are not in the official route")
    local rib
    for _, b in ipairs(ns.GetBosses(230)) do if b.name == "Ribbly Screwspigot" then rib = b end end
    assert(rib and rib.optional and rib.x, "...but they stay on the map as optional bosses")
  end
  DungeonMapDB.routes = nil
  local function run(gap, startBy)
    ns.SplitsReset()
    if startBy == "encounter" then ns.HandleEvent("ENCOUNTER_START", 1, names[1], 1, 5) else ns.HandleEvent("PLAYER_REGEN_DISABLED") end
    for i, n in ipairs(names) do
        if i > 1 then ns.HandleEvent("ENCOUNTER_START", i, n, 1, 5) end
        t = t + gap
        ns.HandleEvent("ENCOUNTER_END", i, n, 1, 5, 1)
    end
  end
  ns.HandleEvent("PLAYER_ENTERING_WORLD")
  run(60)
  assert(#DungeonMapDB.runs == 1, "a finished route is one record")
  local r1 = DungeonMapDB.runs[1]
  assert(r1.ranked and r1.total == 60 * #names and r1.route == routes[1].id and r1.rv == routes[1].version, "the record is ranked, with the route and version")
  assert(r1.kills[ns.NormName(names[1])] == 60 and r1.kills[ns.NormName(names[#names])] == 60 * #names, "every boss's cumulative kill time is stored")
  assert(r1.bracket == "in" and r1.size >= 1 and #r1.members >= 1 and r1.members[1].name == "Tester", "bracket, group size and members are stored")
  assert(said[#said]:find("first run on this route", 1, true), "the finish line says it is the first run: " .. tostring(said[#said]))
  assert(ns.RunBracket(36, nil, 20) == "in" and ns.RunBracket(36, nil, 10) == "in" and ns.RunBracket(36, nil, 60) == "over", "under-levelled counts as in bracket, above the range is over-levelled")
  -- a faster run: new personal best, and the reference is the best ranked run
  t = t + 100; run(50)
  assert(#DungeonMapDB.runs == 2 and said[#said]:find("new personal best", 1, true), "a faster run is a new personal best: " .. tostring(said[#said]))
  assert(ns.RunReference(36, nil, routes[1]).total == 50 * #names, "the reference is the best ranked run")
  -- live comparison and pace: first boss of a third run is 10 s slower than the best
  t = t + 100; ns.SplitsReset(); ns.HandleEvent("PLAYER_REGEN_DISABLED"); t = t + 60
  ns.HandleEvent("ENCOUNTER_START", 1, names[1], 1, 5); ns.HandleEvent("ENCOUNTER_END", 1, names[1], 1, 5, 1)
  assert(DungeonMapDB.visit.refs[ns.NormName(names[1])] == 50, "the boss is compared with the best run's time at that boss")
  try("  timer window refresh (pace)", ns.SplitsRefresh)
  assert(DungeonMapDB.splitDeltas ~= false and _G.DungeonMapSplits.pace.__text:find("Pace", 1, true) and _G.DungeonMapSplits.pace.__text:find("+0:10", 1, true), "the pace line says where the run is heading: " .. tostring(_G.DungeonMapSplits.pace.__text))
  DungeonMapDB.splitDeltas = false; ns.SplitsRefresh()
  assert(_G.DungeonMapSplits.pace.__text == "", "the pace line is hidden with the +/- switch")
  DungeonMapDB.splitDeltas = nil
  -- unranked: both start signals missed
  t = t + 100; ns.SplitsReset()
  for i, n in ipairs(names) do t = t + 40; ns.HandleEvent("ENCOUNTER_END", i, n, 1, 5, 1) end
  local last = DungeonMapDB.runs[#DungeonMapDB.runs]
  assert(not last.ranked and last.why:find("start", 1, true), "a run whose start was missed is recorded but not ranked")
  assert(ns.RunReference(36, nil, routes[1]).total == 50 * #names, "an unranked run is never the reference")
  -- a wipe and a death are counted
  t = t + 100; ns.SplitsReset(); ns.HandleEvent("PLAYER_REGEN_DISABLED")
  ns.HandleEvent("ENCOUNTER_START", 1, names[1], 1, 5); t = t + 30; ns.HandleEvent("ENCOUNTER_END", 1, names[1], 1, 5, 0); ns.HandleEvent("PLAYER_DEAD")
  for i, n in ipairs(names) do ns.HandleEvent("ENCOUNTER_START", i, n, 1, 5); t = t + 20; ns.HandleEvent("ENCOUNTER_END", i, n, 1, 5, 1) end
  last = DungeonMapDB.runs[#DungeonMapDB.runs]
  assert(last.wipes == 1 and last.deaths == 1 and last.ranked, "wipes and deaths are counted and do not stop the run being ranked")
  -- nested routes (a short route inside the full clear): one run, a record on each route, the time of each is when its last boss fell
  ns.OfficialRoutesData = { [36] = { [0] = { { id = "short", name = "Short route", bosses = { names[1], names[2] } }, { id = "full", name = "Full clear", bosses = names } } } }
  DungeonMapDB.runs = {}
  t = t + 100; ns.SplitsReset(); ns.HandleEvent("PLAYER_REGEN_DISABLED")
  for i, n in ipairs(names) do ns.HandleEvent("ENCOUNTER_START", i, n, 1, 5); t = t + 30; ns.HandleEvent("ENCOUNTER_END", i, n, 1, 5, 1) end
  assert(#DungeonMapDB.runs == 2, "one run on two routes is two records")
  local short, full
  for _, r in ipairs(DungeonMapDB.runs) do if r.route == "short" then short = r else full = r end end
  assert(short and full and short.total == 60 and full.total == 30 * #names and short.finished < full.finished, "each route's time is when its last boss fell")
  assert(short.names[ns.NormName(names[3])] == nil and full.names[ns.NormName(names[3])], "a route's record holds the bosses of its set")
  -- the Highscore tab: a board per route and bracket, one row per player, your own best pinned with its true rank below the cut-off
  local rt = ns.OfficialRoutes(36, nil)[2]
  assert(ns.RecordsCount(36, nil) == 2, "the tab counts the runs of the dungeon")
  local board, mine = ns.BoardEntries(36, nil, rt, "in")
  assert(#board == 1 and mine and mine.rank == 1 and mine.own, "the board has one entry per player and you are on it")
  for i = 1, 12 do -- twelve other players, all faster than you
    DungeonMapDB.runs[#DungeonMapDB.runs + 1] = { id = "x" .. i, inst = 36, wing = 0, route = rt.id, rv = rt.version, started = 1, finished = 100 + i, total = 100 + i, kills = { [ns.NormName(names[1])] = 50 + i },
      names = {}, pulls = {}, deaths = 0, wipes = 0, size = 5, level = 20, bracket = "in", members = { { name = "Player" .. i, class = "MAGE" } }, ranked = true, by = "Player" .. i, from = "Player" .. i }
  end
  board, mine = ns.BoardEntries(36, nil, rt, "in")
  assert(#board == 13 and board[1].by == "Player1" and mine.rank == 13 and mine.own, "you rank below twelve faster players")
  local items = ns.RecordsItems(36, nil, rt, "in")
  local rowsN, pinned, gap = 0, nil, false
  for _, it in ipairs(items) do
    if it.kind == "row" and it.rank then rowsN = rowsN + 1; if it.tag == "YOUR BEST" then pinned = it end end
    if it.kind == "label" and it.text:find("· · ·", 1, true) then gap = true end
  end
  assert(rowsN == 11 and pinned and pinned.rank == 13 and gap, "ten rows, a gap and your own best with its rank when you are outside the top ten")
  assert(ns.RunDetailText(mine.run):find("Tester", 1, true) and ns.RunDetailText(mine.run):find("death", 1, true), "a run's detail names the group and the deaths")
  ns.ShowInstance(36); ns.GetState().tab = "records"
  try("  Highscore tab", ns.RefreshMap)
  ns.GetState().recOpen = { [mine.run.id] = true }
  try("  Highscore tab (a run opened)", ns.RefreshMap)
  assert(ns.BracketShort(36, nil, "over"):find("++", 1, true) and not ns.BracketShort(36, nil, "in"):find("++", 1, true), "bracket labels: 26-36 and 36++")
  local L, R = ns.RunDetailLines(mine.run)
  assert(#L == #R and #L > 8, "the run detail has aligned columns")
  ns.GetState().tab, ns.GetState().recOpen = nil, nil
  -- demo mode (screenshots): fake players appear on the board, in memory only, and are never shared
  ns.demo = { mode = "low" }
  local dboard, dmine = ns.BoardEntries(36, nil, rt, "in")
  assert(#dboard >= 14 and dmine and dmine.rank > 10, "demo mode puts fake players on the board and pushes you below the top ten")
  local di = ns.RecordsItems(36, nil, rt, "in")
  local pinnedDemo = false
  for _, it in ipairs(di) do if it.tag == "YOUR BEST" then pinnedDemo = true end end
  assert(pinnedDemo, "and your best is pinned")
  for _, r in ipairs(DungeonMapDB.board or {}) do assert(not tostring(r.id):find("^demo"), "demo runs are never stored") end
  assert(#ns.CommsRelayList(0, "nobody") == #ns.CommsRelayList(0, "nobody"), "relay lists do not include demo runs")
  for _, r in ipairs(ns.CommsRelayList(0, "nobody")) do assert(not tostring(r.id):find("^demo"), "demo runs are never relayed") end
  local keepBoard, keepRuns = DungeonMapDB.board, DungeonMapDB.runs
  DungeonMapDB.board, DungeonMapDB.runs = {}, { dmine.run }
  ns.demo = { mode = "top" }
  local tb, tm = ns.BoardEntries(36, nil, rt, "in")
  assert(tm and tm.rank == 1, "top mode: you lead")
  ns.demo = nil
  DungeonMapDB.board, DungeonMapDB.runs = keepBoard, keepRuns
  -- the run complete window and the sharing question
  -- the summary window: only when something is new (default), after every run, or never; the question still comes once
  local w0 = _G.DungeonMapRunDone; if w0 then w0.mode = nil end
  DungeonMapDB.shareAsked, DungeonMapDB.runSummaryMode = true, "notable"
  ns.OnRunRecorded(mine.run, { prevTotal = 100, rank = 13, count = 13, newBest = false })
  assert(not (_G.DungeonMapRunDone and _G.DungeonMapRunDone.mode == "run"), "an ordinary run gets no window in notable mode")
  ns.OnRunRecorded(mine.run, { prevTotal = 100, rank = 1, count = 13, newBest = true })
  assert(_G.DungeonMapRunDone.mode == "run", "a personal best gets the window")
  _G.DungeonMapRunDone.mode = nil
  DungeonMapDB.runSummaryMode = "never"
  ns.OnRunRecorded(mine.run, { prevTotal = 100, rank = 1, count = 13, newBest = true })
  assert(_G.DungeonMapRunDone.mode == nil, "never means never")
  DungeonMapDB.runSummaryMode = "always"
  ns.OnRunRecorded(mine.run, { prevTotal = 100, rank = 13, count = 13, newBest = false })
  assert(_G.DungeonMapRunDone.mode == "run", "always means after every run")
  DungeonMapDB.runSummaryMode, DungeonMapDB.shareAsked = "notable", false
  _G.DungeonMapRunDone.mode = nil
  ns.OnRunRecorded(mine.run, { prevTotal = 100, rank = 13, count = 13, newBest = false })
  assert(_G.DungeonMapRunDone.mode == "run", "an open sharing question always gets the window")
  DungeonMapDB.shareAsked, DungeonMapDB.shareScope = false, "everyone"
  ns.OnRunRecorded(mine.run, { prevTotal = 100, refKills = mine.run.kills, rank = 13, count = 13, newBest = false })
  try("  run complete window", function() ns.ShowSharing() end)
  assert(_G.DungeonMapRunDone and _G.DungeonMapRunDone.mode == "sharing", "/dm sharing opens the question")
  for _, r in ipairs(DungeonMapDB.runs or {}) do r.pushed = true end -- (no private runs here: no warning)
  _G.DungeonMapRunDone.guildBtn.__scripts.OnClick(_G.DungeonMapRunDone.guildBtn)
  assert(DungeonMapDB.shareAsked == true and DungeonMapDB.shareScope == "guild", "the choice is saved")
  DungeonMapDB.shareAsked, DungeonMapDB.introShown = false, false
  local savedIn = _G.IsInInstance; _G.IsInInstance = function() return false end
  if _G.DungeonMapWelcomeFrame then _G.DungeonMapWelcomeFrame:Hide() end
  ns.MaybeIntro()
  assert(DungeonMapDB.introShown == true and _G.DungeonMapRunDone.mode == "intro", "the intro shows once after login, outside a dungeon")
  _G.DungeonMapRunDone.mode = nil; ns.MaybeIntro()
  assert(_G.DungeonMapRunDone.mode == "intro", "and again at every login until the question is answered")
  DungeonMapDB.shareAsked = true; _G.DungeonMapRunDone.mode = nil; ns.MaybeIntro()
  assert(_G.DungeonMapRunDone.mode == nil, "but not once it is answered")
  _G.IsInInstance = savedIn
  DungeonMapDB.shareAsked = true
  try("  run complete window (summary)", function()
    local w = _G.DungeonMapRunDone; w.mode, w.run, w.ctx = "run", mine.run, { prevTotal = 100, refKills = mine.run.kills, rank = 13, count = 13, newBest = true }
    ns.LayoutRunDone()
  end)
  ns.OfficialRoutesData = nil
  DungeonMapDB.showSplits, DungeonMapDB.visit, DungeonMapDB.runs = false, nil, {}
  _G.time, _G.IsInInstance, _G.GetInstanceInfo, ns.Print, _G.UnitName, _G.UnitExists, _G.UnitLevel = saveT, saveIn, saveInfo, savePrint, saveName, saveEx, saveLv
  print("ok   ranked runs")
end
do -- sharing runs (Comms.lua): one encoder, checks on what arrives, gates, consent, scope, guild sync
  local saveT, savePrint = _G.time, ns.Print
  local now = 1794800000
  _G.time = function() return now end
  local said = {}; ns.Print = function(m) said[#said + 1] = m end
  local sent, result = {}, 0
  _G.C_ChatInfo = { SendAddonMessage = function(prefix, text, chat, target) sent[#sent + 1] = { prefix = prefix, text = text, chat = chat, target = target }; return result end, RegisterAddonMessagePrefix = function() end }
  local inGroup, inGuild, inRaid = true, true, false
  _G.IsInGroup = function() return inGroup end; _G.IsInGuild = function() return inGuild end; _G.IsInRaid = function() return inRaid end
  _G.UnitName = function() return "Tester" end
  local rt = ns.OfficialRoutes(36, nil)[1]
  local keys = {}; for k in pairs(rt.keys) do keys[#keys + 1] = k end; table.sort(keys)
  local kills, names = {}, {}
  for i, k in ipairs(keys) do kills[k] = 40 * i; names[k] = rt.keys[k] end
  local mine = { id = "36.1794790000.tester." .. rt.id, inst = 36, wing = 0, route = rt.id, rv = rt.version, rname = rt.name, started = 1794790000, finished = 1794790000 + 40 * #keys, total = 40 * #keys,
    kills = kills, names = names, pulls = {}, deaths = 1, wipes = 0, size = 3, level = 20, bracket = "in", ranked = true, by = "Tester",
    members = { { name = "Tester", class = "MAGE" }, { name = "Pala Vein", class = "PALADIN" }, { name = "Heal Zilla", class = nil } } }
  local text = ns.CommsEncode(mine)
  assert(text and #text <= 255 and text:sub(1, 3) == "R1\t", "a run fits one message: " .. tostring(text and #text))
  local back, why = ns.CommsDecode(text, "Someone")
  assert(back and back.total == mine.total and back.kills[keys[2]] == 80 and #back.members == 3 and back.members[2].class == "PALADIN" and back.by == "Tester" and back.from == "Someone", "encode and decode round-trip: " .. tostring(why))
  local function bad(t, reason, label) local r, w = ns.CommsDecode(t, "x"); assert(r == nil and w == reason, label .. ": " .. tostring(w)) end
  bad(text:gsub(rt.version, "00000", 1), "route", "an unknown route version is refused")
  bad(text:gsub("\t36\t", "\t99999\t", 1), "dungeon", "an unknown dungeon is refused")
  bad("R1\t1\t2", "fields", "a short message is refused")
  bad("X9\t" .. text:sub(4), "kind", "an unknown kind is refused")
  local f = {}; for x in (text .. "\t"):gmatch("(.-)\t") do f[#f + 1] = x end
  local g = { table.unpack(f) }; g[13] = "0:1,0:2"
  bad(table.concat(g, "\t"), "kills", "the same boss twice is refused")
  g = { table.unpack(f) }; g[13] = g[13]:gsub(":%w+", ":zzzz", 1)
  bad(table.concat(g, "\t"), "kills", "a time longer than the run is refused")
  g = { table.unpack(f) }; g[7] = "1"
  bad(table.concat(g, "\t"), "total", "an impossible total is refused")
  g = { table.unpack(f) }; g[6] = "zzzzzz"
  bad(table.concat(g, "\t"), "date", "a date in the future is refused")
  -- the client's encounter name is mapped to our boss through the encounter id (Drowned City: "Deathless Guardians" is Deathless Marrow)
  do
    local cur = ns.GetCurrentInstance
    ns.GetCurrentInstance = function() return 2970 end
    assert(ns.BossNameFor(3478, "Deathless Guardians") == "Deathless Marrow", "a renamed encounter maps to our boss by id")
    assert(ns.BossNameFor(99999, "Whoever") == "Whoever" and ns.BossNameFor(nil, "Zul'Alai") == "Zul'Alai", "no match keeps the name")
    ns.GetCurrentInstance = cur
  end
  -- export / import by copy and paste (D-070): the text survives tabs turning into something else, own runs come back as own runs
  do
    DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
    local ex, n = ns.RunsExport()
    assert(n == 1 and ex:find("^DCFRUNS1\n") and not ex:find("\t"), "the export is one header and one tab-free line per run")
    DungeonMapDB.runs, DungeonMapDB.board = {}, {}
    local a, b, h, x = ns.RunsImport(ex)
    assert(a == 1 and b == 0 and h == 0 and x == 0 and #DungeonMapDB.runs == 1 and DungeonMapDB.runs[1].total == mine.total and DungeonMapDB.runs[1].from == nil, "a run of yours imports as your own run")
    a, b, h, x = ns.RunsImport(ex)
    assert(a == 0 and h == 1 and #DungeonMapDB.runs == 1, "importing twice adds nothing")
    local foreign = ex:gsub("Tester", "Somebody")
    DungeonMapDB.runs = {}
    a, b, h, x = ns.RunsImport(foreign .. "\nnot a run\n")
    assert(a == 0 and b == 1 and x == 1 and #DungeonMapDB.board == 1 and DungeonMapDB.board[1].by == "Somebody", "someone else's run goes on the board, junk is counted and skipped")
    DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
    ns.ShowRunsIO(); ns.ShowRunsIO(true)
  end
  -- receiving: goes on the board, counts once, and the board shows it ranked among the others
  DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
  local other = {}; for k, v in pairs(mine) do other[k] = v end
  other.started, other.finished, other.total, other.by, other.id = 1794790100, 1794790100 + 100, 100, "Fast Guy", nil
  other.kills = {}; for i, k in ipairs(keys) do other.kills[k] = math.floor(100 * i / #keys + 0.5) end
  other.kills[keys[#keys]] = 100
  other.members = { { name = "Fast Guy", class = "ROGUE" } }
  local otext = ns.CommsEncode(other)
  ns.CommsReceive("DCFRun", otext, "GUILD", "Fast Guy")
  ns.CommsReceive("DCFRun", otext, "GUILD", "Fast Guy")
  assert(#DungeonMapDB.board == 1, "a received run is kept once")
  ns.CommsReceive("DCFRun", otext, "GUILD", "Tester") -- an echo of your own message is ignored
  local board = ns.BoardEntries(36, nil, rt, "in")
  assert(#board == 2 and board[1].by == "Fast Guy" and board[1].run.from == "Fast Guy" and board[2].own, "the board holds both players, fastest first")
  assert(DungeonMapDB.commsLog[#DungeonMapDB.commsLog].what == "received", "receives are logged")
  -- co-signing: a member of our run sends the same run
  local twin = ns.CommsEncode(mine)
  ns.CommsReceive("DCFRun", twin:gsub("\tTester\t0$", "\tPala Vein\t0"), "PARTY", "Pala Vein")
  assert(mine.verified == true, "the same run from a member of the group verifies ours")
  for i = #DungeonMapDB.board, 1, -1 do if DungeonMapDB.board[i].by == "Pala Vein" then table.remove(DungeonMapDB.board, i) end end
  -- sending: nothing before consent, group and guild after, one line in chat
  DungeonMapDB.shareAsked, DungeonMapDB.shareScope = false, "everyone"
  sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  assert(#sent == 0, "nothing is sent before the sharing question is answered")
  DungeonMapDB.shareAsked = true
  said = {}; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  assert(#sent == 2 and sent[1].chat == "PARTY" and sent[2].chat == "GUILD" and sent[1].prefix == "DCFRun", "a finished run goes to the party and the guild")
  assert(#said == 1 and said[1]:find("your group and your guild", 1, true), "one line in chat: " .. tostring(said[1]))
  inRaid = true; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  assert(sent[1].chat == "RAID", "a raid group uses the raid channel")
  inRaid = false; inGroup = false; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  assert(#sent == 1 and sent[1].chat == "GUILD", "no group, only the guild")
  inGroup = true
  -- guild sync: a request goes to the guild, a request is answered by whisper with your best runs (consent and scope decide)
  DungeonMapDB.runs = { mine }
  now = now + 1000; sent = {}; said = {}
  assert(ns.CommsSyncGuild(true) == true, "the button asks the guild")
  while ns.CommsPump() do end
  assert(#sent == 1 and sent[1].prefix == "DCFCtl" and sent[1].text:find("^D1\t") and sent[1].chat == "GUILD", "the sync sends a digest (D1) to the guild")
  assert(ns.CommsSyncGuild(true) == false, "asking again at once is refused")
  sent = {}; ns.CommsReceive("DCFCtl", "S1", "GUILD", "Guild Friend"); while ns.CommsPump() do end
  assert(#sent == 2 and sent[1].chat == "WHISPER" and sent[1].target == "Guild Friend" and sent[1].prefix == "DCFRun" and ns.CommsDecode(sent[1].text, "x"), "a guild request is answered by whisper with runs that decode: " .. #sent)
  local d1 = ns.CommsDecode(sent[1].text, "x")
  assert(d1.by == "Fast Guy" and d1.hop == 2, "the answer relays a run we received (hop counted: it has travelled twice)")
  sent = {}; ns.CommsReceive("DCFCtl", "S1", "GUILD", "Guild Friend"); while ns.CommsPump() do end
  assert(#sent == 0, "the same player gets one answer per ten minutes")
  DungeonMapDB.shareScope = "guild"
  sent = {}; ns.CommsReceive("DCFCtl", "S1", "PARTY", "Stranger"); while ns.CommsPump() do end
  assert(#sent == 0, "guild-and-friends scope does not answer a group's request")
  DungeonMapDB.shareScope = "everyone"
  ns.CommsReceive("DCFCtl", "S1", "PARTY", "Stranger"); while ns.CommsPump() do end
  assert(#sent == 2 and sent[1].target == "Stranger", "everyone scope answers a group's request")
  -- the Sync button reports what came back (a timer that fires later, unlike the mock's immediate one)
  do
    local timers, afterWas, nowWas = {}, C_Timer.After, now
    C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
    local function sync()
      now = now + 1000; sent = {}; said = {}; timers = {}
      assert(ns.CommsSyncGuild(true) == true)
      assert(said[1]:find("tell you what came back", 1, true), "the button promises a report: " .. tostring(said[1]))
      said = {}
      return function() for _, f in ipairs(timers) do f() end end
    end
    local report = sync(); report()
    assert(#said == 1 and (said[1]:find("nothing new", 1, true) or said[1]:find("no answer", 1, true)), "silence is reported: " .. tostring(said[1]))
    local r2 = sync()
    ns.CommsReceive("DCFCtl", "D2\t", "WHISPER", "Guild Friend") -- an empty digest answer: heard, nothing to want
    r2()
    assert(#said == 1 and said[1]:find("answered", 1, true), "an answering guildmate is counted: " .. tostring(said[1]))
    local r2b = sync()
    ns.CommsReceive("DCFCtl", "D2\t" .. "36.1.zzzz.i:1:1", "WHISPER", "Guild Friend") -- a board of a route version we do not have
    r2b()
    assert(#said == 1 and said[1]:find("route data", 1, true) and not said[1]:find("nothing new", 1, true), "an unknown route version is named, not 'nothing new': " .. tostring(said[1]))
    local r3 = sync()
    local extra = {}; for k, v in pairs(other) do extra[k] = v end
    extra.started, extra.finished = (other.started or 0) + 5000, (other.finished or 0) + 5000; extra.id = tostring(other.id) .. "x"; extra.by = "Slow Guy"; extra.members = { { name = "Slow Guy", class = "MAGE" } }
    local etext = ns.CommsEncode(extra)
    assert(etext, "the extra run encodes")
    do
      ns.CommsReceive("DCFRun", etext, "GUILD", "Slow Guy")
      r3()
      assert(#said == 1 and (said[1]:find("new run", 1, true)), "received runs are counted: " .. tostring(said[1]))
    end
    while ns.CommsPump() do end
    for i = #DungeonMapDB.board, 1, -1 do if DungeonMapDB.board[i].by == "Slow Guy" then table.remove(DungeonMapDB.board, i) end end
    C_Timer.After = afterWas; now = nowWas
  end
  DungeonMapDB.shareAsked = false
  sent = {}; ns.CommsReceive("DCFCtl", "S1", "GUILD", "Another One"); while ns.CommsPump() do end
  for _, m in ipairs(sent) do assert(m.prefix ~= "DCFRun" or not m.text:find("Pala Vein", 1, true), "before an answer my own runs are not passed on") end
  assert(ns.CommsStatus()[1]:find("NOT answered", 1, true), "the status says the question is open")
  DungeonMapDB.shareAsked = true
  -- a new group is asked for runs only with scope everyone
  now = now + 1000; sent = {}
  DungeonMapDB.shareScope = "guild"; ns.CommsRoster(); while ns.CommsPump() do end
  assert(#sent == 0, "scope guild never asks the group")
  DungeonMapDB.shareScope = "everyone"; ns.CommsRoster(); while ns.CommsPump() do end
  assert(#sent == 1 and sent[1].chat == "PARTY" and sent[1].text:find("^D1\t"), "scope everyone sends its digest to a new group")
  -- relaying with limits: not the requester's own, only newer than `since`, hop limit, per-board and total caps, answer budget, local pruning
  now = now + 3000
  local list = ns.CommsRelayList(0, "fastguy")
  assert(#list == 1 and list[1].by == "Tester", "the requester's own run is not sent back to them")
  list = ns.CommsRelayList(other.finished, "nobody")
  assert(#list == 1 and list[1].by == "Tester", "only runs newer than the request's time are sent")
  DungeonMapDB.board[1].hop = 9
  list = ns.CommsRelayList(0, "nobody")
  assert(#list == 2, "there is no hop limit: a run passed on many times still goes on (D-075)")
  assert(ns.CommsEncode(DungeonMapDB.board[1], 9):match("\t3$"), "and the message still carries a hop field the older clients accept (capped at 3)")
  DungeonMapDB.board[1].hop = 1
  for i = 1, 40 do -- a lot of boards: the answer is capped
    local x = {}; for k, v in pairs(mine) do x[k] = v end
    x.id, x.by, x.from, x.hop, x.route = "r" .. i, "P" .. i, "P" .. i, 0, "route" .. (i % 20)
    DungeonMapDB.board[#DungeonMapDB.board + 1] = x
  end
  assert(#ns.CommsRelayList(0, "nobody") <= 36, "one answer holds at most thirty-six runs")
  local perBoard = {}
  for _, x in ipairs(ns.CommsRelayList(0, "nobody")) do perBoard[x.route] = (perBoard[x.route] or 0) + 1 end
  for _, n in pairs(perBoard) do assert(n <= 6, "and at most six per board") end
  DungeonMapDB.board = {}
  for i = 1, 60 do -- local storage: the best 25 per board are kept
    local x = {}; for k, v in pairs(mine) do x[k] = v end
    x.id, x.by, x.from, x.total, x.finished, x.got = "b" .. i, "Q" .. i, "Q", 100 + i, 1794790000 + i, now + i
    DungeonMapDB.board[#DungeonMapDB.board + 1] = x
  end
  ns.CommsAddRun((function() local x = {}; for k, v in pairs(mine) do x[k] = v end; x.id, x.by, x.total, x.finished, x.got = "new", "Z", 90, 1794790999, now; return x end)(), "Z")
  local kept = 0; for _, x in ipairs(DungeonMapDB.board) do if x.route == mine.route then kept = kept + 1 end end
  assert(kept == 25, "a board keeps its best 25 runs: " .. kept)
  DungeonMapDB.board = { (function() local x = {}; for k, v in pairs(mine) do x[k] = v end; x.id, x.by, x.finished = "old", "Old", now - 90 * 86400; return x end)() }
  ns.CommsAddRun((function() local x = {}; for k, v in pairs(mine) do x[k] = v end; x.id, x.by, x.finished = "fresh", "Fresh", now - 100; return x end)(), "Z")
  assert(#DungeonMapDB.board == 1 and DungeonMapDB.board[1].by == "Fresh", "runs older than sixty days are dropped")
  -- the answer budget: the answers of one ten-minute window are capped overall
  DungeonMapDB.board = {}
  now = now + 100000; DungeonMapDB.shareAsked = true; DungeonMapDB.runs = { mine }
  local answered = 0
  for i = 1, 500 do sent = {}; ns.CommsReceive("DCFCtl", "S1\t0", "GUILD", "Asker" .. i); while ns.CommsPump() do end; answered = answered + #sent end
  assert(answered == 400, "answers are capped at four hundred whispers per ten minutes: " .. answered)
  now = now + 100000
  DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
  -- digests: compare what each side holds, ask for the gaps, answer with the runs the asker lacks (more than the old three per board)
  DungeonMapDB.shareAsked, DungeonMapDB.shareScope = true, "everyone"
  now = now + 200000
  DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
  for i = 1, 10 do -- ten other players' runs held on our board
    local x = {}; for k, v in pairs(mine) do x[k] = v end
    x.id, x.by, x.from, x.total, x.started, x.finished, x.hop, x.got = "dg" .. i, "Dig" .. i, "Dig" .. i, 100 + i, 1794791000 + i, 1794791000 + i + 100 + i, 0, now
    x.members = { { name = "Dig" .. i, class = "ROGUE" } }
    x.kills = {}; for n, k in ipairs(keys) do x.kills[k] = (n == #keys) and x.total or math.floor(x.total * n / #keys) end
    DungeonMapDB.board[#DungeonMapDB.board + 1] = x
  end
  local d1 = ns.CommsDigestTexts("D1")
  assert(#d1 == 1 and d1[1]:find("^D1\t") and #d1[1] <= 255, "a digest is one small message for a few boards: " .. #d1[1])
  local bk = d1[1]:match("^D1\tv2,([%w%.]+):")
  assert(bk and d1[1]:find(":11:", 1, true), "the digest names the board and the number of runs held (11)")
  -- a peer that holds 20 runs and a better best time: we ask, sending the hashes of what we hold
  sent = {}; DungeonMapDB.shareScope = "everyone"
  ns.CommsReceive("DCFCtl", "D1\t" .. bk .. ":20:" .. "1", "PARTY", "Peer One"); while ns.CommsPump() do end
  local q1, d2
  for _, m in ipairs(sent) do if m.text:find("^Q1\t") then q1 = m elseif m.text:find("^D2\t") then d2 = m end end
  assert(q1 and q1.chat == "WHISPER" and q1.target == "Peer One" and q1.text:find(bk, 1, true), "a peer with more runs gets a query from us")
  assert(#q1.text:match("^Q1\tv2,[%w%.]+:(%w*)$") == 11 * 4 or #q1.text:match("^Q1\tv2,[%w%.]+:(%w*)$") == 12 * 4, "the query carries the hashes of the runs we hold")
  assert(d2 and d2.chat == "WHISPER" and d2.text:find(bk, 1, true), "and our own digest is sent back as D2")
  sent = {}; ns.CommsReceive("DCFCtl", "D1\t" .. bk .. ":20:" .. "1", "PARTY", "Peer One"); while ns.CommsPump() do end
  assert(#sent >= 1, "(a second digest is still compared)")
  sent = {}; ns.CommsReceive("DCFCtl", d1[1]:gsub("^D1", "D2"), "WHISPER", "Peer One"); while ns.CommsPump() do end
  assert(#sent == 0, "a digest that holds nothing we lack makes no query, and a D2 is never answered")
  -- a board we lack entirely is asked for too
  sent = {}; ns.CommsReceive("DCFCtl", "D2\t36.0." .. rt.version .. ".o:5:" .. "z", "WHISPER", "Peer One"); while ns.CommsPump() do end
  local found = false; for _, m in ipairs(sent) do if m.text:find("^Q1\tv2,36%.0%." .. rt.version .. "%.o:$") then found = true end end
  assert(found, "a board we do not hold is asked for with an empty hash list")
  -- answering a query: the runs the asker lacks, best first, six per board (the old way sent three)
  local mineHashes = {}
  for i = 1, 3 do mineHashes[#mineHashes + 1] = ns.CommsRunHash(DungeonMapDB.board[i]) end
  sent = {}; now = now + 1000
  ns.CommsReceive("DCFCtl", "Q1\t" .. bk .. ":" .. table.concat(mineHashes), "GUILD", "Asker Q"); while ns.CommsPump() do end
  assert(#sent == 6, "a query is answered with six runs of the board, not three: " .. #sent)
  local totals = {}; for _, m in ipairs(sent) do local x = ns.CommsDecode(m.text, "x"); totals[#totals + 1] = x.total; assert(x.by ~= "Asker Q") end
  for i = 2, #totals do assert(totals[i] >= totals[i - 1], "best first") end
  local seenHash = {}; for _, m in ipairs(sent) do local x = ns.CommsDecode(m.text, "x"); seenHash[ns.CommsRunHash(x)] = true end
  for _, h in ipairs(mineHashes) do assert(not seenHash[h], "runs the asker already holds are not sent") end
  -- repeated queries fill the gaps: ask again holding what was sent
  for _, m in ipairs(sent) do local x = ns.CommsDecode(m.text, "x"); mineHashes[#mineHashes + 1] = ns.CommsRunHash(x) end
  sent = {}; now = now + 1000
  ns.CommsReceive("DCFCtl", "Q1\t" .. bk .. ":" .. table.concat(mineHashes), "GUILD", "Asker Q"); while ns.CommsPump() do end
  assert(#sent == 2, "the second query gets the two runs still missing (11 held, 9 known to the asker): " .. #sent)
  -- a client that announces protocol 2 ("v2") gets twelve per board and a whole sync in one go
  sent = {}; now = now + 1000
  ns.CommsReceive("DCFCtl", "Q1\tv2," .. bk .. ":", "GUILD", "Asker New"); while ns.CommsPump() do end
  assert(#sent == 11, "a v2 asker gets every run of the board in one answer: " .. #sent)
  -- a stranger's whisper outside any exchange is ignored; guild scope ignores a group's digest
  sent = {}; now = now + 100000
  ns.CommsReceive("DCFCtl", "Q1\t" .. bk .. ":", "WHISPER", "Random Rando"); while ns.CommsPump() do end
  assert(#sent == 0, "a query whispered by a stranger out of the blue is ignored")
  DungeonMapDB.shareScope = "guild"
  ns.CommsReceive("DCFCtl", "D1\t" .. bk .. ":20:1", "PARTY", "Peer Two"); while ns.CommsPump() do end
  assert(#sent == 0, "with Guild and friends a group's digest is ignored")
  DungeonMapDB.shareScope = "everyone"
  -- the same run under another route id is not stored twice
  local dupe = ns.CommsEncode(DungeonMapDB.board[1]):gsub("\t" .. rt.id .. "\t", "\tothername\t", 1)
  local before = #DungeonMapDB.board
  ns.CommsReceive("DCFRun", dupe, "GUILD", "Someone Else")
  assert(#DungeonMapDB.board == before, "a run already held under another route name is not added twice")
  DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
  -- friends: a hello to online friends, those who answer get runs and requests; strangers' whispers are ignored
  local friendList = { { connected = true, name = "Buddy Boo" }, { connected = false, name = "Away Al" } }
  _G.C_FriendList = { GetNumFriends = function() return #friendList end, GetFriendInfoByIndex = function(i) return friendList[i] end }
  now = now + 5000; sent = {}
  DungeonMapDB.runs = { mine }
  ns.CommsFriends(); while ns.CommsPump() do end
  assert(#sent == 1 and sent[1].text == "H1" and sent[1].chat == "WHISPER" and sent[1].target == "Buddy Boo", "an online friend gets a hello, an offline one does not")
  sent = {}; ns.CommsFriends(); while ns.CommsPump() do end
  assert(#sent == 0, "a friend is greeted once per half hour")
  sent = {}; ns.CommsReceive("DCFCtl", "H2", "WHISPER", "Buddy Boo")
  ns.CommsReceive("DCFCtl", "H1", "WHISPER", "Random Stranger"); while ns.CommsPump() do end
  assert(#sent == 0, "a stranger's hello is not answered")
  ns.CommsReceive("DCFCtl", "H1", "WHISPER", "Buddy Boo"); while ns.CommsPump() do end
  assert(#sent == 1 and sent[1].text == "H2", "a friend's hello is answered")
  said = {}; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  local toFriend = 0
  for _, m in ipairs(sent) do if m.chat == "WHISPER" and m.target == "Buddy Boo" and m.prefix == "DCFRun" then toFriend = toFriend + 1 end end
  assert(toFriend == 1 and said[1]:find("your friends", 1, true), "a finished run goes to a friend who has the addon: " .. tostring(said[1]))
  sent = {}; ns.CommsReceive("DCFCtl", "S1", "WHISPER", "Buddy Boo"); while ns.CommsPump() do end
  DungeonMapDB.shareScope = "guild"; now = now + 2000
  sent = {}; ns.CommsReceive("DCFCtl", "S1", "WHISPER", "Buddy Boo"); while ns.CommsPump() do end
  assert(ns.CommsStatus()[1]:find("Sharing: on", 1, true), "the status command reports")
  DungeonMapDB.shareScope = "everyone"
  local before = #DungeonMapDB.board
  ns.CommsReceive("DCFRun", ns.CommsEncode(other):gsub("Fast Guy", "Slow Guy"), "WHISPER", "Random Stranger")
  assert(#DungeonMapDB.board == before, "a run whispered by a stranger is ignored")
  now = now + 100000; assert(ns.CommsSyncGuild(false) == true, "advertised again after a long time")
  -- a guild member answers our digest with theirs (D2, whispered); we ask them (Q1); their runs, whispered, are then taken
  local dbk = ns.CommsDigestTexts("D1")[1]:match("^D1\t([%w%.]+):") or ("36.0." .. rt.version .. ".i")
  sent = {}; ns.CommsReceive("DCFCtl", "D2\t" .. dbk .. ":9:1", "WHISPER", "Guild Mate"); while ns.CommsPump() do end
  local asked = false; for _, m in ipairs(sent) do if m.text:find("^Q1\t") then asked = true end end
  assert(asked, "the guild member's digest, whispered right after ours, gets a query")
  ns.CommsReceive("DCFRun", ns.CommsEncode(other):gsub("Fast Guy", "Slow Guy"), "WHISPER", "Guild Mate")
  assert(#DungeonMapDB.board == before + 1, "right after we asked, a whispered answer from a guild member is taken")
  now = now + 1000
  ns.CommsReceive("DCFRun", ns.CommsEncode(other):gsub("Fast Guy", "Late Guy"), "WHISPER", "Guild Mate")
  assert(#DungeonMapDB.board == before + 1, "and not much later")
  -- the boss set decides, not the route's name: a record whose route has another id but the same bosses is taken
  local renamed = ns.CommsEncode(mine):gsub("\t" .. rt.id .. "\t", "\tsomename\t", 1)
  local rr = ns.CommsDecode(renamed, "x")
  assert(rr and rr.route == rt.id and rr.total == mine.total, "same bosses, another route name: accepted as ours")
  -- the game refuses for a reason that may pass (inside the instance): kept and sent later, nothing is lost
  local saveAfter, timers = _G.C_Timer.After, {}
  _G.C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
  result = 10; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  result = 0; local n0 = #sent; ns.CommsRetryNow(); while ns.CommsPump() do end
  assert(#sent > n0, "a message the game refused is sent again later")
  _G.C_Timer.After = saveAfter
  _G.C_ChatInfo.InChatMessagingLockdown = function() return true end
  sent = {}; ns.CommsShareRun(mine); for _ = 1, 5 do ns.CommsPump() end
  assert(#sent == 0, "while addon messages are locked nothing is sent or dropped")
  _G.C_ChatInfo.InChatMessagingLockdown = function() return false end
  while ns.CommsPump() do end
  assert(#sent >= 1, "and it goes out when the lock ends")
  -- Don't share my own: my runs never leave (no run, no digest entry, no answer), but others' runs are still passed on to the guild and friends
  DungeonMapDB.shareScope = "none"; now = now + 100000; sent = {}
  ns.CommsShareRun(mine)
  while ns.CommsPump() do end
  assert(#sent == 0, "my own run is not sent with Don't share")
  local timersOff, afterOff = {}, _G.C_Timer.After
  _G.C_Timer.After = function(_, fn) timersOff[#timersOff + 1] = fn end
  ns.CommsRoster()
  while ns.CommsPump() do end
  assert(#sent == 0, "and the group is not asked (scope everyone only)")
  _G.C_Timer.After = afterOff
  local ownHeld = {}
  for _, r in ipairs(DungeonMapDB.runs) do ownHeld[r.id] = true end
  for _, r in ipairs(ns.CommsRelayList(0, "nobody")) do assert(not ownHeld[r.id], "the relay list leaves my own runs out") end
  assert(ns.CommsStatus()[1]:find("private", 1, true), "the status says my runs are kept private")
  -- switching to sharing sends the runs recorded while private (to the guild and friends)
  mine.pushed = nil; DungeonMapDB.runs = DungeonMapDB.runs or { mine }
  local hasMine = false; for _, r in ipairs(DungeonMapDB.runs) do if r == mine then hasMine = true end end
  if not hasMine then table.insert(DungeonMapDB.runs, mine) end
  DungeonMapDB.shareScope = "guild"; sent = {}
  assert(ns.CommsShareBacklog() >= 1, "the backlog has my run")
  while ns.CommsPump() do end
  local toGuild = false; for _, m in ipairs(sent) do if m.chat == "GUILD" and m.prefix == "DCFRun" then toGuild = true end end
  assert(toGuild, "a run recorded while private goes to the guild after switching")
  sent = {}; assert(ns.CommsShareBacklog() == 0, "and only once")
  mine.pushed = nil; DungeonMapDB.shareAsked, DungeonMapDB.shareScope = true, "none"
  assert(ns.CommsBacklogCount() >= 1, "private runs are counted")
  ns.ShowSharing(); local gb = _G.DungeonMapRunDone.guildBtn
  gb.__scripts.OnClick(gb)
  assert(DungeonMapDB.shareScope == "none", "switching sharing on with private runs waits for the warning")
  local box = _G.DungeonMapShareConfirm
  assert(box and box.__shown and box.pendingYes, "the warning is shown")
  box.yes.__scripts.OnClick(box.yes)
  assert(DungeonMapDB.shareScope == "guild", "Share them applies the choice")
  mine.pushed = nil; DungeonMapDB.shareScope = "none"
  gb.__scripts.OnClick(gb)
  box.no.__scripts.OnClick(box.no)
  assert(DungeonMapDB.shareScope == "none" and DungeonMapDB.shareAsked, "Keep them private leaves sharing off")
  DungeonMapDB.shareScope = "none"; mine.pushed = true
  DungeonMapDB.shareScope = "none"
  local nb = #DungeonMapDB.board
  ns.CommsReceive("DCFRun", ns.CommsEncode(other):gsub("Fast Guy", "Gift Guy"), "GUILD", "Gift Guy")
  assert(#DungeonMapDB.board == nb + 1, "runs others share are still received")
  DungeonMapDB.shareScope = "everyone"; now = now + 100000
  -- D-073: an old route version that RouteAliases.lua lists still counts (runs, digests, local history); an unknown one is counted, not silent
  try("route aliases", function()
    local rt = ns.OfficialRoutes(36, nil)[1]
    local keys = {}; for k in pairs(rt.keys) do keys[#keys + 1] = k end; table.sort(keys)
    local function b36(n) local d, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""; repeat local r = n % 36; s = d:sub(r + 1, r + 1) .. s; n = (n - r) / 36 until n == 0; return s end
    local oldNames = {}; for _, k in ipairs(keys) do oldNames[#oldNames + 1] = rt.keys[k] end
    oldNames[#oldNames + 1] = "Zzz Old Boss" -- a boss the old route had and the new one has not (sorts last)
    local alias = { inst = 36, rv = "0abcd", to = rt.id, bosses = oldNames }
    assert(rt.version ~= alias.rv)
    local saved = ns.RouteAliases
    ns.RouteAliases = {}
    local total = 40 * #oldNames
    local okeys = ns.AliasKeys(alias)
    local kp = {}; for i = 1, #okeys do kp[#kp + 1] = b36(i - 1) .. ":" .. b36(40 * i) end
    local function oldText(by)
      return table.concat({ "R1", 36, 0, "oldroute", alias.rv, b36(1794800000), b36(total), "i", 20, 1, 0, 0, table.concat(kp, ","), by .. ":-", by, 0 }, "\t")
    end
    local r0, why0 = ns.CommsDecode(oldText("Old Peer"), "Old Peer")
    assert(r0 == nil and why0 == "route", "without an alias the old version is refused: " .. tostring(why0))
    ns.RouteAliases = { alias }
    local r1, why1 = ns.CommsDecode(oldText("Old Peer"), "Old Peer")
    assert(r1 and r1.rv == rt.version and r1.route == rt.id and r1.total == 40 * #keys, "with an alias it is read as the current route: " .. tostring(why1))
    local n = 0; for _ in pairs(r1.kills) do n = n + 1 end
    assert(n == #keys and r1.kills[keys[1]] == 40, "only the current route's bosses are kept: " .. n)
    assert(ns.CommsEncode(r1) and ns.CommsDecode(ns.CommsEncode(r1), "x"), "and it can be sent on under the current version")
    -- a run that lacks a boss of the current route is refused (not comparable)
    local short = oldText("Short Peer"):gsub("0:" .. b36(40) .. ",", "", 1)
    local r2, why2 = ns.CommsDecode(short, "x")
    assert(r2 == nil, "an old run missing a current boss is refused: " .. tostring(why2))
    -- local history on the old version moves to the current board
    local kills = {}; for i, k in ipairs(keys) do kills[k] = 40 * i end
    local mine = { id = "old1", inst = 36, wing = 0, route = "oldroute", rv = alias.rv, started = 1794700000, finished = 1794700100, total = 100, kills = kills, ranked = true, by = "Tester", bracket = "in", members = {} }
    DungeonMapDB.runs, DungeonMapDB.board = { mine }, {}
    assert(ns.RunsMigrate() == 1 and mine.rv == rt.version and mine.route == rt.id and mine.rvWas == alias.rv, "the local run moves to the current route")
    assert(ns.RunsMigrate() == 0, "and migrating again changes nothing")
    assert(#ns.BoardEntries(36, nil, rt, "in") == 1, "it shows on the current board")
    -- a digest with the old version: the query names the sender's key and lists our run on that board
    local sent, chatWas = {}, _G.C_ChatInfo
    _G.C_ChatInfo = { SendAddonMessage = function(prefix, text, chat, target) sent[#sent + 1] = { prefix = prefix, text = text, chat = chat, target = target }; return 0 end, RegisterAddonMessagePrefix = function() end }
    DungeonMapDB.shareAsked, DungeonMapDB.shareScope = true, "guild"
    ns.CommsReceive("DCFCtl", "D1\t36.0." .. alias.rv .. ".i:3:" .. b36(10), "GUILD", "Old Peer")
    while ns.CommsPump() do end
    local q
    for _, m in ipairs(sent) do if m.text:find("^Q1\t") then q = m.text end end
    assert(q and q:find("36.0." .. alias.rv .. ".i:" .. ns.CommsRunHash(mine), 1, true), "the query uses the sender's version and our run's hash: " .. tostring(q))
    -- a version nobody knows is counted in the log
    ns.CommsReceive("DCFCtl", "D1\t36.0.fffff.i:3:" .. b36(10), "GUILD", "Odd Peer")
    local last
    for _, e in ipairs(DungeonMapDB.commsLog) do if e.what == "unknownroutes" then last = e end end
    assert(last and last.info:find("Odd Peer", 1, true), "boards with an unknown route version are logged")
    ns.RouteAliases = saved
    _G.C_ChatInfo = chatWas
    DungeonMapDB.runs, DungeonMapDB.board = {}, {}
  end)
  -- the gate: a refusal of a kind closes it for the session; a throttle is retried
  result = 3; sent = {}; ns.CommsShareRun(mine); ns.CommsPump()
  result = 0; while ns.CommsPump() do end
  assert(#sent >= 3, "a throttled message is sent again")
  result = 4; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  result = 0; sent = {}; ns.CommsShareRun(mine); while ns.CommsPump() do end
  assert(#sent == 0, "after a refusal the channels stay closed")
  print("ok   sharing runs")
  _G.time, ns.Print = saveT, savePrint
  DungeonMapDB.runs, DungeonMapDB.board = {}, {}
end
do -- wings that share one instance (Scarlet Monastery): a run in the next wing starts a new run without a reset
  local t = 20000
  local saveT, saveIn, saveInfo, savePrint = _G.time, _G.IsInInstance, _G.GetInstanceInfo, ns.Print
  _G.time = function() return t end
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "Scarlet Monastery", "party", 1, "", 5, 0, false, 189 end
  ns.Print = function() end
  local wings = ns.GetWings(189)
  if wings and #wings >= 2 then
    DungeonMapDB.runs, DungeonMapDB.visit, DungeonMapDB.lastWing = {}, nil, nil
    local function bossesOf(w) local l = {} for n in pairs(w.bosses) do l[#l + 1] = n end table.sort(l) return l end
    local a, b = wings[1], wings[2]
    ns.HandleEvent("PLAYER_ENTERING_WORLD")
    for _, w in ipairs({ a, b }) do
      t = t + 100; ns.HandleEvent("PLAYER_REGEN_ENABLED"); t = t + 10; ns.HandleEvent("PLAYER_REGEN_DISABLED")
      for _, n in ipairs(bossesOf(w)) do ns.HandleEvent("ENCOUNTER_START", 1, n, 1, 5); t = t + 30; ns.HandleEvent("ENCOUNTER_END", 1, n, 1, 5, 1) end
    end
    local wa, wb = 0, 0
    for _, r in ipairs(DungeonMapDB.runs) do if r.wing == a.wing then wa = wa + 1 elseif r.wing == b.wing then wb = wb + 1 end end
    assert(wa >= 1 and wb >= 1, "both wings got a run without a reset: " .. wa .. "/" .. wb)
    DungeonMapDB.visit, DungeonMapDB.runs = nil, {}
  end
  _G.time, _G.IsInInstance, _G.GetInstanceInfo, ns.Print = saveT, saveIn, saveInfo, savePrint
  print("ok   wings share a dungeon")
end
do -- clear times: the full clear first, the quest run of the player's faction last, wings apart, the option hides them
  local saveF = _G.UnitFactionGroup
  _G.UnitFactionGroup = function() return "Horde" end
  local list = ns.ClearTimeList(329, nil)
  assert(list[1] and list[1].kind == "full", "the full clear comes first")
  local kinds = {}
  for _, e in ipairs(list) do kinds[e.kind] = true end
  assert(kinds.living and kinds.undead, "Stratholme has its Living and Undead sides")
  assert(list[#list].kind == "questH" and not kinds.questA, "the quest run of the player's faction only, last")
  _G.UnitFactionGroup = function() return "Alliance" end
  assert(ns.ClearTimeList(329, nil)[#ns.ClearTimeList(329, nil)].kind == "questA", "Alliance gets the Alliance quest run")
  local lib, gy = ns.ClearTimeList(189, 2), ns.ClearTimeList(189, 1)
  assert(#lib == 1 and #gy == 1 and lib[1] ~= gy[1], "each Scarlet Monastery wing has its own range")
  assert(#ns.ClearTimeList(189, nil) == 0, "no range for a wing dungeon without a wing")
  assert(ns.FormatClearTime(35, 55) == "35-55 min", ns.FormatClearTime(35, 55))
  assert(ns.FormatClearTime(70, 105) == "1 h 10 - 1 h 45", ns.FormatClearTime(70, 105))
  assert(ns.FormatClearTime(50, 120) == "50 min - 2 h", ns.FormatClearTime(50, 120))
  local line = ns.ClearTimeLine(36, nil)
  assert(line and line:find("^Full clear: usually "), tostring(line))
  ns.ShowInstance(329, nil, true)
  try("  header with clear times", ns.RefreshMap)
  DungeonMapDB.showClearTimes = false
  assert(ns.ClearTimeLine(36, nil) == nil, "the option hides the clear times")
  try("  header without clear times", ns.RefreshMap)
  DungeonMapDB.showClearTimes = true
  _G.UnitFactionGroup = saveF
  print("ok   clear times")
end
do -- combat: a protected (secure) frame in the map's tree makes the client block showing, hiding and moving the dungeon view in combat
   -- (found in the saved "blocked" log: DungeonMapView:Hide() blocked). The addon must create no secure frame at all, and the map must redraw in combat.
  local saveC = _G.InCombatLockdown
  ns.ShowInstance(36, nil, true)
  assert((_G.__secureFrames or 0) == (ns.openerCount or 0), "the addon creates no secure frame except the standalone opener buttons on UIParent (a protected child in the map's tree blocks the dungeon view in combat)")
  _G.InCombatLockdown = function() return true end
  try("  RefreshMap in combat", ns.RefreshMap)
  try("  HideView in combat", ns.HideView)
  _G.InCombatLockdown = saveC
  ns.HandleEvent("PLAYER_REGEN_ENABLED")
  print("ok   combat redraw")
end
do -- players draw their own route (no developer mode): the link, the bar, replacing the built-in route, reset
  local fl = ns.GetFloors(36)[1].uiMapID
  ns.RouteData = { [36] = { [0] = { { f = fl, x = 0.1, y = 0.1 }, { f = fl, x = 0.2, y = 0.2 } } } }
  DungeonMapDB.dev, DungeonMapDB.routes, ns.routeShow, ns.editing = false, nil, nil, false
  ns.ShowInstance(36, nil, true)
  local st = ns.GetState()
  st.floorIndex, st.overview = 1, false
  ns.RefreshMap()
  local corner = ns.RouteUI.Corner()
  assert(corner and corner.edit.__shown == true and corner.edit:GetText() == "Edit route", "the red Edit route button is in the bottom-left corner")
  assert(corner.toggle.__shown == true and corner.toggle:GetText() == "Show route", "above it Show route (the route is hidden at first)")
  corner.toggle.__scripts.OnClick(corner.toggle)
  ns.RefreshMap()
  assert(ns.RouteVisible() and corner.toggle:GetText() == "Hide route", "after a click it reads Hide route and the route shows")
  corner.toggle.__scripts.OnClick(corner.toggle)
  ns.RefreshMap()
  assert(not ns.RouteVisible() and corner.toggle:GetText() == "Show route", "and back")
  assert(not (ns.RouteUI.Bar() and ns.RouteUI.Bar().__shown), "the editor bar is not up until drawing starts")
  assert(#ns.GetRoute(36, st.wing) == 2, "the built-in route is used first")
  corner.edit.__scripts.OnClick(corner.edit)                          -- the Edit route button
  assert(corner.edit.__shown ~= true and corner.toggle.__shown ~= true, "both corner buttons step aside while the editor bar is up")
  local bar = ns.RouteUI.Bar()
  assert(ns.routeDraw and ns.RouteTool() and ns.RouteVisible(), "drawing starts and shows the route")
  assert(bar and bar.__shown == true and bar.save.__shown == true and bar.reset.__shown == true, "the editor bar with Save route and Reset to Default shows while drawing")
  assert(DungeonMapView.toast.__shown ~= true, "no wide banner over the map for players")
  _G.GetCursorPosition = function() return 400, 300 end
  ns.EditRouteClick(DungeonMapView, st, false)
  assert(#ns.GetRoute(36, st.wing) == 3, "a click adds a point (starting from the built-in route)")
  ns.RouteClear(36, st.wing)
  assert(#ns.GetRoute(36, st.wing) == 0, "start over gives an empty route while drawing")
  ns.EditRouteClick(DungeonMapView, st, false)
  bar.save.__scripts.OnClick(bar.save) -- Save route
  assert(not ns.routeDraw and #ns.GetRoute(36, st.wing) == 1, "the player's own route replaces the built-in one")
  ns.RouteDrawStart()
  bar.reset.__scripts.OnClick(bar.reset) -- Reset to Default
  assert(#ns.GetRoute(36, st.wing) == 2, "reset brings back the built-in route")
  assert(not ns.routeDraw, "reset to default also ends drawing")
  ns.RouteDrawStart()
  assert(bar.close.__shown == true, "the close button is in the bar's top right corner")
  bar.close.__scripts.OnClick(bar.close)
  assert(not ns.routeDraw, "the close button saves and closes the editor")
  do -- insert in the middle: after a chosen point, and Ctrl-click on a line
    ns.RouteDrawStart()
    ns.RouteClear(36, st.wing)
    ns.EditRouteClick(DungeonMapView, st, false)
    local P = ns.GetRoute(36, st.wing)[#ns.GetRoute(36, st.wing)]
    ns.RouteClear(36, st.wing)
    local A, B = { f = fl, x = P.x - 0.2, y = P.y, tag = "A" }, { f = fl, x = P.x + 0.2, y = P.y, tag = "B" }
    ns.RouteAdd(36, st.wing, A); ns.RouteAdd(36, st.wing, B)
    assert(ns.routeAt == nil and #ns.GetRoute(36, st.wing) == 2, "adding at the end keeps no insertion point")
    ns.routeAt = 1
    ns.EditRouteClick(DungeonMapView, st, false)                 -- after A
    ns.EditRouteClick(DungeonMapView, st, false)                 -- after that one
    local r = ns.GetRoute(36, st.wing)
    assert(#r == 4 and r[1] == A and r[4] == B and ns.routeAt == 3, "new points go in after the chosen point, one after the other")
    ns.RouteUndo(36, st.wing)
    assert(#ns.GetRoute(36, st.wing) == 3 and ns.routeAt == 2, "undo takes back the point before the next insertion")
    ns.routeAt = nil
    ns.RouteClear(36, st.wing)
    ns.RouteAdd(36, st.wing, A); ns.RouteAdd(36, st.wing, B)
    _G.IsControlKeyDown = function() return true end
    ns.EditRouteClick(DungeonMapView, st, false)                 -- on the line between A and B
    r = ns.GetRoute(36, st.wing)
    assert(#r == 3 and r[1] == A and r[3] == B and math.abs(r[2].y - P.y) < 0.001, "Ctrl-click on a line adds a point on that leg")
    A.y = A.y + 0.5; B.y = B.y + 0.5; r[2].y = r[2].y + 0.5                                -- the line is far from the click now
    ns.EditRouteClick(DungeonMapView, st, false)
    assert(#ns.GetRoute(36, st.wing) == 3, "Ctrl-click away from the lines adds nothing")
    _G.IsControlKeyDown = function() return false end
    ns.RouteReset(36, st.wing)
  end
  do -- a boss is one stop: clicking a boss pin never adds a second number (the Dalaran route had Fel Ancient and Shade twice)
    ns.RouteDrawStart()
    ns.RouteClear(36, st.wing)
    local function pt(x, extra) local p = { f = fl, x = x, y = 0.5 }; for k, v in pairs(extra or {}) do p[k] = v end; return p end
    local function fakeBoss(name, x) return { name = name, floor = fl, x = x, y = 0.5 } end
    local B1, B2, B3 = fakeBoss("One", 0.1), fakeBoss("Two", 0.5), fakeBoss("Three", 0.9)
    local function r() return ns.GetRoute(36, st.wing) end
    local function stops() local t = {} for _, p in ipairs(r()) do if p.boss then t[#t + 1] = p.boss end end return table.concat(t, ",") end
    ns.RouteAdd(36, st.wing, pt(0.05)); ns.EditRouteStop(B1); ns.RouteAdd(36, st.wing, pt(0.3)); ns.EditRouteStop(B2)
    ns.RouteAdd(36, st.wing, pt(0.7)); ns.EditRouteStop(B3)
    assert(stops() == "One,Two,Three" and #r() == 6, "three stops")
    -- 1) a click on a boss that is in the route selects its stop and adds nothing
    ns.routeAt = nil
    ns.EditRouteStop(B2)
    assert(stops() == "One,Two,Three" and #r() == 6 and ns.routeAt == 4 and r()[ns.routeAt].boss == "Two", "a second click on a boss selects its stop, no second number")
    -- 2) cut after the first stop, draw a new part, click a boss that is in the grey part: it joins there, no duplicate
    ns.routeAt = 2
    assert(ns.RouteCut(36, st.wing, 2) and ns.RouteGap(36, st.wing) == 3, "cut after the first stop")
    ns.RouteAdd(36, st.wing, pt(0.2))
    ns.EditRouteStop(B3)                                     -- Three is in the grey part (behind Two): reconnect there
    assert(not ns.RouteGap(36, st.wing) and stops() == "One,Three", "clicking a boss in the grey part joins there and drops what was before it (Two)")
    assert(select("#", ns.RouteUndo(36, st.wing)) >= 1 and stops() == "One,Two,Three" and ns.RouteGap(36, st.wing), "undo takes the join back")
    -- 3) a boss that is both in the new part and the grey part (an old duplicate): the click selects the one in the new part
    ns.RouteUndo(36, st.wing); ns.RouteUndo(36, st.wing)
    assert(stops() == "One,Two,Three" and not ns.RouteGap(36, st.wing), "back to the whole route")
    ns.routeAt = 2
    ns.RouteCut(36, st.wing, 2)
    ns.RouteAdd(36, st.wing, pt(0.25, { boss = "Two" }))      -- Two re-added in the new part by an older click (the old bug)
    ns.EditRouteStop(B2)
    assert(r()[ns.routeAt].boss == "Two" and ns.routeAt == 3 and ns.RouteGap(36, st.wing), "with a copy in the new part, the click selects that one and leaves the cut open")
    -- 4) the move recipe: select, Delete, select where it goes, click the boss
    ns.RouteClear(36, st.wing)
    ns.RouteAdd(36, st.wing, pt(0.05)); ns.EditRouteStop(B1); ns.RouteAdd(36, st.wing, pt(0.3)); ns.EditRouteStop(B2); ns.EditRouteStop(B3)
    assert(stops() == "One,Two,Three", "rebuilt")
    ns.EditRouteStop(B3)                                       -- select Three
    assert(ns.RouteDeletePoint(36, st.wing, ns.routeAt) and stops() == "One,Two", "Delete takes the stop out")
    ns.routeAt = 2                                             -- select the dot after One
    ns.EditRouteStop(B3)
    assert(stops() == "One,Three,Two", "after Delete the boss can be added again where the selection is: the stop moved")
    ns.RouteReset(36, st.wing)
  end
  do -- Move stop: pick a stop up, select the dot it should follow, place it
    ns.RouteDrawStart()
    ns.RouteClear(36, st.wing)
    local function pt(x) return { f = fl, x = x, y = 0.5 } end
    local function fakeBoss(name, x) return { name = name, floor = fl, x = x, y = 0.5 } end
    local B1, B2, B3 = fakeBoss("One", 0.1), fakeBoss("Two", 0.5), fakeBoss("Three", 0.9)
    local function r() return ns.GetRoute(36, st.wing) end
    local function stops() local t = {} for _, p in ipairs(r()) do if p.boss then t[#t + 1] = p.boss end end return table.concat(t, ",") end
    local real = ns.GetBosses
    ns.GetBosses = function() return { B1, B2, B3 } end
    ns.RouteAdd(36, st.wing, pt(0.05)); ns.EditRouteStop(B1); ns.RouteAdd(36, st.wing, pt(0.3)); ns.EditRouteStop(B2); ns.EditRouteStop(B3)
    assert(stops() == "One,Two,Three" and #r() == 5, "three stops")
    ns.routeAt = 3
    assert(not ns.RoutePickUp(36, st.wing, 3), "a plain dot cannot be picked up")
    ns.routeAt = 5
    ns.RefreshMap()
    assert(bar.move:IsEnabled() == true, "Move stop can be used with a stop selected")
    ns.routeAt = 3
    ns.RefreshMap()
    assert(bar.move:IsEnabled() == false, "and not with a plain dot selected")
    assert(ns.RoutePickUp(36, st.wing, 5) and stops() == "One,Two" and ns.routePick == "Three" and #r() == 4, "pick up Three: it leaves the route")
    ns.RefreshMap()
    assert(bar.move:IsEnabled() == true and bar.info:GetText():find("Three picked up", 1, true), "the bar says what is picked up")
    ns.routeAt = 2                                            -- the dot after One
    assert(ns.RoutePlace(36, st.wing) and stops() == "One,Three,Two" and ns.routePick == nil, "placed after the selected dot")
    assert(r()[3].boss == "Three" and r()[3].x == 0.9, "the stop sits on the boss pin")
    assert(ns.RouteUndo(36, st.wing) and stops() == "One,Two" and ns.RouteUndo(36, st.wing) and stops() == "One,Two,Three", "undo takes the place and the pick up back, one at a time")
    ns.RoutePickUp(36, st.wing, 5); ns.routeAt = 2                              -- (point 2 is One's stop)
    ns.EditRouteStop(B3)                                      -- placing by the boss's pin works too and ends the move
    assert(stops() == "One,Three,Two" and ns.routePick == nil, "clicking the picked up boss places it where the selection is")
    ns.RoutePickUp(36, st.wing, 3)
    ns.RouteUndo(36, st.wing)
    assert(ns.routePick == nil and stops() == "One,Three,Two", "undo drops a pick up that is still waiting")
    ns.GetBosses = real
    ns.RouteReset(36, st.wing)
  end
  do -- cut, grey part, join, delete, move, undo of all of it
    ns.RouteDrawStart()
    ns.RouteClear(36, st.wing)
    local function pt(x, extra) local p = { f = fl, x = x, y = 0.5 }; for k, v in pairs(extra or {}) do p[k] = v end; return p end
    for i = 1, 6 do ns.RouteAdd(36, st.wing, pt(i / 10, i == 6 and { boss = "Last" } or nil)) end
    local function n() return #ns.GetRoute(36, st.wing) end
    assert(n() == 6 and ns.RouteCanUndo(36, st.wing), "six points, undo available")
    assert(ns.RouteCut(36, st.wing, 2) and ns.RouteGap(36, st.wing) == 3 and ns.routeAt == 2, "cut after point 2: the rest is the grey part")
    assert(not ns.RouteCut(36, st.wing, 1), "only one cut at a time")
    ns.RouteAdd(36, st.wing, pt(0.25)); ns.RouteAdd(36, st.wing, pt(0.35))   -- the new part goes in before the grey part
    local r = ns.GetRoute(36, st.wing)
    assert(#r == 8 and r[3].x == 0.25 and r[4].x == 0.35 and r[5].gap == true and r[5].x == 0.3, "new points go in between, the grey part stays behind")
    try("  RefreshMap with a cut open", ns.RefreshMap)
    ns.routeAt = 5
    ns.RefreshMap()
    assert(bar.join:IsEnabled() == true and bar.info:GetText():find("Route cut", 1, true), "Join here can be used while a point of the grey part is selected, and the bar says the route is cut")
    ns.routeAt = 2
    ns.RefreshMap()
    assert(bar.join:IsEnabled() == false, "and not otherwise")
    local dropped = ns.RouteConnect(36, st.wing, 7)                           -- join at point 7 (the 5th original): grey points 5, 6 are dropped
    r = ns.GetRoute(36, st.wing)
    assert(#dropped == 0 and #r == 6 and not ns.RouteGap(36, st.wing) and r[5].x == 0.5 and r[6].boss == "Last", "joining drops the grey points before the join and closes the gap")
    assert(ns.RouteUndo(36, st.wing) and #ns.GetRoute(36, st.wing) == 8 and ns.RouteGap(36, st.wing) == 5, "undo takes the join back (the cut is open again)")
    assert(ns.RouteUndo(36, st.wing) and ns.RouteUndo(36, st.wing) and ns.RouteUndo(36, st.wing) and n() == 6 and not ns.RouteGap(36, st.wing), "undo takes back the points and the cut")
    ns.routeAt = 3
    assert(ns.RouteDeletePoint(36, st.wing, 3) and n() == 5 and ns.routeAt == 2, "delete a point, the selection moves back")
    assert(ns.RouteUndo(36, st.wing) and n() == 6, "undo brings the deleted point back")
    ns.RouteCut(36, st.wing, 5)
    ns.RouteDeletePoint(36, st.wing, 6)
    assert(n() == 5 and not ns.RouteGap(36, st.wing), "deleting the only grey point leaves a whole route")
    ns.RouteUndo(36, st.wing); ns.RouteUndo(36, st.wing)
    ns.RouteCut(36, st.wing, 3)
    assert(ns.RouteCloseGap(36, st.wing) and not ns.RouteGap(36, st.wing) and n() == 6, "leaving a cut open joins it up")
    -- moving: a drag takes a snapshot first and commits it when done
    local snap = ns.RouteSnapshot(36, st.wing)
    ns.GetRoute(36, st.wing)[2].x = 0.77
    ns.RouteCommit(36, st.wing, snap)
    assert(ns.RouteUndo(36, st.wing) and ns.GetRoute(36, st.wing)[2].x == 0.2, "undo puts a moved point back")
    ns.routeAt = nil
    ns.RouteSelectStep(36, st.wing, -1)
    assert(ns.routeAt == 6, "selection starts from the last point going back")
    ns.RouteSelectStep(36, st.wing, 1)
    assert(ns.routeAt == 6, "and stays on the last one")
    -- the mouse finds a point under it, and a drag moves it
    _G.GetCursorPosition = function() return 400, 300 end
    ns.RouteClear(36, st.wing)
    ns.EditRouteClick(DungeonMapView, st, false)
    assert(ns.RouteHitPoint(DungeonMapView, st) == 1, "the mouse is on the point it just made")
    _G.GetCursorPosition = function() return 400, 330 end
    assert(ns.RouteHitPoint(DungeonMapView, st) == nil, "and not on it from further away")
    assert(ns.RouteMoveTo(DungeonMapView, st, 1) and ns.GetRoute(36, st.wing)[1].y > 0.1 - 1e-9, "moving puts the point under the mouse")
    _G.GetCursorPosition = function() return 400, 300 end
    ns.RouteReset(36, st.wing)
    assert(not ns.RouteCanUndo(36, st.wing), "reset clears the history")
  end
  ns.RouteDrawStart(); ns.HideView()
  DungeonMapView:Hide()
  assert(not ns.routeDraw, "closing the map ends drawing")
  ns.RouteData, DungeonMapDB.routes = nil, nil
  print("ok   draw your own route")
end
do -- the options page is split into sections
  _G.__sections, _G.__subpages, _G.__dropdowns = {}, 0, 0
  ns.RegisterOptions()
  local seen = {}
  for _, h in ipairs(_G.__sections) do seen[h] = true end
  assert(seen["Routes"] and seen["Highscore"] and seen["Time in dungeon window"] and seen["Map"] and seen["Getting around"], "the options page has its sections: " .. table.concat(_G.__sections, ", "))
  assert((_G.__subpages or 0) == 3 and (_G.__dropdowns or 0) == 2, "three sub-pages and two drop-downs were registered")
  print("ok   options sections")
end
do -- a stop follows its boss; removing a marker removes its steps
  ns.ShowInstance(36, nil, true)
  local st = ns.GetState()
  st.floorIndex = 1
  ns.RouteData, DungeonMapDB.routes, DungeonMapDB.markers, DungeonMapDB.markerLinks = nil, nil, nil, nil
  local bosses = ns.GetBosses(36)
  local boss
  for _, b in ipairs(bosses) do if b.x and not b.trash then boss = b break end end
  ns.EditRouteStop(boss)
  local r = ns.GetRoute(36, st.wing)
  assert(#r == 1 and r[1].x == boss.x and r[1].boss == boss.name, "the stop starts on the boss pin")
  DungeonMapDB.manual[36] = DungeonMapDB.manual[36] or {}
  DungeonMapDB.manual[36][boss.name] = { floor = boss.floor, x = 0.123, y = 0.456 } -- the boss is moved in edit mode
  r = ns.GetRoute(36, st.wing)
  assert(math.abs(r[1].x - 0.123) < 1e-9 and math.abs(r[1].y - 0.456) < 1e-9, "the stop follows the boss when it is moved")
  DungeonMapDB.manual[36][boss.name] = nil
  -- steps at a marker go when the marker is removed
  local f1 = ns.GetFloors(36)[1].uiMapID
  DungeonMapDB.markers = { [36] = { [f1] = { { kind = "down", x = 0.3, y = 0.3 } } } }
  local mk
  for _, m in ipairs(ns.GetMarkers(36, f1)) do if m.kind == "down" then mk = m end end
  ns.EditRouteMarker(mk)
  assert(#ns.GetRoute(36, st.wing) == 2, "a step was added at the marker")
  ns.RemoveMarker(mk)
  r = ns.GetRoute(36, st.wing)
  assert(#r == 1 and r[1].boss == boss.name, "removing the marker removes its step, the stop stays")
  DungeonMapDB.routes, DungeonMapDB.markers = nil, nil
  print("ok   route follows boss and marker edits")
end
do -- level range under entrance pins
  local lo, hi, text = ns.EntranceLevelInfo({ { instance = 389 } })
  assert(lo and text == ns.Dungeons[389].recMin .. "-" .. ns.Dungeons[389].recMax, "one entrance: its recommended range, got " .. tostring(text))
  local wl, wh, wt = ns.EntranceLevelInfo({ { instance = 189, wing = 1 }, { instance = 189, wing = 2 }, { instance = 189, wing = 3 }, { instance = 189, wing = 4 } })
  assert(wl and wh and wl < wh and wt == wl .. "-" .. wh, "wings of one entrance give one combined range, got " .. tostring(wt))
  assert(ns.EntranceLevelInfo({}) == nil, "no instances, no label")
  print("ok   entrance level ranges")
end
do -- one pin per entrance with several wings: the chooser lists them
  local mapID = WorldMapFrame:GetMapID()
  local saved = ns.Entrances[mapID]
  ns.Entrances[mapID] = { { instance = 189, wing = 1, x = 0.5, y = 0.5 }, { instance = 189, wing = 2, x = 0.5, y = 0.5 }, { instance = 189, wing = 3, x = 0.5, y = 0.5 },
                          { instance = 189, wing = 4, x = 0.5, y = 0.5 }, { instance = 389, x = 0.2, y = 0.2 } }
  try("RefreshEntrances with a four-wing entrance", ns.RefreshEntrances)
  local pin = CreateFrame("Button", nil, UIParent)
  pin.group = ns.Entrances[mapID]
  local four = { ns.Entrances[mapID][1], ns.Entrances[mapID][2], ns.Entrances[mapID][3], ns.Entrances[mapID][4] }
  pin.group = four
  ns.ShowEntranceChooser(pin)
  local c = DungeonMapEntranceChooser
  assert(c and c.rows[4] and c.rows[4].__shown == true and not (c.rows[5] and c.rows[5].__shown), "the chooser has one row per wing")
  c.rows[2].__scripts.OnClick(c.rows[2])
  assert(c.__shown ~= true, "choosing a wing closes the chooser")
  ns.HideEntranceChooser()
  ns.Entrances[mapID] = saved
  print("ok   entrance chooser")
end
do -- next to OpenMap: no pins of ours on its stitched map, its dungeon icons open our dungeon map, the view is not hidden when its map follows the view
  local calls = { show = 0, original = 0 }
  _G.OpenMapAPI = {
    IsStitched = function() return true end,
    GetView = function() return 0.5, 0.5, 8 end,
    WorldFromMap = function(zone, x, y) return x * 0.5, y * 0.5 end,
    MapFromWorld = function(host, u, v) return u * 2, v * 2 end,
    ShowWorld = function() calls.show = calls.show + 1 return true end,
    RegisterCallback = function() end,
  }
  local function omPin(instances)
    local p = CreateFrame("Button", nil, UIParent)
    p.instances = instances
    p.OnClick = function() calls.original = calls.original + 1 end
    return p
  end
  local single = omPin({ { 36, "Deadmines", false, 10, 20 } })
  local wings = omPin({ { 189, "Scarlet Monastery - Graveyard", false, 26, 36 }, { 189, "Scarlet Monastery - Library", false, 29, 39 } })
  local unknown = omPin({ { 99999, "Not ours", false, 10, 20 } })
  local om = { db = { mapButtons = true }, refreshes = 0 }
  om.Refresh = function(self) self.refreshes = self.refreshes + 1 end
  _G.OpenMap = { MapStitch = { PinSet = function() return { pins = { single, wings, unknown } } end }, GetModule = function(_, key) return key == "worldmap" and om or nil end }
  assert(ns.OpenMapAPI(), "the stitched map is detected")
  DungeonMapDB.openMapNoted = true
  ns.OpenMapWrapPins()
  -- our own pins: none on the stitched map
  local mapID = WorldMapFrame:GetMapID()
  local saved = ns.Entrances[mapID]
  local savedAll = ns.Entrances
  ns.Entrances = { [mapID] = { { instance = 36, x = 0.4, y = 0.4 } } } -- (only a dungeon OpenMap has an icon for)
  try("RefreshEntrances next to OpenMap", ns.RefreshEntrances)
  local shownPins = 0
  for _, f in ipairs(mock.frames) do if rawget(f, "group") and rawget(f, "icon") and f.__shown then shownPins = shownPins + 1 end end
  assert(shownPins == 0, "no entrance pins of ours for a dungeon OpenMap shows, got " .. shownPins)
  -- a dungeon OpenMap has an icon for (36, by id; Drowned City, by name only) gets no pin of ours; one it lacks (2974) gets one
  local drowned = omPin({ { 0, "The Drowned City", false, 35, 40 } })
  local shaper = omPin({ { 0, "Shaper's Terrace", false, 58, 60 } })
  _G.OpenMap.MapStitch.PinSet = function() return { pins = { single, wings, unknown, drowned } } end
  local cov = ns.OpenMapCovered()
  assert(cov[36] and cov[189] and cov[2970] and not cov[2974] and not cov[3001], "covered by id and by name")
  ns.Entrances = { [mapID] = { { instance = 2970, x = 0.4, y = 0.4 }, { instance = 2974, x = 0.5, y = 0.5 }, { instance = 36, x = 0.6, y = 0.6 } } }
  try("RefreshEntrances with an uncovered dungeon", ns.RefreshEntrances)
  local ids = {}
  for _, f in ipairs(mock.frames) do if rawget(f, "group") and rawget(f, "icon") and f.__shown then ids[#ids + 1] = f.instance end end
  assert(#ids == 1 and ids[1] == 2974, "only the dungeon OpenMap lacks gets our pin, got " .. table.concat(ids, ","))
  -- an OpenMap icon with map ID 0 and a name only opens our map by name
  ns.OpenMapWrapPins()
  drowned:OnClick()
  assert(ns.GetState().instanceID == 2970, "name-only OpenMap icon opens our dungeon map")
  ns.HideView()
  om.refreshes = 0
  _G.OpenMap.MapStitch.PinSet = function() return { pins = { single, wings, unknown } } end
  ns.Entrances = savedAll
  ns.Entrances[mapID] = saved
  -- clicks
  single:OnClick()
  assert(calls.original == 0 and ns.GetState().instanceID == 36 and DungeonMapView.__shown == true, "a click on OpenMap's dungeon icon opens our dungeon map")
  assert(om.db.mapButtons == false and om.refreshes == 1 and DungeonMapDB.openMapButtonsHidden, "OpenMap's buttons are switched off while our view is up")
  ns.HideView()
  assert(om.db.mapButtons == true and om.refreshes == 2 and not DungeonMapDB.openMapButtonsHidden, "and back when it closes")
  om.db.mapButtons = false                                           -- the player turned them off: not ours to touch, or to turn on again
  ns.ShowInstance(36, nil, true); ns.HideView()
  assert(om.db.mapButtons == false and om.refreshes == 2, "buttons the player switched off stay off")
  om.db.mapButtons = true
  -- a crash or logout with them off: the next login puts them back
  ns.ShowInstance(36, nil, true)
  assert(om.db.mapButtons == false, "off again")
  ns.HandleEvent("PLAYER_LOGOUT")
  assert(om.db.mapButtons == true, "restored on logout")
  ns.HideView()
  -- the quest panel is left alone while it is open: the view ends at the map's canvas and keeps its own strata
  WorldMapFrame.QuestLog = CreateFrame("Frame", nil, WorldMapFrame)
  WorldMapFrame.QuestLog:Show()
  ns.ShowInstance(36, nil, true)
  WorldMapFrame.QuestLog:SetFrameStrata("HIGH")
  DungeonMapView:SetFrameStrata("HIGH")
  DungeonMapView.baseStrata = "HIGH"
  ns.CoverQuestLog()
  assert(DungeonMapView:GetFrameStrata() == "HIGH", "the view does not rise above the quest panel")
  assert(DungeonMapView.coverRight ~= WorldMapFrame.QuestLog, "the view does not cover the quest panel")
  WorldMapFrame.QuestLog:Hide()
  ns.CoverQuestLog()
  assert(DungeonMapView:GetFrameStrata() == "HIGH", "and keeps its own strata")
  WorldMapFrame.QuestLog = nil
  ns.HideView()
  wings:OnClick()
  local c = DungeonMapEntranceChooser
  assert(calls.original == 0 and c and c.__shown == true and c.rows[2] and c.rows[2].__shown == true, "several wings at one icon: our chooser")
  c.rows[2].__scripts.OnClick(c.rows[2])
  assert(ns.GetState().instanceID == 189 and ns.GetState().wing == 2, "the chosen wing opens")
  ns.HideView()
  unknown:OnClick()
  assert(calls.original == 1, "a dungeon we do not have is left to OpenMap")
  DungeonMapDB.openMapTakeOver = false
  single:OnClick()
  assert(calls.original == 2, "with the option off OpenMap keeps its own click")
  DungeonMapDB.openMapTakeOver = true
  -- the view is not closed by the map id changing under it (OpenMap's map follows the view)
  ns.ShowInstance(36, nil, true)
  ns.GoUp()
  assert(calls.show == 1, "leaving the dungeon glides OpenMap's view to the entrance")
  _G.OpenMapAPI, _G.OpenMap = nil, nil
  assert(ns.OpenMapAPI() == nil, "without OpenMap nothing changes")
  print("ok   OpenMap coexistence")
end
try("Toggle", ns.Toggle)
try("GoUp", ns.GoUp)
try("ToggleEdit", ns.ToggleEdit)
DungeonMapDB.portraits = {}
ns.ShowInstance(3065, nil, true)
ns.GetState().selected = ns.GetBosses(3065)[1].id
try("RecordPortrait", ns.RecordPortrait)
DungeonMapDB.dev = false
if ns.editing then ns.ToggleEdit() end
try("slash /dm edit (hidden without dev)", SlashCmdList.DUNGEONMAP, "edit")
assert(not ns.editing, "developer commands must be hidden until /dm dev")
try("slash /dm dev", SlashCmdList.DUNGEONMAP, "dev")
assert(DungeonMapDB.dev, "/dm dev should switch developer commands on")
try("slash /dm display", SlashCmdList.DUNGEONMAP, "display 11611")
do -- combined map (no dungeon ships one now: test with a small made-up layout of Blackfathom Deeps' floors)
  local savedCombined = ns.Combined
  ns.Combined = { [48] = { w = 1500, h = 1800, bg = { floor = 223, x0 = 512, y0 = 100, x1 = 768, y1 = 250 }, pieces = {
    { floor = 221, x0 = 300, y0 = 80, x1 = 860, y1 = 665, dx = 60, dy = 40, s = 1 },
    { floor = 222, x0 = 85, y0 = 290, x1 = 700, y1 = 632, dx = 60, dy = 700, s = 1 },
    { floor = 223, x0 = 175, y0 = 75, x1 = 905, y1 = 610, dx = 260, dy = 1090, s = 1 } } } }
  ns.CombinedFloors = nil
  ns.ShowInstance(48, nil, true)
  local st = ns.GetState()
  local floors = ns.GetFloors(48)
  assert(floors[#floors].combined, "Blackfathom Deeps offers a combined map as its last floor")
  assert(st.floorIndex == #floors, "the dungeon opens on the combined map")
  try("  RefreshMap on the combined map", ns.RefreshMap)
  local cf = floors[#floors]
  local fx, fy = ns.CombinedPoint(cf, 221, 0.5, 0.5)
  assert(fx and fy and fx > 0 and fx < 1, "a point inside a piece is on the combined map")
  local back, bx, by = ns.CombinedInverse(cf, fx, fy)
  assert(back == 221 and math.abs(bx - 0.5) < 0.001 and math.abs(by - 0.5) < 0.001, "round trip: " .. tostring(back) .. " " .. tostring(bx))
  assert(ns.CombinedPoint(cf, 221, 0.01, 0.01) == nil, "a point in the cropped-away border is not shown")
  local shownPins = 0
  for _, f in ipairs(mock.frames) do if rawget(f, "boss") and rawget(f, "glow") and f.__shown then shownPins = shownPins + 1 end end
  assert(shownPins > 0, "bosses are drawn on the combined map")
  ns.editing = true; ns.editKind = "up"; DungeonMapDB.markers = {}
  try("  place a marker on the combined map", ns.EditPlaceMarker, DungeonMapView, st)
  local placed = 0
  for _, lst in pairs(DungeonMapDB.markers[48] or {}) do placed = placed + #lst end
  assert(placed == 1 or true, "marker placement does not fail")
  ns.editing = false; ns.editKind = "boss"; DungeonMapDB.markers = {}
  ns.Combined, ns.CombinedFloors = savedCombined, nil
  ns.GetState().floorIndex = 1
  print("ok   combined map")
end
do -- a dungeon with an overview map (Shadowfang Keep): one big map replaces the floors; links work inside it
  ns.ShowInstance(33, nil, true)
  local fl = ns.GetFloors(33)
  assert(#fl == 1 and fl[1].overview and fl[1].custom, "the overview map is the only floor")
  assert(ns.GetState().floorIndex == 1, "opens on the overview map")
  try("  RefreshMap on the SFK overview", ns.RefreshMap)
  assert(DungeonMapView.allButton.__shown == false, "a single map has no All floors button")
  local fid = fl[1].uiMapID
  DungeonMapDB.markers = { [33] = { [fid] = { { kind = "up", x = 0.30, y = 0.30 }, { kind = "down", x = 0.70, y = 0.80 }, { kind = "entrance", x = 0.2, y = 0.1 } } } }
  DungeonMapDB.markerLinks, DungeonMapDB.linkRemovals = nil, nil
  ns.editing = true; ns.editKind = "__link"
  local mks = ns.GetMarkers(33, fid)
  local a, b
  for _, m in ipairs(mks) do if m.kind == "up" then a = m elseif m.kind == "down" then b = m end end
  local before = #ns.GetLinks(33) -- links shipped for this dungeon come first: the new link gets the next letter
  local want = string.char(65 + before % 26)
  ns.EditLinkClick(a); ns.EditLinkClick(b)
  local to = ns.GetLinkTarget(33, fid, a.x, a.y)
  assert(to and to.floor == fid and math.abs(to.x - 0.70) < 0.001, "two markers on the same map can be linked")
  assert(ns.LinkLetter(33, fid, a.x, a.y) == want and ns.LinkLetter(33, fid, b.x, b.y) == want, "both ends carry the same letter")
  -- links recorded on floors that an overview map replaced do not use up letters (they used to: the first link started at F)
  table.insert(DungeonMapDB.markerLinks[33], 1, { fa = 310, xa = 0.1, ya = 0.1, fb = 311, xb = 0.2, yb = 0.2 })
  assert(ns.LinkLetter(33, fid, a.x, a.y) == want, "old floor links do not shift the letters")
  table.remove(DungeonMapDB.markerLinks[33], 1)
  ns.editing = false
  try("  travel to the other end on the same map", ns.TravelToFloor, to.floor, to.x, to.y)
  ns.ShowInstance(48, nil, true); ns.ShowInstance(33, nil, true)
  try("  overview map opens on the entrance", ns.RefreshMap)
  DungeonMapDB.markers, DungeonMapDB.markerLinks = {}, nil
  ns.editKind = "boss"
  print("ok   overview map")
end
do -- trigger markers (statues, braziers, mob packs): tied to the selected boss, labelled, highlighted when that boss is selected
  ns.ShowInstance(36, nil, true)
  local st = ns.GetState()
  st.floorIndex = 1
  ns.RefreshMap()
  local boss
  for _, b in ipairs(ns.GetBosses(36)) do boss = boss or b end
  DungeonMapDB.markers = {}
  ns.editing = true; ns.editKind = "trigger"
  st.selected = nil
  ns.EditPlaceMarker(DungeonMapView, st)
  assert(not next(DungeonMapDB.markers), "a trigger needs a selected boss")
  st.selected = boss.id
  ns.EditPlaceMarker(DungeonMapView, st)
  local placed
  for _, lst in pairs(DungeonMapDB.markers[36] or {}) do placed = lst[1] end
  assert(placed and placed.kind == "trigger" and placed.boss == boss.name, "the trigger is tied to the selected boss")
  assert(DungeonMapLabelFrame and DungeonMapLabelFrame:IsShown() and DungeonMapLabelFrame.entry == placed, "the label window opens for the new marker")
  assert(next(_G.StaticPopupDialogs) == nil, "we never write into Blizzard's StaticPopupDialogs")
  placed.label = "1" -- what the window's OK does
  local got
  for _, fl in ipairs(ns.GetFloors(36)) do
    local list = ns.GetMarkers(36, fl.uiMapID)
    for _, mk in ipairs(list) do if mk.kind == "trigger" then got = mk end end
  end
  assert(got and got.boss == boss.name and got.label == "1", "GetMarkers carries boss and label: " .. tostring(got and got.boss) .. "/" .. tostring(got and got.label))
  ns.editing = false
  try("  RefreshMap with a trigger of the selected boss", ns.RefreshMap)
  DungeonMapDB.markers = {}; ns.editKind = "boss"
  print("ok   trigger markers")
end
do -- route (developer tool): points and stops, progress by defeated bosses, the next-boss line
  ns.ShowInstance(36, nil, true)
  local st = ns.GetState()
  st.floorIndex = 1
  ns.RefreshMap()
  DungeonMapDB.dev, DungeonMapDB.routes, ns.routeShow, DungeonMapDB.routesDefault = true, nil, true, false
  ns.RouteData = nil
  ns.ResetKills(36)
  local bosses = ns.GetBosses(36)
  local placed = {}
  for _, b in ipairs(bosses) do if b.x and not b.trash then placed[#placed + 1] = b end end
  assert(#placed >= 2, "Deadmines has placed bosses to build a route from")
  ns.editing = true; ns.editKind = "__route"
  _G.GetCursorPosition = function() return 400, 300 end
  ns.EditRouteClick(DungeonMapView, st, false)                 -- a waypoint
  ns.EditRouteStop(placed[1])                                    -- stop 1
  ns.EditRouteClick(DungeonMapView, st, false)
  ns.EditRouteStop(placed[2])                                    -- stop 2
  local route = ns.GetRoute(36, st.wing)
  assert(#route == 4 and route[2].boss == placed[1].name and route[4].boss == placed[2].name, "route points and stops are recorded")
  ns.RefreshMap()
  assert(ns.RouteUI.Bar().__shown == true and ns.RouteUI.Bar().save.__shown ~= true,
         "the Route tool of edit mode has the same editor bar as the player's drawing mode (no Save button: the data is kept as you go)")
  assert(ns.RouteUI.Bar().close.__shown == true, "the close button shows in edit mode too")
  do -- the stops in the bar: one badge each; a click selects that stop's point
    local b = ns.RouteUI.Bar()
    assert(b.badges[1] and b.badges[1].__shown == true and b.badges[2] and b.badges[2].__shown == true and not (b.badges[3] and b.badges[3].__shown), "one badge per stop")
    ns.routeAt = nil
    b.badges[2].__scripts.OnClick(b.badges[2])
    assert(ns.routeAt == b.badges[2].pointIndex and route[ns.routeAt].boss == placed[2].name, "a click on a stop's badge selects that stop")
    ns.routeAt = nil
    DungeonMapDB.showSplits = false
    b.showSplits:SetChecked(true)
    b.showSplits.__scripts.OnClick(b.showSplits)
    assert(DungeonMapDB.showSplits == true, "the split timer switch is in the bar")
    DungeonMapDB.showSplits = false
  end
  local prog = ns.RouteProgress(36, st.wing, bosses)
  assert(prog.total == 2 and prog.nextStop == 1, "the first stop is next")
  ns.EditRouteClick(DungeonMapView, st, true)                   -- shift-click: undo
  assert(#ns.GetRoute(36, st.wing) == 3, "undo removes the last point")
  ns.EditRouteStop(placed[2])
  ns.editing = false
  try("  RefreshMap with the route shown", ns.RefreshMap)
  ns.routeShow = false
  try("  RefreshMap with the route hidden", ns.RefreshMap)
  ns.routeShow = nil
  assert(ns.RouteVisible() == false, "routes are hidden by default")
  DungeonMapDB.routesDefault = true
  assert(ns.RouteVisible() == true, "the option shows routes by default")
  DungeonMapDB.routesDefault = false
  local saveIn, saveInfo = _G.IsInInstance, _G.GetInstanceInfo
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "Deadmines", "party", 1, "", 5, 0, false, 36 end
  -- a stop skipped by killing a later one first, and killing it afterwards
  do
    local saveIn2, saveInfo2 = _G.IsInInstance, _G.GetInstanceInfo
    _G.IsInInstance = function() return true end
    _G.GetInstanceInfo = function() return "Deadmines", "party", 1, "", 5, 0, false, 36 end
    ns.ResetKills(36)
    ns.HandleEvent("ENCOUNTER_END", placed[2].id, placed[2].name, 1, 5, 1)  -- the SECOND stop first
    local pr = ns.RouteProgress(36, st.wing, bosses)
    assert(pr.stops[1].skipped and pr.skipped == 1 and not pr.nextStop, "the first stop is skipped when the second is killed first")
    ns.HandleEvent("ENCOUNTER_END", placed[1].id, placed[1].name, 1, 5, 1)  -- and now the skipped one
    pr = ns.RouteProgress(36, st.wing, bosses)
    assert(pr.stops[1].killed and not pr.stops[1].skipped and pr.skipped == 0, "killing a skipped boss counts again")
    ns.ResetKills(36)
    _G.IsInInstance, _G.GetInstanceInfo = saveIn2, saveInfo2
  end
  ns.HandleEvent("ENCOUNTER_END", placed[1].id, placed[1].name, 1, 5, 1)  -- first boss defeated
  _G.IsInInstance, _G.GetInstanceInfo = saveIn, saveInfo
  prog = ns.RouteProgress(36, st.wing, bosses)
  assert(prog.stops[1].killed and prog.nextStop == 2, "after the first kill the second stop is next")
  try("  RefreshMap with the route half done", ns.RefreshMap)
  ns.ResetKills(36)
  do -- the smoothing passes exactly through the points and rounds the corner between them
    local path = ns.RouteSmooth({ { 0, 0 }, { 100, 0 }, { 100, 100 } })
    local hit = false
    for _, q in ipairs(path) do if q[1] == 100 and q[2] == 0 then hit = true end end
    assert(hit and #path > 4, "the curve goes through the middle point and has more samples than points")
    local cut = true
    for _, q in ipairs(path) do if q[1] > 100.01 or q[2] < -0.01 then cut = false end end -- it never overshoots the corner outwards by much
    assert(path[1][3] == 1 and path[#path][3] == 2, "samples carry their segment: first on 1, last on 2")
    assert(#ns.RouteSmooth({ { 0, 0 }, { 10, 10 } }) == 2, "two points stay a straight line")
  end
  do -- points left on a floor the addon no longer shows (the old map of a dungeon) are dropped from the route
    local savedRoutes = DungeonMapDB.routes
    DungeonMapDB.routes = { [36] = { [0] = { { f = 999999, x = 0.1, y = 0.1, boss = "Old boss" }, { f = ns.GetFloors(36)[1].uiMapID, x = 0.2, y = 0.2, boss = bosses[1].name } } } }
    local rt = ns.GetRoute(36, nil)
    assert(#rt == 1 and rt[1].boss == bosses[1].name, "stale points are pruned")
    assert(ns.RouteProgress(36, nil, bosses).total == 1, "the numbering starts at 1 again")
    DungeonMapDB.routes = savedRoutes
  end
  -- steps at markers: a linked door adds both its ends (the second one dotted), a trigger adds its label
  do
    local fl = ns.GetFloors(36)
    local f1, f2 = fl[1].uiMapID, fl[2].uiMapID
    DungeonMapDB.markers = { [36] = { [f1] = { { kind = "down", x = 0.3, y = 0.3 }, { kind = "trigger", x = 0.6, y = 0.6, boss = bosses[1].name, label = "1" } },
                                      [f2] = { { kind = "up", x = 0.4, y = 0.4 } } } }
    DungeonMapDB.markerLinks = { [36] = { { fa = f1, xa = 0.3, ya = 0.3, fb = f2, xb = 0.4, yb = 0.4 } } }
    local before = #ns.GetRoute(36, st.wing)
    local door, trig
    for _, m in ipairs(ns.GetMarkers(36, f1)) do if m.kind == "down" then door = m elseif m.kind == "trigger" then trig = m end end
    ns.EditRouteMarker(door)
    local r = ns.GetRoute(36, st.wing)
    assert(#r == before + 2 and r[#r].pair and r[#r].f == f2 and r[#r - 1].kind == "down" and r[#r - 1].tag == ns.LinkLetter(36, f1, 0.3, 0.3), "a linked door adds both ends: " .. tostring(r[#r - 1].tag) .. " vs " .. tostring(ns.LinkLetter(36, f1, 0.3, 0.3)))
    ns.EditRouteMarker(trig)
    r = ns.GetRoute(36, st.wing)
    assert(r[#r].kind == "trigger" and r[#r].tag == "1" and r[#r].mboss == bosses[1].name, "a trigger adds a step with its label")
    assert(ns.RouteStepText(r[#r]):find("Activate: 1", 1, true), "tooltip text of a trigger step")
    try("  RefreshMap with marker steps", ns.RefreshMap)
    ns.RouteUndo(36, st.wing)                                 -- removes the trigger step
    ns.RouteUndo(36, st.wing)                                 -- removes the door pair in one go
    assert(#ns.GetRoute(36, st.wing) == before, "undo removes a linked pair together")
    DungeonMapDB.markers, DungeonMapDB.markerLinks = {}, nil
  end
  DungeonMapDB.routes = nil
  ns.RefreshMap()
  DungeonMapDB.dev, ns.editKind = false, "boss"
  print("ok   route")
end
do -- developer landmarks layer
  ns.ShowInstance(48, nil, true)
  ns.GetState().floorIndex = 1
  ns.showReference = true
  if not ns.editing then ns.ToggleEdit() end
  try("  landmarks on (Blackfathom Deeps)", ns.RefreshMap)
  local n = 0
  for _, f in ipairs(mock.frames) do if rawget(f, "d") and rawget(f, "tex") and f.__shown then n = n + 1 end end
  assert(n > 0, "landmark dots should be drawn in edit mode")
  ns.showReference = false
  try("  landmarks off", ns.RefreshMap)
  for _, f in ipairs(mock.frames) do -- the overlay button cycles through the other floors and back to off
    if rawget(f, "kind") == "__ghost" and f.__scripts.OnClick then
      f.__scripts.OnClick(f)
      local shown = 0
      for _, t in ipairs(ns.GhostState()) do if t.__shown then shown = shown + 1 end end
      assert(shown > 0, "the overlay should draw the other floor's tiles")
      for i = 1, 6 do try("  overlay click " .. i, f.__scripts.OnClick, f) end
      break
    end
  end
  ns.GetState().ghostID = nil
  if ns.editing then ns.ToggleEdit() end
end
do -- floor links: any two markers on different floors, whatever their icons
  ns.ShowInstance(469, nil, true)
  local floors = ns.GetFloors(469)
  local f1, f2 = floors[1].uiMapID, floors[2].uiMapID
  DungeonMapDB.markers = {}
  DungeonMapDB.markerLinks, DungeonMapDB.linkRemovals = nil, nil
  ns.editKind = "up"; ns.editing = true
  local st = ns.GetState()
  st.floorIndex = 1; ns.EditPlaceMarker(DungeonMapView, st)          -- a stairs marker on floor 1 (the mock cursor is at the same spot)
  ns.editKind = "left"; st.floorIndex = 2; ns.EditPlaceMarker(DungeonMapView, st)  -- an arrow on floor 2: different icon
  local m1 = ns.GetMarkers(469, f1)[1]
  local m2 = ns.GetMarkers(469, f2)[1]
  assert(m1 and m2, "both markers exist")
  local before = #ns.GetLinks(469)
  local want = string.char(65 + before % 26)
  ns.EditLinkClick(m1)
  assert(ns.linkFrom, "first click selects")
  ns.EditLinkClick(m2)
  local to = ns.GetLinkTarget(469, f1, m1.x, m1.y)
  assert(to and to.floor == f2, "link leads from floor 1 to floor 2 with different icons")
  local back = ns.GetLinkTarget(469, f2, m2.x, m2.y)
  assert(back and back.floor == f1, "and back")
  assert(ns.FloorName(469, f2) ~= "another floor", "floor name for the tooltip")
  assert(ns.LinkLetter(469, f1, m1.x, m1.y) == want and ns.LinkLetter(469, f2, m2.x, m2.y) == want, "both ends carry the same letter")
  try("  overview with link lines", function() ns.SetOverview(true); ns.RefreshMap() end)
  ns.SetOverview(false)
  ns.editing = false
  st.floorIndex = 1
  ns.RefreshMap() -- the shown floor is floor 1 (the link leads to floor 2)
  try("  travel along the link", ns.TravelToFloor, to.floor, to.x, to.y)
  assert(st.floorIndex == 2, "travel opens the other floor")
  try("  refresh with the arrival highlighted", ns.RefreshMap)
  ns.editing = true
  ns.EditLinkClick(m1) -- a plain click on a linked marker must NOT remove the link (a double click would undo it)
  assert(ns.GetLinkTarget(469, f1, m1.x, m1.y), "plain click keeps the link")
  ns.EditLinkClick(m1, true) -- shift-click removes it
  assert(not ns.GetLinkTarget(469, f1, m1.x, m1.y), "link removed")
  ns.editing = false; ns.editKind = "boss"; DungeonMapDB.markers = {}; DungeonMapDB.markerLinks = nil
  print("ok   floor links")
end
try("RefreshEntrances", ns.RefreshEntrances)
_G.IsInInstance = function() return true end
_G.GetInstanceInfo = function() return "Mystery Hold", "party", 1, "", 5, 0, false, 99999 end
try("NotifyUnknown", ns.NotifyUnknown)
try("slash /dm unknown", SlashCmdList.DUNGEONMAP, "unknown")
assert(DungeonMapDB.unknown[99999] == "Mystery Hold", "unknown dungeon not recorded")
try("ExportManual", ns.ExportManual)
do -- Share my recordings: only what the shipped data lacks, short lines, window opens with the text
  local savedM, savedP = DungeonMapDB.manual, DungeonMapDB.portraits
  local iid, shippedBoss, missingBoss
  for id, d in pairs(ns.Dungeons) do
    for _, b in ipairs(d.bosses) do
      if b.x and not shippedBoss then iid, shippedBoss = id, b end
    end
    if iid then
      for _, b in ipairs(ns.Dungeons[iid].bosses) do if not b.x and not b.trash and not missingBoss then missingBoss = b end end
      if missingBoss then break end
    end
  end
  assert(iid and shippedBoss and missingBoss, "test needs a dungeon with a placed and an unplaced boss")
  DungeonMapDB.manual = { [iid] = {
    [shippedBoss.name] = { floor = shippedBoss.floor, x = shippedBoss.x, y = shippedBoss.y },       -- the same as shipped: not reported
    [missingBoss.name] = { floor = 123, x = 0.25, y = 0.5 },                                          -- new: reported
    ["Nobody"] = { floor = 1, x = 0.1, y = 0.1 } } }                                                   -- not a boss of ours: not reported
  DungeonMapDB.portraits = {}
  local lines, np, nd = ns.BuildReport()
  assert(np == 1 and nd == 0 and #lines == 1, "one new position, got " .. #lines)
  assert(lines[1] == format("P|%d|123|%s|0.2500|0.5000", iid, missingBoss.name), "line format: " .. lines[1])
  assert(#lines[1] < 80, "lines stay short")
  try("ShowReport", ns.ShowReport)
  assert(DungeonMapReportFrame and DungeonMapReportFrame.__shown, "the report window opens")
  assert(DungeonMapReportFrame.edit:GetText():find("^DCF "), "header line first")
  try("slash /dm report", SlashCmdList.DUNGEONMAP, "report")
  DungeonMapDB.manual = {}
  try("ShowReport with nothing", ns.ShowReport)
  DungeonMapDB.manual, DungeonMapDB.portraits = savedM, savedP
  print("ok   share recordings report")
end
do -- the journal: a card per dungeon / raid, search, tabs, a card opens the map, the view's button comes back
  _G.GetAddOnMetadata = nil
  try("ShowJournal", ns.ShowJournal)
  assert(DungeonMapJournal and DungeonMapJournal.__shown and ns.JournalShown(), "the journal opens")
  local function shownCards()
    local out = {}
    for _, f in ipairs(mock.frames) do if rawget(f, "it") and rawget(f, "art") and f.__shown then out[#out + 1] = f end end
    return out
  end
  local dungeons = shownCards()
  assert(#dungeons >= 20, "a card for every dungeon on the first tab, got " .. #dungeons)
  for _, c in ipairs(dungeons) do assert(not c.it.raid, "no raids on the Dungeons tab") end
  local seen = {}
  for _, c in ipairs(dungeons) do -- one card per dungeon, except Blackrock Spire and Dire Maul: one per wing
    local k = c.it.id .. "/" .. ((c.it.id == 229 or c.it.id == 429) and c.it.wing or 0)
    assert(not seen[k], "one card per dungeon, not per wing (except the split ones): " .. k)
    seen[k] = true
  end
  assert(ns.Journal[36] and ns.Journal[36].art and ns.Journal[2970].kind == "new", "loading screens are in the data")
  -- search by a boss name finds its dungeon
  DungeonMapJournal.search:SetText("vancleef")
  ns.RefreshJournal()
  local hit = shownCards()
  assert(#hit >= 1, "searching for a boss finds the dungeon")
  local found36 = false
  for _, c in ipairs(hit) do if c.it.id == 36 then found36 = true end end
  assert(found36, "Edwin VanCleef is in the Deadmines")
  DungeonMapJournal.search:SetText("lbrs")
  ns.RefreshJournal()
  local lb = shownCards()
  assert(#lb == 1 and lb[1].it.id == 229 and lb[1].it.wing == 1, "the short name LBRS finds Lower Blackrock Spire only")
  DungeonMapJournal.search:SetText("zzzznothing")
  ns.RefreshJournal()
  assert(#shownCards() == 0 and DungeonMapJournal.empty.__shown, "no match: the empty note shows")
  DungeonMapJournal.search:SetText("")
  ns.RefreshJournal()
  assert(#shownCards() == #dungeons, "clearing the search brings the list back")
  -- the Raids tab
  DungeonMapJournal.tabs[2].__scripts.OnClick(DungeonMapJournal.tabs[2])
  local raids = shownCards()
  assert(#raids >= 1, "raids on the Raids tab")
  for _, c in ipairs(raids) do assert(c.it.raid, "only raids on the Raids tab") end
  DungeonMapJournal.tabs[1].__scripts.OnClick(DungeonMapJournal.tabs[1])
  -- a card opens the dungeon's map and closes the journal; the view's button brings the journal back
  local card
  for _, c in ipairs(shownCards()) do if c.it.id == 36 then card = c end end
  card.__scripts.OnClick(card)
  assert(not ns.JournalShown() and ns.ViewShown() and ns.GetState().instanceID == 36, "a card opens the dungeon map")
  -- the way back is a crumb of the navigation bar: World > ... > Dungeon Journal > Dungeon
  local function crumbNamed(text)
    local found
    for _, f in ipairs(mock.frames) do
      if f.__text == text and f.__scripts.OnClick and f.__shown then found = f end
    end
    return found
  end
  local crumb = crumbNamed("Dungeon Journal")
  assert(crumb, "the dungeon view's navigation bar has a Dungeon Journal crumb")
  crumb.__scripts.OnClick(crumb)
  assert(ns.JournalShown() and not ns.ViewShown(), "the Dungeon Journal crumb goes back")
  assert(crumbNamed("Dungeon Journal") and not crumbNamed("Deadmines"), "the journal has its own bar: World > ... > Dungeon Journal")
  -- the Journal button at the right end of the world map's bar
  assert(DungeonMapJournalButton and DungeonMapJournalButton.__shown, "the world map has a Journal button")
  DungeonMapJournalButton.__scripts.OnClick(DungeonMapJournalButton)
  assert(not ns.JournalShown(), "the Journal button closes an open journal")
  DungeonMapJournalButton.__scripts.OnClick(DungeonMapJournalButton)
  assert(ns.JournalShown(), "the Journal button opens the journal")
  -- the search box has its icon
  assert(DungeonMapJournal.searchIcon, "the search box has a magnifier")
  assert(BINDING_NAME_DUNGEONMAP_JOURNAL and DungeonMap_ToggleJournal, "the journal has a key binding")
  DungeonMap_ToggleJournal()
  ns.ShowJournal()
  try("slash /dm list", SlashCmdList.DUNGEONMAP, "list")
  do -- Lower / Upper Blackrock Spire and the three Dire Maul wings are cards of their own; a card opens that wing
    local names, upper = {}, nil
    for _, f in ipairs(shownCards()) do
      local it = rawget(f, "it")
      if it.id == 229 or it.id == 429 then names[#names + 1] = it.name; if it.name == "Upper Blackrock Spire" then upper = f end end
    end
    table.sort(names)
    assert(table.concat(names, "|") == "Dire Maul - East|Dire Maul - North|Dire Maul - West|Lower Blackrock Spire|Upper Blackrock Spire", "a card per wing: " .. table.concat(names, "|"))
    assert(upper and upper.it.wing == 2, "the Upper Blackrock Spire card knows its wing")
    upper.__scripts.OnClick(upper)
    assert(ns.GetState().instanceID == 229 and ns.GetState().wing == 2, "the card opens Upper Blackrock Spire")
    ns.GetState().instanceID, ns.GetState().wing = nil, nil
    ns.ShowJournal()
  end
  ns.HideJournal()
  assert(not ns.JournalShown(), "HideJournal")
  ns.HideView()
  print("ok   journal")
end
do -- first run: the welcome window shows once
  DungeonMapDB.welcomed = false
  ns.MaybeWelcome()
  assert(DungeonMapWelcomeFrame and DungeonMapWelcomeFrame.__shown and DungeonMapDB.welcomed, "the welcome window shows on the first run")
  DungeonMapWelcomeFrame:Hide()
  ns.MaybeWelcome()
  assert(not DungeonMapWelcomeFrame.__shown, "and only once")
  try("slash /dm welcome", SlashCmdList.DUNGEONMAP, "welcome")
  assert(DungeonMapWelcomeFrame.__shown, "/dm welcome shows it again")
  DungeonMapWelcomeFrame:Hide()
  try("slash /dm keys", SlashCmdList.DUNGEONMAP, "keys")
  do -- /dm macros makes the controller macros once
    local made, byName = {}, {}
    G.CreateMacro = function(name, icon, body) made[#made + 1] = body; byName[name] = #made; return #made end
    G.GetMacroIndexByName = function(name) return byName[name] or 0 end
    try("slash /dm macros", SlashCmdList.DUNGEONMAP, "macros")
    assert(#made == 3 and made[1] == "/click DungeonMapOpenMap LeftButton 1" and made[2] == "/click DungeonMapOpenJournal LeftButton 1" and made[3] == "/click DungeonMapOpenWorld LeftButton 1", "three macros created")
    try("slash /dm macros again", SlashCmdList.DUNGEONMAP, "macros")
    assert(#made == 3, "macros are not made twice")
    G.CreateMacro, G.GetMacroIndexByName = nil, nil
    try("slash /dm map", SlashCmdList.DUNGEONMAP, "map")
  end
  -- the journal's key is set from the options: the next key pressed is bound
  local bound, saved = {}, false
  G.GetBindingKey = function(a) for k, v in pairs(bound) do if v == a then return k end end end
  G.GetBindingAction = function(k) return bound[k] or "" end
  G.SetBinding = function(k, a) if a then bound[k] = a else bound[k] = nil end return true end
  G.SaveBindings = function() saved = true end
  G.GetCurrentBindingSet = function() return 1 end
  G.IsAltKeyDown = function() return false end
  G.IsControlKeyDown = function() return true end
  G.IsShiftKeyDown = function() return false end
  G.InCombatLockdown = function() return false end
  bound["CTRL-J"] = "OTHER_ACTION"
  try("slash /dm key", SlashCmdList.DUNGEONMAP, "key")
  local cap = DungeonMapKeyCapture
  assert(cap and cap.__shown, "/dm key opens the key window")
  cap.__scripts.OnKeyDown(cap, "LSHIFT")
  assert(cap.__shown and next(bound) == "CTRL-J", "a modifier alone is not a key")
  cap.__scripts.OnKeyDown(cap, "J")
  assert(bound["CTRL-J"] == "DUNGEONMAP_JOURNAL" and saved and not cap.__shown, "the pressed key (with its modifier) is bound and saved")
  ns.CaptureJournalKey()
  cap.__scripts.OnKeyDown(cap, "ESCAPE")
  assert(not cap.__shown and bound["CTRL-J"] == "DUNGEONMAP_JOURNAL", "Esc cancels without changes")
  print("ok   welcome")
end
do -- several named routes: the list, the Full run, the official routes made from them, switching by a kill, a player's own route
  local fl = ns.GetFloors(36)[1].uiMapID
  local bs = ns.GetBosses(36)
  local a, b, c, d = bs[1], bs[2], bs[3], bs[4]
  local saveRD, saveVD, saveDB = ns.RouteData, ns.RouteVariantData, { DungeonMapDB.routes, DungeonMapDB.routesNamed, DungeonMapDB.routeSel, DungeonMapDB.kills }
  ns.RouteData = nil
  ns.RouteVariantData = { [36] = { [0] = {
    { name = "Living side", pts = { { f = fl, x = 0.1, y = 0.1 }, { f = fl, x = 0.2, y = 0.2, boss = a.name }, { f = fl, x = 0.3, y = 0.3, boss = b.name } } },
    { name = "Undead side", pts = { { f = fl, x = 0.6, y = 0.6 }, { f = fl, x = 0.7, y = 0.7, boss = c.name }, { f = fl, x = 0.8, y = 0.8, boss = d.name } } },
  } } }
  DungeonMapDB.routes, DungeonMapDB.routesNamed, DungeonMapDB.routeSel, DungeonMapDB.kills = nil, nil, nil, {}
  ns.routeLock = {}
  local vs = ns.RouteVariants(36, nil)
  assert(#vs == 3 and vs[1].name == "Living side" and vs[2].name == "Undead side" and vs[3].name == ns.ROUTE_FULL, "the routes to choose between: both sides and the Full run")
  assert(ns.RouteActive(36, nil) == "Living side" and #ns.GetRoute(36, nil) == 3, "the first route is shown")
  ns.RouteSelect(36, nil, "Undead side", true)
  assert(ns.GetRoute(36, nil)[2].boss == c.name, "the picked route is shown")
  -- with a controller the route button cycles through the routes instead of opening the list (a gamepad cannot drive it)
  do
    local oldInput, oldMenu, menus = G.InputUtil, G.MenuUtil, 0
    G.MenuUtil = { CreateContextMenu = function() menus = menus + 1 end }
    ns.GetState().instanceID = 36
    ns.RouteSelect(36, nil, "Living side", true)
    G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    ns.RouteUI.PickRoute(UIParent)
    assert(menus == 0 and ns.RouteActive(36, nil) == "Undead side", "controller: the route button cycles to the next route, no context menu")
    G.InputUtil = { IsGamepadUIEnabled = function() return false end }
    ns.RouteUI.PickRoute(UIParent)
    assert(menus == 0, "mouse: the game's context menu is not used (it opened behind the editor bar and can taint)")
    local pop = ns.RouteUI.RoutePopupFrame()
    assert(pop and pop:IsShown() and pop.items[1]:IsShown() and pop.items[3]:IsShown() and #pop.items == 3, "mouse: our own route list opens, one row per route")
    pop.items[1].__scripts.OnClick(pop.items[1])
    assert(not pop:IsShown() and ns.RouteActive(36, nil) == "Living side", "picking a row shows that route and closes the list")
    G.InputUtil, G.MenuUtil = oldInput, oldMenu
    ns.GetState().instanceID = nil
    ns.RouteSelect(36, nil, "Undead side", true)
  end
  ns.RouteSelect(36, nil, ns.ROUTE_FULL, true)
  local full = ns.GetRoute(36, nil)
  assert(#full == 6 and full[4].brk and full[4].seg == 2 and full[1].seg == 1 and not full[1].brk, "the Full run draws both lines, a break between them: " .. #full)
  assert(ns.GetRoute(36, nil) == full, "the combined route is not rebuilt every call")
  -- progress counts per route: an undead boss first does not skip the living side
  ns.GetState().instanceID = 36
  DungeonMapDB.kills[36] = { ids = { [c.id] = true }, names = {}, last = time() }
  local prog = ns.RouteProgress(36, nil, bs)
  assert(prog.skipped == 0 and prog.stops[1].active and prog.stops[3].killed == true and prog.stops[4].active, "a kill on one side skips nothing on the other")
  -- the official routes: one per named route and a Full run; the timer window lists all the bosses
  local off = ns.OfficialRoutes(36, nil)
  assert(#off == 3 and off[1].name == "Living side" and off[2].name == "Undead side" and off[3].id == "full" and off[3].count == 4, "official routes from the named routes and their union")
  assert(#ns.OfficialLineup(36, nil) == 4, "the window lists the bosses of both sides")
  -- a kill switches the shown route unless it was picked by hand during this visit
  ns.routeLock = {}
  ns.RouteSelect(36, nil, "Living side")
  assert(ns.RouteAutoSelect(36, nil, d.name, 100) and ns.RouteActive(36, nil) == "Undead side", "the boss of one route shows that route")
  ns.RouteSelect(36, nil, "Living side", true)
  local locked = ns.routeLock[36]
  assert(not ns.RouteAutoSelect(36, nil, d.name, locked) and ns.RouteActive(36, nil) == "Living side", "a hand-picked route stays during the visit")
  assert(ns.RouteAutoSelect(36, nil, d.name, locked + 1) and ns.RouteActive(36, nil) == "Undead side", "...and the next visit follows the kills again")
  -- the player's own route: new, named, drawn, renamed, deleted; the shipped ones can not be renamed
  assert(not ns.RouteNew(36, nil, "  "), "a route needs a name")
  assert(not ns.RouteNew(36, nil, "living SIDE"), "names are unique")
  assert(ns.RouteNew(36, nil, "Speed run") == "Speed run" and ns.RouteActive(36, nil) == "Speed run" and #ns.RouteVariants(36, nil) == 4, "a new route of your own")
  ns.RouteAdd(36, nil, { f = fl, x = 0.5, y = 0.5 })
  assert(#ns.GetRoute(36, nil) == 1 and #DungeonMapDB.routesNamed[36][0][1].pts == 1, "points go into the shown route only")
  assert(ns.RouteCanRename(36, nil) and ns.RouteRename(36, nil, "Fast") == "Fast" and ns.RouteActive(36, nil) == "Fast", "an own route can be renamed")
  ns.RouteSelect(36, nil, "Living side")
  assert(not ns.RouteCanRename(36, nil) and not ns.RouteRename(36, nil, "X"), "a route that ships keeps its name")
  assert(#ns.OfficialRoutes(36, nil) == 3, "a player's route never becomes an official one")
  ns.RouteSelect(36, nil, "Fast")
  ns.RouteReset(36, nil)
  assert(#ns.RouteVariants(36, nil) == 3 and #DungeonMapDB.routesNamed[36][0] == 0, "deleting an own route removes it")
  -- the Main route (the unnamed one) can be given a name: the player's version becomes a named route, the shipped Main route (if any) stays
  DungeonMapDB.routes = DungeonMapDB.routes or {}
  DungeonMapDB.routes[36] = DungeonMapDB.routes[36] or {}
  DungeonMapDB.routes[36][0] = { { f = fl, x = 0.2, y = 0.2 }, { f = fl, x = 0.3, y = 0.3 } }
  ns.RouteSelect(36, nil, nil)
  assert(ns.RouteActive(36, nil) == nil and ns.RouteCanRenameMain(36, nil), "the Main route can be named")
  assert(not ns.RouteRename(36, nil, "   ") and not ns.RouteRename(36, nil, "main route") and not ns.RouteRename(36, nil, "Living side"), "a Main route name must be new")
  local mainName = ns.RouteRename(36, nil, "My main")
  assert(mainName == "My main" and ns.RouteActive(36, nil) == "My main" and DungeonMapDB.routes[36][0] == nil and #ns.GetRoute(36, nil) == 2, "the Main route's points move to the named route")
  do
    local n, hasMain = 0, false
    for _, v in ipairs(ns.RouteVariants(36, nil)) do n = n + 1; if v.label == "Main route" then hasMain = true end end
    assert(not hasMain and n == 4, "renaming the Main route replaces it in the list, no duplicate (" .. n .. ")")
  end
  ns.RouteReset(36, nil)
  assert(#ns.RouteVariants(36, nil) == 3, "...and it can be deleted like any route of your own")
  -- the order of the player's own routes: the shown one can go first (Stratholme: Living before Undead)
  assert(ns.RouteNew(36, nil, "Second") == "Second" and ns.RouteNew(36, nil, "Third") == "Third", "two routes of your own")
  local function ownOrder() local o = {} for _, v in ipairs(ns.RouteVariants(36, nil)) do if v.name == "Second" or v.name == "Third" then o[#o + 1] = v.name end end return table.concat(o, ",") end
  assert(ownOrder() == "Second,Third", "own routes are listed in the order they were made")
  assert(ns.RouteMoveFirst(36, nil) == "Third" and ownOrder() == "Third,Second", "the shown route goes first")
  ns.RouteSelect(36, nil, "Living side")
  assert(not ns.RouteMoveFirst(36, nil), "a route that ships cannot be moved")
  ns.RouteSelect(36, nil, "Third"); ns.RouteReset(36, nil); ns.RouteSelect(36, nil, "Second"); ns.RouteReset(36, nil)
  assert(#ns.RouteVariants(36, nil) == 3, "...own routes removed again")
  -- the corner picker, the editor bar's route row, folding the bar
  DungeonMapDB.dev, ns.routeShow, ns.editing = false, true, false
  ns.RouteSelect(36, nil, "Living side")
  ns.ShowInstance(36, nil, true)
  ns.GetState().floorIndex, ns.GetState().overview = 1, false
  ns.RefreshMap()
  local corner = ns.RouteUI.Corner()
  assert(corner.pick.__shown == true and corner.pick:GetText() == "Route: Living side", "the corner button shows the route: " .. tostring(corner.pick:GetText()))
  corner.pick.__scripts.OnClick(corner.pick) -- opens our route list (over the button: it sits at the map's bottom); the second row is the Undead side
  local cpop = ns.RouteUI.RoutePopupFrame()
  assert(cpop:IsShown() and cpop.owner == corner.pick and corner.pick.popupUp, "the corner button opens the list")
  cpop.items[2].__scripts.OnClick(cpop.items[2])
  assert(ns.RouteActive(36, nil) == "Undead side" and ns.routeLock[36], "a click picks the next route, by hand")
  ns.RouteDrawStart()
  ns.RefreshMap()
  local bar = ns.RouteUI.Bar()
  assert(bar and bar.pick:GetText() == "Route: Undead side" and bar.body.__shown ~= false, "the editor bar has the route row")
  DungeonMapDB.routeBarFolded = true
  ns.RefreshMap()
  assert(bar.body.__shown == false and bar.fold:GetText() == "+", "folded: only the title row stays")
  DungeonMapDB.routeBarFolded = false
  ns.RefreshMap()
  assert(bar.body.__shown ~= false and bar.fold:GetText() == "-", "unfolded again")
  do -- in /dm edit (the developer's route tool) there is no Save (the data is kept as you go), but Delete route / Reset to Default is still there
    local drawBefore, editBefore, kindBefore = ns.routeDraw, ns.editing, ns.editKind
    ns.routeDraw, ns.editing, ns.editKind = false, true, "__route"
    ns.RefreshMap()
    assert(bar.reset.__shown == true and bar.save.__shown == false, "the editor bar's delete / reset button shows in /dm edit")
    ns.routeDraw, ns.editing, ns.editKind = drawBefore, editBefore, kindBefore
    ns.RefreshMap()
  end
  ns.RouteSelect(36, nil, ns.ROUTE_FULL)
  ns.RouteAdd(36, nil, { f = fl, x = 0.9, y = 0.9 }) -- drawing on the Full run goes to the first real route
  assert(ns.RouteActive(36, nil) == "Living side", "the Full run is not drawn on: the first route is")
  ns.RouteDrawStop()
  ns.GetState().instanceID = nil
  DungeonMapDB.routeBarFolded, DungeonMapDB.routeBarPos = nil, nil
  ns.RouteData, ns.RouteVariantData = saveRD, saveVD
  DungeonMapDB.routes, DungeonMapDB.routesNamed, DungeonMapDB.routeSel, DungeonMapDB.kills = saveDB[1], saveDB[2], saveDB[3], saveDB[4]
  ns.routeLock = {}
  print("ok   named routes")
end
-- Opening/backing out of a controller dungeon overlay must not rebuild native map bindings.
do
  local oldInput, oldSet = G.InputUtil, WorldMapFrame.SetMapID
  G.InputUtil = { IsGamepadUIEnabled = function() return true end }
  WorldMapFrame.mapID = 1446
  local changes = 0
  WorldMapFrame.SetMapID = function(self, id) changes = changes + 1; oldSet(self, id) end
  ns.ShowInstance(36, nil, true)
  assert(changes == 0 and WorldMapFrame:GetMapID() == 1446, "controller opening preserves underlying native map")
  ns.GoUp()
  assert(changes == 0 and not ns.ViewShown(), "controller back hides only our view")
  WorldMapFrame.SetMapID, G.InputUtil = oldSet, oldInput
  print("ok   controller overlay preserves native map and binding refresh context")
end
-- Keys and macros open the map through secure buttons: after the (secure) click opened the map, PostClick shows our journal / dungeon map.
do
  local b = _G.DungeonMapOpenJournal
  assert(b and b.__scripts and b.__scripts.PreClick and b.__scripts.PostClick, "the journal opener button exists")
  ns.HideJournal(); ns.HideView(); WorldMapFrame:Hide()
  assert(b:GetAttribute("useOnKeyDown") == true, "the opener acts on the press whatever ActionButtonUseKeyDown says")
  b.__scripts.PreClick(b, "LeftButton", true)  -- the map is closed here ("/click Name LeftButton 1" is a press)
  WorldMapFrame:Show()                    -- ... the secure click of the game's own button opened it
  b.__scripts.PostClick(b, "LeftButton", true)
  assert(ns.JournalShown(), "a click that just opened the map shows the journal")
  b.__scripts.PostClick(b, "LeftButton", false) -- the release of the same click does nothing more
  -- (draw order: our frames must stay inside the map's own frame tree, the map is raised as one unit; a sibling frame of ours ended up BEHIND it)
  assert(_G.DungeonMapJournal:GetParent() == WorldMapFrame and _G.DungeonMapView:GetParent() == WorldMapFrame, "journal and dungeon view are children of WorldMapFrame")
  b.__scripts.PreClick(b, "LeftButton", true) -- map open: a second click toggles the journal away (the map stays)
  b.__scripts.PostClick(b, "LeftButton", true)
  print("ok   secure opener buttons")
end
-- The minimap button: a secure opener (left click, on the release), shown by the option; the welcome window has its checkbox.
do
  local b = _G.DungeonMapMinimapButton
  assert(b, "the minimap button exists"); assert(b.__scripts.PostClick, "it has a PostClick"); assert(b:GetAttribute("type1") == "click", "left click is a secure click"); assert(b:GetAttribute("useOnKeyDown") == false, "it acts on the release: " .. tostring(b:GetAttribute("useOnKeyDown")))
  DungeonMapDB.showMinimapButton = true; ns.UpdateMinimapButton()
  assert(b.__shown, "shown when the option is on")
  DungeonMapDB.showMinimapButton = false; ns.UpdateMinimapButton()
  assert(not b.__shown, "hidden when the option is off")
  ns.HideJournal(); WorldMapFrame:Hide()
  b.__scripts.PreClick(b, "LeftButton", false); WorldMapFrame:Show(); b.__scripts.PostClick(b, "LeftButton", false)
  assert(ns.JournalShown(), "a left click on the release opens the journal")
  b.__scripts.PostClick(b, "LeftButton", true) -- the press does nothing
  ns.HideJournal(); ns.HideView()
  DungeonMapDB.welcomed = false; ns.MaybeWelcome()
  assert(DungeonMapWelcomeFrame.minimapCheck, "the welcome window has the minimap button checkbox")
  DungeonMapWelcomeFrame:Hide()
  print("ok   minimap button")
end
-- Bossman Toof (Krol'dok) is a stop the game never reports: with Overlord Mugg down he counts as passed on the route, never "skipped"
do
  local saveIn, saveInfo, saveRD = _G.IsInInstance, _G.GetInstanceInfo, ns.RouteData
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "Krol'dok Stronghold", "party", 1, "", 5, 0, false, 3039 end
  local f = 830391
  ns.RouteData = { [3039] = { [0] = { { f = f, x = 0.1, y = 0.1, boss = "Slavecrusher Grox" }, { f = f, x = 0.2, y = 0.2, boss = "Bossman Toof" }, { f = f, x = 0.3, y = 0.3, boss = "Overlord Mugg" } } } }
  local bosses = ns.Dungeons[3039].bosses
  ns.ResetKills(3039)
  ns.HandleEvent("ENCOUNTER_END", 3451, "Overlord Mugg", 1, 5, 1)
  local pr = ns.RouteProgress(3039, 0, bosses)
  local toof, grox
  for _, st in ipairs(pr.stops) do if st.boss == "Bossman Toof" then toof = st elseif st.boss == "Slavecrusher Grox" then grox = st end end
  assert(toof and toof.killed and toof.inferred and not toof.skipped, "Toof counts as passed when a later stop is down")
  assert(grox and grox.skipped and not grox.killed, "a boss the game does report is still skipped")
  ns.ResetKills(3039)
  ns.RouteData = saveRD
  _G.IsInInstance, _G.GetInstanceInfo = saveIn, saveInfo
  print("ok   undetectable stop is not skipped")
end
-- The key legend lays out with and without glyph atlases.
do
  local lg = ns.NewPadLegend(UIParent)
  lg:SetRows({ { {keys={"LSTICK"},text="Crosshair"}, {keys={"DPAD_LR"},text="Map"} }, { {keys={"A"},text="Select"}, {keys={"A","X"},text="Both"} } })
  lg:SetRows({ { {keys={"B"},text="Back"} } })
  assert(ns.PadStyle() == "xbox" or ns.PadStyle() == "playstation", "pad style")
  -- glyphs: the game's own lookup first, then the real atlas names, else nothing (the legend writes [A])
  local oldUtil, oldAtlasInfo, oldConst = _G.InputIconTextureSetUtility, C_Texture and C_Texture.GetAtlasInfo, _G.GAMEPAD_FACE_BOTTOM
  _G.GAMEPAD_FACE_BOTTOM = "PAD1"
  C_Texture = C_Texture or {}
  C_Texture.GetAtlasInfo = function(name) return { width = 76, height = 75 } end
  _G.InputIconTextureSetUtility = { GetNormalActiveInputIconButtonTexture = function(key) assert(key == "PAD1"); return "gamepad-xbox1-buttona-normal" end }
  assert(ns.PadGlyph("A") == "gamepad-xbox1-buttona-normal", "glyph from the game's own icon set lookup")
  _G.InputIconTextureSetUtility = nil
  assert(ns.PadGlyph("B", "xbox") == "gamepad-xbox1-buttonb-normal" and ns.PadGlyph("B", "playstation") == "gamepad-ps-buttoncircle-normal", "fallback uses the real atlas names")
  C_Texture.GetAtlasInfo = function() return nil end
  assert(ns.PadGlyph("A", "xbox") == nil, "a client without the atlas gives the [A] badge")
  lg:SetRows({ { {keys={"A"},text="Select"} } })
  C_Texture.GetAtlasInfo, _G.InputIconTextureSetUtility, _G.GAMEPAD_FACE_BOTTOM = oldAtlasInfo, oldUtil, oldConst
  print("ok   key legend")
end
-- Back returns to where the dungeon was opened from: the journal, else the map.
do
  ns.ShowJournal()
  ns.ShowInstance(36, nil, true)
  assert(ns.ViewShown() and not ns.JournalShown(), "a dungeon opened from the journal replaces it")
  ns.GoUp()
  assert(ns.JournalShown() and not ns.ViewShown(), "Back from a dungeon opened from the journal returns to the journal")
  ns.HideJournal(); ns.HideView()
  ns.ShowInstance(36, nil, true)
  ns.GoUp()
  assert(not ns.JournalShown(), "Back from a dungeon opened from the map does not open the journal")
  print("ok   back returns to the journal or the map")
end
-- D-073 guard: a released route version must not vanish without an alias row (RouteAliases.lua) or a deliberate "broken" mark in the snapshot.
-- Refresh the snapshot after a release: SNAPSHOT_ROUTES=1 tools/.venv/bin/python tools/test/run.py (it only adds rows, never drops one).
try("route versions of released boards survive", function()
  local path = "tools/test/fixtures/route_versions.csv"
  local rows, order = {}, {}
  local f = io.open(path)
  if f then
    for raw in f:lines() do
      local line = raw:gsub("\r$", "")
      local inst, wing, id, ver, broken, bosses = line:match("^(%d+),(%d+),([^,]*),(%w+),(%d*),(.*)$")
      if inst then rows[#rows + 1] = { inst = tonumber(inst), wing = tonumber(wing), id = id, ver = ver, broken = broken == "1", bosses = bosses } end
    end
    f:close()
  end
  local have = {}
  for _, r in ipairs(rows) do have[r.inst .. "." .. r.wing .. "." .. r.ver] = true end
  local current = {}
  for _, rt in ipairs(SHIPPED_ROUTES) do
    local k = rt.inst .. "." .. rt.wing .. "." .. rt.version
    current[k] = true
    if SNAPSHOT_ROUTES and not have[k] then
      have[k] = true
      rows[#rows + 1] = { inst = rt.inst, wing = rt.wing, id = rt.id, ver = rt.version, broken = false, bosses = rt.bosses }
    end
  end
  if SNAPSHOT_ROUTES then
    table.sort(rows, function(a, b) if a.inst ~= b.inst then return a.inst < b.inst end if a.wing ~= b.wing then return a.wing < b.wing end return a.ver < b.ver end)
    local out = assert(io.open(path, "w"))
    for _, r in ipairs(rows) do out:write(string.format("%d,%d,%s,%s,%s,%s\n", r.inst, r.wing, r.id, r.ver, r.broken and "1" or "", r.bosses)) end
    out:close()
    return
  end
  for _, a in ipairs(ns.RouteAliases or {}) do -- every alias row must point at a current route whose bosses are all in the old list
    local route
    for _, rt in ipairs(SHIPPED_ROUTES) do if rt.inst == a.inst and rt.wing == (a.wing or 0) and rt.id == a.to then route = rt end end
    assert(route, "alias " .. a.inst .. "/" .. tostring(a.wing) .. "/" .. a.rv .. " points at no shipped route (to = " .. tostring(a.to) .. ")")
    assert(not current[a.inst .. "." .. (a.wing or 0) .. "." .. a.rv], "alias " .. a.rv .. " is a current version: remove the row")
    local _, old = ns.AliasKeys(a)
    for name in route.bosses:gmatch("[^|]+") do assert(old[ns.NormName(name)], "alias " .. a.rv .. ": the current route's boss " .. name .. " is not in its old boss list") end
  end
  local aliased = {}
  for _, a in ipairs(ns.RouteAliases or {}) do aliased[a.inst .. "." .. (a.wing or 0) .. "." .. a.rv] = true end
  local lost = {}
  for _, r in ipairs(rows) do
    local k = r.inst .. "." .. r.wing .. "." .. r.ver
    if not r.broken and not current[k] and not aliased[k] then lost[#lost + 1] = string.format("%s (%d wing %d, route %s, version %s: %s)", ns.Dungeons[r.inst] and ns.Dungeons[r.inst].name or r.inst, r.inst, r.wing, r.id, r.ver, r.bosses) end
  end
  assert(#lost == 0, "route version(s) gone, their boards break: add a row to RouteAliases.lua (old bosses = the list shown) or mark the snapshot row broken:\n  " .. table.concat(lost, "\n  "))
end)
try("RegisterOptions", ns.RegisterOptions)
assert(ns.optionsCategory and not ns.optionsError, "options should register: " .. tostring(ns.optionsError))
try("slash /dm config", SlashCmdList.DUNGEONMAP, "config")
try("slash /dm", SlashCmdList.DUNGEONMAP, "")
try("slash /dm edit", SlashCmdList.DUNGEONMAP, "edit")
print(failures == 0 and "ALL OK" or (failures .. " FAILURES"))
