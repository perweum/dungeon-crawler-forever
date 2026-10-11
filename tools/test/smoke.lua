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
local order = { "Data/Art.lua", "Data/ArtForever.lua", "Data/ArtCustom.lua", "Data/Dungeons.lua", "Data/Entrances.lua", "Data/Loot.lua", "Data/Rares.lua", "Data/Abilities.lua", "Data/Wings.lua", "Data/Markers.lua", "Core.lua", "Model.lua", "UI/View.lua", "UI/Overview.lua", "UI/Entrances.lua", "UI/Options.lua", "UI/Edit.lua", "Commands.lua" }
for _, p in ipairs(order) do loadAddonFile("addon/DungeonCrawlerForever/" .. p) end

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
  assert(#ns.GetFloors(229, 1) == 6 and #ns.GetFloors(229, 2) == 3, "LBRS 6 maps, UBRS 3 bundled maps")
  assert(ns.GetFloors(229, 2)[3].name == "Blackrock Stadium" and ns.GetFloors(229, 2)[1].custom, "UBRS floors are the bundled custom maps")
  for _, b in ipairs(u) do assert(b.x == nil, "UBRS bosses have no pin until recorded on a UBRS map: " .. b.name) end
  print("ok   wings: LBRS " .. #l .. " bosses / 6 maps, UBRS " .. #u .. " bosses / 3 maps")
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
local ml = ns.GetMarkers(36, art36.uiMapID)
assert(#ml == 1 and ml[1].db and ml[1].kind == "exit", "marker should be listed")
try("RefreshMap with marker", ns.RefreshMap)
ns.RemoveMarker(ml[1]) ; assert(#ns.GetMarkers(36, art36.uiMapID) == 0, "marker removed")
ns.editing = false ; ns.editKind = "boss"
print("ok   overview, strip, markers")
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
try("RefreshEntrances", ns.RefreshEntrances)
_G.IsInInstance = function() return true end
_G.GetInstanceInfo = function() return "Mystery Hold", "party", 1, "", 5, 0, false, 99999 end
try("NotifyUnknown", ns.NotifyUnknown)
try("slash /dm unknown", SlashCmdList.DUNGEONMAP, "unknown")
assert(DungeonMapDB.unknown[99999] == "Mystery Hold", "unknown dungeon not recorded")
try("ExportManual", ns.ExportManual)
try("RegisterOptions", ns.RegisterOptions)
assert(ns.optionsCategory and not ns.optionsError, "options should register: " .. tostring(ns.optionsError))
try("slash /dm config", SlashCmdList.DUNGEONMAP, "config")
try("slash /dm", SlashCmdList.DUNGEONMAP, "")
try("slash /dm edit", SlashCmdList.DUNGEONMAP, "edit")
print(failures == 0 and "ALL OK" or (failures .. " FAILURES"))
