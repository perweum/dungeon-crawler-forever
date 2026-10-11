-- Edit mode: record boss positions in-game (no player coordinates needed — you click the spot on the map).
-- /dm edit   toggle; select a boss in the list, click the map to place it. Saved in DungeonMapDB.manual.
-- /dm export prints CSV lines for data/manual/bosses.csv (instanceMapID,uiMapID,name,x,y).
local _, ns = ...

ns.editing = false
ns.editKind = "boss" -- what a click places: boss | entrance | exit | up | down | portal

function ns.EditPlaceAtCursor(canvas, state)
    if not state.selected then
        ns.Print("Select a boss in the list first.")
        return
    end
    local floors = ns.GetFloors(state.instanceID, state.wing)
    local floor = floors and floors[state.floorIndex]
    if not floor then return end
    local left, top = canvas:GetLeft(), canvas:GetTop()
    local scale = canvas:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local x = (cx / scale - left) / canvas:GetWidth()
    local y = (top - cy / scale) / canvas:GetHeight()
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    local bosses = ns.GetBosses(state.instanceID, state.diff, state.wing)
    for _, b in ipairs(bosses) do
        if b.id == state.selected then
            local m = DungeonMapDB.manual
            m[state.instanceID] = m[state.instanceID] or {}
            m[state.instanceID][b.name] = { floor = floor.uiMapID, x = x, y = y }
            ns.Print(format("%s placed at %.4f, %.4f (floor %d)", b.name, x, y, floor.uiMapID))
        end
    end
    ns.RefreshMap()
end

function ns.ToggleEdit()
    ns.editing = not ns.editing
    ns.Print("Edit mode " .. (ns.editing and "ON" or "OFF"))
    ns.RefreshMap()
end

function ns.ExportManual()
    local lines = {}
    for instanceID, bosses in pairs(DungeonMapDB.manual) do
        for name, m in pairs(bosses) do
            lines[#lines + 1] = format('%d,%d,"%s",%.4f,%.4f', instanceID, m.floor, name, m.x, m.y)
        end
    end
    table.sort(lines)
    local disp = {}
    for instanceID, bosses in pairs(DungeonMapDB.portraits or {}) do
        for name, id in pairs(bosses) do
            disp[#disp + 1] = format('%d,"%s",%d', instanceID, name, id)
        end
    end
    table.sort(disp)
    local marks = {}
    for instanceID, floors in pairs(DungeonMapDB.markers or {}) do
        for floorID, list in pairs(floors) do
            for _, mk in ipairs(list) do
                marks[#marks + 1] = format("%d,%d,%s,%.4f,%.4f", instanceID, floorID, mk.kind, mk.x, mk.y)
            end
        end
    end
    table.sort(marks)
    if #lines == 0 and #disp == 0 and #marks == 0 then ns.Print("Nothing recorded yet.") return end
    if #marks > 0 then
        for i = #marks, 1, -1 do table.insert(lines, 1, marks[i]) end
        table.insert(lines, 1, "# data/manual/markers.csv: instanceMapID,uiMapID,kind,x,y")
    end
    if #lines > 0 then table.insert(lines, 1, "# data/manual/bosses.csv: instanceMapID,uiMapID,name,x,y") end
    if #disp > 0 then
        table.insert(lines, "# data/manual/boss_display.csv: instanceMapID,name,displayID")
        for _, d in ipairs(disp) do lines[#lines + 1] = d end
    end
    local f = DungeonMapExportFrame
    if not f then
        f = ns.NewWindow("DungeonMapExportFrame")
        f:SetSize(520, 340)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        tinsert(UISpecialFrames, "DungeonMapExportFrame")
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -34)
        sf:SetPoint("BOTTOMRIGHT", -30, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(470)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        if f.SetTitle then f:SetTitle("Dungeon Crawler export (Ctrl+A, Ctrl+C)") end
    end
    f.edit:SetText(table.concat(lines, "\n"))
    f.edit:HighlightText()
    f:Show()
end

-- Small window with a selectable link (WoW addons cannot open a browser).
function ns.ShowLink(url)
    local f = DungeonMapLinkFrame
    if not f then
        f = ns.NewWindow("DungeonMapLinkFrame")
        f:SetSize(460, 90)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        tinsert(UISpecialFrames, "DungeonMapLinkFrame")
        local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        eb:SetSize(420, 24)
        eb:SetPoint("CENTER", 0, -6)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        f.edit = eb
        if f.SetTitle then f:SetTitle("Copy link (Ctrl+C)") end
    end
    f.edit:SetText(url)
    f.edit:HighlightText()
    f:Show()
end

-- /dm portrait: with a boss selected in the list and the real boss targeted in the world, remember the target's
-- creature display ID so the boss gets a proper portrait (no image files needed). Read back with tools/import_manual.py.
function ns.RecordPortrait()
    local state = ns.GetState()
    if not state.instanceID or not state.selected then
        ns.Print("Select a boss in the list first, target that boss in the world, then type /dm portrait.")
        return
    end
    local boss
    for _, b in ipairs(ns.GetBosses(state.instanceID, state.diff, state.wing)) do
        if b.id == state.selected then boss = b end
    end
    if not boss then return end
    if not UnitExists("target") then
        ns.Print("Target the boss first.")
        return
    end
    local model = ns.portraitModel or CreateFrame("PlayerModel", nil, UIParent)
    ns.portraitModel = model
    model:SetSize(8, 8)
    model:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    model:SetUnit("target")
    C_Timer.After(0.5, function()
        local id = model.GetDisplayInfo and model:GetDisplayInfo()
        if type(id) == "number" and id > 0 then
            local d = DungeonMapDB.portraits
            d[state.instanceID] = d[state.instanceID] or {}
            d[state.instanceID][boss.name] = id
            ns.Print(format("%s portrait saved (display ID %d).", boss.name, id))
            ns.RefreshMap()
        else
            ns.Print("Could not read the target's display ID (the model may still be loading - try again).")
        end
    end)
end

-- /dm display <id>: set the selected boss's creature display ID by hand (e.g. looked up on a database site).
function ns.SetDisplayID(id)
    local state = ns.GetState()
    if not state.instanceID or not state.selected then
        ns.Print("Select a boss in the list first, then type /dm display <displayID>.")
        return
    end
    for _, b in ipairs(ns.GetBosses(state.instanceID, state.diff, state.wing)) do
        if b.id == state.selected then
            local d = DungeonMapDB.portraits
            d[state.instanceID] = d[state.instanceID] or {}
            d[state.instanceID][b.name] = id
            ns.Print(format("%s portrait set to display ID %d.", b.name, id))
            ns.RefreshMap()
            return
        end
    end
end

-- Place a floor marker (entrance / exit / stairs / portal) where the cursor is.
function ns.EditPlaceMarker(canvas, state)
    local floors = ns.GetFloors(state.instanceID, state.wing)
    local floor = floors and floors[state.floorIndex]
    if not floor then return end
    local left, top = canvas:GetLeft(), canvas:GetTop()
    local scale = canvas:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local x = (cx / scale - left) / canvas:GetWidth()
    local y = (top - cy / scale) / canvas:GetHeight()
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    DungeonMapDB.markers = DungeonMapDB.markers or {}
    local m = DungeonMapDB.markers
    m[state.instanceID] = m[state.instanceID] or {}
    m[state.instanceID][floor.uiMapID] = m[state.instanceID][floor.uiMapID] or {}
    table.insert(m[state.instanceID][floor.uiMapID], { kind = ns.editKind, x = x, y = y })
    ns.Print(format("%s placed on %s (%.3f, %.3f). Shift-click a marker to remove it.", ns.MARKER_KINDS[ns.editKind].label, floor.name or "this floor", x, y))
    ns.RefreshMap()
end

function ns.RemoveMarker(mk)
    local list = DungeonMapDB.markers and DungeonMapDB.markers[mk.instance] and DungeonMapDB.markers[mk.instance][mk.floor]
    if list and list[mk.idx] then
        table.remove(list, mk.idx)
        ns.Print("Marker removed.")
        ns.RefreshMap()
    end
end
