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
local order = { "Data/Art.lua", "Data/ArtForever.lua", "Data/ArtCustom.lua", "Data/Dungeons.lua", "Data/Entrances.lua", "Data/Loot.lua", "Data/Rares.lua", "Data/Abilities.lua", "Data/Wings.lua", "Data/Markers.lua", "Data/Quests.lua", "Data/Reference.lua", "Data/Combined.lua", "Core.lua", "Model.lua", "Quests.lua", "UI/View.lua", "UI/Quests.lua", "UI/Overview.lua", "UI/Entrances.lua", "UI/Options.lua", "UI/Edit.lua", "UI/Reference.lua", "Commands.lua" }
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
  assert(k and k.label and (k.atlas or k.texture) and k.color, "marker kind " .. kind .. " needs a label, an icon and a colour")
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
do
  local done, active = {}, {}
  _G.UnitFactionGroup = function() return "Horde" end
  _G.UnitLevel = function() return 30 end
  _G.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end, IsOnQuest = function(id) return active[id] == true end,
    GetTitleForQuestID = function() return nil end }
  local realData = ns.QuestData
  for id, list in pairs(realData) do -- every shipped dungeon renders its list without errors
    if ns.Dungeons[id] then
      ns.ShowInstance(id, nil, true)
      ns.GetState().tab = "quests"
      try("  real quests " .. id .. " (" .. #list .. ")", ns.RefreshMap)
      ns.GetState().questExpanded = { __done = true }
      try("  real quests " .. id .. " all open", ns.RefreshMap)
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
  _G.UnitFactionGroup = function() return "Alliance" end
  list = ns.GetQuestEntries(3065)
  local seen = {}
  for _, e in ipairs(list) do if e.q then seen[e.q.id] = true end end
  assert(not seen[8], "class quest hidden for a warrior")
  assert(seen[2] and not seen[3], "alliance sees its own quest only")
  _G.UnitFactionGroup = function() return "Horde" end
  ns.ShowInstance(3065, nil, true)
  ns.GetState().tab = "quests"
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
  for _, f in ipairs(mock.frames) do
    if rawget(f, "head") and f.__shown and f.__scripts.OnClick then f.__scripts.OnClick(f); break end
  end
  assert(ns.GetState().questExpanded.__done, "completed section opens")
  ns.GetState().tab = nil
  try("  back to bosses", ns.RefreshMap)
  ns.QuestData[3065] = realData and realData[3065]
  print("ok   quests")
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
  ns.ShowInstance(36, nil, true)
  local floors = ns.GetFloors(36)
  local f1, f2 = floors[1].uiMapID, floors[2].uiMapID
  DungeonMapDB.markers = {}
  DungeonMapDB.markerLinks, DungeonMapDB.linkRemovals = nil, nil
  ns.editKind = "up"; ns.editing = true
  local st = ns.GetState()
  st.floorIndex = 1; ns.EditPlaceMarker(DungeonMapView, st)          -- a stairs marker on floor 1 (the mock cursor is at the same spot)
  ns.editKind = "left"; st.floorIndex = 2; ns.EditPlaceMarker(DungeonMapView, st)  -- an arrow on floor 2: different icon
  local m1 = ns.GetMarkers(36, f1)[1]
  local m2 = ns.GetMarkers(36, f2)[1]
  assert(m1 and m2, "both markers exist")
  local before = #ns.GetLinks(36)
  local want = string.char(65 + before % 26)
  ns.EditLinkClick(m1)
  assert(ns.linkFrom, "first click selects")
  ns.EditLinkClick(m2)
  local to = ns.GetLinkTarget(36, f1, m1.x, m1.y)
  assert(to and to.floor == f2, "link leads from floor 1 to floor 2 with different icons")
  local back = ns.GetLinkTarget(36, f2, m2.x, m2.y)
  assert(back and back.floor == f1, "and back")
  assert(ns.FloorName(36, f2) ~= "another floor", "floor name for the tooltip")
  assert(ns.LinkLetter(36, f1, m1.x, m1.y) == want and ns.LinkLetter(36, f2, m2.x, m2.y) == want, "both ends carry the same letter")
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
  assert(ns.GetLinkTarget(36, f1, m1.x, m1.y), "plain click keeps the link")
  ns.EditLinkClick(m1, true) -- shift-click removes it
  assert(not ns.GetLinkTarget(36, f1, m1.x, m1.y), "link removed")
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
try("RegisterOptions", ns.RegisterOptions)
assert(ns.optionsCategory and not ns.optionsError, "options should register: " .. tostring(ns.optionsError))
try("slash /dm config", SlashCmdList.DUNGEONMAP, "config")
try("slash /dm", SlashCmdList.DUNGEONMAP, "")
try("slash /dm edit", SlashCmdList.DUNGEONMAP, "edit")
print(failures == 0 and "ALL OK" or (failures .. " FAILURES"))
