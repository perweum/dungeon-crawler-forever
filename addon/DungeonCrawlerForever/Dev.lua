-- DEVELOPER ONLY, NOT SHIPPED: tools/package.py leaves this file (and its line in the TOC) out of the release zip (D-078).
-- View the quests as the other faction, to test Alliance quests on a Horde character (and the other way round).
-- /dm dropmarkers <questID> deletes the markers recorded in game for a quest; /dm dropboss <name> forgets a boss position recorded in game.
-- /dm devtimer [instanceID] shows the time in dungeon window outside a dungeon, with a made-up run, to work on its layout; /dm devtimer off puts everything back.
-- /dm runlist [text] lists the runs you hold (your own "o1, o2 ..." and the ones received from others "b1, b2 ..."), newest first, optionally only those that match the text
-- (a dungeon, a player); /dm rundel o1 b3 ... deletes them. A deleted run is remembered (DungeonMapDB.deletedRuns) so it does not come back when others share it again.
-- A button in edit mode cycles: real faction -> Alliance -> Horde; /dm viewas alliance|horde|off does the same. Kept for this session only (not saved).
local _, ns = ...

local NAME = { A = "Alliance", H = "Horde" }

local function set(f)
    ns.devFaction = f
    ns.Print(f and format("DEV: quests are shown as %s now (this session only; /dm viewas off to go back). Quests you do not have are not marked as started or done.", NAME[f])
        or "DEV: quests are shown for your own faction again.")
    if ns.RefreshMap then ns.RefreshMap() end
end

local function cycle()
    local nextF = { [false] = "A", A = "H", H = false }
    set(nextF[ns.devFaction or false] or nil)
end

-- /dm devtimer: the time in dungeon window outside a dungeon. ns.GetCurrentInstance answers with the chosen dungeon while it is on (a real dungeon wins), and a made-up
-- visit (the clock at 12:34, the first bosses defeated) is put in DungeonMapDB.visit; /dm devtimer off restores what was there. Not saved: /reload ends it.
local devTimer, devTimerOff
local function devTimerOn(inst)
    if devTimer then devTimerOff() end
    if not ns.Dungeons[inst] then ns.Print("DEV: no dungeon with the map id " .. tostring(inst) .. ".") return end
    devTimer = { inst = inst, realGet = ns.GetCurrentInstance, oldVisit = DungeonMapDB.visit, oldShow = DungeonMapDB.showSplits }
    local real = ns.GetCurrentInstance
    ns.GetCurrentInstance = function(...) return real(...) or inst end
    local now = time()
    local v = { fmt = 2, instance = inst, entered = now - 800, started = now - 754, startedBy = "combat", kills = {}, refs = {}, routesDone = {}, pulls = {}, deaths = 1, level = 30, members = {}, size = 5 }
    local names = ns.SplitLineup and ns.SplitLineup(inst, nil) or {}
    local t = 0
    for i, name in ipairs(names) do
        if i > 3 then break end
        t = t + 140 + i * 40
        v.kills[ns.NormName(name)] = t
    end
    DungeonMapDB.visit = v
    DungeonMapDB.showSplits = true
    ns.Print(format("DEV: the time in dungeon window is shown for %s with a made-up run. /dm devtimer off to end it.", ns.Dungeons[inst].name))
    if ns.SplitsRefresh then ns.SplitsRefresh() end
end
function devTimerOff()
    if not devTimer then return end
    ns.GetCurrentInstance = devTimer.realGet
    DungeonMapDB.visit = devTimer.oldVisit
    DungeonMapDB.showSplits = devTimer.oldShow
    devTimer = nil
    ns.Print("DEV: the time in dungeon window is back to normal.")
    if ns.SplitsRefresh then ns.SplitsRefresh() end
end

-- Runs: list and delete (own runs and the ones received from others). Local to this game: nothing is told to anyone, and the shipped addon is not involved.
local listed = {} -- token -> { list, run }
local function runLine(tag, r)
    local d = ns.Dungeons[r.inst]
    return format("%s: %s %s%s, %s, %s, %s%s", tag, d and d.name or r.inst, r.rname or "", (r.bracket == "over") and " (over)" or "", ns.FormatTime and ns.FormatTime(r.total or 0) or tostring(r.total),
        tostring(r.by or "?"), date and date("%d.%m %H:%M", r.finished or 0) or "", r.ranked and "" or " [not ranked]")
end
local function runList(filter)
    listed = {}
    filter = filter and filter:lower() or ""
    local shown = 0
    for _, def in ipairs({ { "o", DungeonMapDB.runs or {} }, { "b", DungeonMapDB.board or {} } }) do
        local rows = {}
        for _, r in ipairs(def[2]) do rows[#rows + 1] = r end
        table.sort(rows, function(a, b) return (a.finished or 0) > (b.finished or 0) end)
        for i, r in ipairs(rows) do
            local tag = def[1] .. i
            local line = runLine(tag, r)
            if filter == "" or line:lower():find(filter, 1, true) then
                listed[tag] = { def[2], r }
                if shown < 40 then ns.Print(line) end
                shown = shown + 1
            end
        end
    end
    ns.Print(format("DEV: %d run(s)%s. /dm rundel o1 b3 ... deletes the ones you name (the first 40 are listed; give some text to narrow it down).", shown, filter ~= "" and (" matching '" .. filter .. "'") or ""))
end
local function runDelete(tokens)
    DungeonMapDB.deletedRuns = DungeonMapDB.deletedRuns or {}
    local n = 0
    for tok in tokens:gmatch("%S+") do
        local e = listed[tok:lower()]
        if not e then ns.Print("DEV: " .. tok .. " is not in the last list (/dm runlist first).")
        else
            for i = #e[1], 1, -1 do
                if e[1][i] == e[2] then
                    if e[2].id then DungeonMapDB.deletedRuns[e[2].id] = time() end
                    table.remove(e[1], i)
                    listed[tok:lower()] = nil
                    n = n + 1
                    break
                end
            end
        end
    end
    ns.Print(format("DEV: %d run(s) deleted. The numbers changed: /dm runlist again before the next delete.", n))
    if ns.RefreshMap then ns.RefreshMap() end
end
local function purgeDeleted()
    local gone = DungeonMapDB and DungeonMapDB.deletedRuns
    if not gone or not next(gone) then return end
    for _, list in ipairs({ DungeonMapDB.board or {}, DungeonMapDB.runs or {} }) do
        for i = #list, 1, -1 do if list[i].id and gone[list[i].id] then table.remove(list, i) end end
    end
end
if ns.CommsReceive then -- what others share is checked against the deleted ones, so a run you removed does not come back
    local origReceive = ns.CommsReceive
    ns.CommsReceive = function(...)
        local r = origReceive(...)
        purgeDeleted()
        return r
    end
end

-- /dm viewas: wrap the slash handler so Commands.lua (shipped) does not know about it
local orig = SlashCmdList.DUNGEONMAP
SlashCmdList.DUNGEONMAP = function(msg)
    local arg = type(msg) == "string" and msg:match("^%s*viewas%s*(%S*)%s*$")
    if arg then
        arg = arg:lower()
        if arg == "alliance" or arg == "a" then set("A")
        elseif arg == "horde" or arg == "h" then set("H")
        elseif arg == "off" then set(nil)
        else cycle() end
        return
    end
    if type(msg) == "string" and (msg:match("^%s*runlist") ) then
        runList(msg:match("^%s*runlist%s*(.-)%s*$"))
        return
    end
    local del = type(msg) == "string" and msg:match("^%s*rundel%s+(.-)%s*$")
    if del then runDelete(del) return end
    local dt = type(msg) == "string" and msg:match("^%s*devtimer%s*(%S*)%s*$")
    if dt then
        if dt == "off" then devTimerOff()
        else devTimerOn(tonumber(dt) or 36) end -- (Deadmines unless you give a dungeon's map id)
        return
    end
    local dropBoss = type(msg) == "string" and msg:match("^%s*dropboss%s+(.-)%s*$")
    if dropBoss and dropBoss ~= "" then -- /dm dropboss <name>: forget the position recorded in game for that boss (the shipped one comes back)
        local n = 0
        for _, bosses in pairs(DungeonMapDB.manual or {}) do
            if bosses[dropBoss] then bosses[dropBoss] = nil; n = n + 1 end
        end
        ns.Print(format("DEV: %d recorded position(s) of %s removed (the shipped position is used again after /reload).", n, dropBoss))
        if ns.RefreshMap then ns.RefreshMap() end
        return
    end
    local drop = type(msg) == "string" and msg:match("^%s*dropmarkers%s+(%d+)%s*$")
    if drop then -- /dm dropmarkers <questID>: delete the quest markers recorded in game for that quest (a wrong pick that cannot be shift-clicked away)
        local id, n = tonumber(drop), 0
        for _, floors in pairs(DungeonMapDB.markers or {}) do
            for _, list in pairs(floors) do
                for i = #list, 1, -1 do
                    if list[i].quest == id then table.remove(list, i); n = n + 1 end
                end
            end
        end
        ns.Print(format("DEV: %d recorded marker(s) of quest %d removed (shipped markers are not touched).", n, id))
        if ns.RefreshMap then ns.RefreshMap() end
        return
    end
    return orig(msg)
end

-- the edit-mode button, made when the map view exists and shown only in edit mode
local btn
local function update()
    local view = _G.DungeonMapView
    if not view then return end
    if not btn then
        btn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        btn:SetFrameLevel(view:GetFrameLevel() + 100)
        btn:SetSize(170, 22)
        btn:SetPoint("TOPLEFT", view, "TOPLEFT", 8, -8)
        btn:SetScript("OnClick", cycle)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Developer: view quests as")
            GameTooltip:AddLine("Cycles your own faction, Alliance and Horde, to test the quests of the other side. Not saved, not in the release.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
    end
    btn:SetText("View as: " .. (ns.devFaction and NAME[ns.devFaction] or "my faction"))
    btn:SetShown(ns.editing and true or false)
end
hooksecurefunc(ns, "RefreshMap", update)
