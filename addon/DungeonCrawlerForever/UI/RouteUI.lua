-- The route's surfaces in the dungeon map:
--  * two red buttons in the map's bottom-left corner: "Hide route" / "Show route" (toggles) and "Edit route";
--  * the EDITOR BAR over the map while a route is being drawn (the player's "Edit route", or the Route tool of /dm edit): tool tiles for the selection
--    (previous / next / to the end), the changes (cut, join, delete) and the history (undo, start over), Save route and Reset to default, the stops
--    (click one to select it) with their best times, the split timer switches, a status line and the hints.
-- The route's data and rules are in UI/Route.lua; the clicks on the map itself are handled in UI/View.lua and UI/Edit.lua.
local _, ns = ...
local ui = {}
ns.RouteUI = ui

local BRONZE = { 0.66, 0.49, 0.28 }
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function setIcon(tex, name)
    if type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
        tex:SetAtlas(name)
    else
        tex:SetTexture(name)
    end
end

-- Where a tooltip goes: under the editor bar (centred), so it never covers the tile, the badge or the button it is about; for the corner buttons to
-- their right (the corner is at the bottom of the map: below would be pushed back up over the button).
local function tooltip(owner, tip)
    if owner.tipBelow then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOP", owner.tipBelow, "BOTTOM", 0, -6)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    end
    local title, body = tip:match("^(.-)\n(.*)$")
    GameTooltip:SetText(title or tip)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function redButton(parent, w, h, text, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    if tip then
        b:SetScript("OnEnter", function(self) tooltip(self, tip) end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    return b
end

--------------------------------------------------------------------------------------------------------------------------------
-- The editor bar
--------------------------------------------------------------------------------------------------------------------------------

local function checkbox(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    cb:SetScript("OnClick", onClick)
    return cb
end

local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function stopBadge(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.ring:SetAllPoints()
    b.disc = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.disc:SetPoint("TOPLEFT", 2, -2)
    b.disc:SetPoint("BOTTOMRIGHT", -2, 2)
    b.disc:SetColorTexture(0.06, 0.05, 0.03, 0.95)
    for _, t in ipairs({ b.ring, b.disc }) do
        local m = b:CreateMaskTexture()
        m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.num:SetPoint("CENTER")
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetAtlas("common-icon-checkmark")
    b.check:SetSize(12, 12)
    b.check:SetPoint("BOTTOMRIGHT", 3, -3)
    b:SetScript("OnClick", function(self)
        if self.pointIndex then ns.routeAt = self.pointIndex end
        ns.RefreshMap()
    end)
    b.tipBelow = parent
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOP", self.tipBelow, "BOTTOM", 0, -6)
        GameTooltip:SetText(self.boss or "")
        local best = self.best and ns.FormatTime(self.best)
        if self.skipped then GameTooltip:AddLine("Skipped in this run", 0.7, 0.7, 0.7)
        elseif self.killed then GameTooltip:AddLine("Defeated", 0.4, 0.85, 0.4) end
        if best then GameTooltip:AddLine("Best kill " .. best, 1, 1, 1) end
        GameTooltip:AddLine("Click to select this stop", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local bar
function ui.Bar() return bar end -- (the smoke test looks at it)

-- a tile: an icon over a gold label in a bronze frame; greyed when it cannot be used now, gold-edged when it is the thing going on
local function tile(parent, label, icon, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(58, 50)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.4)
    b.edges = {}
    for i = 1, 4 do
        b.edges[i] = b:CreateTexture(nil, "BORDER")
        b.edges[i]:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
    end
    b.edges[1]:SetPoint("TOPLEFT"); b.edges[1]:SetPoint("TOPRIGHT"); b.edges[1]:SetHeight(1)
    b.edges[2]:SetPoint("BOTTOMLEFT"); b.edges[2]:SetPoint("BOTTOMRIGHT"); b.edges[2]:SetHeight(1)
    b.edges[3]:SetPoint("TOPLEFT"); b.edges[3]:SetPoint("BOTTOMLEFT"); b.edges[3]:SetWidth(1)
    b.edges[4]:SetPoint("TOPRIGHT"); b.edges[4]:SetPoint("BOTTOMRIGHT"); b.edges[4]:SetWidth(1)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(24, 24)
    b.icon:SetPoint("TOP", 0, -6)
    setIcon(b.icon, icon)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("BOTTOM", 0, 4)
    b.label:SetText(label)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) tooltip(self, tip) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b.tipBelow = parent -- (the editor bar)
    function b:SetUsable(on)
        on = on and true or false
        self:SetEnabled(on)
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.4)
        if on then self.label:SetTextColor(1, 0.82, 0) else self.label:SetTextColor(0.5, 0.5, 0.5) end
    end
    function b:SetActive(on)
        local c = on and { 1, 0.82, 0 } or BRONZE
        for _, e in ipairs(self.edges) do e:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    return b
end

local function state() return ns.GetState() end
local function refresh() ns.RefreshMap() end

local function buildBar(view)
    -- the same look as the sidebar: its grainy bronze background and thin golden-bronze border
    bar = CreateFrame("Frame", nil, view)
    bar:SetFrameLevel(view:GetFrameLevel() + 260)
    bar:SetSize(720, 198)
    bar:EnableMouse(true) -- clicks on the bar are not clicks on the map under it
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAtlas("heavybronze-frame-background")
    bar.bg:SetPoint("TOPLEFT", 3, -3)
    bar.bg:SetPoint("BOTTOMRIGHT", -3, 3)
    local okb, border = pcall(CreateFrame, "Frame", nil, bar, "TooltipBorderBackdropTemplate")
    if not (okb and border) then
        border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        pcall(border.SetBackdrop, border, { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    end
    border:SetAllPoints(bar)
    border:SetFrameLevel(bar:GetFrameLevel() + 1)
    pcall(border.SetBackdropColor, border, 0, 0, 0, 0)
    pcall(border.SetBackdropBorderColor, border, 0.78, 0.6, 0.32, 1)
    bar.border = border
    bar.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bar.title:SetPoint("TOP", 0, -9)

    local function group(label, x)
        local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, -32)
        fs:SetText(label)
        return fs
    end
    local function place(t, x) t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -48) end

    group("Selection", 16)
    bar.prev = tile(bar, "Previous", "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", "Previous point\nSelect the previous point of the route, stops and steps too.", function()
        ns.RouteSelectStep(state().instanceID, state().wing, -1); refresh()
    end)
    bar.next = tile(bar, "Next", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Next point\nSelect the next point of the route, stops and steps too.", function()
        ns.RouteSelectStep(state().instanceID, state().wing, 1); refresh()
    end)
    bar.toEnd = tile(bar, "To the end", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Add at the end\nDeselect the point: new points go at the end of the route again.", function()
        ns.routeAt = nil; refresh()
    end)
    place(bar.prev, 16); place(bar.next, 78); place(bar.toEnd, 140)

    group("Change", 216)
    bar.cut = tile(bar, "Cut here", "Interface\\Icons\\INV_Weapon_ShortBlade_05",
        "Cut the route here\nTo replace a stretch of the route:\n1. Click a dot on the route to select it.\n2. Press Cut here. Everything after that point turns dark grey and is no longer connected.\n3. Click the map, a boss or a marker to draw the new part.\n4. Click a dot in the grey part, or select one and press Join here. The grey points before it are dropped.\nUndo takes any step back.",
        function()
            local st = state()
            if not ns.routeAt then ns.Print("Cut: first click a dot on the route to select where to cut.") refresh() return end
            if ns.RouteGap(st.instanceID, st.wing) then ns.Print("Cut: the route is already cut. Draw the new part and click a dot in the grey part to join it.") refresh() return end
            if not ns.RouteCut(st.instanceID, st.wing, ns.routeAt) then ns.Print("Cut: select a point that has another point behind it (not the last one).") end
            refresh()
        end)
    bar.join = tile(bar, "Join here", "Interface\\Icons\\INV_Misc_Gear_01", "Join the new part here\nWith a point in the grey part selected (click its dot, or step to it), this joins the new part to it. The grey points before it are dropped.", function()
        local st = state()
        local g = ns.RouteGap(st.instanceID, st.wing)
        if not (g and ns.routeAt and ns.routeAt >= g) then ns.Print("Join: select a point in the grey part first.") return end
        local dropped = ns.RouteConnect(st.instanceID, st.wing, ns.routeAt)
        if dropped and #dropped > 0 then ns.Print("Joined up. Removed the stops: " .. table.concat(dropped, ", ") .. " (Undo brings them back).") end
        refresh()
    end)
    bar.delete = tile(bar, "Delete", "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "Delete point\nRemove the selected point (a linked door loses both ends).", function()
        local st = state()
        ns.RouteDeletePoint(st.instanceID, st.wing, ns.routeAt)
        refresh()
    end)
    place(bar.cut, 216); place(bar.join, 278); place(bar.delete, 340)

    group("History", 416)
    bar.undo = tile(bar, "Undo", "Interface\\Buttons\\UI-RefreshButton", "Undo\nTake back the last thing you did: a point, a move, a cut, a delete. Shift-click on the map does the same.", function()
        local st = state()
        if ns.RouteUndo(st.instanceID, st.wing) then refresh() else ns.Print("Nothing to undo.") end
    end)
    bar.startOver = tile(bar, "Start over", "Interface\\TimeManager\\ResetButton", "Start over\nRemove every point and start with an empty route. Undo brings it back.", function()
        local st = state()
        ns.RouteClear(st.instanceID, st.wing); refresh()
    end)
    place(bar.undo, 416); place(bar.startOver, 478)

    bar.save = redButton(bar, 122, 30, "Save route", "Save route\nKeep the route and stop drawing.", function()
        ns.RouteDrawStop()
        ns.Print("Route saved. Open the Route tab to show or hide it.")
    end)
    bar.save.tipBelow = bar
    bar.save:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -16, -46)
    bar.reset = redButton(bar, 122, 22, "Reset to Default", "Reset to Default\nRemove your drawing and go back to the route that comes with the addon (or no route, if this dungeon has none).", function()
        local st = state()
        ns.RouteReset(st.instanceID, st.wing)
        ns.RouteDrawStop()
        ns.Print("Back to the built-in route of this dungeon.")
    end)
    bar.reset.tipBelow = bar
    bar.reset:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -16, -82)
    bar.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    bar.close:SetPoint("TOPRIGHT", 2, 2)
    bar.close:SetScript("OnClick", function() ns.RouteDrawStop() end)

    -- the stops: a numbered badge each (in the leg's colour); a click selects that stop's point, so it can be cut at, deleted or added after
    bar.stopsLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.stopsLabel:SetPoint("TOPLEFT", 16, -110)
    bar.stopsLabel:SetText("Stops")
    bar.badges = {}

    -- the split timer
    bar.timerLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.timerLabel:SetPoint("TOPLEFT", 16, -142)
    bar.timerLabel:SetText("Split timer")
    bar.showSplits = checkbox(bar, "Show the timer window", function(self)
        DungeonMapDB.showSplits = self:GetChecked() and true or false
        if ns.SplitsRefresh then ns.SplitsRefresh() end
    end)
    bar.showSplits:SetPoint("TOPLEFT", 84, -137)
    bar.autoStart = checkbox(bar, "Start it when I enter a dungeon", function(self)
        DungeonMapDB.splitsAutoStart = self:GetChecked() and true or false
    end)
    bar.autoStart:SetPoint("TOPLEFT", 264, -137)
    bar.compareLast = checkbox(bar, "Compare with my last run", function(self)
        DungeonMapDB.splitCompareLast = self:GetChecked() and true or false
        if ns.SplitsRefresh then ns.SplitsRefresh() end
    end)
    bar.compareLast:SetPoint("TOPLEFT", 484, -137)

    bar.info = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.info:SetPoint("BOTTOMLEFT", 16, 24)
    bar.info:SetJustifyH("LEFT")
    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.hint:SetPoint("BOTTOMLEFT", 16, 8)
    bar.hint:SetJustifyH("LEFT")
    bar.hint:SetText("|cffffd100Click|r the map: add a point   |cffffd100Click|r a boss or marker: add a stop or step   |cffffd100Drag|r a dot: move it   |cffffd100Ctrl-click|r a line: insert   |cffffd100Shift-click|r: undo   |cffffd100Esc|r: close the map")
    bar:Hide()
end

-- Shown while a route is drawn. reserve = the width the sidebar takes, so the bar centres over the map.
function ui.UpdateBar(view, show, reserve)
    if not show then
        if bar then bar:Hide() end
        return
    end
    if not bar then buildBar(view) end
    local st = state()
    local inst, wing = st.instanceID, st.wing
    local route = ns.GetRoute(inst, wing) or {}
    local sel, gap = ns.routeAt, ns.RouteGap(inst, wing)
    local stops = 0
    for _, p in ipairs(route) do if p.boss then stops = stops + 1 end end
    bar.title:SetText("Edit route - " .. ns.DungeonTitle(inst, wing))
    bar.prev:SetUsable(#route > 0)
    bar.next:SetUsable(#route > 0)
    bar.toEnd:SetUsable(sel ~= nil)
    bar.cut:SetUsable(sel ~= nil and not gap and sel < #route)
    bar.cut:SetActive(gap ~= nil)
    bar.join:SetUsable(gap ~= nil and sel ~= nil and sel >= gap)
    bar.join:SetActive(gap ~= nil)
    bar.delete:SetUsable(sel ~= nil)
    bar.undo:SetUsable(ns.RouteCanUndo(inst, wing))
    bar.startOver:SetUsable(#route > 0)
    -- the stops
    local prog = #route > 0 and ns.RouteProgress(inst, wing, ns.GetBosses(inst, st.diff, wing)) or nil
    local list = prog and prog.stops or {}
    for i, stop in ipairs(list) do
        local b = bar.badges[i]
        if not b then
            b = stopBadge(bar)
            bar.badges[i] = b
        end
        local cr, cg, cb = ns.RouteLegColor(i)
        b.ring:SetColorTexture(cr, cg, cb, 1)
        b.num:SetText(tostring(i))
        b.num:SetTextColor(cr, cg, cb)
        b.boss, b.killed, b.skipped, b.pointIndex = stop.boss, stop.killed, stop.skipped, stop.index
        b.best = ns.GetBestTime and ns.GetBestTime(inst, stop.boss) or nil
        b.check:SetShown(stop.killed and true or false)
        b:SetAlpha(stop.skipped and 0.5 or 1)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", 66 + (i - 1) * 28, -106)
        b:Show()
    end
    for i = #list + 1, #bar.badges do bar.badges[i]:Hide() end
    bar.stopsLabel:SetText(#list > 0 and "Stops" or "Stops: none yet")
    -- the split timer
    bar.showSplits:SetChecked(DungeonMapDB.showSplits == true)
    bar.autoStart:SetChecked(DungeonMapDB.splitsAutoStart ~= false)
    bar.compareLast:SetChecked(DungeonMapDB.splitCompareLast == true)
    local player = ns.routeDraw == true -- the player's Edit route; in /dm edit the data is kept as you go
    bar.save:SetShown(player)
    bar.reset:SetShown(player)
    bar.close:SetShown(player)
    if gap then
        bar.info:SetText("|cffff7a5aRoute cut.|r Draw the new part, then click a dot in the |cffaaaaaagrey part|r to join it (or press Join here).")
    elseif sel then
        bar.info:SetText(format("Points %d   Stops %d   -   point %d of %d selected: new points go in after it", #route, stops, sel, #route))
    else
        bar.info:SetText(format("Points %d   Stops %d   -   nothing selected: new points go at the end of the route", #route, stops))
    end
    local avail = view:GetWidth() - (reserve or 0) - 24
    local scale = math.max(0.6, math.min(1, avail / 720))
    bar:SetScale(scale)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", view, "TOP", -(reserve or 0) / 2 / scale, (ns.editing and -66 or -10) / scale) -- (edit mode has its row of tool buttons above)
    bar:Show()
end


--------------------------------------------------------------------------------------------------------------------------------
-- The two buttons in the map's bottom-left corner: Hide route / Show route above Edit route (over the zoom row)
--------------------------------------------------------------------------------------------------------------------------------

local corner
function ui.Corner() return corner end

function ui.UpdateCorner(view, showMap)
    if not corner then
        corner = {}
        corner.edit = redButton(view, 124, 22, "Edit route", "Edit route\nDraw your own route: click the map to add points, a boss for a stop, a stairs or door marker for a step. Your route replaces the built-in one for this dungeon, and Reset to Default brings it back.", function()
            ns.RouteDrawStart()
        end)
        corner.edit:SetFrameLevel(view:GetFrameLevel() + 120)
        corner.edit:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 10, 36)
        corner.toggle = redButton(view, 124, 22, "Hide route", "Hide route\nShow or hide this dungeon's route on the map for this session. The option \"Show the dungeon route by default\" sets where it starts.", function()
            ns.routeShow = not ns.RouteVisible()
            ns.RefreshMap()
        end)
        corner.toggle:SetFrameLevel(view:GetFrameLevel() + 120)
        corner.toggle:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 10, 62)
    end
    local st = state()
    local idle = showMap and not ns.editing and not ns.routeDraw and ns.RouteAvailable()
    local route = idle and ns.GetRoute(st.instanceID, st.wing)
    local has = route and #route > 1
    corner.edit:SetText(has and "Edit route" or "Draw a route")
    corner.edit:SetShown(idle and true or false)
    corner.toggle:SetText(ns.RouteVisible() and "Hide route" or "Show route")
    corner.toggle:SetShown(idle and has and true or false)
end
