-- Ranked runs (D-063, D-066): the official routes of a dungeon, the record of a finished run, personal bests and the reference a live run is compared with.
-- No networking here. UI/Splits.lua owns the clock and calls in here when a boss falls; the Records tab and the chat summary read from here.
--
-- A route is a SET of bosses (order does not matter). A run stores the cumulative kill time of every boss once; the time on a route is the moment the
-- last boss of its set fell, so one run counts on every route whose set it completed (a short Blackrock Depths route and the full clear).
-- The yardstick is always OUR route (D-066): the shipped route, never the one a player drew (ns.GetRoute returns that one first).
-- A dungeon without an official route uses "all regular bosses" (the same list the timer window shows).
--
-- Saved: DungeonMapDB.runs = array of records (own runs, newest last):
--   { id, inst, wing, route = routeId, rv = routeVersion, rname, started = time(), finished = time(), total = seconds, kills = { [normalised boss] = cumulative seconds },
--     names = { [normalised boss] = display name }, pulls = { {boss, at, len, ok} }, deaths, wipes, size, level, bracket = "in"|"over", diff,
--     members = { {name, class} }, ranked = bool, why = reason it is not ranked, v = addon version, start = "combat"|"encounter"|"kill" }
local _, ns = ...

local MAX_RUNS = 300

local function norm(n) return ns.NormName(n) end

-- A short stable hash of a set of boss names (order independent): the route's version. A changed boss list starts a new board.
local function setVersion(keys)
    local list = {}
    for k in pairs(keys) do list[#list + 1] = k end
    table.sort(list)
    local h = 5381
    local s = table.concat(list, "|")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%05x", h % 1048576)
end

local function routeFrom(id, name, bossNames, auto)
    local keys, shown = {}, {}
    for _, n in ipairs(bossNames) do
        local k = norm(n)
        if k ~= "" and not keys[k] then keys[k] = n; shown[#shown + 1] = n end
    end
    return { id = id, name = name, bosses = shown, keys = keys, version = setVersion(keys), auto = auto or false, count = #shown }
end

-- The regular bosses of a dungeon (no trash, summoned, optional or sub bosses), in the dungeon's own order.
local function regularBosses(instanceID, wing)
    local out = {}
    for _, b in ipairs(ns.GetBosses(instanceID, nil, wing) or {}) do
        if not b.trash and not b.summoned and not b.optional and not b.sub then out[#out + 1] = b.name end
    end
    return out
end

-- The official routes of a dungeon (a wing of it): a list of { id, name, bosses = {display names}, keys = { [norm] = name }, version, auto, count }.
-- Sources, in order: ns.OfficialRoutesData[instance][wing or 0] (named routes, the generator will fill it: { {id, name, bosses = {...}} }), the shipped
-- route's boss stops (Data/Routes.lua, one route per dungeon today), else the regular bosses ("auto"). Never DungeonMapDB.routes.
function ns.OfficialRoutes(instanceID, wing)
    if not (instanceID and ns.Dungeons[instanceID]) then return {} end
    local w = wing or 0
    local out = {}
    local named = ns.OfficialRoutesData and ns.OfficialRoutesData[instanceID] and ns.OfficialRoutesData[instanceID][w]
    if named then
        for _, r in ipairs(named) do
            if r.id and r.bosses and #r.bosses > 0 then out[#out + 1] = routeFrom(r.id, r.name or r.id, r.bosses) end
        end
    end
    if #out == 0 then
        local shipped = ns.RouteData and ns.RouteData[instanceID] and ns.RouteData[instanceID][w]
        if shipped then
            local names = {}
            for _, p in ipairs(shipped) do if p.boss then names[#names + 1] = p.boss end end
            if #names > 0 then out[#out + 1] = routeFrom("main", "Official route", names) end
        end
        -- named routes that ship (Stratholme: Living side, Undead side): one route each, made from the boss stops of the drawn route, and a
        -- "Full run" of all of them together when there are two or more. The clock does not care which one a run is on: every route whose
        -- bosses are all down is finished at that kill (UI/Splits.lua), so a full clear records all of them.
        local named = ns.RouteShippedVariants and ns.RouteShippedVariants(instanceID, wing) or {}
        local all, seen = {}, {}
        for _, e in ipairs(named) do
            out[#out + 1] = routeFrom(ns.NormName(e.name):gsub("%s+", "-"), e.name, e.bosses)
            for _, n in ipairs(e.bosses) do if not seen[n] then seen[n] = true; all[#all + 1] = n end end
        end
        if #named >= 2 then out[#out + 1] = routeFrom("full", "Full run", all) end
    end
    if #out == 0 then
        local names = regularBosses(instanceID, wing)
        if #names > 0 then out[#out + 1] = routeFrom("auto", "All regular bosses", names, true) end
    end
    return out
end

function ns.RouteKey(r) return r.id .. "." .. r.version end

-- The bosses a visit goes through (the timer window's lines): the first official route's bosses, in route order.
function ns.OfficialLineup(instanceID, wing)
    local routes = ns.OfficialRoutes(instanceID, wing)
    local r = routes[1]
    for _, x in ipairs(routes) do if x.id == "full" then r = x end end -- several named routes: all their bosses, route after route
    return r and r.bosses or {}
end

-- Level bracket: "in" (the character's level is in the dungeon's range or below it) or "over" (above it).
function ns.RunBracket(instanceID, wing, level)
    local d = ns.Dungeons[instanceID] and ns.LevelData(instanceID, wing)
    local max = d and (d.recMax or d.minLevel)
    if type(level) == "number" and max and level > max then return "over" end
    return "in"
end

function ns.BracketLabel(instanceID, wing, bracket)
    local d = ns.Dungeons[instanceID] and ns.LevelData(instanceID, wing)
    if not d or not d.recMax then return bracket == "over" and "Over-levelled" or "In bracket" end
    if bracket == "over" then return format("Level %d++", d.recMax) end
    return format("Level %s", ns.LevelLabel(d))
end

-- Who is in the group now: { {name, class} }, you first. Unit data can be secret in an instance: such a member is skipped (not guessed).
-- Forever gives UnitName(unit) as first name and surname; they are joined with a space (the form chat uses, OQ-033).
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
function ns.RunMembers()
    local out = {}
    local units = { "player", "party1", "party2", "party3", "party4" }
    for _, u in ipairs(units) do
        local okE, exists = pcall(UnitExists, u)
        if okE and exists and readable(exists) then
            local ok, name, extra = pcall(UnitName, u)
            if ok and type(name) == "string" and readable(name) and name ~= "" then
                if type(extra) == "string" and readable(extra) and extra ~= "" then name = name .. " " .. extra end
                local okC, _, class = pcall(UnitClass, u)
                out[#out + 1] = { name = name, class = (okC and type(class) == "string" and readable(class)) and class or nil }
            end
        end
    end
    return out
end

local function addonVersion()
    local f = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local ok, v = pcall(f, ns.name or "DungeonCrawlerForever", "Version")
    return ok and type(v) == "string" and v or "?"
end

local function runs()
    DungeonMapDB.runs = DungeonMapDB.runs or {}
    return DungeonMapDB.runs
end

-- Keep the newest MAX_RUNS; the best ranked run of every board is never dropped.
local function prune()
    local list = runs()
    if #list <= MAX_RUNS then return end
    local keep, best = {}, {}
    for i, r in ipairs(list) do
        local k = r.inst .. "." .. (r.wing or 0) .. "." .. r.route .. "." .. r.rv .. "." .. (r.bracket or "in")
        if r.ranked and (not best[k] or r.total < list[best[k]].total) then best[k] = i end
    end
    for _, i in pairs(best) do keep[i] = true end
    local drop, out = #list - MAX_RUNS, {}
    for i, r in ipairs(list) do
        if drop > 0 and not keep[i] then drop = drop - 1 else out[#out + 1] = r end
    end
    DungeonMapDB.runs = out
end

-- Own runs of one route, newest last.
function ns.RunsFor(instanceID, wing, routeKeyOrNil)
    local out = {}
    for _, r in ipairs(DungeonMapDB and DungeonMapDB.runs or {}) do
        if r.inst == instanceID and (r.wing or 0) == (wing or 0) and (not routeKeyOrNil or (r.route .. "." .. r.rv) == routeKeyOrNil) then out[#out + 1] = r end
    end
    return out
end

-- The personal best ranked run on a route (any bracket), or the last ranked one.
function ns.RunReference(instanceID, wing, route, useLast)
    local pick
    for _, r in ipairs(ns.RunsFor(instanceID, wing, ns.RouteKey(route))) do
        if r.ranked then
            if useLast then pick = r elseif not pick or r.total < pick.total then pick = r end
        end
    end
    return pick
end

-- Best cumulative time at one boss over the ranked runs of a route (for per-boss records), and the segment is derived by the caller.
function ns.RunBossBest(instanceID, wing, route, bossKey)
    local best
    for _, r in ipairs(ns.RunsFor(instanceID, wing, ns.RouteKey(route))) do
        local t = r.ranked and r.kills[bossKey]
        if t and (not best or t < best) then best = t end
    end
    return best
end

-- A finished route: write the record, say so in chat. `v` is the visit (UI/Splits.lua), `route` an official route, `cum` the seconds at its last kill.
function ns.RecordRun(v, route, cum)
    if not (DungeonMapDB and v and v.started and route) then return end
    local kills, names = {}, {}
    for key, display in pairs(route.keys) do
        if v.kills[key] then kills[key] = v.kills[key]; names[key] = display end
    end
    local bracket = ns.RunBracket(v.instance, v.wing, v.level)
    local wipes = 0
    for _, p in ipairs(v.pulls or {}) do if not p.ok then wipes = wipes + 1 end end
    local raid = ns.Dungeons[v.instance] and ns.Dungeons[v.instance].raid
    local why = v.why or (raid and "raid") or nil
    local me = norm((UnitName and select(1, UnitName("player"))) or "me")
    local rec = {
        id = format("%d.%d.%s.%s", v.instance, v.started, me, route.id), inst = v.instance, wing = v.wing or 0, route = route.id, rv = route.version,
        rname = route.name, started = v.started, finished = v.started + cum, total = cum, kills = kills, names = names,
        pulls = v.pulls or {}, deaths = v.deaths or 0, wipes = wipes, size = v.size or 1, level = v.level, bracket = bracket, diff = v.diff,
        members = v.members or {}, ranked = why == nil, why = why, v = addonVersion(), start = v.startedBy, by = ns.MyRunName(),
    }
    -- the previous personal best on this board, before this run counts
    local prev, prevRun
    for _, r in ipairs(ns.RunsFor(v.instance, v.wing, ns.RouteKey(route))) do
        if r.ranked and r.bracket == bracket and (not prev or r.total < prev) then prev, prevRun = r.total, r end
    end
    local list = runs()
    list[#list + 1] = rec
    prune()
    local text = format("|cffffd100%s|r complete: |cffffffff%s|r", route.name, ns.FormatTime(cum))
    if not rec.ranked then
        text = text .. format(" |cff9a9a9a(not ranked: %s)|r", why)
    elseif not prev then
        text = text .. " |cff9a9a9a(first run on this route)|r"
    elseif cum < prev then
        text = text .. format(" |cff66ff66(new personal best, was %s)|r", ns.FormatTime(prev))
    elseif cum == prev then
        text = text .. " |cffffd100(equal to your best)|r"
    else
        text = text .. format(" |cff9a9a9a(best %s, +%s)|r", ns.FormatTime(prev), ns.FormatTime(cum - prev))
    end
    if rec.deaths > 0 or rec.wipes > 0 then text = text .. format(" |cff9a9a9a- %d death(s), %d wipe(s)|r", rec.deaths, rec.wipes) end
    ns.Print(text)
    local rank, count
    if rec.ranked and ns.BoardEntries then
        local list = ns.BoardEntries(v.instance, v.wing, route, bracket)
        count = #list
        for _, e in ipairs(list) do if e.run == rec or (e.own and e.run.id == rec.id) then rank = e.rank end end
        if not rank then -- your best on this board was faster: the new run is below it, and your entry shows that one
            for _, e in ipairs(list) do if e.own then rank = e.rank end end
        end
    end
    local ctx = { prevTotal = prev, refKills = prevRun and prevRun.kills, rank = rank, count = count, newBest = rec.ranked and (not prev or cum < prev) }
    ns.lastRun = { rec = rec, ctx = ctx }
    if ns.CommsShareRun then pcall(ns.CommsShareRun, rec) end
    if ns.OnRunRecorded then pcall(ns.OnRunRecorded, rec, ctx) end
    return rec
end

-- Encounter pulls (every boss pull is logged: a pull without a kill is a wipe; informational only, never a ranking factor).
function ns.RunPullStart(v, name, cum)
    if not v then return end
    v.pulls = v.pulls or {}
    if #v.pulls >= 80 then return end
    v.openPull = { boss = name or "?", at = cum or 0, t0 = GetTime() }
end

function ns.RunPullEnd(v, name, success)
    if not (v and v.openPull) then return end
    local p = v.openPull
    v.openPull = nil
    v.pulls = v.pulls or {}
    if #v.pulls < 80 then v.pulls[#v.pulls + 1] = { boss = p.boss or name or "?", at = p.at, len = math.max(0, math.floor(GetTime() - p.t0 + 0.5)), ok = success and true or false } end
end
