-- Time in dungeon: a small window in the dungeon with one line per boss. The clock runs from the moment you come in, so buffing, waiting for
-- people and corpse runs count too: it is the time you spent there, not a race clock. Each boss line shows the segment time (since the previous
-- boss), the time in the dungeon when it fell, and the difference to your best (or last) visit: green = faster or the first time set, red = slower.
-- Light on purpose: no per-frame code, one 1-second ticker while the window is visible, two numbers saved per boss.
-- Off by default: Options "Show the time in dungeon window", the X on the window, or /dm timer (/dm splits).
-- The visit (DungeonMapDB.visit) survives /reload and leaving for a short while (a corpse run, repairs): it is kept when you come back to the
-- same dungeon within AWAY seconds, and starts over after a dungeon reset, the Reset button, or a longer time away.
-- Saved data: DungeonMapDB.splits[instanceID] = { best = {[boss] = seconds in the dungeon}, bestSeg = {[boss] = seconds}, last = {[boss] = seconds}, total = best full visit }
-- The route (when the dungeon has one) decides the order of the lines, otherwise the dungeon's boss list does.
local _, ns = ...

local GREEN, RED, GREY, WHITE = "|cff66ff66", "|cffff6666", "|cff9a9a9a", "|cffffffff"
local AWAY = 1800 -- seconds outside the dungeon after which coming back starts a new visit
local win

-- the visit: { instance, wing, started = time() when you came in, kills = { [normalised boss name] = seconds in the dungeon },
--   refs = { [boss] = reference or false }, done = time() when the last boss fell, left = time() when you went out }
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

-- The bosses a visit goes through, in order: the route's stops, else the regular bosses of the dungeon (no trash, no summoned ones).
local function lineup(instanceID, wing)
    local out, seen = {}, {}
    local route = ns.GetRoute and ns.GetRoute(instanceID, wing)
    if route then
        for _, p in ipairs(route) do
            if p.boss and not seen[ns.NormName(p.boss)] then
                seen[ns.NormName(p.boss)] = true
                out[#out + 1] = p.boss
            end
        end
    end
    if #out == 0 then
        for _, b in ipairs(ns.GetBosses(instanceID, nil, wing)) do
            if not b.trash and not b.summoned and not b.sub and not seen[ns.NormName(b.name)] then
                seen[ns.NormName(b.name)] = true
                out[#out + 1] = b.name
            end
        end
    end
    return out
end
ns.SplitLineup = lineup

local function currentWing(instanceID)
    return DungeonMapDB.lastWing and DungeonMapDB.lastWing[instanceID] or nil
end

-- The comparison for a boss: your best time in the dungeon there, or the last visit's (option).
local function reference(instanceID, name)
    local r = rec(instanceID)
    local key = ns.NormName(name)
    if DungeonMapDB.splitCompareLast then return r.last[key] end
    return r.best[key]
end

-- Colour and text for a split: nil reference = first time set (green).
function ns.SplitDelta(cum, ref)
    if not ref then return GREEN, "new" end
    local d = cum - ref
    if d <= 0 then return GREEN, "-" .. ns.FormatTime(-d) end
    return RED, "+" .. ns.FormatTime(d)
end

local function newVisit(inst)
    DungeonMapDB.visit = { instance = inst, wing = currentWing(inst), started = time(), kills = {}, refs = {} }
    return DungeonMapDB.visit
end

-- The visit in this dungeon (made when missing). nil outside a dungeon.
local function current()
    local inst = ns.GetCurrentInstance()
    if not inst then return nil end
    local v = visit()
    if not v or v.instance ~= inst or type(v.started) ~= "number" or v.started > time() then v = newVisit(inst) end
    return v
end

-- Seconds spent in the current dungeon (frozen when the last boss fell), or nil outside one.
function ns.TimeInDungeon()
    local inst = ns.GetCurrentInstance()
    local v = visit()
    if not (inst and v and v.instance == inst and v.started) then return nil end
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

-- Every loading screen: coming into a dungeon starts the clock, unless this is the same visit (a /reload, or back within AWAY seconds).
function ns.SplitsEntered()
    if not DungeonMapDB then return end
    local inst = ns.GetCurrentInstance()
    local v = visit()
    if not inst then
        if v and not v.left then v.left = time() end
        return
    end
    if v and v.instance == inst and type(v.started) == "number" and v.started <= time() and (not v.left or time() - v.left <= AWAY) then
        v.left = nil
    else
        newVisit(inst)
    end
end

function ns.SplitsPull() current() end -- (the clock already runs from the door; this only makes sure a visit exists)

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
    local cum = time() - v.started
    v.kills[key] = cum
    local r = rec(inst)
    -- the segment is the time since the previous split of this visit
    local prev = 0
    for _, t in pairs(v.kills) do if t < cum and t > prev then prev = t end end
    local seg = cum - prev
    local refCum = reference(inst, name) -- what to compare with: taken before this split can change it
    v.refs = v.refs or {}
    v.refs[key] = refCum or false
    if not r.best[key] or cum < r.best[key] then r.best[key] = cum end
    if not r.bestSeg[key] or seg < r.bestSeg[key] then r.bestSeg[key] = seg end
    r.last[key] = cum
    local all = true
    for _, n in ipairs(lineup(inst, v.wing)) do if not v.kills[ns.NormName(n)] then all = false end end
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
        GameTooltip:SetText("Start the clock again from now")
        GameTooltip:Show()
    end)
    win.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    win.title:SetText("Time in " .. (ns.Dungeons[inst] and ns.Dungeons[inst].name or "dungeon"))
    win.timer:SetText((run.done and GREEN or "") .. ns.FormatTime(ns.TimeInDungeon() or 0))
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
            r.delta:SetText(color .. txt)
        elseif i < lastKilled then
            r.name:SetTextColor(0.5, 0.5, 0.5)
            r.seg:SetText("")
            r.cum:SetText(GREY .. "skipped")
            r.delta:SetText("")
        else
            local ref = reference(inst, name)
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
    win.reset:ClearAllPoints()
    win.reset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 6)
    win:SetHeight(y + 28)
    win:Show()
    -- the clock: one tick per second while the window is shown and the visit is going (no per-frame code)
    if not run.done and C_Timer.NewTicker and not win.ticker then
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
    ns.Print("Time in dungeon window " .. (DungeonMapDB.showSplits and "on: it counts from the moment you come in, buffs and waiting included. /dm timer again to turn it off." or "off."))
    ns.SplitsRefresh()
end
