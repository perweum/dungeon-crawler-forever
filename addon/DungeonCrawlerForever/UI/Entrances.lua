-- Dungeon entrance pins on the regular world map. Clicking one opens that dungeon's map inside the world map.
-- Data: ns.Entrances[zoneUiMapID] = { { instance = <instanceMapID>, x = 0..1, y = 0..1 }, ... } (Data/Entrances.lua)
local _, ns = ...

local pins = {}
local CONTINENT_FACTOR = 0.42 -- continent maps: small pins, so they neither fill the map nor hide the city icons underneath

-- The zone map an instance belongs to (for the breadcrumb): the lowest zone map id that is not a continent map.
function ns.EntranceZoneFor(instanceID)
    local best
    for zone, list in pairs(ns.Entrances or {}) do
        for _, e in ipairs(list) do
            if e.instance == instanceID then
                local info = C_Map.GetMapInfo(zone)
                local continent = info and info.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2)
                if not continent and (not best or zone < best) then best = zone end
            end
        end
    end
    return best
end

-- The chooser for an entrance with several dungeons or wings: a small list under the pin, one row per instance with its level range. It is our own
-- frame (no Blizzard menu or dropdown template), closes when the mouse leaves it and the pin, and is never put in Blizzard's UISpecialFrames.
local chooser
function ns.HideEntranceChooser() if chooser then chooser:Hide() end end

function ns.ShowEntranceChooser(pin, groupOverride)
    if not chooser then
        chooser = CreateFrame("Frame", "DungeonMapEntranceChooser", UIParent, "BackdropTemplate")
        chooser:SetFrameStrata("FULLSCREEN_DIALOG")
        chooser:SetClampedToScreen(true)
        pcall(chooser.SetBackdrop, chooser, { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        pcall(chooser.SetBackdropColor, chooser, 0.05, 0.04, 0.03, 0.95)
        pcall(chooser.SetBackdropBorderColor, chooser, 0.78, 0.6, 0.32, 1)
        chooser.rows = {}
        chooser:SetScript("OnHide", function(self)
            if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        end)
    end
    local group = groupOverride or pin.group or {}
    local width = 0
    for i, e in ipairs(group) do
        local row = chooser.rows[i]
        if not row then
            row = CreateFrame("Button", nil, chooser)
            row:SetHeight(22)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(1, 0.82, 0, 0.18)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("LEFT", 8, 0)
            row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.level:SetPoint("RIGHT", -8, 0)
            row:SetScript("OnClick", function(self)
                chooser:Hide()
                ns.ShowInstance(self.entry.instance, nil, true, self.entry.wing)
            end)
            chooser.rows[i] = row
        end
        row.entry = e
        row.name:SetText(ns.DungeonTitle(e.instance, e.wing))
        local _, _, text, r, g, b = ns.EntranceLevelInfo({ e })
        row.level:SetText(text or "")
        row.level:SetTextColor(r or 1, g or 1, b or 1)
        local w = (row.name:GetStringWidth() or 100) + (row.level:GetStringWidth() or 30) + 44
        if w > width then width = w end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", chooser, "TOPLEFT", 6, -6 - (i - 1) * 22)
        row:Show()
    end
    for i = #group + 1, #chooser.rows do chooser.rows[i]:Hide() end
    for i = 1, #group do chooser.rows[i]:SetWidth(math.max(160, width) - 12) end
    chooser:SetSize(math.max(160, width), #group * 22 + 12)
    chooser.owner, chooser.shownAt = pin, GetTime()
    chooser:ClearAllPoints()
    chooser:SetPoint("TOP", pin, "BOTTOM", 0, -16)
    chooser:Show()
    if C_Timer and C_Timer.NewTicker and not chooser.ticker then
        chooser.ticker = C_Timer.NewTicker(0.25, function()
            if GetTime() - (chooser.shownAt or 0) < 0.4 then return end
            local over = chooser:IsMouseOver() or (chooser.owner and chooser.owner:IsMouseOver())
            if not over or not (WorldMapFrame and WorldMapFrame:IsShown()) then chooser:Hide() end
        end)
    end
end

local function getPin(i, canvas)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, canvas)
    p:SetSize(DungeonMapDB.entranceSize or 48, DungeonMapDB.entranceSize or 48) -- resized on every refresh
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p.icon:SetAtlas("Dungeon")
    p.hl = p:CreateTexture(nil, "HIGHLIGHT")
    p.hl:SetAllPoints()
    p.hl:SetAtlas("Dungeon")
    p.hl:SetBlendMode("ADD")
    p.level = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- level range under the icon
    p.level:SetPoint("TOP", p, "BOTTOM", 0, 3)
    local lf, ls = p.level:GetFont()
    if lf then p.level:SetFont(lf, ls, "OUTLINE") end
    p:SetScript("OnEnter", function(self)
        local group = self.group or {}
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if #group > 1 then
            -- several dungeons / wings at one entrance: list them, a click opens the chooser
            local same = true
            for _, e in ipairs(group) do if e.instance ~= group[1].instance then same = false end end
            GameTooltip:SetText(same and ns.Dungeons[group[1].instance].name or "Dungeons and raids here")
            for _, e in ipairs(group) do
                local _, _, text, r, g, b = ns.EntranceLevelInfo({ e })
                GameTooltip:AddDoubleLine(ns.DungeonTitle(e.instance, e.wing), text or "", 1, 1, 1, r or 1, g or 1, b or 1)
            end
            GameTooltip:AddLine("Click to choose", 0.5, 0.8, 1)
            GameTooltip:Show()
            return
        end
        local d = ns.Dungeons[self.instance]
        GameTooltip:SetText(ns.DungeonTitle(self.instance, self.wing))
        GameTooltip:AddLine(d.raid and "Raid entrance" or "Dungeon entrance", 1, 1, 1)
        local ld = ns.LevelData(self.instance, self.wing)
        local lv = ns.LevelLabel(ld)
        if lv ~= "" then
            local r, g, b = ns.LevelColor(ld)
            GameTooltip:AddLine("Level " .. lv, r, g, b)
        end
        local bosses = {}
        for _, boss in ipairs(ns.GetBosses(self.instance, nil, self.wing)) do
            if not boss.trash then bosses[#bosses + 1] = boss end -- the Trash entry is not a boss
        end
        if #bosses > 0 then
            local killed = 0
            for _, boss in ipairs(bosses) do
                if ns.IsKilled(boss, self.instance) then killed = killed + 1 end
            end
            GameTooltip:AddLine(format("%d bosses%s", #bosses, killed > 0 and format(", %d defeated", killed) or ""), 0.8, 0.8, 0.8)
        end
        local ctLine = not d.raid and ns.ClearTimeLine and ns.ClearTimeLine(self.instance, self.wing)
        if ctLine then GameTooltip:AddLine("|TInterface\\Icons\\INV_Misc_PocketWatch_01:12:12:0:0:64:64:5:59:5:59|t " .. ctLine, 0.85, 0.85, 0.85) end
        if d.status == "classic" then GameTooltip:AddLine("Classic data - not confirmed for Forever yet", 0.9, 0.55, 0.2) end
        GameTooltip:AddLine("Click to view the dungeon map", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
    p:SetScript("OnClick", function(self)
        local group = self.group or {}
        if #group > 1 then ns.ShowEntranceChooser(self) else ns.ShowInstance(self.instance, nil, true, self.wing) end
    end)
    pins[i] = p
    return p
end

-- Where an instance's entrance is: its zone map and the spot on it (the first entry of the data, a wing's own when it has one).
function ns.EntrancePosition(instanceID, wing)
    local best
    for zone, list in pairs(ns.Entrances or {}) do
        for _, e in ipairs(list) do
            if e.instance == instanceID and (not best or (wing and e.wing == wing)) then best = { zone, e.x, e.y } end
        end
    end
    if best then return best[1], best[2], best[3] end
end

-- Entrance pins of ours on OpenMap's stitched map, only for dungeons it shows no icon of (ns.OpenMapCovered). The spot is converted with OpenMap's own
-- WorldFromMap / MapFromWorld (zone map spot -> stitched world -> the map under the view). Returns how many pins were used.
function ns.RefreshOpenMapPins(canvas, mapID, scale, api)
    local covered = ns.OpenMapCovered and ns.OpenMapCovered()
    if not covered or not canvas or not api.WorldFromMap or not api.MapFromWorld then return 0 end
    local base = DungeonMapDB.entranceSize or 48
    local size = math.floor(base * CONTINENT_FACTOR + 0.5) -- small, like OpenMap's own icons
    local level = canvas:GetFrameLevel() + 2050
    if api.ArtTopLevel then
        local ok, top = pcall(api.ArtTopLevel)
        if ok and type(top) == "number" and top + 15 > level then level = top + 15 end
    end
    level = math.min(9400, level)
    local used, seen = 0, {}
    if DungeonMapDB.showEntrances ~= false then
        for zone, list in pairs(ns.Entrances or {}) do
            local info = C_Map.GetMapInfo(zone)
            local isContinent = info and type(info.mapType) == "number" and info.mapType <= (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2)
            if not isContinent then -- (continent maps repeat the zone entrances)
                for _, e in ipairs(list) do
                    local d = ns.Dungeons[e.instance]
                    local hidden = d and d.raid and (DungeonMapDB.showRaids == false or (d.status == "classic" and DungeonMapDB.showClassicRaids == false))
                    if d and not hidden and not covered[e.instance] then
                        local ok, u, v = pcall(api.WorldFromMap, zone, e.x, e.y)
                        local x, y
                        if ok and type(u) == "number" and type(v) == "number" then
                            local ok2, mx, my = pcall(api.MapFromWorld, mapID, u, v)
                            if ok2 and type(mx) == "number" and type(my) == "number" then x, y = mx, my end
                        end
                        local key = x and format("%d:%.3f,%.3f", e.instance, x, y)
                        if x and not seen[key] then
                            seen[key] = true
                            used = used + 1
                            local p = getPin(used, canvas)
                            p.group = { e }
                            p.instance = e.instance
                            p.wing = e.wing
                            local atlas = d.raid and "Raid" or "Dungeon"
                            p.icon:SetAtlas(atlas)
                            p.hl:SetAtlas(atlas)
                            p:SetFrameLevel(level)
                            p:SetSize(size, size)
                            p.level:Hide()
                            p:SetScale(1 / scale)
                            p:ClearAllPoints()
                            p:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() * scale, -y * canvas:GetHeight() * scale)
                            p:Show()
                        end
                    end
                end
            end
        end
    end
    return used
end

function ns.RefreshEntrances()
    if not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    local canvas = WorldMapFrame:GetCanvas()
    local mapID = WorldMapFrame:GetMapID()
    local list = ns.Entrances and ns.Entrances[mapID]
    local scale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    -- Next to OpenMap's stitched map we draw no pins of our own: its dungeon icons are there and win every click, so UI/OpenMap.lua takes
    -- their clicks and opens our dungeon map from them.
    local api = ns.OpenMapAPI()
    if api then
        ns.HideEntranceChooser()
        -- ... except for a dungeon OpenMap has no icon for (new ones, until it knows them): its entrance is drawn here, from our own data
        local used = ns.RefreshOpenMapPins and ns.RefreshOpenMapPins(canvas, mapID, scale, api) or 0
        for i = used + 1, #pins do pins[i]:Hide() end
        if ns.RefreshQuestPins then pcall(ns.RefreshQuestPins, canvas, mapID, scale) end -- tracked quests are ours alone: still drawn
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    local base = DungeonMapDB.entranceSize or 48
    local isContinent = info and info.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2)
    local size = isContinent and math.floor(base * CONTINENT_FACTOR + 0.5) or base
    if DungeonMapDB.showEntrances == false then list = nil end
    local used = 0
    ns.HideEntranceChooser()
    -- one pin per entrance spot: entries that share a position (wings, dungeons at one door) become one pin with a chooser
    local order, groups = {}, {}
    if list then
        for _, e in ipairs(list) do
            local d = ns.Dungeons[e.instance]
            local hidden = d and d.raid and (DungeonMapDB.showRaids == false or (d.status == "classic" and DungeonMapDB.showClassicRaids == false))
            if d and not hidden then
                local key = format("%.4f,%.4f", e.x, e.y)
                if not groups[key] then groups[key] = {}; order[#order + 1] = key end
                table.insert(groups[key], e)
            end
        end
    end
    if canvas then
        for _, key in ipairs(order) do
            local g = groups[key]
            local e = g[1]
            used = used + 1
            local p = getPin(used, canvas)
            p.group = g
            p.instance = e.instance
            p.wing = e.wing
            local allRaids = true
            for _, x in ipairs(g) do if not ns.Dungeons[x.instance].raid then allRaids = false end end
            local atlas = allRaids and "Raid" or "Dungeon"
            p.icon:SetAtlas(atlas)
            p.hl:SetAtlas(atlas)
            p:SetFrameLevel(math.min(9000, canvas:GetFrameLevel() + 2000)) -- above Blizzard's own pins
            p:SetSize(size, size)
            if DungeonMapDB.showEntranceLevels ~= false and not isContinent then
                local _, _, text, r, gr, b = ns.EntranceLevelInfo(g)
                if text then
                    p.level:SetText(text)
                    p.level:SetTextColor(r, gr, b)
                    p.level:Show()
                else
                    p.level:Hide()
                end
            else
                p.level:Hide()
            end
            p:SetScale(1 / scale)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", e.x * canvas:GetWidth() * scale, -e.y * canvas:GetHeight() * scale)
            p:Show()
        end
    end
    for i = used + 1, #pins do pins[i]:Hide() end
    if ns.RefreshQuestPins then pcall(ns.RefreshQuestPins, canvas, mapID, scale) end
end

-- Tracked quests (D-072): a blue quest marker where each one starts, on its zone map and on the maps around it (continent, a city's zone).
-- Left-click puts the game's own map pin there (it shows the way in the world), right-click stops tracking.
local qpins = {}
local QUEST_SIZE = 30

local function questAtlas()
    if ns.questAtlas == nil then
        local ok, info = pcall(C_Texture and C_Texture.GetAtlasInfo, "QuestDaily") -- the game's blue "!" (repeatable quests)
        ns.questAtlas = (ok and info) and "QuestDaily" or false
    end
    return ns.questAtlas
end

-- the tracked-quest marker on a texture (also the row icon in the Quests list)
function ns.SetQuestMarker(tex)
    local atlas = questAtlas()
    if atlas then
        tex:SetAtlas(atlas)
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1)
    else -- no blue marker on this client: the yellow one, turned blue
        tex:SetAtlas("QuestNormal")
        tex:SetDesaturated(true)
        tex:SetVertexColor(0.45, 0.75, 1)
    end
end

-- Where a quest's start lies on the map shown, or nil. Not through world coordinates: on Forever those only line up on the world map
-- (OpenMap's notes on HereBeDragons), so:
--   OpenMap's stitched map: its own conversion (OpenMapAPI.WorldFromMap / MapFromWorld); the spot may lie past the map underneath,
--     the stitched view shows beyond it (returns true as third value)
--   the giver's map inside the one shown (a zone on its continent, a city in its zone): the client's map rectangles (C_Map.GetMapRectOnMap)
local function questPos(q, mapID)
    local gx, gy = q.gx / 100, q.gy / 100
    local om = ns.OpenMapAPI()
    if om and om.WorldFromMap and om.MapFromWorld then
        local ok, u, v = pcall(om.WorldFromMap, q.gmap, gx, gy)
        if ok and type(u) == "number" and type(v) == "number" then
            local ok2, x, y = pcall(om.MapFromWorld, mapID, u, v)
            if ok2 and type(x) == "number" and type(y) == "number" then return x, y, true end
        end
    end
    if mapID == q.gmap then return gx, gy end
    if not C_Map.GetMapRectOnMap then return end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, q.gmap, mapID)
    if not ok or type(minX) ~= "number" or type(maxX) ~= "number" or type(minY) ~= "number" or type(maxY) ~= "number" then return end
    if maxX <= minX or maxY <= minY then return end
    local x, y = minX + gx * (maxX - minX), minY + gy * (maxY - minY)
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    return x, y
end

local function setWaypoint(q)
    if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(q.gmap) then return false end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(q.gmap, q.gx / 100, q.gy / 100))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    return ok
end

local function getQuestPin(i, canvas)
    local p = qpins[i]
    if p then return p end
    p = CreateFrame("Button", nil, canvas)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p.hl = p:CreateTexture(nil, "HIGHLIGHT")
    p.hl:SetAllPoints()
    p.hl:SetBlendMode("ADD")
    p:SetScript("OnEnter", function(self)
        local q = self.q
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.QuestTitle(q), 0.45, 0.75, 1)
        GameTooltip:AddLine("Quest for " .. ns.DungeonTitle(self.instance), 1, 1, 1)
        if q.giver then GameTooltip:AddLine("Starts: " .. q.giver, 0.85, 0.85, 0.85) end
        if q.min then
            local lvl = UnitLevel and UnitLevel("player")
            local low = type(lvl) == "number" and lvl < q.min
            GameTooltip:AddLine("Requires level " .. q.min, low and 1 or 0.85, low and 0.55 or 0.85, low and 0.38 or 0.85)
        end
        GameTooltip:AddLine("Click to put a map pin here", 0.5, 0.8, 1)
        GameTooltip:AddLine("Right-click to stop tracking", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
    p:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            GameTooltip:Hide()
            ns.SetQuestTracked(self.q, self.instance, false)
            if ns.ViewShown and ns.ViewShown() then ns.RefreshMap() end
        elseif not setWaypoint(self.q) then
            ns.Print("The game does not allow a map pin on this map.")
        end
    end)
    qpins[i] = p
    return p
end

-- Questie draws its own "!" on quest givers: ours then sits just above it, so both can be seen and hovered
local function questieLoaded()
    if _G.QuestieLoader then return true end
    local f = C_AddOns and C_AddOns.IsAddOnLoaded
    local ok, on = pcall(f or function() end, "Questie")
    return ok and on and true or false
end

function ns.RefreshQuestPins(canvas, mapID, scale)
    local used = 0
    if canvas and mapID and ns.TrackedQuests then
        local info = C_Map.GetMapInfo(mapID)
        local small = info and type(info.mapType) == "number" and info.mapType <= (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2) -- world and continent maps
        local size = small and math.floor(QUEST_SIZE * 0.6 + 0.5) or QUEST_SIZE
        local level = canvas:GetFrameLevel() + 2100 -- above the entrance pins and Questie's icons (from 2015)
        local om = ns.OpenMapAPI()
        if om and om.ArtTopLevel then
            local ok, top = pcall(om.ArtTopLevel) -- OpenMap's stitched art reaches this level on the canvas
            if ok and type(top) == "number" and top + 20 > level then level = top + 20 end
        end
        level = math.min(9500, level)
        local lift = questieLoaded() and size * 0.7 or 0
        for _, t in ipairs(ns.TrackedQuests()) do
            local x, y = questPos(t.q, mapID)
            if x then
                used = used + 1
                local p = getQuestPin(used, canvas)
                p.q, p.instance = t.q, t.instance
                ns.SetQuestMarker(p.icon)
                ns.SetQuestMarker(p.hl)
                p:SetFrameLevel(level)
                p:SetSize(size, size)
                p:SetScale(1 / scale)
                p:ClearAllPoints()
                p:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() * scale, -y * canvas:GetHeight() * scale + lift)
                p:Show()
            end
        end
    end
    for i = used + 1, #qpins do qpins[i]:Hide() end
end

-- (Map changes are followed by the watcher frame in UI/View.lua, which calls ns.RefreshEntrances; nothing is hooked on Blizzard's map.)
function ns.HookEntrances() end

-- Debug: record the state of every entrance pin on the current map (read back from SavedVariables).
function ns.DumpPins()
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local d = { mapID = WorldMapFrame and WorldMapFrame:GetMapID(), pins = {}, entries = ns.Entrances and ns.Entrances[WorldMapFrame:GetMapID()] and #ns.Entrances[WorldMapFrame:GetMapID()] or 0 }
    if canvas then
        d.canvas = { w = canvas:GetWidth(), h = canvas:GetHeight(), scale = canvas:GetScale(), effScale = canvas:GetEffectiveScale(),
            level = canvas:GetFrameLevel(), strata = canvas:GetFrameStrata(), mapScale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() }
    end
    for i, p in ipairs(pins) do
        local pt, rel, rp, ox, oy = p:GetPoint(1)
        d.pins[i] = { instance = p.instance, name = ns.Dungeons[p.instance or 0] and ns.Dungeons[p.instance].name, shown = p:IsShown(),
            visible = p:IsVisible(), w = p:GetWidth(), h = p:GetHeight(), scale = p:GetScale(), effScale = p:GetEffectiveScale(),
            alpha = p:GetEffectiveAlpha(), level = p:GetFrameLevel(), strata = p:GetFrameStrata(), point = tostring(pt) .. "/" .. tostring(rp) .. " " .. tostring(ox) .. "," .. tostring(oy),
            left = p:GetLeft(), top = p:GetTop(), iconShown = p.icon:IsShown(), iconAtlas = p.icon:GetAtlas(), iconTexture = tostring(p.icon:GetTexture()) }
    end
    DungeonMapDB.pindump = d
    ns.Print(format("pin dump saved: map %s, %d data entries, %d pin frames. /reload to flush.", tostring(d.mapID), d.entries, #d.pins))
end
