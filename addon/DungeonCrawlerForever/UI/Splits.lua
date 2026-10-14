-- Split timer (speedrun style): a small window in the dungeon with one line per boss. Each line shows the segment time (since the previous split),
-- the time since the start and the difference to your best (or last) time: green = faster or the first time set, red = slower.
-- Light on purpose: no per-frame code, one 1-second ticker while the window is visible, two numbers saved per boss.
-- Off by default: Options "Show the split timer in dungeons", the X on the window, or /dm splits.
-- Saved data: DungeonMapDB.splits[instanceID] = { best = {[boss] = cumulative seconds}, bestSeg = {[boss] = seconds}, last = {[boss] = cumulative}, total = best full run }
-- The route (when the dungeon has one) decides the order of the lines, otherwise the dungeon's boss list does.
local _, ns = ...

local GREEN, RED, GREY, WHITE = "|cff66ff66", "|cffff6666", "|cff9a9a9a", "|cffffffff"
local run -- { instance, wing, start = GetTime() or nil (not started), kills = { [normalised boss name] = cumulative seconds }, done = bool }
local win

local function rec(instanceID)
    DungeonMapDB.splits = DungeonMapDB.splits or {}
    local r = DungeonMapDB.splits[instanceID]
    if not r then
        r = { best = {}, bestSeg = {}, last = {} }
        DungeonMapDB.splits[instanceID] = r
    end
    return r
end

-- The bosses a run goes through, in order: the route's stops, else the regular bosses of the dungeon (no trash, no summoned ones).
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

local function clock(sec)
    local neg = sec < 0
    sec = math.floor(math.abs(sec) + 0.5)
    local s = ns.FormatTime(sec)
    return (neg and "-" or "") .. s
end

local function currentWing(instanceID)
    return DungeonMapDB.lastWing and DungeonMapDB.lastWing[instanceID] or nil
end

-- The comparison for a boss: your best cumulative time there, or the last run's (option).
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

function ns.SplitsRunning() return run and run.start ~= nil end

function ns.SplitsStart(force)
    local inst = ns.GetCurrentInstance()
    if not inst then return end
    if run and run.instance == inst and run.start and not force then return end
    run = { instance = inst, wing = currentWing(inst), start = GetTime(), kills = {}, done = false }
    if ns.SplitsRefresh then ns.SplitsRefresh() end
end

function ns.SplitsReset()
    local inst = ns.GetCurrentInstance()
    run = inst and { instance = inst, wing = currentWing(inst), start = nil, kills = {}, done = false } or nil
    if ns.SplitsRefresh then ns.SplitsRefresh() end
end

-- first combat in the dungeon starts the clock
function ns.SplitsPull()
    if not ns.SplitsEnabled() then return end
    local inst = ns.GetCurrentInstance()
    if not inst then return end
    if not run or run.instance ~= inst then run = { instance = inst, wing = currentWing(inst), start = nil, kills = {}, done = false } end
    if not run.start and not run.done then ns.SplitsStart() end
end

function ns.SplitsEnabled()
    return DungeonMapDB and DungeonMapDB.showSplits == true
end

-- A boss was defeated: write its split.
function ns.SplitsKill(name)
    if not ns.SplitsEnabled() or not name then return end
    local inst = ns.GetCurrentInstance()
    if not inst then return end
    if not run or run.instance ~= inst or not run.start then ns.SplitsStart() end
    if not (run and run.start) then return end
    local key = ns.NormName(name)
    if run.kills[key] then return end
    local cum = GetTime() - run.start
    run.kills[key] = cum
    local r = rec(inst)
    -- the segment is the time since the previous split of this run
    local prev = 0
    for _, v in pairs(run.kills) do if v < cum and v > prev then prev = v end end
    local seg = cum - prev
    local refCum = reference(inst, name) -- what to compare with: taken before this split can change it
    run.refs = run.refs or {}
    run.refs[key] = refCum or false
    if not r.best[key] or cum < r.best[key] then r.best[key] = cum end
    if not r.bestSeg[key] or seg < r.bestSeg[key] then r.bestSeg[key] = seg end
    r.last[key] = cum
    local all = true
    for _, n in ipairs(lineup(inst, run.wing)) do if not run.kills[ns.NormName(n)] then all = false end end
    if all then
        run.done = true
        if not r.total or cum < r.total then r.total = cum end
    end
    run.lastDelta = { name = name, cum = cum, ref = refCum }
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
    win.timer = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.timer:SetPoint("TOPRIGHT", -26, -6)
    win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    win.close:SetSize(22, 22)
    win.close:SetPoint("TOPRIGHT", 2, 2)
    win.close:SetScript("OnClick", function()
        DungeonMapDB.showSplits = false
        ns.Print("Split timer off. Turn it on again with /dm splits or in the options.")
        ns.SplitsRefresh()
    end)
    win.reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.reset:SetSize(54, 18)
    win.reset:SetText("Reset")
    win.reset:SetScript("OnClick", function() ns.SplitsReset() end)
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
    if not run or run.instance ~= inst then run = { instance = inst, wing = currentWing(inst), start = nil, kills = {}, done = false } end
    if DungeonMapDB.splitsPos then
        local p = DungeonMapDB.splitsPos
        win:ClearAllPoints()
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif not win.placed then
        win:SetPoint("RIGHT", UIParent, "RIGHT", -30, 80)
        win.placed = true
    end
    local names = lineup(inst, run.wing)
    win.title:SetText(ns.Dungeons[inst] and ns.Dungeons[inst].name or "Splits")
    local elapsed = run.start and (GetTime() - run.start) or 0
    win.timer:SetText(run.start and ns.FormatTime(elapsed) or (GREY .. "0:00"))
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
    -- the clock: one tick per second while the window is shown and a run is going (no per-frame code)
    if run.start and not run.done and C_Timer.NewTicker and not win.ticker then
        win.ticker = C_Timer.NewTicker(1, function()
            if win:IsShown() and run and run.start and not run.done then
                win.timer:SetText(ns.FormatTime(GetTime() - run.start))
            else
                win.ticker:Cancel()
                win.ticker = nil
            end
        end)
    end
end

function ns.SplitsToggle()
    DungeonMapDB.showSplits = not DungeonMapDB.showSplits
    ns.Print("Split timer " .. (DungeonMapDB.showSplits and "on: the clock starts with the first fight in a dungeon. /dm splits again to turn it off." or "off."))
    ns.SplitsRefresh()
end
