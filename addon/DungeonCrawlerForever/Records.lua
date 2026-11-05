-- Run records (speedrun records, milestone 1 of LEADERBOARD.md: local only, no sharing yet).
-- A run is measured against the dungeon's OFFICIAL route (Data/Routes.lua, the route that ships with the addon, never a player's own):
-- it is finished when every boss on that route is dead, in any order. The clock is the split timer's (UI/Splits.lua), which starts at the
-- first fight in the dungeon (D-063). Records are kept per dungeon in DungeonMapDB.runs[instanceID] = { record, ... }:
--   { id, wing (0 = none), ver (route version), date (time()), total (seconds), ranked (bool), why (reason it is unranked),
--     level, bracket ("in" | "over"), size (group size), deaths, kills = { { name, cumulative seconds }, ... },
--     pulls = { { name, seconds, 1 = kill / 0 = wipe }, ... }, who = { { name, classFile }, ... }, mock = true (test data) }
-- Two level brackets (D-063): "in" = the dungeon's level range and below, "over" = above it.
local _, ns = ...

local KEEP = 60 -- runs kept per dungeon; the best ranked run of each board is never dropped

local function wingKey(wing) return wing or 0 end

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- The bosses of the official route for a dungeon (or wing), in route order, and the route version; nil when there is no official route.
function ns.RecordsRoute(instanceID, wing)
    local byWing = instanceID and ns.RouteData and ns.RouteData[instanceID]
    local list = byWing and byWing[wingKey(wing)]
    if not list then return nil end
    local out, seen = {}, {}
    for _, p in ipairs(list) do
        if p.boss and not seen[ns.NormName(p.boss)] then
            seen[ns.NormName(p.boss)] = true
            out[#out + 1] = p.boss
        end
    end
    if #out == 0 then return nil end
    -- the version is a checksum of the boss set (order does not matter for a finish), so a route redrawn with the same bosses keeps its board
    local keys = {}
    for _, n in ipairs(out) do keys[#keys + 1] = ns.NormName(n) end
    table.sort(keys)
    local sum = 0
    local s = table.concat(keys, ",")
    for i = 1, #s do sum = (sum * 31 + s:byte(i)) % 2147483647 end
    return out, "r" .. sum
end

function ns.RecordsHasRoute(instanceID)
    return instanceID and ns.RouteData and ns.RouteData[instanceID] ~= nil or false
end

-- "in" or "over" for a character level in a dungeon (under-levelled counts as "in": there are only two brackets)
function ns.RecordsBracket(instanceID, level)
    local d = ns.Dungeons and ns.Dungeons[instanceID]
    if d and d.recMax and type(level) == "number" and level > d.recMax then return "over" end
    return "in"
end

function ns.RecordsBracketLabel(instanceID, bracket)
    local d = ns.Dungeons and ns.Dungeons[instanceID]
    if not (d and d.recMin and d.recMax) then return bracket == "over" and "Overlevelled" or "All levels" end
    if bracket == "over" then return format("Level %d++", d.recMax) end
    return format("Level %d-%d", d.recMin, d.recMax)
end

function ns.RecordsPlayerLevel()
    local l = UnitLevel and UnitLevel("player")
    if readable(l) and type(l) == "number" then return l end
end

local function groupSize()
    local n = GetNumGroupMembers and GetNumGroupMembers()
    if readable(n) and type(n) == "number" and n > 0 then return n end
    return 1
end

local function member(unit)
    if not (UnitExists and UnitExists(unit) and UnitName) then return nil end
    local name = UnitName(unit)
    if not (readable(name) and type(name) == "string") then return nil end
    local _, class = nil, nil
    if UnitClass then _, class = UnitClass(unit) end
    return { name, readable(class) and class or nil }
end

local function members()
    local out = {}
    local me = member("player")
    if me then out[#out + 1] = me end
    for i = 1, 4 do
        local m = member("party" .. i)
        if m then out[#out + 1] = m end
    end
    return out
end

local function store(instanceID)
    DungeonMapDB.runs = DungeonMapDB.runs or {}
    local list = DungeonMapDB.runs[instanceID]
    if not list then
        list = {}
        DungeonMapDB.runs[instanceID] = list
    end
    return list
end

local function faster(a, b)
    if a.ranked ~= b.ranked then return a.ranked and true or false end
    if a.total ~= b.total then return a.total < b.total end
    return (a.date or 0) < (b.date or 0)
end

-- The runs of one board (dungeon, wing, current route version, bracket): ranked runs by time, then unranked ones by time.
function ns.RecordsList(instanceID, wing, bracket)
    local _, ver = ns.RecordsRoute(instanceID, wing)
    local out, older = {}, 0
    local list = DungeonMapDB and DungeonMapDB.runs and DungeonMapDB.runs[instanceID] or {}
    for _, r in ipairs(list) do
        if r.wing == wingKey(wing) and (not bracket or r.bracket == bracket) then
            if r.ver == ver then out[#out + 1] = r else older = older + 1 end
        end
    end
    table.sort(out, faster)
    return out, older
end

function ns.RecordsBest(instanceID, wing, bracket)
    local list = ns.RecordsList(instanceID, wing, bracket)
    if list[1] and list[1].ranked then return list[1] end
end

-- drop the oldest runs past KEEP, but never the best ranked run of a board
local function trim(instanceID)
    local list = store(instanceID)
    if #list <= KEEP then return end
    local keep = {}
    for _, r in ipairs(list) do
        local best = ns.RecordsBest(instanceID, r.wing ~= 0 and r.wing or nil, r.bracket)
        if best then keep[best] = true end
    end
    table.sort(list, function(a, b) return (a.date or 0) > (b.date or 0) end)
    local out = {}
    for _, r in ipairs(list) do
        if #out < KEEP or keep[r] then out[#out + 1] = r end
    end
    DungeonMapDB.runs[instanceID] = out
end

-- A finished run (from UI/Splits.lua). bosses/ver = the official route it was measured against. Returns the record.
function ns.RecordsAdd(run, bosses, ver, finish)
    local inst = run.instance
    local kills = {}
    for _, n in ipairs(bosses) do
        local t = run.kills[ns.NormName(n)]
        if t then kills[#kills + 1] = { n, math.floor(t + 0.5) } end
    end
    table.sort(kills, function(a, b) return a[2] < b[2] end)
    local level = run.level or ns.RecordsPlayerLevel()
    local rec = {
        id = format("%d-%d", time(), math.random(1000, 9999)),
        wing = wingKey(run.wing), ver = ver, date = time(), total = math.floor(finish + 0.5),
        ranked = run.why == nil, why = run.why, level = level, bracket = ns.RecordsBracket(inst, level),
        size = groupSize(), deaths = run.deaths or 0, kills = kills, pulls = run.pulls or {}, who = members(),
    }
    local before = ns.RecordsBest(inst, run.wing, rec.bracket)
    local list = store(inst)
    list[#list + 1] = rec
    trim(inst)
    ns.RecordsAnnounce(inst, run.wing, rec, before)
    if ns.ViewShown and ns.ViewShown() and ns.RefreshMap then pcall(ns.RefreshMap) end
    return rec
end

-- one chat line at the finish, in the style of the kill-time lines
function ns.RecordsAnnounce(instanceID, wing, rec, before)
    local d = ns.Dungeons[instanceID]
    local name = d and d.name or "Dungeon"
    local text = format("|cffffd100%s|r cleared in |cffffffff%s|r |cff9a9a9a(%s)|r", name, ns.FormatTime(rec.total), ns.RecordsBracketLabel(instanceID, rec.bracket))
    if not rec.ranked then
        text = text .. format(" |cff9a9a9a- unranked: %s|r", rec.why or "?")
    elseif not before then
        text = text .. " |cff66ff66- first record!|r"
    elseif rec.total < before.total then
        text = text .. format(" |cff66ff66- new personal best (was %s)|r", ns.FormatTime(before.total))
    else
        local list = ns.RecordsList(instanceID, wing, rec.bracket)
        local rank, n = 0, 0
        for _, r in ipairs(list) do
            if r.ranked then
                n = n + 1
                if r == rec then rank = n end
            end
        end
        text = text .. format(" |cff9a9a9a- your best %s, this run #%d of %d|r", ns.FormatTime(before.total), rank, n)
    end
    ns.Print(text)
end

-- detail lines for a record (tooltip and the wide view's detail pane)
function ns.RecordsDetailLines(instanceID, rec)
    local lines = {}
    lines[#lines + 1] = format("|cffffd100%s|r  %s", ns.FormatTime(rec.total), date("%Y-%m-%d %H:%M", rec.date or 0))
    local info = {}
    if rec.level then info[#info + 1] = "level " .. rec.level end
    info[#info + 1] = rec.size == 1 and "solo" or (rec.size .. " players")
    info[#info + 1] = (rec.deaths or 0) == 1 and "1 death" or ((rec.deaths or 0) .. " deaths")
    local wipes = 0
    for _, p in ipairs(rec.pulls or {}) do if p[3] == 0 then wipes = wipes + 1 end end
    info[#info + 1] = wipes == 1 and "1 wipe" or (wipes .. " wipes")
    lines[#lines + 1] = "|cff9a9a9a" .. table.concat(info, " · ") .. "|r"
    if not rec.ranked then lines[#lines + 1] = "|cffff9a5aUnranked: " .. (rec.why or "?") .. "|r" end
    if rec.mock then lines[#lines + 1] = "|cff9a9a9aTest data (/dm records clear removes it)|r" end
    lines[#lines + 1] = " "
    local prev = 0
    for _, k in ipairs(rec.kills or {}) do
        local tries = 0
        for _, p in ipairs(rec.pulls or {}) do if ns.NormName(p[1]) == ns.NormName(k[1]) then tries = tries + 1 end end
        lines[#lines + 1] = format("%s  |cffffffff%s|r  |cff9a9a9a(+%s)%s|r", k[1], ns.FormatTime(k[2]), ns.FormatTime(k[2] - prev), tries > 1 and format(" x%d", tries) or "")
        prev = k[2]
    end
    if rec.who and #rec.who > 0 then
        local names = {}
        for _, m in ipairs(rec.who) do
            local c = m[2] and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m[2]]
            names[#names + 1] = c and c.colorStr and ("|c" .. c.colorStr .. m[1] .. "|r") or m[1]
        end
        lines[#lines + 1] = " "
        lines[#lines + 1] = table.concat(names, ", ")
    end
    return lines
end

-- Test data, so the Records tab can be looked at before real runs exist: /dm records mock (adds), /dm records clear (removes test data only).
function ns.RecordsMock(instanceID, wing)
    local bosses, ver = ns.RecordsRoute(instanceID, wing)
    if not bosses then return false end
    local d = ns.Dungeons[instanceID]
    local list = store(instanceID)
    local names = { { "Kong", "WARRIOR" }, { "Brightleaf", "DRUID" }, { "Mossfoot", "HUNTER" }, { "Ashvale", "MAGE" }, { "Tindra", "PRIEST" } }
    for i = 1, 6 do
        local over = i > 4
        local total = (over and 600 or 1500) + i * 97
        local kills, pulls = {}, {}
        for j, n in ipairs(bosses) do
            local t = math.floor(total * j / #bosses)
            kills[#kills + 1] = { n, t }
            if i == 2 and j == 1 then pulls[#pulls + 1] = { n, 41, 0 } end
            pulls[#pulls + 1] = { n, 30 + j * 7, 1 }
        end
        list[#list + 1] = {
            id = "mock-" .. i, wing = wingKey(wing), ver = ver, date = time() - i * 86400, total = total,
            ranked = i ~= 3, why = i == 3 and "some bosses were already dead" or nil,
            level = over and ((d.recMax or 20) + 8) or (d.recMin or 15) + i, bracket = over and "over" or "in",
            size = i == 4 and 3 or 5, deaths = i % 3, kills = kills, pulls = pulls, who = names, mock = true,
        }
    end
    return true
end

function ns.RecordsClearMock()
    local n = 0
    for inst, list in pairs(DungeonMapDB.runs or {}) do
        local out = {}
        for _, r in ipairs(list) do if r.mock then n = n + 1 else out[#out + 1] = r end end
        DungeonMapDB.runs[inst] = out
    end
    return n
end
