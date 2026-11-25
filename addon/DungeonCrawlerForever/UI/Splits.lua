-- Time in dungeon and the ranked run (D-063, D-066). ONE clock, started by the first engagement (first combat in the dungeon, or an encounter start,
-- or, if both were missed, the first boss kill: that run is then not ranked). Walking in, buffing and waiting for people do not count. The clock runs
-- whether or not this window is shown: a run is recorded in the background (Runs.lua) and the window is only the live view.
-- Each boss line shows the segment time (since the previous boss), the time on the clock when it fell, and the difference to the reference: your best
-- ranked run on the route (or the last one): green = faster or the first time, red = slower, yellow = equal. A pace line under the bosses says where
-- the run is heading. The differences can be hidden with the +/- button (a relaxed run). Off by default as a window: Options, the X, or /dm timer.
-- The lines are the first official route's bosses (Runs.lua), never the route a player drew.
-- Light on purpose: no per-frame code, one 1-second ticker while the window is visible, two numbers saved per boss.
-- The visit (DungeonMapDB.visit) survives /reload and leaving for a short while (a corpse run, repairs): it is kept when you come back to the
-- same dungeon however long you are away: a run goes on until you stop it (Reset), the dungeon is reset, or its routes are finished. Only after AWAY
-- (12 hours, so yesterday's forgotten run does not greet you) does coming back start over. The window shows from the moment you come in, at 0:00 and not
-- ticking, until the first engagement.
-- Saved data: DungeonMapDB.splits[instanceID] = { best = {[boss] = seconds on the clock}, bestSeg = {[boss] = seconds}, last = {[boss] = seconds}, total = best full visit }
-- (kept for the per-boss records of dungeons without a finished run yet); the finished runs are DungeonMapDB.runs (Runs.lua).
local _, ns = ...

local GREEN, RED, GREY, WHITE, YELLOW = "|cff66ff66", "|cffff6666", "|cff9a9a9a", "|cffffffff", "|cffffd100"
local GRACE = 3 -- seconds after a loading screen in which a combat event does not start the clock
local AWAY = 43200 -- seconds outside the dungeon after which coming back starts a new visit (a run lasts until you stop it; this is only the safety net)
local win

-- the visit: { fmt = 2, instance, wing, entered = time() when you came in, started = time() of the first engagement (nil until then),
--   startedBy = "combat"|"encounter"|"kill", why = reason the run is not ranked, kills = { [normalised boss name] = seconds on the clock },
--   refs = { [boss] = reference or false }, routesDone = { [route key] = seconds }, pulls, deaths, level, size, members, diff,
--   done = time() when the last official route was completed, left = time() when you went out }
local function visit() return DungeonMapDB and DungeonMapDB.visit end

local function rec(instanceID)
    DungeonMapDB.splits = DungeonMapDB.splits or {}
    local r = DungeonMapDB.splits[instanceID]
    if not r then
        r = { best = {}, bestSeg = {}, last = {} }
        DungeonMapDB.splits[instanceID] = r
    end
    return r
end

-- The bosses a visit goes through, in order: the official route's stops, else the regular bosses of the dungeon (Runs.lua).
local function lineup(instanceID, wing) return ns.OfficialLineup(instanceID, wing) end
ns.SplitLineup = lineup

-- A kill whose name is no boss of this dungeon cannot count towards a route. Remember it (DungeonMapDB.unmatched) and say so once per session, so a
-- name that the game gives differently is seen the day it happens and not days later as a missing highscore run.
local saidUnmatched = {}
local function noteUnmatched(inst, name, key)
    local d = ns.Dungeons and ns.Dungeons[inst]
    if not d or #(ns.RunCreditedBy and ns.RunCreditedBy(inst, key) or {}) > 0 then return end -- an encounter that stands for a route stop is expected
    for _, b in ipairs(d.bosses or {}) do if ns.NormName(b.name) == key then return end end
    DungeonMapDB.unmatched = DungeonMapDB.unmatched or {}
    local u = DungeonMapDB.unmatched[inst] or {}
    DungeonMapDB.unmatched[inst] = u
    u[tostring(name)] = (u[tostring(name)] or 0) + 1
    if not saidUnmatched[inst .. key] then
        saidUnmatched[inst .. key] = true
        ns.Print(format("Heard |cffffd100%s|r die, but it is not in this dungeon's boss list, so it does not count for the run. If it is a boss, please report it.", tostring(name)))
    end
end

-- Failsafe: the route is exactly one boss short, and exactly one kill in this visit is a name that is no boss of the dungeon. That is the signature of a
-- name that did not match (the Drowned City bug), so the run is saved anyway, UNRANKED (never shared, not on the board), with the reason in the record.
-- Returns true when a run was saved. Works on any stored visit (also called by /dm recover), so a bug fixed later can still rescue the visit.
local function salvageUnmatched(v)
    if not (v and v.fmt == 2 and v.started and ns.RecordRun and next(v.kills or {})) then return false end
    local d = ns.Dungeons and ns.Dungeons[v.instance]
    if not d then return false end
    local known = {}
    for _, b in ipairs(d.bosses or {}) do known[ns.NormName(b.name)] = true end
    local stray
    for k, t in pairs(v.kills) do
        if not known[k] then
            if stray then return false end -- two unknown names: not clear which is which
            stray = { key = k, t = t }
        end
    end
    if not stray then return false end
    v.salvaged = v.salvaged or {}
    for _, rt in ipairs(ns.OfficialRoutes(v.instance, v.wing)) do
        local rk = ns.RouteKey(rt)
        if rt.id ~= "full" and not v.salvaged[rk] and not (v.routesDone and v.routesDone[rk]) then
            local missing = {}
            for k, display in pairs(rt.keys) do
                if not v.kills[k] and not (ns.BossUndetectable and ns.BossUndetectable(v.instance, k)) then missing[#missing + 1] = { key = k, name = display } end
            end
            if #missing == 1 then
                local copy = {}
                for k, val in pairs(v) do copy[k] = val end
                copy.kills = {}
                for k, val in pairs(v.kills) do copy.kills[k] = val end
                copy.kills[missing[1].key] = stray.t
                copy.why = v.why or format("a boss name did not match (%s counted as %s)", stray.key, missing[1].name)
                local cum = 0
                for k in pairs(rt.keys) do if copy.kills[k] and copy.kills[k] > cum then cum = copy.kills[k] end end
                v.salvaged[rk] = true
                ns.Print(format("The route was one boss short: |cffffd100%s|r was heard but did not match |cffffd100%s|r. Saving the run as unranked.", stray.key, missing[1].name))
                pcall(ns.RecordRun, copy, rt, cum)
                return true
            end
        end
    end
    return false
end

-- /dm recover: try the saved visit again (after an update that fixes names, or when a run was not saved).
function ns.SplitsRecover()
    local v = DungeonMapDB and DungeonMapDB.visit
    if not (v and v.fmt == 2) then ns.Print("No dungeon visit is stored to recover.") return end
    if not salvageUnmatched(v) then ns.Print("Nothing to recover: the stored visit is either complete or too far from a finished route (more than one boss missing).") end
end

-- Leaving a dungeon with a run that was close but not finished: say which boss was never seen (the usual cause of a missing run is a name that does not match).
local function reportUnfinished(v)
    if not (v and v.started and not v.done and next(v.kills or {})) then return end
    local routes = ns.OfficialRoutes(v.instance, v.wing)
    local best
    for _, rt in ipairs(routes) do
        if rt.id ~= "full" then
            local missing = {}
            for k, display in pairs(rt.keys) do
                if not v.kills[k] and not (ns.BossUndetectable and ns.BossUndetectable(v.instance, k)) then missing[#missing + 1] = display end
            end
            if not best or #missing < #best then best = missing end
        end
    end
    if best and #best > 0 and #best <= 2 then
        table.sort(best)
        ns.Print("No highscore run recorded: the route was not finished. Not yet seen: " .. table.concat(best, ", ") .. ".")
    end
end

local function boolKills(kills, route, instanceID)
    local any = false
    for k in pairs(route.keys) do
        if kills and kills[k] then any = true
        elseif not (instanceID and ns.BossUndetectable and ns.BossUndetectable(instanceID, k)) then return false end
    end
    return any
end

-- The route the live run is racing: of the routes not completed yet, the one with most of this run's kills (Stratholme: after an undead boss
-- that is the Undead side, not the Living side that comes first in the list); the Full run only once the others are done; else the first.
local function targetRoute(instanceID, wing, kills)
    local routes = ns.OfficialRoutes(instanceID, wing)
    local best, bestN, full
    for _, r in ipairs(routes) do
        if not boolKills(kills, r, instanceID) then
            if r.id == "full" then
                full = r
            else
                local n = 0
                for k in pairs(r.keys) do if kills and kills[k] then n = n + 1 end end
                if not best or n > bestN then best, bestN = r, n end
            end
        end
    end
    if best or full then return best or full, routes end
    return routes[1], routes
end

local function currentWing(instanceID)
    return DungeonMapDB.lastWing and DungeonMapDB.lastWing[instanceID] or nil
end

-- The comparison for a boss: the time at that boss in your best ranked run on the route (or the last one, option). Before a run has finished the
-- route there is nothing to compare with and the line says "new".
local function reference(instanceID, name, run)
    local key = ns.NormName(name)
    local route = targetRoute(instanceID, run and run.wing, run and run.kills)
    if route then
        local ref = ns.RunReference(instanceID, run and run.wing, route, DungeonMapDB.splitCompareLast)
        if ref and ref.kills[key] then return ref.kills[key] end
    end
    return nil -- (the old per-boss bests were counted from the door, a different clock: never mixed in)
end

-- Colour and text for a split: nil reference = first time set (green), equal = yellow.
function ns.SplitDelta(cum, ref)
    if not ref then return GREEN, "new" end
    local d = cum - ref
    if d == 0 then return YELLOW, "0:00" end
    if d < 0 then return GREEN, "-" .. ns.FormatTime(-d) end
    return RED, "+" .. ns.FormatTime(d)
end

-- The wing (Graveyard, Library ...) a boss belongs to in a dungeon that has wings, else nil.
local function wingOfBoss(inst, name)
    local key = ns.NormName(name)
    for _, w in ipairs(ns.GetWings(inst) or {}) do
        for bossName in pairs(w.bosses or {}) do
            if ns.NormName(bossName) == key then return w.wing end
        end
    end
end

local function newVisit(inst, wing)
    local _, _, diff = GetInstanceInfo()
    DungeonMapDB.visit = { fmt = 2, instance = inst, wing = wing or currentWing(inst), entered = time(), kills = {}, refs = {}, routesDone = {}, pulls = {}, deaths = 0,
        diff = type(diff) == "number" and not (issecretvalue and issecretvalue(diff)) and diff or nil }
    return DungeonMapDB.visit
end

-- The first engagement: starts the clock, reads the level and the group (D-063).
local function begin(v, how)
    if v.started then return end
    v.started, v.startedBy = time(), how
    local okL, lvl = pcall(UnitLevel, "player")
    v.level = okL and type(lvl) == "number" and not (issecretvalue and issecretvalue(lvl)) and lvl or nil
    v.members = ns.RunMembers()
    v.size = math.max(1, #v.members)
    if ns.MeterBegin then pcall(ns.MeterBegin, v) end -- the damage meter's numbers at the start (Meter.lua)
end

-- The visit in this dungeon (made when missing). nil outside a dungeon.
local function current()
    local inst = ns.GetCurrentInstance()
    if not inst then return nil end
    local v = visit()
    if not v or v.fmt ~= 2 or v.instance ~= inst or type(v.entered) ~= "number" or v.entered > time() then v = newVisit(inst) end
    return v
end

-- Seconds on the clock (0 until the first engagement; frozen when the last route was completed), or nil outside a dungeon.
function ns.TimeInDungeon()
    local inst = ns.GetCurrentInstance()
    local v = visit()
    if not (inst and v and v.fmt == 2 and v.instance == inst and v.entered) then return nil end
    if not v.started then return 0 end
    return (v.done or time()) - v.started
end

function ns.SplitsRunning() return ns.TimeInDungeon() ~= nil end

-- Start over from now (the Reset button, a dungeon reset).
function ns.SplitsReset()
    local inst = ns.GetCurrentInstance()
    if inst then newVisit(inst) elseif DungeonMapDB then DungeonMapDB.visit = nil end
    if ns.SplitsRefresh then ns.SplitsRefresh() end
end
ns.SplitsStart = ns.SplitsReset

-- Every loading screen: coming into a dungeon starts the clock, unless this is the same visit (a /reload, or back within AWAY seconds, however long that is).
function ns.SplitsEntered()
    if not DungeonMapDB then return end
    local inst = ns.GetCurrentInstance()
    local v = visit()
    if not inst then
        if v and not v.left then v.left = time(); if v.fmt == 2 and not salvageUnmatched(v) then pcall(reportUnfinished, v) end end
        return
    end
    if v and v.fmt == 2 and v.instance == inst and type(v.entered) == "number" and v.entered <= time() and (not v.left or time() - v.left <= AWAY) and not (v.done and v.left) then
        v.left = nil
    else
        v = newVisit(inst)
    end
    -- Combat that was already going on when you came through the door is not the first fight of the run: it is ignored until it has ended (waitCalm),
    -- and so is a combat event in the first moments after the loading screen (GRACE), which the game can fire for the combat you came in with.
    v.arrived = time()
    v.waitCalm = (InCombatLockdown and InCombatLockdown()) and true or nil
end

-- Combat ended (PLAYER_REGEN_ENABLED): the next fight can start the clock.
function ns.SplitsCalm()
    local v = visit()
    if v and v.fmt == 2 then v.waitCalm = nil end
end

-- First combat in the dungeon or an encounter start: the clock starts (once per visit).
function ns.SplitsPull(how)
    local v = current()
    if v and not v.started then
        if (how or "combat") == "combat" and (v.waitCalm or (v.arrived and time() - v.arrived < GRACE)) then return end -- carried in from outside, not a fight here
        begin(v, how or "combat")
        if ns.SplitsRefresh then ns.SplitsRefresh() end
    end
end

-- A boss pull begins / ends (encounter events): logged for the run's detail (wipes are informational, never a ranking factor).
function ns.SplitsPullEncounter(name)
    local v = current()
    if not v then return end
    local w = name and wingOfBoss(v.instance, name)
    if w and v.wing ~= w then
        if v.done or next(v.kills or {}) then v = newVisit(v.instance, w) else v.wing = w end
    end
    begin(v, "encounter")
    ns.RunPullStart(v, name, time() - v.started)
end
function ns.SplitsPullEnd(name, success)
    local v = visit()
    if v and v.fmt == 2 and v.instance == ns.GetCurrentInstance() then ns.RunPullEnd(v, name, success) end
end
-- You died (PLAYER_DEAD): counted while a run is going.
function ns.SplitsDeath()
    local v = visit()
    if v and v.fmt == 2 and v.started and not v.done and v.instance == ns.GetCurrentInstance() then v.deaths = (v.deaths or 0) + 1 end
end

function ns.SplitsEnabled()
    return DungeonMapDB and DungeonMapDB.showSplits == true
end

-- A boss was defeated: write its split (also while the window is closed, so it is complete when opened).
function ns.SplitsKill(name)
    if not name or not DungeonMapDB then return end
    local v = current()
    if not v then return end
    local inst = v.instance
    local key = ns.NormName(name)
    v.kills = v.kills or {}
    if v.kills[key] then return end
    local bw = wingOfBoss(inst, name)
    if bw and v.wing ~= bw then -- a boss of another wing: a new run in that wing (Graveyard, then Library without a reset)
        if v.done or next(v.kills) then v = newVisit(inst, bw) else v.wing = bw end
    end
    if not v.started then -- both start signals were missed: the clock starts now and the run is not ranked
        begin(v, "kill")
        v.why = v.why or "the start of the run was missed"
    end
    for _, m in ipairs(ns.RunMembers()) do -- people who joined or left on the way are in the record too
        local known = false
        for _, o in ipairs(v.members or {}) do
            if o.name == m.name then known = true; if not o.class then o.class = m.class end break end
        end
        if not known then v.members = v.members or {}; v.members[#v.members + 1] = m end
    end
    if ns.MeterSample then pcall(ns.MeterSample, v) end -- what everybody has done so far (a player who leaves is not lost)
    local cum = time() - v.started
    v.kills[key] = cum
    for _, stop in ipairs(ns.RunCreditedBy and ns.RunCreditedBy(inst, key) or {}) do -- this encounter also stands for another route stop
        if not v.kills[stop] then v.kills[stop] = cum end
    end
    noteUnmatched(inst, name, key)
    if ns.RouteAutoSelect then pcall(ns.RouteAutoSelect, inst, v.wing, name, v.started) end -- a boss of only one named route: show that route
    local r = rec(inst)
    -- the segment is the time since the previous split of this visit
    local prev = 0
    for _, t in pairs(v.kills) do if t < cum and t > prev then prev = t end end
    local seg = cum - prev
    local refCum = reference(inst, name, v) -- what to compare with: taken before this split can change it
    v.refs = v.refs or {}
    v.refs[key] = refCum or false
    if not r.best[key] or cum < r.best[key] then r.best[key] = cum end
    if not r.bestSeg[key] or seg < r.bestSeg[key] then r.bestSeg[key] = seg end
    r.last[key] = cum
    -- every official route whose bosses are all down is finished now, at this kill: one record each (Runs.lua)
    v.routesDone = v.routesDone or {}
    local routes = ns.OfficialRoutes(inst, v.wing)
    local all = #routes > 0
    for _, rt in ipairs(routes) do
        local rk = ns.RouteKey(rt)
        if not v.routesDone[rk] and boolKills(v.kills, rt, inst) then
            v.routesDone[rk] = cum
            pcall(ns.RecordRun, v, rt, cum)
        end
        if not v.routesDone[rk] then all = false end
    end
    if all and not v.done then
        v.done = time()
        if not r.total or cum < r.total then r.total = cum end
    end
    if ns.SplitsRefresh then ns.SplitsRefresh() end
end

-- Window --------------------------------------------------------------------------------------------------------------------------
local ROW_H, MAX_ROWS = 15, 14

local function build()
    win = CreateFrame("Frame", "DungeonMapSplits", UIParent, "BackdropTemplate")
    win:SetSize(300, 60)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        DungeonMapDB.splitsPos = { p, rp, x, y }
    end)
    pcall(win.SetBackdrop, win, { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    pcall(win.SetBackdropColor, win, 0, 0, 0, 0.65)
    pcall(win.SetBackdropBorderColor, win, 0.6, 0.48, 0.25, 1)
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.title:SetPoint("TOPLEFT", 10, -8)
    win.title:SetPoint("RIGHT", win, "RIGHT", -96, 0)
    win.title:SetJustifyH("LEFT")
    win.title:SetWordWrap(false)
    win.timer = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.timer:SetPoint("TOPRIGHT", -26, -6)
    win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    win.close:SetSize(22, 22)
    win.close:SetPoint("TOPRIGHT", 2, 2)
    win.close:SetScript("OnClick", function()
        DungeonMapDB.showSplits = false
        ns.Print("Time in dungeon window off. Turn it on again with /dm timer or in the options.")
        ns.SplitsRefresh()
    end)
    win.reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.reset:SetSize(54, 18)
    win.reset:SetText("Reset")
    win.reset:SetScript("OnClick", function() ns.SplitsReset() end)
    win.reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Stop this run and start over (the clock waits for the next first fight)")
        GameTooltip:Show()
    end)
    win.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.delta = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.delta:SetSize(38, 18)
    win.delta:SetScript("OnClick", function()
        DungeonMapDB.splitDeltas = DungeonMapDB.splitDeltas == false
        ns.SplitsRefresh()
    end)
    win.delta:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Show or hide the +/- against your best run, and the pace line")
        GameTooltip:Show()
    end)
    win.delta:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.pace = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.rows = {}
    win:Hide()
end

local function row(i)
    local r = win.rows[i]
    if not r then
        r = {}
        r.name = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.seg = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.cum = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.delta = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        win.rows[i] = r
    end
    return r
end

local function place(i, y)
    local r = row(i)
    r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -y); r.name:SetWidth(112)
    r.seg:ClearAllPoints(); r.seg:SetPoint("TOPRIGHT", win, "TOPLEFT", 178, -y)
    r.cum:ClearAllPoints(); r.cum:SetPoint("TOPRIGHT", win, "TOPLEFT", 234, -y)
    r.delta:ClearAllPoints(); r.delta:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -y)
    return r
end

function ns.SplitsRefresh()
    if not win then build() end
    local inst = ns.GetCurrentInstance()
    if not (ns.SplitsEnabled() and inst) then win:Hide() return end
    local run = current()
    run.kills, run.refs = run.kills or {}, run.refs or {}
    if DungeonMapDB.splitsPos then
        local p = DungeonMapDB.splitsPos
        win:ClearAllPoints()
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif not win.placed then
        win:SetPoint("RIGHT", UIParent, "RIGHT", -30, 80)
        win.placed = true
    end
    local names = lineup(inst, run.wing)
    local showDeltas = DungeonMapDB.splitDeltas ~= false
    win.title:SetText("Time in " .. (ns.Dungeons[inst] and ns.Dungeons[inst].name or "dungeon"))
    win.timer:SetText((run.done and GREEN or (not run.started and GREY or "")) .. ns.FormatTime(ns.TimeInDungeon() or 0))
    -- a boss is skipped when a later one in the list was defeated first (it can still be killed afterwards)
    local lastKilled = 0
    for i, name in ipairs(names) do if run.kills[ns.NormName(name)] then lastKilled = i end end
    local y, n = 30, 0
    for i, name in ipairs(names) do
        if i > MAX_ROWS then break end
        n = n + 1
        local r = place(i, y)
        local key = ns.NormName(name)
        local cum = run.kills[key]
        r.name:SetText(name)
        r.name:SetTextColor(cum and 0.7 or 1, cum and 0.7 or 1, cum and 0.7 or 1)
        if cum then
            local prev = 0
            for _, v in pairs(run.kills) do if v < cum and v > prev then prev = v end end
            local color, txt = ns.SplitDelta(cum, run.refs and run.refs[key] or nil)
            r.seg:SetText(GREY .. ns.FormatTime(cum - prev))
            r.cum:SetText(WHITE .. ns.FormatTime(cum))
            r.delta:SetText(showDeltas and (color .. txt) or "")
        elseif i < lastKilled and ns.BossUndetectable and ns.BossUndetectable(inst, key) then
            -- a stop the game never reports (Bossman Toof's bridge event): not skipped, it is credited when the run finishes
            r.seg:SetText("")
            r.cum:SetText(GREY .. "event")
            r.delta:SetText("")
        elseif i < lastKilled then
            r.name:SetTextColor(0.5, 0.5, 0.5)
            r.seg:SetText("")
            r.cum:SetText(GREY .. "skipped")
            r.delta:SetText("")
        else
            local ref = reference(inst, name, run)
            r.seg:SetText("")
            r.cum:SetText(ref and (GREY .. ns.FormatTime(ref)) or "")
            r.delta:SetText("")
        end
        r.name:Show(); r.seg:Show(); r.cum:Show(); r.delta:Show()
        y = y + ROW_H
    end
    for i = n + 1, #win.rows do
        local r = win.rows[i]
        r.name:Hide(); r.seg:Hide(); r.cum:Hide(); r.delta:Hide()
    end
    -- the pace line: where the run is heading, from the reference run's remaining time after the last boss that both runs have
    local pace
    local route = targetRoute(inst, run.wing, run.kills)
    local refRun = route and run.started and not run.done and showDeltas and ns.RunReference(inst, run.wing, route, DungeonMapDB.splitCompareLast)
    if refRun then
        local lastK, lastT
        for k in pairs(route.keys) do
            local t = run.kills[k]
            if t and refRun.kills[k] and (not lastT or t > lastT) then lastK, lastT = k, t end
        end
        if lastK then
            local projected = lastT + (refRun.total - refRun.kills[lastK])
            local color, txt = ns.SplitDelta(projected, refRun.total)
            pace = format("%sPace %s|r  %s(%s)", WHITE, ns.FormatTime(projected), color, txt)
        end
    end
    if not pace and run.started and not run.done and next(run.routesDone or {}) then -- a route finished while the clock goes on (Living side done, on to the Undead side)
        local parts = {}
        for _, rt in ipairs(ns.OfficialRoutes(inst, run.wing)) do
            local t = run.routesDone[ns.RouteKey(rt)]
            if t then parts[#parts + 1] = format("%s %s", rt.name, ns.FormatTime(t)) end
        end
        pace = GREEN .. table.concat(parts, "  ") .. "|r"
    end
    win.pace:SetText(pace or (not run.started and (GREY .. "The clock starts with the first fight") or ""))
    win.delta:SetText(showDeltas and "+/-" or (GREY .. "+/-"))
    win.reset:ClearAllPoints()
    win.reset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 6)
    win.delta:ClearAllPoints()
    win.delta:SetPoint("RIGHT", win.reset, "LEFT", -4, 0)
    win.pace:ClearAllPoints()
    win.pace:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 10, 9)
    win:SetHeight(y + 28)
    win:Show()
    -- the clock: one tick per second while the window is shown and the visit is going (no per-frame code)
    if run.started and not run.done and C_Timer.NewTicker and not win.ticker then
        win.ticker = C_Timer.NewTicker(1, function()
            local v, t = visit(), ns.TimeInDungeon()
            if win:IsShown() and v and t and not v.done then
                win.timer:SetText(ns.FormatTime(t))
            else
                win.ticker:Cancel()
                win.ticker = nil
            end
        end)
    end
end

function ns.SplitsToggle()
    DungeonMapDB.showSplits = not DungeonMapDB.showSplits
    ns.Print("Time in dungeon window " .. (DungeonMapDB.showSplits and "on: the clock starts with the first fight. /dm timer again to turn it off." or "off."))
    ns.SplitsRefresh()
end
