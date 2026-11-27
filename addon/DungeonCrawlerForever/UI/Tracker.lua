-- Quest tracker: a small window that follows the quest journey of one dungeon (the Journey view in the Quests tab) and says what to do next.
-- Turned on with "Track quests" in the Quests tab, with the offer after your first quest from a dungeon, or /dm tracker. It stays open until you close it.
-- Saved: DungeonMapDB.tracker = { instance, x, y, offered }, DungeonMapDB.questSkip[character][kind .. questID] = true ("Skip step", per character).
local _, ns = ...

local frame
local refresh -- used by the header buttons built before its definition
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

-- Blue markers on the world map for the tracked steps: the next step and the steps after it in the same place that have a known spot. Returns the
-- same { q, instance } list as ns.TrackedQuests (q is a copy whose gmap / gx / gy is the spot of the step; handin = true for a hand-in).
function ns.TrackerPins()
    local inst = ns.TrackerInstance()
    if not inst then return {} end
    local steps = ns.TrackerSteps(inst)
    local out, place = {}, nil
    for _, s in ipairs(steps) do
        if place and s.place ~= place then break end
        local m, x, y = stepSpot(s)
        if m then
            place = s.place
            local q = {}
            for k, v in pairs(s.e.q) do q[k] = v end
            q.gmap, q.gx, q.gy = m, x, y
            if s.kind == "handin" then q.handin = true; q.giver = s.e.q.turnin end
            out[#out + 1] = { q = q, instance = inst, tracker = true }
        elseif not place then
            -- the next step has no spot (inside the dungeon, or unknown): nothing to mark yet
            break
        end
    end
    return out
end

-- Art and collapse states used by Blizzard_DamageMeter on the Forever client.
local W = 320
local HEADER_H, BAR_H, PAD, GAP = 32, 26, 12, 10

local function makeButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(text)
    return b
end

local function tooltip(b, tip)
    b.tip = tip
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.tip or "")
        if self.tipText then GameTooltip:AddLine(self.tipText, 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function build()
    if frame then return frame end
    local f = CreateFrame("Frame", "DungeonCrawlerTracker", UIParent)
    f:SetSize(W, 100)
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
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H)
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    f.body.bg = f.body:CreateTexture(nil, "BACKGROUND")
    f.body.bg:SetAllPoints()
    f.body.bg:SetAtlas("damagemeters-background")
    f.body.bg:SetAlpha(0.8)

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(HEADER_H)
    head.bg = head:CreateTexture(nil, "BACKGROUND")
    head.bg:SetAllPoints()
    head.bg:SetAtlas("ui-damagemeters-header-bar")
    f.head = head

    f.collapse = CreateFrame("Button", nil, head)
    f.collapse:SetSize(18, 19)
    f.collapse:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
    tooltip(f.collapse, "Collapse")
    f.collapse:SetPoint("RIGHT", f.head, "RIGHT", -42, 0)
    f.collapse:SetScript("OnClick", function()
        local c = cfg()
        c.collapsed = not c.collapsed
        if ns.TrackerInstance() then refresh() end
    end)
    f.close = CreateFrame("Button", nil, head, "UIPanelCloseButton")
    tooltip(f.close, "Close the quest tracker")
    f.close:SetPoint("RIGHT", head, "RIGHT", -2, 0)
    f.close:SetScript("OnClick", function() ns.TrackerSet(nil) end)
    f.skip = makeButton(f.body, "Skip step", 100)
    tooltip(f.skip, "Skip step")
    f.skip.tipText = "Leaves this step out for this character (a quest you do not want, or already did another way)."
    f.skip:SetScript("OnClick", function() ns.TrackerSkip() end)
    f.waypoint = makeButton(f.body, "Waypoint", 100)
    tooltip(f.waypoint, "Waypoint")
    f.waypoint.tipText = "Sets the map waypoint for the next step. It follows the next step until you close the tracker."
    f.waypoint:SetScript("OnClick", function() ns.TrackerWaypoint() end)

    f.dungeon = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.dungeon:SetPoint("LEFT", head, "LEFT", PAD, 0)
    f.dungeon:SetPoint("RIGHT", f.collapse, "LEFT", -GAP, 0)
    f.dungeon:SetJustifyH("LEFT")
    f.dungeon:SetWordWrap(false)

    -- the next step as one coloured bar with the quest icon, like a meter row
    local bar = CreateFrame("Frame", nil, f.body)
    bar:SetPoint("TOPLEFT", f.body, "TOPLEFT", PAD, -PAD)
    bar:SetPoint("RIGHT", f.body, "RIGHT", -PAD, 0)
    bar:SetHeight(BAR_H)
    bar.fill = bar:CreateTexture(nil, "BACKGROUND")
    bar.fill:SetAllPoints()
    bar.fill:SetAtlas("UI-HUD-CoolDownManager-Bar")
    bar.fill:SetVertexColor(0.27, 0.5, 0.82, 0.85)
    bar.edge = bar:CreateTexture(nil, "BORDER")
    bar.edge:SetAtlas("ui-damagemeters-bar-shadowedge")
    bar.edge:SetPoint("TOPLEFT", -2, 2)
    bar.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(24, 24)
    bar.icon:SetPoint("LEFT")
    f.bar = bar
    f.next = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.next:SetPoint("LEFT", bar.icon, "RIGHT", 8, 0)
    f.next:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    f.next:SetJustifyH("LEFT")
    f.next:SetWordWrap(true)
    f.where = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.where:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -GAP)
    f.where:SetWidth(W - 2 * PAD)
    f.where:SetJustifyH("LEFT")
    f.where:SetTextColor(0.8, 0.8, 0.8)
    f.then1 = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.then1:SetPoint("TOPLEFT", f.where, "BOTTOMLEFT", 0, -GAP)
    f.then1:SetWidth(W - 2 * PAD)
    f.then1:SetJustifyH("LEFT")
    f.then1:SetTextColor(0.7, 0.7, 0.7)
    f.then1:SetSpacing(5)
    f.status = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetJustifyH("LEFT")
    f.status:SetWidth(W - 2 * PAD)
    f.status:SetTextColor(1, 0.62, 0.38)

    f.yes = makeButton(f.body, "Track it", 90)
    f.yes:SetScript("OnClick", function() if f.offerInstance then ns.TrackerSet(f.offerInstance) end end)
    f.no = makeButton(f.body, "No thanks", 90)
    f.no:SetScript("OnClick", function() f.offerInstance = nil; f:Hide() end)

    local c = cfg()
    f:ClearAllPoints()
    if c.x and c.y then f:SetPoint(c.point or "TOPLEFT", UIParent, c.relPoint or "TOPLEFT", c.x, c.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    f:Hide()
    frame = f
    return f
end

local function layout(f, offer)
    local collapsed = cfg().collapsed and not offer
    f.waypoint:SetShown(not offer)
    f.skip:SetShown(not offer)
    f.close:SetShown(not offer)
    f.collapse:SetShown(not offer)
    f.dungeon:ClearAllPoints()
    f.dungeon:SetPoint("LEFT", f.head, "LEFT", PAD, 0)
    f.dungeon:SetPoint("RIGHT", offer and f.head or f.collapse, offer and "RIGHT" or "LEFT", -PAD, 0)
    local state = collapsed and "expand" or "collapse"
    f.collapse:SetNormalAtlas("ui-questtrackerbutton-" .. state .. "-all")
    f.collapse:SetPushedAtlas("ui-questtrackerbutton-" .. state .. "-all-pressed")
    f.collapse.tip = collapsed and "Expand" or "Collapse"
    f.body:SetShown(not collapsed)
    f.yes:SetShown(offer)
    f.no:SetShown(offer)
    f.then1:SetShown(not offer)
    if collapsed then f:SetHeight(HEADER_H) return end
    local barHeight = math.max(BAR_H, f.next:GetStringHeight() + 8)
    f.bar:SetHeight(barHeight)
    local h = PAD + barHeight + GAP + f.where:GetStringHeight()
    local anchor = f.where
    if not offer and f.then1:GetText() ~= "" then
        h = h + GAP + f.then1:GetStringHeight()
        anchor = f.then1
    end
    f.status:ClearAllPoints()
    f.status:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -GAP)
    if f.status:GetText() ~= "" then
        h = h + GAP + f.status:GetStringHeight()
        anchor = f.status
    end
    local left, right = offer and f.yes or f.waypoint, offer and f.no or f.skip
    left:ClearAllPoints(); right:ClearAllPoints()
    left:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -GAP)
    right:SetPoint("LEFT", left, "RIGHT", GAP, 0)
    f:SetHeight(HEADER_H + h + GAP + 24 + PAD)
end

refresh = function()
    local inst = ns.TrackerInstance()
    if not inst or not frame then return end
    local f = frame
    f.offerInstance = nil
    local dname = ns.Dungeons[inst] and ns.Dungeons[inst].name or ("Dungeon " .. inst)
    local steps = ns.TrackerSteps(inst)
    f.dungeon:SetText(dname)
    f.status:SetText("")
    if #steps == 0 then
        f.bar.fill:SetVertexColor(0.25, 0.6, 0.3, 0.85)
        f.bar.icon:SetAtlas("QuestTurnin")
        f.next:SetText("Journey complete")
        f.where:SetText("Nothing left to do for the quests of this dungeon.")
        f.then1:SetText("")
        f.cur = nil
    else
        local s = steps[1]
        f.cur = s
        local t, w = stepText(s, inst)
        f.bar.fill:SetVertexColor(0.27, 0.5, 0.82, 0.85)
        f.bar.icon:SetAtlas(s.kind == "handin" and "QuestTurnin" or "QuestNormal")
        f.next:SetText(t)
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
    if ns.RefreshEntrances then pcall(ns.RefreshEntrances) end -- the blue markers follow the next step
    local has = f.cur and stepSpot(f.cur) and true or false
    f.waypoint:SetEnabled(has)
    f.waypoint:SetAlpha(has and 1 or 0.4)
    f.skip:SetEnabled(f.cur ~= nil)
    f.skip:SetAlpha(f.cur and 1 or 0.4)
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
    if ns.RefreshEntrances then pcall(ns.RefreshEntrances) end
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
        layout(f, false)
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
        ns.Print("Open a dungeon's Quests tab (or stand in a dungeon) and use /dm tracker, or press Track quests there.")
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
    f.bar.fill:SetVertexColor(0.27, 0.5, 0.82, 0.85)
    f.bar.icon:SetAtlas("QuestNormal")
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
