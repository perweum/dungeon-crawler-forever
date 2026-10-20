-- The route's two surfaces in the dungeon map:
--  * the sidebar's ROUTE TAB (next to Bosses and Quests): show the route, Edit route, the stops with kill marks and best times, the split timer switches;
--  * the EDITOR BAR over the map while a route is being drawn (the player's "Edit route", or the Route tool of /dm edit): tool tiles for the selection
--    (previous / next / to the end), the changes (cut, join, delete) and the history (undo, start over), Save route and Reset to default, a status line
--    and the hints. The route's data and rules are in UI/Route.lua; the clicks on the map itself are handled in UI/View.lua and UI/Edit.lua.
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

local function tooltip(owner, tip)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
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
    bar = ns.CreateBox(view)
    bar:SetFrameLevel(view:GetFrameLevel() + 260)
    bar:SetSize(700, 138)
    bar:SetCut(9)
    bar:EnableMouse(true) -- clicks on the bar are not clicks on the map under it
    bar.title:ClearAllPoints()
    bar.title:SetPoint("TOP", 0, -9)
    bar.title:SetFontObject("GameFontNormalLarge")

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
    bar.save:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -16, -46)
    bar.reset = redButton(bar, 122, 22, "Reset to Default", "Reset to Default\nRemove your drawing and go back to the route that comes with the addon (or no route, if this dungeon has none).", function()
        local st = state()
        ns.RouteReset(st.instanceID, st.wing)
        ns.RouteDrawStop()
        ns.Print("Back to the built-in route of this dungeon.")
    end)
    bar.reset:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -16, -82)
    bar.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    bar.close:SetPoint("TOPRIGHT", 2, 2)
    bar.close:SetScript("OnClick", function() ns.RouteDrawStop() end)

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
    local scale = math.max(0.6, math.min(1, avail / 700))
    bar:SetScale(scale)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", view, "TOP", -(reserve or 0) / 2 / scale, (ns.editing and -66 or -10) / scale) -- (edit mode has its row of tool buttons above)
    bar:Show()
end

--------------------------------------------------------------------------------------------------------------------------------
-- The Route tab
--------------------------------------------------------------------------------------------------------------------------------

local rows = {}

local function checkbox(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    cb:SetScript("OnClick", onClick)
    return cb
end

local function stopRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.ring = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.disc = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.disc:SetColorTexture(0.06, 0.05, 0.03, 0.95)
    for _, t in ipairs({ r.ring, r.disc }) do
        local m = r:CreateMaskTexture()
        m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.time:SetJustifyH("RIGHT")
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetAtlas("common-icon-checkmark")
    r:SetScript("OnClick", function(self)
        if self.bossId then
            ns.GetState().selected = self.bossId
            ns.RefreshMap()
        end
    end)
    return r
end

local function buildTab(panel)
    local box = ns.CreateBox(panel)
    box.title:SetText("Route")
    box.status = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.status:SetJustifyH("LEFT")
    box.status:SetWordWrap(false)
    box.edit = redButton(box, 140, 24, "Edit route", "Edit route\nDraw your own route: click the map to add points, a boss for a stop, a stairs or door marker for a step. Your route replaces the built-in one for this dungeon, and Reset to Default brings it back.", function()
        ns.RouteDrawStart()
    end)
    box.keep = checkbox(box, "Keep the route on the map in the other tabs", function(self)
        ns.routeShow = self:GetChecked() and true or false -- for this session; "Show the dungeon route by default" in the options sets where it starts
        ns.RefreshMap()
    end)
    box.stopsHead = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.stopsHead:SetText("Stops")
    box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    box.content = CreateFrame("Frame", nil, box.scroll)
    box.content:SetSize(10, 10)
    box.scroll:SetScrollChild(box.content)
    box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    box.empty:SetText("No stops yet.")
    box.timerHead = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.timerHead:SetText("Split timer")
    box.showSplits = checkbox(box, "Show the timer window in dungeons", function(self)
        DungeonMapDB.showSplits = self:GetChecked() and true or false
        if ns.SplitsRefresh then ns.SplitsRefresh() end
    end)
    box.autoStart = checkbox(box, "Start it when I enter a dungeon", function(self)
        DungeonMapDB.splitsAutoStart = self:GetChecked() and true or false
    end)
    box.compareLast = checkbox(box, "Compare with my last run, not my best", function(self)
        DungeonMapDB.splitCompareLast = self:GetChecked() and true or false
        if ns.SplitsRefresh then ns.SplitsRefresh() end
    end)
    box:Hide()
    panel.routeBox = box
    ui.tab = box -- (the smoke test looks at it)
end

-- show = the Route tab is the active one. S = the sidebar's scale, wide = the wide view, top = where the boxes start.
function ui.UpdateTab(panel, instanceID, show, wide, S, top)
    if not panel.routeBox then buildTab(panel) end
    local box = panel.routeBox
    box:SetShown(show)
    if not show then return end
    local st = state()
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
    box:SetCut(wide and 11 or 7)
    box.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")
    local font = S > 1 and "GameFontHighlightLarge" or "GameFontHighlight"
    for _, fs in ipairs({ box.status, box.keep.label, box.showSplits.label, box.autoStart.label, box.compareLast.label }) do fs:SetFontObject(font) end
    box.stopsHead:SetFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
    box.timerHead:SetFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")

    local wing = st.wing
    local route = ns.GetRoute(instanceID, wing)
    local n = route and #route or 0
    local custom = ns.RouteIsCustom(instanceID, wing) and n > 0
    local bosses = ns.GetBosses(instanceID, st.diff, wing)
    local prog = n > 0 and ns.RouteProgress(instanceID, wing, bosses) or nil
    if n == 0 then
        box.status:SetText("No route for this dungeon yet.")
        box.edit:SetText("Draw a route")
    else
        box.status:SetText((custom and "Your own route" or "Built-in route") .. format(" - %d stops", prog and prog.total or 0))
        box.edit:SetText("Edit route")
    end
    box.edit:SetEnabled(not ns.RouteTool())

    local y = (wide and 42 or 32) * S
    box.status:ClearAllPoints()
    box.status:SetPoint("TOPLEFT", 12, -y)
    box.status:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    y = y + 22 * S
    box.edit:SetSize(140 * S, 24 * S)
    box.edit:ClearAllPoints()
    box.edit:SetPoint("TOPLEFT", 12, -y)
    y = y + 32 * S
    box.keep:SetSize(24 * S, 24 * S)
    box.keep:ClearAllPoints()
    box.keep:SetPoint("TOPLEFT", 6, -y)
    local keep = ns.routeShow
    if keep == nil then keep = DungeonMapDB.routesDefault == true end
    box.keep:SetChecked(keep)
    y = y + 28 * S
    box.stopsHead:ClearAllPoints()
    box.stopsHead:SetPoint("TOPLEFT", 12, -y)
    y = y + 22 * S

    -- the timer switches sit at the bottom, the stops scroll in between
    local rowH = 26 * S
    for i, cb in ipairs({ box.compareLast, box.autoStart, box.showSplits }) do
        cb:SetSize(24 * S, 24 * S)
        cb:ClearAllPoints()
        cb:SetPoint("BOTTOMLEFT", 6, 6 + (i - 1) * rowH)
    end
    box.showSplits:SetChecked(DungeonMapDB.showSplits == true)
    box.autoStart:SetChecked(DungeonMapDB.splitsAutoStart ~= false)
    box.compareLast:SetChecked(DungeonMapDB.splitCompareLast == true)
    box.timerHead:ClearAllPoints()
    box.timerHead:SetPoint("BOTTOMLEFT", 12, 6 + 3 * rowH + 4)

    box.scroll:ClearAllPoints()
    box.scroll:SetPoint("TOPLEFT", 6, -y)
    box.scroll:SetPoint("BOTTOMRIGHT", -26, 6 + 3 * rowH + 4 + 22 * S + 6)
    box.content:SetWidth(math.max(40, (panel:GetWidth() or 300) - 28 - 34))
    box.empty:ClearAllPoints()
    box.empty:SetPoint("TOPLEFT", box.scroll, "TOPLEFT", 8, -8)
    box.empty:SetShown(not prog or prog.total == 0)

    local list = prog and prog.stops or {}
    local yy = 0
    for i, stop in ipairs(list) do
        local r = rows[i] or stopRow(box.content)
        rows[i] = r
        r:SetParent(box.content)
        r:SetHeight(rowH)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", box.content, "TOPLEFT", 0, -yy)
        r:SetPoint("TOPRIGHT", box.content, "TOPRIGHT", 0, -yy)
        local d = 22 * S
        r.ring:SetSize(d, d)
        r.ring:ClearAllPoints()
        r.ring:SetPoint("LEFT", 6, 0)
        r.disc:SetSize(d - 4 * S, d - 4 * S)
        r.disc:ClearAllPoints()
        r.disc:SetPoint("CENTER", r.ring, "CENTER")
        local cr, cg, cb = ns.RouteLegColor(i)
        r.ring:SetColorTexture(cr, cg, cb, 1)
        r.num:SetFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
        r.num:ClearAllPoints()
        r.num:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
        r.num:SetText(tostring(i))
        r.num:SetTextColor(cr, cg, cb)
        r.name:SetFontObject(font)
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r.ring, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -(70 * S), 0)
        r.name:SetText(stop.boss)
        local grey = stop.killed or stop.skipped
        r.name:SetTextColor(grey and 0.55 or 1, grey and 0.55 or 1, grey and 0.55 or 1)
        local best = ns.GetBestTime and ns.GetBestTime(instanceID, stop.boss)
        r.time:SetFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        r.time:ClearAllPoints()
        r.time:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        if stop.skipped then
            r.time:SetText("skipped")
        else
            r.time:SetText(best and ns.FormatTime(best) or "")
        end
        r.time:SetTextColor(0.6, 0.6, 0.6)
        r.check:SetSize(16 * S, 16 * S)
        r.check:ClearAllPoints()
        r.check:SetPoint("RIGHT", r.time, "LEFT", -6, 0)
        r.check:SetShown(stop.killed and true or false)
        r.bossId = nil
        for _, b in ipairs(bosses) do if b.name == stop.boss then r.bossId = b.id end end
        r:Show()
        yy = yy + rowH
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    box.content:SetHeight(math.max(yy, 10))
end
