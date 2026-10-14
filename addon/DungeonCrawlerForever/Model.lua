-- Data access: which dungeons exist, which floors they have, which bosses (and where) for a difficulty.
local _, ns = ...

-- Wings: one instance map shared by several dungeons the game's finder lists separately.
function ns.GetWings(instanceID) return ns.Wings and ns.Wings[instanceID] end
function ns.WingInfo(instanceID, wing)
    local w = ns.GetWings(instanceID)
    if not w then return nil end
    for _, x in ipairs(w) do
        if x.wing == wing then return x end
    end
end
-- Wing to show when the caller does not say: the one used last, else the first.
function ns.PickWing(instanceID)
    if not ns.GetWings(instanceID) then return nil end
    local last = DungeonMapDB and DungeonMapDB.lastWing and DungeonMapDB.lastWing[instanceID]
    return (last and ns.WingInfo(instanceID, last)) and last or ns.GetWings(instanceID)[1].wing
end
-- Name shown for an instance (+ wing).
function ns.DungeonTitle(instanceID, wing)
    local w = wing and ns.WingInfo(instanceID, wing)
    return w and w.name or ns.Dungeons[instanceID].name
end
-- Level data for an instance (+ wing): a table with recMin / recMax / minLevel.
function ns.LevelData(instanceID, wing)
    local d, w = ns.Dungeons[instanceID], wing and ns.WingInfo(instanceID, wing)
    if w then return { recMin = w.recMin, recMax = w.recMax, minLevel = d.minLevel } end
    return d
end

function ns.LevelLabel(d)
    if d.recMin and d.recMax then return format("%d-%d", d.recMin, d.recMax) end
    if d.minLevel then return tostring(d.minLevel) .. "+" end
    return ""
end

-- Colour for a level range against the player's level (same grey/green/yellow/orange/red scale as quest levels).
function ns.LevelColor(d)
    local lvl = (d.recMin and d.recMax) and (d.recMin + d.recMax) / 2 or d.minLevel
    if lvl and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(lvl)
        if type(c) == "table" and c.r then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

-- All instances: dungeons ordered by level then name, followed by raids ordered by name.
function ns.GetDungeonList()
    local list = {}
    local db = DungeonMapDB or {}
    for id, d in pairs(ns.Dungeons) do
      local hidden = d.raid and (db.showRaids == false or (d.status == "classic" and db.showClassicRaids == false))
      if not hidden then
        local wings = ns.GetWings(id)
        if wings then
            for _, w in ipairs(wings) do
                local data = ns.LevelData(id, w.wing)
                list[#list + 1] = { id = id, wing = w.wing, name = w.name, hasArt = d.hasArt and ns.GetFloors(id, w.wing) ~= nil, raid = d.raid, status = d.status,
                    minLevel = d.minLevel, recMin = w.recMin, maxLevel = w.recMax, level = ns.LevelLabel(data), data = data }
            end
        else
            list[#list + 1] = { id = id, name = d.name, hasArt = d.hasArt, raid = d.raid, status = d.status, minLevel = d.minLevel,
                recMin = d.recMin, maxLevel = d.recMax, level = ns.LevelLabel(d), data = d }
        end
      end
    end
    table.sort(list, function(a, b)
        if a.raid ~= b.raid then return not a.raid end
        local la, lb = a.recMin or a.minLevel or 999, b.recMin or b.minLevel or 999
        if la ~= lb and not a.raid then return la < lb end
        return a.name < b.name
    end)
    return list
end

-- Floors of an instance; for a wing with its own floor list (Scarlet Monastery's four wings, Dire Maul) only those.
-- A combined map (Data/Combined.lua) is offered as one more floor, the last one: pieces of the dungeon's own floor art on one big map.
local function withCombined(instanceID, floors)
    local c = ns.Combined and ns.Combined[instanceID]
    if not c or not floors then return floors end
    ns.CombinedFloors = ns.CombinedFloors or {}
    local cf = ns.CombinedFloors[instanceID]
    if not cf then
        cf = { uiMapID = 900000 + instanceID, name = "Combined map", combined = true, w = c.w, h = c.h, data = c, instanceID = instanceID }
        ns.CombinedFloors[instanceID] = cf
    end
    local out = {}
    for i, fl in ipairs(floors) do out[i] = fl end
    out[#out + 1] = cf
    return out
end

-- the art floor a piece of a combined map is cut from (its size is needed to convert pixels and fractions)
local function sourceFloor(instanceID, floorID)
    for _, src in ipairs({ ns.ArtCustom and ns.ArtCustom[instanceID] or {}, ns.ArtData[instanceID] or {}, ns.ArtForever and ns.ArtForever[instanceID] or {} }) do
        for _, fl in ipairs(src) do
            if fl.uiMapID == floorID then return fl end
        end
    end
end
ns.CombinedSource = sourceFloor

-- A point (x, y fractions of a floor's art) on the combined map: returns canvas fractions, or nil when the point is not in any piece.
function ns.CombinedPoint(cf, srcFloorID, x, y)
    for _, p in ipairs(cf.data.pieces) do
        if p.floor == srcFloorID then
            local sf = p.src or sourceFloor(cf.instanceID, p.floor)
            p.src = sf
            if sf then
                local px, py = x * sf.w, y * sf.h
                if px >= p.x0 and px <= p.x1 and py >= p.y0 and py <= p.y1 then
                    return (p.dx + (px - p.x0) * p.s) / cf.w, (p.dy + (py - p.y0) * p.s) / cf.h, p
                end
            end
        end
    end
end

-- The other way: a point on the combined map (canvas fractions) -> floor id and x, y fractions of that floor's art, or nil outside the pieces.
function ns.CombinedInverse(cf, cx, cy)
    local X, Y = cx * cf.w, cy * cf.h
    for i = #cf.data.pieces, 1, -1 do -- the piece drawn last is on top
        local p = cf.data.pieces[i]
        local sf = p.src or sourceFloor(cf.instanceID, p.floor)
        p.src = sf
        if sf and X >= p.dx and X <= p.dx + (p.x1 - p.x0) * p.s and Y >= p.dy and Y <= p.dy + (p.y1 - p.y0) * p.s then
            return p.floor, (p.x0 + (X - p.dx) / p.s) / sf.w, (p.y0 + (Y - p.dy) / p.s) / sf.h
        end
    end
end

function ns.GetFloors(instanceID, wing)
    return withCombined(instanceID, ns.GetArtFloors(instanceID, wing))
end

function ns.GetArtFloors(instanceID, wing)
    local all = (ns.ArtCustom and ns.ArtCustom[instanceID]) or ns.ArtData[instanceID] or (ns.ArtForever and ns.ArtForever[instanceID])
    local w = wing and ns.WingInfo(instanceID, wing)
    if w and w.floors and #w.floors == 0 then return nil end -- explicit: this wing has no map art yet
    if w and w.floors then
        -- a wing lists its own floors, which may mix bundled custom art with client art (Blackrock Spire)
        local keep, pool = {}, {}
        for _, id in ipairs(w.floors) do keep[id] = true end
        for _, src in ipairs({ ns.ArtCustom and ns.ArtCustom[instanceID] or {}, ns.ArtData[instanceID] or {}, ns.ArtForever and ns.ArtForever[instanceID] or {} }) do
            for _, fl in ipairs(src) do pool[#pool + 1] = fl end
        end
        local out = {}
        for _, id in ipairs(w.floors) do
            for _, fl in ipairs(pool) do
                if fl.uiMapID == id then out[#out + 1] = fl break end
            end
        end
        if #out > 0 then return out end
    end
    return all
end


-- Boss list for the difficulty that best matches `difficultyID`.
-- Forever stores encounters under several DifficultyIDs. 0 and 1 together form the normal 5-player list
-- (e.g. Blackfathom Deeps splits its bosses between them); other ids (198, 201, 215...) are separate modes.
-- Preference: exact match, else the normal list (0+1), else the lowest id present.
local NORMAL = { [0] = true, [1] = true }

function ns.GetBosses(instanceID, difficultyID, wing)
    local d = ns.Dungeons[instanceID]
    if not d then return {} end
    local present = {}
    for _, b in ipairs(d.bosses) do present[b.diff] = true end
    local want = {}
    if difficultyID and present[difficultyID] and not NORMAL[difficultyID] then
        want[difficultyID] = true
    elseif present[0] or present[1] then
        want[0], want[1] = true, true
    else
        local lowest
        for diff in pairs(present) do
            if not lowest or diff < lowest then lowest = diff end
        end
        want[lowest] = true
    end
    local manual = DungeonMapDB and DungeonMapDB.manual and DungeonMapDB.manual[instanceID]
    local displays = DungeonMapDB and DungeonMapDB.portraits and DungeonMapDB.portraits[instanceID]
    local out, seen = {}, {}
    for _, b in ipairs(d.bosses) do
        if want[b.diff] and not seen[b.name] then
            seen[b.name] = true
            local m = manual and manual[b.name]
            local disp = displays and displays[b.name]
            if m or disp then
                local c = {}
                for k, v in pairs(b) do c[k] = v end
                if m then c.floor, c.x, c.y, c.recorded, c.approx = m.floor, m.x, m.y, true, nil end
                if disp then c.display = disp end
                b = c
            end
            out[#out + 1] = b
        end
    end
    -- hand-set route numbers (data/manual/boss_order.csv) define the list order; unnumbered bosses follow in journal order
    table.sort(out, function(a, b)
        if a.num or b.num then
            if a.num and b.num then return a.num < b.num end
            return a.num ~= nil
        end
        return a.order < b.order
    end)
    local w = wing and ns.WingInfo(instanceID, wing)
    if w then -- a wing of a shared map (Lower/Upper Blackrock Spire ...): only its own bosses
        local mine = {}
        local floorSet
        if w.floors then
            floorSet = {}
            for _, id in ipairs(w.floors) do floorSet[id] = true end
        end
        for _, b in ipairs(out) do
            if w.bosses[b.name] then
                if floorSet and b.floor and not floorSet[tonumber(b.floor)] then
                    -- positioned on a map this wing does not show: list it without a pin until it is recorded on one of the wing's maps
                    local c = {}
                    for k, v in pairs(b) do c[k] = v end
                    c.floor, c.x, c.y = nil, nil, nil
                    b = c
                end
                mine[#mine + 1] = b
            end
        end
        return mine
    end
    return out
end

-- Saved lockout of a dungeon/raid, if the game reports one: { reset = seconds, killed = n, total = n, bosses = { [name] = true } }.
function ns.GetLockout(instanceID)
    local dungeonName = ns.Dungeons[instanceID] and ns.Dungeons[instanceID].name
    local ok, res = pcall(function()
        for i = 1, (GetNumSavedInstances() or 0) do
            local name, _, reset, _, locked, _, _, _, _, _, numEncounters, progress = GetSavedInstanceInfo(i)
            if name == dungeonName and reset and reset > 0 then
                local lock = { reset = reset, killed = progress or 0, total = numEncounters or 0, bosses = {} }
                for e = 1, (numEncounters or 0) do
                    local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, e)
                    if bossName and isKilled then lock.bosses[bossName] = true end
                end
                return lock
            end
        end
    end)
    return ok and res or nil
end

-- Defeated in the current run (BOSS_KILL, remembered until reset) or in a saved lockout.
function ns.IsKilled(boss, instanceID)
    local rec = ns.GetRunKills and ns.GetRunKills(instanceID)
    if rec and (rec.ids[boss.id] or (ns.NormName and rec.names[ns.NormName(boss.name)])) then return true end
    local lock = ns.GetLockout(instanceID)
    return lock and lock.bosses[boss.name] or false
end

-- Loot for a boss: { {itemID, forever(0/1), dropPercent|nil}, ... } or nil. Data/Loot.lua is generated from AtlasLoot Forever.
function ns.GetLoot(instanceID, bossName)
    local d = ns.Loot and ns.Loot[instanceID]
    return d and d[bossName]
end

-- Ability spell IDs for a boss ({ spellID, ... }) or nil. Data/Abilities.lua is generated from CMaNGOS classic-db; names, icons and
-- descriptions come from the client at runtime. Forever-new bosses have none (the panel shows a fallback text).
function ns.GetAbilities(instanceID, bossName)
    local d = ns.Abilities and ns.Abilities[instanceID]
    return d and d[bossName]
end

function ns.IsRare(instanceID, bossName)
    local r = ns.Rares and ns.Rares[instanceID]
    return r and r[bossName] or false
end

-- Floor markers (entrance, exit, stairs, portal): authored with /dm edit, shipped in Data/Markers.lua, plus the ones recorded locally.
ns.MARKER_ORDER = { "entrance", "exit", "up", "down", "left", "right", "portal", "trigger" }
-- the game's own door icons show direction: up / down are used for stairs, left / right as plain direction markers
ns.MARKER_KINDS = {
    entrance = { label = "Entrance", atlas = "Dungeon", color = { 0.55, 1, 0.55 }, scale = 1.6 }, -- the artwork has a lot of empty margin: drawn bigger
    exit = { label = "Exit", atlas = "poi-door", color = { 1, 0.5, 0.4 } },
    up = { label = "Stairs up", atlas = "poi-door-up", fallback = "poi-door-arrow-up", color = { 1, 1, 1 } },
    down = { label = "Stairs down", atlas = "poi-door-down", fallback = "poi-door-arrow-down", color = { 1, 1, 1 } },
    left = { label = "Left", atlas = "poi-door-left", fallback = "poi-door-arrow-up", fallbackRotation = math.pi / 2, color = { 1, 1, 1 } },
    right = { label = "Right", atlas = "poi-door-right", fallback = "poi-door-arrow-up", fallbackRotation = -math.pi / 2, color = { 1, 1, 1 } },
    portal = { label = "Portal", atlas = "worldquest-icon-dungeon", color = { 0.8, 0.6, 1 } },
    -- something you have to use or kill to start a boss (a statue, a brazier, a gong, a pack of mobs): tied to a boss, with a short label
    trigger = { label = "Trigger", texture = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\trigger_gear", color = { 1, 0.85, 0.4 }, scale = 0.55 },
}
-- names used briefly in earlier builds
ns.MARKER_ALIASES = { arrow_up = "up", arrow_down = "down", arrow_left = "left", arrow_right = "right" }

function ns.GetMarkers(instanceID, floorUiMapID)
    local out = {}
    local gen = ns.Markers and ns.Markers[instanceID] and ns.Markers[instanceID][floorUiMapID]
    local removed = DungeonMapDB and DungeonMapDB.markerRemovals or {}
    for _, m in ipairs(gen or {}) do
        local gone = false
        for _, r in ipairs(removed) do -- a shipped marker the maintainer removed in game, until the next import deletes it from the data
            if r.instance == instanceID and r.floor == floorUiMapID and r.kind == m.kind and math.abs(r.x - m.x) < 0.004 and math.abs(r.y - m.y) < 0.004 then gone = true end
        end
        if not gone then out[#out + 1] = { kind = m.kind, x = m.x, y = m.y, boss = m.boss, label = m.label, instance = instanceID, floor = floorUiMapID } end
    end
    local db = DungeonMapDB and DungeonMapDB.markers and DungeonMapDB.markers[instanceID] and DungeonMapDB.markers[instanceID][floorUiMapID]
    for i, m in ipairs(db or {}) do
        local dup = false
        for _, g in ipairs(gen or {}) do
            if g.kind == m.kind and math.abs(g.x - m.x) < 0.004 and math.abs(g.y - m.y) < 0.004 then dup = true end
        end
        if not dup then out[#out + 1] = { kind = m.kind, x = m.x, y = m.y, boss = m.boss, label = m.label, db = true, idx = i, instance = instanceID, floor = floorUiMapID } end
    end
    return out
end

-- Floor links: two markers (any icon) on different floors that lead to each other. Shipped in Data/Markers.lua (ns.MarkerLinks),
-- plus links recorded in game (DungeonMapDB.markerLinks) and removals (DungeonMapDB.linkRemovals) until the next import.
local LINK_TOL = 0.006
local function near(f1, x1, y1, f2, x2, y2) return f1 == f2 and math.abs(x1 - x2) < LINK_TOL and math.abs(y1 - y2) < LINK_TOL end

local function linkRemoved(instanceID, l)
    for _, r in ipairs(DungeonMapDB and DungeonMapDB.linkRemovals or {}) do
        if r.instance == instanceID and ((near(r.fa, r.xa, r.ya, l.fa, l.xa, l.ya) and near(r.fb, r.xb, r.yb, l.fb, l.xb, l.yb))
            or (near(r.fa, r.xa, r.ya, l.fb, l.xb, l.yb) and near(r.fb, r.xb, r.yb, l.fa, l.xa, l.ya))) then return true end
    end
end

-- the floors of an instance that the addon shows (all wings): links on other floors (a dungeon that now has an overview map) do not count
local function shownFloorSet(instanceID)
    local set = {}
    for _, w in ipairs(ns.GetWings(instanceID) or { { wing = nil } }) do
        for _, fl in ipairs(ns.GetFloors(instanceID, w.wing) or {}) do set[fl.uiMapID] = true end
    end
    return set
end

ns.ShownFloorSet = shownFloorSet

-- All links of an instance as { fa, xa, ya, fb, xb, yb, db = true if recorded in game }
function ns.GetLinks(instanceID)
    local out = {}
    local shown = shownFloorSet(instanceID)
    for _, l in ipairs(ns.MarkerLinks and ns.MarkerLinks[instanceID] or {}) do
        if not linkRemoved(instanceID, l) and shown[l.fa] and shown[l.fb] then out[#out + 1] = l end
    end
    local shipped = #out
    for i, l in ipairs(DungeonMapDB and DungeonMapDB.markerLinks and DungeonMapDB.markerLinks[instanceID] or {}) do
        local dup = false
        for j = 1, shipped do -- already imported: the shipped copy wins
            local g = out[j]
            if (near(g.fa, g.xa, g.ya, l.fa, l.xa, l.ya) and near(g.fb, g.xb, g.yb, l.fb, l.xb, l.yb))
                or (near(g.fa, g.xa, g.ya, l.fb, l.xb, l.yb) and near(g.fb, g.xb, g.yb, l.fa, l.xa, l.ya)) then dup = true end
        end
        if not dup and shown[l.fa] and shown[l.fb] then out[#out + 1] = { fa = l.fa, xa = l.xa, ya = l.ya, fb = l.fb, xb = l.xb, yb = l.yb, db = true, idx = i } end
    end
    return out
end

-- The other end of the link that starts at the marker (floor, x, y), or nil: { floor, x, y, link }
function ns.GetLinkTarget(instanceID, floor, x, y)
    for _, l in ipairs(ns.GetLinks(instanceID)) do
        if near(l.fa, l.xa, l.ya, floor, x, y) then return { floor = l.fb, x = l.xb, y = l.yb, link = l } end
        if near(l.fb, l.xb, l.yb, floor, x, y) then return { floor = l.fa, x = l.xa, y = l.ya, link = l } end
    end
end

-- Letters for the links of an instance: A for the first link made, B for the next ... (the order they were recorded in; shipped links first, in
-- the order of data/manual/marker_links.csv, then the ones recorded in game). Both ends of a link carry the same letter.
-- Each wing counts on its own (Upper Blackrock Spire starts at A again). Returns a list of { letter, link }.
function ns.LinkLetters(instanceID)
    local wingOf = {}
    for _, w in ipairs(ns.GetWings(instanceID) or { { wing = nil } }) do
        for _, fl in ipairs(ns.GetFloors(instanceID, w.wing) or {}) do wingOf[fl.uiMapID] = w.wing or 0 end
    end
    local count, list = {}, {}
    for _, l in ipairs(ns.GetLinks(instanceID)) do
        local key = wingOf[l.fa] or 0
        count[key] = (count[key] or 0) + 1
        list[#list + 1] = { link = l, letter = string.char(65 + (count[key] - 1) % 26) }
    end
    return list
end

-- The letter of the link that ends at the marker (floor, x, y), or nil.
function ns.LinkLetter(instanceID, floor, x, y)
    for _, e in ipairs(ns.LinkLetters(instanceID)) do
        local l = e.link
        if near(l.fa, l.xa, l.ya, floor, x, y) or near(l.fb, l.xb, l.yb, floor, x, y) then return e.letter end
    end
end
