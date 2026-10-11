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
    p:SetScript("OnEnter", function(self)
        local d = ns.Dungeons[self.instance]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.DungeonTitle(self.instance, self.wing))
        GameTooltip:AddLine(d.raid and "Raid entrance" or "Dungeon entrance", 1, 1, 1)
        local ld = ns.LevelData(self.instance, self.wing)
        local lv = ns.LevelLabel(ld)
        if lv ~= "" then
            local r, g, b = ns.LevelColor(ld)
            GameTooltip:AddLine("Level " .. lv, r, g, b)
        end
        local bosses = ns.GetBosses(self.instance, nil, self.wing)
        if #bosses > 0 then
            local killed = 0
            for _, boss in ipairs(bosses) do
                if ns.IsKilled(boss, self.instance) then killed = killed + 1 end
            end
            GameTooltip:AddLine(format("%d bosses%s", #bosses, killed > 0 and format(", %d defeated", killed) or ""), 0.8, 0.8, 0.8)
        end
        if d.status == "classic" then GameTooltip:AddLine("Classic data - not confirmed for Forever yet", 0.9, 0.55, 0.2) end
        GameTooltip:AddLine("Click to view the dungeon map", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
    p:SetScript("OnClick", function(self) ns.ShowInstance(self.instance, nil, true, self.wing) end)
    pins[i] = p
    return p
end

function ns.RefreshEntrances()
    if not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    local canvas = WorldMapFrame:GetCanvas()
    local mapID = WorldMapFrame:GetMapID()
    local list = ns.Entrances and ns.Entrances[mapID]
    local scale = (WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale()) or 1
    local info = C_Map.GetMapInfo(mapID)
    local base = DungeonMapDB.entranceSize or 48
    local isContinent = info and info.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2)
    local size = isContinent and math.floor(base * CONTINENT_FACTOR + 0.5) or base
    if DungeonMapDB.showEntrances == false then list = nil end
    local used = 0
    if list and canvas then
        for _, e in ipairs(list) do
            local d = ns.Dungeons[e.instance]
            local hidden = d and d.raid and (DungeonMapDB.showRaids == false or (d.status == "classic" and DungeonMapDB.showClassicRaids == false))
            if d and not hidden then
                used = used + 1
                local p = getPin(used, canvas)
                p.instance = e.instance
                p.wing = e.wing
                local atlas = ns.Dungeons[e.instance].raid and "Raid" or "Dungeon"
                p.icon:SetAtlas(atlas)
                p.hl:SetAtlas(atlas)
                p:SetFrameLevel(math.min(9000, canvas:GetFrameLevel() + 2000)) -- above Blizzard's own pins
                p:SetSize(size, size)
                p:SetScale(1 / scale)
                p:ClearAllPoints()
                local ps = 1 / scale -- anchor offsets are expressed in the pin's own (scaled) units
                -- clustered entrances share one position and are offset by whole pin sizes (ox, oy), so the group stays tight at any map size
                local gap = size * (isContinent and 0.85 or 1.1) -- continent: pins may overlap slightly, so groups read as one place
                p:SetPoint("CENTER", canvas, "TOPLEFT", e.x * canvas:GetWidth() / ps + (e.ox or 0) * gap, -e.y * canvas:GetHeight() / ps - (e.oy or 0) * gap)
                p:Show()
            end
        end
    end
    for i = used + 1, #pins do pins[i]:Hide() end
end

function ns.HookEntrances()
    if ns.entrancesHooked or not WorldMapFrame then return end
    ns.entrancesHooked = true
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.RefreshEntrances)
    end
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", ns.RefreshEntrances)
    end
    WorldMapFrame:HookScript("OnShow", ns.RefreshEntrances)
end

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
