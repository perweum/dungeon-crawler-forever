-- Quest tracker: a small window that follows the quest journey of one dungeon (the Journey view in the Quests tab) and says what to do next.
-- Turned on with "Track journey" in the Quests tab, with the offer after your first quest from a dungeon, or /dm tracker. It stays open until you close it.
-- Saved: DungeonMapDB.tracker = { instance, x, y, offered }, DungeonMapDB.questSkip[character][kind .. questID] = true ("Skip step", per character).
local _, ns = ...

local frame
local MAX_THEN = 2

local function charKey()
    return ((UnitName and UnitName("player")) or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function skipSet()
    DungeonMapDB.questSkip = DungeonMapDB.questSkip or {}
    local k = charKey()
    DungeonMapDB.questSkip[k] = DungeonMapDB.questSkip[k] or {}
    return DungeonMapDB.questSkip[k]
end

local function cfg()
    DungeonMapDB.tracker = DungeonMapDB.tracker or {}
    return DungeonMapDB.tracker
end

function ns.TrackerInstance() return DungeonMapDB and DungeonMapDB.tracker and DungeonMapDB.tracker.instance or nil end

local function stepKey(s) return s.kind .. s.e.q.id end

-- the steps still to do for this character: the journey without the ones you skipped
function ns.TrackerSteps(instanceID)
    local steps = ns.GetQuestJourney and ns.GetQuestJourney(instanceID)
    if not steps then return {} end
    local skip, out = skipSet(), {}
    for _, s in ipairs(steps) do
        if not skip[stepKey(s)] then out[#out + 1] = s end
    end
    return out
end

local function stepText(s, instanceID)
    local q = s.e.q
    local title = ns.QuestTitle(q)
    local dname = ns.Dungeons[instanceID] and ns.Dungeons[instanceID].name or "the dungeon"
    if s.kind == "dungeon" then
        return format("In %s: |cffffd100%s|r", dname, title), q.objective
    elseif s.kind == "handin" then
        local who = q.turnin and q.turnin ~= "" and q.turnin or nil
        local zone = q.turninZone and ns.JourneyZone(q.turninZone) or nil
        local where = who and (zone and (who .. ", " .. zone) or who) or zone
        return format("Hand in |cffffd100%s|r", title), where
    end
    local who = q.giver and q.giver ~= "" and q.giver or nil
    local zone = q.giverZone and ns.JourneyZone(q.giverZone) or nil
    local where = who and (zone and (who .. ", " .. zone) or who) or zone
    return format("Pick up |cffffd100%s|r", title), where
end

-- where the step is on a zone map: uiMapID, x, y (percent) or nil
local function stepSpot(s)
    local q = s.e.q
    if s.kind == "handin" then
        if q.tmap and q.tx and q.ty then return q.tmap, q.tx, q.ty end
    elseif s.kind == "pickup" then
        if q.gmap and q.gx and q.gy then return q.gmap, q.gx, q.gy end
    end
end

local function setWaypoint(map, x, y)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return false end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    return ok
end

local function makeButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

local function build()
    if frame then return frame end
    local f = ns.NewWindow("DungeonCrawlerTracker")
    f:SetSize(300, 150)
    f:SetFrameStrata("MEDIUM") -- under the world map, which is full screen
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local c = cfg()
        c.point, _, c.relPoint, c.x, c.y = self:GetPoint()
    end)
    if f.TitleText then f.TitleText:SetText("Quest journey") elseif f.title then f.title:SetText("Quest journey") end
    local close = f.CloseButton or _G["DungeonCrawlerTrackerCloseButton"]
    if type(close) == "table" and close.SetScript then close:SetScript("OnClick", function() ns.TrackerSet(nil) end) end

    f.dungeon = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.dungeon:SetPoint("TOPLEFT", 14, -30)
    f.dungeon:SetWidth(272)
    f.dungeon:SetJustifyH("LEFT")
    f.next = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.next:SetPoint("TOPLEFT", f.dungeon, "BOTTOMLEFT", 0, -6)
    f.next:SetWidth(272)
    f.next:SetJustifyH("LEFT")
    f.where = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.where:SetPoint("TOPLEFT", f.next, "BOTTOMLEFT", 0, -2)
    f.where:SetWidth(272)
    f.where:SetJustifyH("LEFT")
    f.where:SetTextColor(0.75, 0.75, 0.75)
    f.then1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.then1:SetPoint("TOPLEFT", f.where, "BOTTOMLEFT", 0, -6)
    f.then1:SetWidth(272)
    f.then1:SetJustifyH("LEFT")
    f.then1:SetTextColor(0.6, 0.6, 0.6)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(1, 0.62, 0.38)

    f.waypoint = makeButton(f, "Waypoint", 84)
    f.waypoint:SetScript("OnClick", function() ns.TrackerWaypoint() end)
    f.skip = makeButton(f, "Skip step", 84)
    f.skip:SetScript("OnClick", function() ns.TrackerSkip() end)
    f.skip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Skip step")
        GameTooltip:AddLine("Leaves this step out for this character (a quest you do not want, or already did another way).", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    f.skip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.yes = makeButton(f, "Track it", 90)
    f.yes:SetScript("OnClick", function() if f.offerInstance then ns.TrackerSet(f.offerInstance) end end)
    f.no = makeButton(f, "No thanks", 90)
    f.no:SetScript("OnClick", function() f.offerInstance = nil; f:Hide() end)

    local c = cfg()
    f:ClearAllPoints()
    if c.x and c.y then f:SetPoint(c.point or "TOPLEFT", UIParent, c.relPoint or "TOPLEFT", c.x, c.y)
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120) end
    f:Hide()
    frame = f
    return f
end

local function layout(f, offer)
    f.waypoint:SetShown(not offer)
    f.skip:SetShown(not offer)
    f.yes:SetShown(offer)
    f.no:SetShown(offer)
    f.then1:SetShown(not offer)
    f.status:ClearAllPoints()
    f.status:SetPoint("TOPLEFT", offer and f.where or f.then1, "BOTTOMLEFT", 0, -4)
    f.status:SetWidth(272)
    local h = 30 + f.dungeon:GetStringHeight() + 6 + f.next:GetStringHeight() + 2 + f.where:GetStringHeight()
    if not offer then h = h + 6 + f.then1:GetStringHeight() end
    h = h + 4 + math.max(0, f.status:GetStringHeight()) + 10
    for _, b in ipairs(offer and { f.yes, f.no } or { f.waypoint, f.skip }) do b:ClearAllPoints() end
    local a, b = (offer and f.yes or f.waypoint), (offer and f.no or f.skip)
    a:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    b:SetPoint("LEFT", a, "RIGHT", 6, 0)
    f:SetHeight(h + 22 + 12)
end

local function refresh()
    local inst = ns.TrackerInstance()
    if not inst or not frame then return end
    local f = frame
    f.offerInstance = nil
    local dname = ns.Dungeons[inst] and ns.Dungeons[inst].name or ("Dungeon " .. inst)
    local steps = ns.TrackerSteps(inst)
    f.dungeon:SetText(dname)
    f.status:SetText("")
    if #steps == 0 then
        f.next:SetText("|cff66dd66Journey complete|r")
        f.where:SetText("Nothing left to do for the quests of this dungeon.")
        f.then1:SetText("")
        f.cur = nil
    else
        local s = steps[1]
        f.cur = s
        local t, w = stepText(s, inst)
        f.next:SetText("Next: " .. t)
        f.where:SetText(w or "")
        local lines = {}
        for i = 2, math.min(#steps, 1 + MAX_THEN) do
            local tt = stepText(steps[i], inst)
            lines[#lines + 1] = "then: " .. tt
        end
        if #steps > 1 + MAX_THEN then lines[#lines + 1] = format("+ %d more steps", #steps - 1 - MAX_THEN) end
        f.then1:SetText(table.concat(lines, "\n"))
        if f.wpOn then
            local m, x, y = stepSpot(s)
            if m then setWaypoint(m, x, y) end
        end
    end
    local has = f.cur and stepSpot(f.cur) and true or false
    f.waypoint:SetEnabled(has)
    f.skip:SetEnabled(f.cur ~= nil)
    layout(f, false)
end

local pending
local function refreshSoon()
    if pending or not ns.TrackerInstance() or not (frame and frame:IsShown()) then return end
    pending = true
    C_Timer.After(0.4, function() pending = nil; pcall(refresh) end)
end

-- turn the tracker on for a dungeon (nil: off and hidden)
function ns.TrackerSet(instanceID)
    local c = cfg()
    local f = build()
    if not instanceID then
        c.instance = nil
        f.wpOn = nil
        f:Hide()
    else
        c.instance = instanceID
        c.offered = true
        f:Show()
        refresh()
    end
    if ns.RefreshMap then pcall(ns.RefreshMap) end
end

function ns.TrackerToggle(instanceID)
    if ns.TrackerInstance() == instanceID then ns.TrackerSet(nil) else ns.TrackerSet(instanceID) end
end

function ns.TrackerWaypoint()
    local f = frame
    if not (f and f.cur) then return end
    local m, x, y = stepSpot(f.cur)
    if m and setWaypoint(m, x, y) then
        f.wpOn = true
        f.status:SetText("")
        if ns.Print then ns.Print("Waypoint set. It follows the next step until you close the tracker.") end
    else
        f.status:SetText("No waypoint possible for this step.")
        layout(f, false)
    end
end

function ns.TrackerSkip()
    local f = frame
    if not (f and f.cur) then return end
    skipSet()[stepKey(f.cur)] = true
    refresh()
end

-- /dm tracker: open it for the dungeon you are looking at or standing in, close it when it is open
function ns.TrackerCommand()
    if ns.TrackerInstance() then ns.TrackerSet(nil); ns.Print("Quest tracker closed.") return end
    local st = ns.GetState and ns.GetState()
    local inst = st and st.instanceID or (ns.GetCurrentInstance and ns.GetCurrentInstance())
    if inst and ns.QuestData and ns.QuestData[inst] then
        ns.TrackerSet(inst)
    else
        ns.Print("Open a dungeon's Quests tab (or stand in a dungeon) and use /dm tracker, or press Track journey there.")
    end
end

-- the dungeon whose quest list has this quest, for this character
local function instanceOfQuest(id)
    for inst, list in pairs(ns.QuestData or {}) do
        for _, q in ipairs(list) do
            if q.id == id and not (ns.QuestHiddenReason and ns.QuestHiddenReason(q)) then return inst end
        end
    end
end

-- first quest of a dungeon: offer the tracker once
local function offer(inst)
    local f = build()
    f.offerInstance = inst
    local dname = ns.Dungeons[inst] and ns.Dungeons[inst].name or "this dungeon"
    f.dungeon:SetText(dname)
    f.next:SetText("Follow the quests of this dungeon?")
    f.where:SetText("A small window says what to do next and can set a waypoint.")
    f.then1:SetText("")
    f.status:SetText("")
    layout(f, true)
    f:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_REMOVED")
ev:SetScript("OnEvent", function(_, event, a, b)
    if not DungeonMapDB then return end
    if event == "PLAYER_LOGIN" then
        if ns.TrackerInstance() then
            build():Show()
            C_Timer.After(2, function() pcall(refresh) end)
        end
    elseif event == "QUEST_ACCEPTED" then
        local id = type(a) == "number" and a or b
        local c = cfg()
        if not c.instance and not c.offered and type(id) == "number" then
            local inst = instanceOfQuest(id)
            if inst then c.offered = true; offer(inst) end
        end
        refreshSoon()
    else
        refreshSoon()
    end
end)
