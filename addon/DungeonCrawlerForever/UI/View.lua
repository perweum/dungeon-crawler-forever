-- Dungeon view: drawn inside the regular world map frame (same size/look), with a breadcrumb entry and a
-- boss panel on the right. Floor art = client tiles by FileDataID. Boss pins are clickable.
local _, ns = ...

local PIN_SIZE = 34 -- default; the real size comes from the options (DungeonMapDB.pinSize)
local SILVER = { 0.78, 0.80, 0.88 }
local PURPLE = { 0.68, 0.45, 0.95 } -- ring of a summoned boss (Dreadsteed, 0.5 gear ...)
local GOLD = { 0.86, 0.68, 0.22 }
local SIDE_W = 400 -- sidebar width in "side" mode
local PANEL_W = SIDE_W
local GLOW = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\glow"
local PIN_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local view, art, tileHost, tiles, pins, rows, itemRows, floorButtons, dungeonList, panel, crumbs
local ghostTiles = {} -- edit-mode overlay: another floor drawn faintly on top of the art (textures in tileHost, so they are cropped to the art and sit above its tiles)
local state = { instanceID = nil, floorIndex = 1, diff = nil, selected = nil }
ns.internalNav = false

-- Sidebar mode: "side" (next to the map), "hidden" (map only) or "wide" (sidebar over the whole view, no map).
-- Default: open in the full-size world map, closed in the small one. A choice made with the arrow / tab is remembered per window
-- size (DungeonMapDB.sideChoice); opening the sidebar by clicking a boss, and the wide view, are temporary (state.tempMode).
local function windowMode()
    local ok, max = pcall(function() return WorldMapFrame and WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() end)
    return (ok and max) and "full" or "small"
end

local function sideMode()
    local m = state.tempMode
    if not m then
        local c = DungeonMapDB and DungeonMapDB.sideChoice
        m = c and c[windowMode()]
    end
    if m == "side" or m == "wide" or m == "hidden" then return m end
    return windowMode() == "full" and "side" or "hidden"
end
-- Width taken from the map area by the sidebar (the map is centred in what is left).
local function reserved()
    return sideMode() == "side" and (SIDE_W + 12) or 0
end

local function container()
    return WorldMapFrame and (WorldMapFrame.ScrollContainer or WorldMapFrame)
end

-- Pins ----------------------------------------------------------------------------------------

local function setPortrait(tex, boss)
    if boss.trash then -- the "Trash" entry of a dungeon: no creature, a bag icon
        tex:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif boss.display and SetPortraitTextureFromCreatureDisplayID then
        SetPortraitTextureFromCreatureDisplayID(tex, boss.display)
        tex:SetTexCoord(0.1, 0.9, 0.1, 0.9) -- model renders are small on a transparent square: crop in
    elseif boss.portrait then
        -- the Encounter Journal's creature pictures are 128 x 64 (twice as wide as high) with the creature in the middle: the middle square, so
        -- the picture is not squeezed into the round icon
        tex:SetTexture(boss.portrait)
        tex:SetTexCoord(0.25, 0.75, 0, 1)
    else
        tex:SetAtlas("DungeonSkull")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function addMask(owner, tex)
    local mask = owner:CreateMaskTexture()
    mask:SetTexture(PIN_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

local function selectBoss(b, jumpToFloor)
    state.selected = b and b.id or nil
    local onCombined = state.floor and state.floor.combined and ns.CombinedPoint(state.floor, tonumber(b and b.floor), b and b.x or 0, b and b.y or 0)
    if jumpToFloor and b and b.floor and not onCombined then
        local floors = ns.GetFloors(state.instanceID, state.wing)
        for idx, fl in ipairs(floors or {}) do
            if fl.uiMapID == tonumber(b.floor) then state.floorIndex = idx end
        end
    end
    ns.RefreshMap()
    if b and ns.EnsureBossVisible then ns.EnsureBossVisible(b) end
end

local function onPinEnter(self)
    local b = self.boss
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(b.name)
    GameTooltip:AddLine(ns.IsKilled(b, state.instanceID) and "|cff00ff00Defeated|r" or "Not defeated", 1, 1, 1)
    if b.approx then GameTooltip:AddLine("Approximate position", 1, 0.6, 0.2) end
    if not ns.editing then GameTooltip:AddLine("Double-click: wide view with loot", 0.7, 0.7, 0.7) end
    if ns.editing then GameTooltip:AddLine("Edit mode: click the map to move this boss", 1, 0.82, 0) end
    GameTooltip:Show()
end

local function sizePin(p, size)
    p:SetSize(size, size)
    p.glow:SetSize((size + 12) * 2.1, (size + 12) * 2.1)
    p.rimDark:SetSize(size + 12, size + 12)
    p.rimGold:SetSize(size + 8, size + 8)
    p.hover:SetSize((size + 12) * 2.3, (size + 12) * 2.3)
    p.check:SetSize(math.max(12, size * 0.47), math.max(12, size * 0.47))
end

local function createPin(parent)
    local p = CreateFrame("Button", nil, parent or art)
    p:SetSize(PIN_SIZE, PIN_SIZE)
    p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
    p.glow:SetSize((PIN_SIZE + 12) * 2.1, (PIN_SIZE + 12) * 2.1)
    p.glow:SetPoint("CENTER")
    p.glow:SetTexture(GLOW) -- soft round halo for the selected boss
    p.glow:SetBlendMode("ADD")
    p.glow:SetVertexColor(1, 0.8, 0.2)
    p.back = p:CreateTexture(nil, "BACKGROUND", nil, 3) -- dark disc: transparent model renders sit on this, not on the gold rim
    p.back:SetAllPoints()
    p.back:SetColorTexture(0.08, 0.07, 0.06, 1)
    addMask(p, p.back)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    addMask(p, p.icon)
    -- border sits outside the portrait: a gold disc and a dark disc behind it, both cut round with the same mask
    p.rimDark = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.rimDark:SetSize(PIN_SIZE + 12, PIN_SIZE + 12)
    p.rimDark:SetPoint("CENTER")
    p.rimDark:SetColorTexture(0.08, 0.05, 0.02, 1)
    addMask(p, p.rimDark)
    p.rimGold = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    p.rimGold:SetSize(PIN_SIZE + 8, PIN_SIZE + 8)
    p.rimGold:SetPoint("CENTER")
    p.rimGold:SetColorTexture(0.86, 0.68, 0.22, 1)
    addMask(p, p.rimGold)
    p.check = p:CreateTexture(nil, "OVERLAY", nil, 2)
    p.check:SetSize(16, 16)
    p.check:SetPoint("BOTTOMRIGHT", 2, -2)
    p.check:SetAtlas("common-icon-checkmark")
    -- kill-order number on the pin (Atlas style)
    p.num = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.num:SetPoint("BOTTOMLEFT", -3, -3)
    local nf, nsz, nfl = p.num:GetFont()
    if nf then p.num:SetFont(nf, nsz, "OUTLINE") end
    -- hover glow like the game's own map icons (soft yellow-white halo around the whole pin)
    p.hover = p:CreateTexture(nil, "BACKGROUND", nil, -2) -- behind the portrait so only the halo outside it glows
    p.hover:SetTexture(GLOW)
    p.hover:SetBlendMode("ADD")
    p.hover:SetSize((PIN_SIZE + 12) * 2.3, (PIN_SIZE + 12) * 2.3)
    p.hover:SetPoint("CENTER")
    p.hover:SetVertexColor(1, 0.92, 0.6)
    p.hover:Hide()
    p:SetScript("OnEnter", function(self)
        self.hover:Show()
        onPinEnter(self)
    end)
    p:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    p:SetScript("OnHide", function(self) self.hover:Hide() end)
    p:SetScript("OnClick", function(self) -- click: select the boss and open the sidebar if it is closed
        if ns.RouteTool() then ns.EditRouteStop(self.boss) return end -- route tool: a click on a boss adds it as a stop
        state.scrollTo = self.boss.id
        if state.groupKids and state.groupKids[self.boss.id] then -- an encounter with several opponents: show them
            state.expandedGroups = state.expandedGroups or {}
            state.expandedGroups[self.boss.id] = true
        end
        if sideMode() == "hidden" and not ns.editing then
            state.selected = self.boss.id
            ns.SetSideMode("side", true)
        else
            selectBoss(self.boss, false)
        end
    end)
    p:SetScript("OnDoubleClick", function(self) -- double click on the map: same, the wide view
        if ns.editing then return end
        state.scrollTo = self.boss.id
        selectBoss(self.boss, false)
        if sideMode() ~= "wide" then ns.SetSideMode("wide", true) end
    end)
    return p
end

-- Fill a pin from a boss (shared by the big map and the overview). idx = kill-order number.
local function fillPin(p, b, idx)
    local id = state.instanceID
    p.boss = b
    setPortrait(p.icon, b)
    local killed = ns.IsKilled(b, id)
    local rare = DungeonMapDB.markRares ~= false and ns.IsRare(id, b.name)
    local c = b.summoned and PURPLE or (rare and SILVER or GOLD)
    p.rimGold:SetColorTexture(c[1], c[2], c[3], 1)
    p.check:SetShown(killed)
    p.icon:SetDesaturated(killed and DungeonMapDB.greyDefeated ~= false)
    p.glow:SetShown(state.selected == b.id)
    p.num:SetText(b.num and tostring(b.num) or "")
end

-- Floor markers: small icons for entrance / exit / stairs / portal.
local markerFrames = {}
local function createMarker(parent)
    local m = CreateFrame("Button", nil, parent)
    m.ring = m:CreateTexture(nil, "BACKGROUND") -- gold halo: the marker picked for linking, or the one you arrive at after travelling
    m.ring:SetPoint("CENTER")
    m.ring:SetTexture(GLOW)
    m.ring:SetBlendMode("ADD")
    m.ring:SetVertexColor(1, 0.85, 0.3)
    m.ring:Hide()
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    m.letter = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- link letter: both ends of a link carry the same one
    m.letter:SetPoint("LEFT", m, "RIGHT", 1, 0)
    m.letter:SetTextColor(0.55, 0.75, 1)
    local lf, ls = m.letter:GetFont()
    if lf then m.letter:SetFont(lf, ls, "OUTLINE") end
    m:SetScript("OnEnter", function(self)
        local kind = ns.MARKER_KINDS[self.mk.kind] or ns.MARKER_KINDS[ns.MARKER_ALIASES[self.mk.kind] or ""]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(kind and kind.label or self.mk.kind)
        if self.mk.kind == "trigger" then
            if self.mk.boss then GameTooltip:AddLine("Starts " .. self.mk.boss, 0.7, 0.9, 1) end
            if self.mk.label and self.mk.label ~= "" then GameTooltip:AddLine(self.mk.label, 1, 1, 1, true) end
        end
        local to = ns.GetLinkTarget(self.mk.instance, self.mk.floor, self.mk.x, self.mk.y)
        if to then
            local letter = ns.LinkLetter(self.mk.instance, self.mk.floor, self.mk.x, self.mk.y)
            if to.floor == self.mk.floor then
                GameTooltip:AddLine("Linked to the matching " .. (letter or "") .. " marker", 1, 1, 1)
            else
                GameTooltip:AddLine("Leads to: " .. ns.FloorName(self.mk.instance, to.floor), 1, 1, 1)
            end
            if ns.RouteTool() then
                GameTooltip:AddLine("Click to add a step to the route", 1, 0.82, 0)
            elseif not ns.editing then
                GameTooltip:AddLine("Click to go there", 0.7, 0.9, 0.7)
            end
        end
        if ns.editing then
            if ns.editKind == "__link" then
                GameTooltip:AddLine(to and "Shift-click to remove the link" or "Click to link markers", 1, 0.82, 0)
            else
                GameTooltip:AddLine("Shift-click to remove", 1, 0.82, 0)
            end
        end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", GameTooltip_Hide)
    m:SetScript("OnClick", function(self)
        if ns.RouteTool() then
            ns.EditRouteMarker(self.mk) -- route tool: a click on a marker adds a step there
        elseif ns.editing and ns.editKind == "__link" then
            ns.EditLinkClick(self.mk, IsShiftKeyDown())
        elseif ns.editing and IsShiftKeyDown() then
            ns.RemoveMarker(self.mk)
        elseif not ns.editing then
            local to = ns.GetLinkTarget(self.mk.instance, self.mk.floor, self.mk.x, self.mk.y)
            if to then ns.TravelToFloor(to.floor, to.x, to.y) end
        end
    end)
    return m
end

local MARKER_SIZE = 1.5 -- all floor markers (entrance, exit, stairs, left / right, portal) are drawn 50 % larger than their base size

local function fillMarker(m, mk, size)
    local kind = ns.MARKER_KINDS[mk.kind] or ns.MARKER_KINDS[ns.MARKER_ALIASES[mk.kind] or ""] or ns.MARKER_KINDS.entrance
    m.mk = mk
    local box = size * MARKER_SIZE * (kind.scale or 1)
    m:SetSize(box, box)
    local atlas, rotation = kind.atlas, 0
    if kind.fallback and not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(kind.atlas)) then
        atlas, rotation = kind.fallback, kind.fallbackRotation or 0 -- an atlas this client does not have: the older arrow, turned if needed
    end
    if kind.texture then
        m.icon:SetTexture(kind.texture)
        m.icon:SetTexCoord(0, 1, 0, 1)
    else
        m.icon:SetTexCoord(0, 1, 0, 1)
        m.icon:SetAtlas(atlas)
    end
    m.icon:SetRotation(rotation)
    m.icon:SetVertexColor(kind.color[1], kind.color[2], kind.color[3])
    -- a trigger of the selected boss is drawn bigger and with a gold halo; the others stay small and dim
    local mine = mk.kind == "trigger" and mk.boss and state.selectedName == mk.boss
    if mk.kind == "trigger" then
        m:SetSize(box * (mine and 1.35 or 0.85), box * (mine and 1.35 or 0.85))
        m.icon:SetAlpha(mine and 1 or 0.75)
    else
        m.icon:SetAlpha(1)
    end
    local function same(p) return p and p.floor == mk.floor and math.abs(p.x - mk.x) < 0.006 and math.abs(p.y - mk.y) < 0.006 end
    local lit = same(ns.linkFrom) or (state.pulse and GetTime() < state.pulse.untilTime and same(state.pulse)) or mine
    m.ring:SetSize(box * 2.4, box * 2.4)
    local linkedHere = not lit and ns.editing and ns.editKind == "__link" and ns.GetLinkTarget(mk.instance, mk.floor, mk.x, mk.y)
    if linkedHere then
        m.ring:SetVertexColor(0.4, 1, 0.5) -- green: already linked (link tool)
    else
        m.ring:SetVertexColor(1, 0.85, 0.3) -- gold: picked for linking / arrival
    end
    m.ring:SetShown((lit or linkedHere) and true or false)
    local tag = ns.LinkLetter(mk.instance, mk.floor, mk.x, mk.y)
    if not tag and mk.kind == "trigger" and mk.label and #mk.label <= 3 then tag = mk.label end -- short labels (1, 2, A) show next to the icon; longer ones are in the tooltip
    m.letter:SetText(tag or "")
end

-- A short confirmation on the map banner (edit mode): "Linked ..." etc.
function ns.LinkNotice(text)
    state.linkMsg = { text = text, untilTime = GetTime() + 4 }
    C_Timer.After(4.1, function() if ns.ViewShown and ns.ViewShown() then ns.RefreshMap() end end)
end

-- Floor name for the tooltip ("Leads to: ...")
function ns.FloorName(instanceID, floorID)
    for _, w in ipairs(ns.GetWings(instanceID) or { { wing = nil } }) do
        for _, fl in ipairs(ns.GetFloors(instanceID, w.wing) or {}) do
            if fl.uiMapID == floorID then return fl.name or ("floor " .. fl.uiMapID) end
        end
    end
    return "another floor"
end

-- Open the floor a link leads to and highlight the marker you arrive at for a few seconds.
function ns.TravelToFloor(floorID, x, y)
    if state.floor and (state.floor.combined or state.floor.uiMapID == floorID) then -- the other end is on this very map: show it
        state.pulse = { floor = floorID, x = x, y = y, untilTime = GetTime() + 4 }
        C_Timer.After(4.1, function() if ns.ViewShown and ns.ViewShown() then ns.RefreshMap() end end)
        ns.RefreshMap()
        if not state.floor.combined and ns.CenterOn then
            ns.CenterOn(x, y, 2.4) -- pan there (and zoom in if the whole map is shown)
            ns.RefreshMap()
        end
        return
    end
    local function find(wing)
        for i, fl in ipairs(ns.GetFloors(state.instanceID, wing) or {}) do
            if fl.uiMapID == floorID then return i end
        end
    end
    local idx = find(state.wing)
    if not idx then -- a floor of another wing (Lower / Upper Blackrock Spire)
        for _, w in ipairs(ns.GetWings(state.instanceID) or {}) do
            idx = find(w.wing)
            if idx then state.wing = w.wing break end
        end
    end
    if not idx then return end
    state.pulse = { floor = floorID, x = x, y = y, untilTime = GetTime() + 4 }
    C_Timer.After(4.1, function() if ns.ViewShown and ns.ViewShown() then ns.RefreshMap() end end)
    ns.OpenFloor(idx)
end

-- Floor art -----------------------------------------------------------------------------------

-- Zoom / pan --------------------------------------------------------------------------------------
-- The art frame is resized (not scaled) so boss pins keep their size; the view clips whatever overflows.

local MAX_ZOOM = 6
local zoomAt, relayout, positionPins -- defined below, used by the view's event handlers
local zoom = { k = 1, x = 0, y = 0 }

local function resetZoom()
    zoom.k, zoom.x, zoom.y = 1, 0, 0
end

-- How far the art may be moved: until its edge meets the edge of the map area. Zero when it fits inside (no panning needed).
local function panLimits()
    local aw, ah = art:GetWidth(), art:GetHeight()
    local rw, rh = view:GetWidth() - reserved(), view:GetHeight()
    return math.max(0, (aw - rw) / 2), math.max(0, (ah - rh) / 2)
end

local function canPan()
    local lx, ly = panLimits()
    return lx > 1 or ly > 1
end

local function clampPan()
    local lx, ly = panLimits()
    zoom.x = math.max(-lx, math.min(lx, zoom.x))
    zoom.y = math.max(-ly, math.min(ly, zoom.y))
end

-- Edit mode: draw another floor (state.ghostID) faintly over this one, placed by the floors' world bounds, so the places where two floors
-- connect (stairs, ramps) can be seen: a corridor that ends on one floor continues at the same spot on the other.
local function layoutGhost(floor)
    local gf
    if ns.editing and state.ghostID and floor and floor.bounds and not state.overview then
        for _, fl in ipairs(ns.GetFloors(state.instanceID, state.wing) or {}) do
            if fl.uiMapID == state.ghostID and fl.bounds and not fl.yards and fl.uiMapID ~= floor.uiMapID then gf = fl end
        end
    end
    if not gf then
        for i = 1, #ghostTiles do ghostTiles[i]:Hide() end
        return
    end
    local a, b = floor.bounds, gf.bounds -- { x0, y0, x1, y1 } = Region_0, Region_1, Region_3, Region_4; u runs along world y (right to left), v along world x
    local W, H = art:GetWidth(), art:GetHeight()
    local uL, uR = (a[4] - b[4]) / (a[4] - a[2]), (a[4] - b[2]) / (a[4] - a[2])
    local vT, vB = (a[3] - b[3]) / (a[3] - a[1]), (a[3] - b[1]) / (a[3] - a[1])
    local gw, gh = (uR - uL) * W, (vB - vT) * H
    local used = 0
    local tw, th = gf.tile / gf.w * gw, gf.tile / gf.h * gh
    for r, row in ipairs(gf.tiles) do
        for c, fileID in ipairs(row) do
            used = used + 1
            local t = ghostTiles[used]
            if not t then
                t = tileHost:CreateTexture(nil, "ARTWORK", nil, 7)
                ghostTiles[used] = t
            end
            t:ClearAllPoints()
            t:SetSize(tw + 0.5, th + 0.5)
            t:SetPoint("TOPLEFT", tileHost, "TOPLEFT", uL * W + (c - 1) * tw, -(vT * H + (r - 1) * th))
            t:SetTexture(fileID)
            t:SetDesaturated(true)
            t:SetVertexColor(0.45, 0.75, 1)
            t:SetAlpha(0.5)
            t:Show()
        end
    end
    for i = used + 1, #ghostTiles do ghostTiles[i]:Hide() end
end

function ns.GhostState() return ghostTiles end -- for the smoke test

local function layoutArt(floor)
    local used = 0
    if not floor then
        for i = 1, #tiles do tiles[i]:Hide() end
        for i = 1, #ghostTiles do ghostTiles[i]:Hide() end
        return
    end
    -- the map is fitted (aspect kept) into the area left of the sidebar and centred there
    local vw, vh = view:GetWidth() - reserved() - (floor.yards and 12 or 0), view:GetHeight() - (floor.yards and 16 or 0)
    -- "fill" scales the map to cover the whole map area (centred; the edges are cropped), otherwise it is fitted with bars
    local pick = (floor.overview or DungeonMapDB.fillMap ~= false) and math.max or math.min -- an overview map always fills the window
    local s = pick(vw / floor.w, vh / floor.h) * zoom.k
    art.baseX = -reserved() / 2
    art:ClearAllPoints()
    art:SetSize(floor.w * s, floor.h * s)
    art:SetPoint("CENTER", view, "CENTER", art.baseX + zoom.x, zoom.y)
    local function tileTex()
        used = used + 1
        local t = tiles[used]
        if not t then
            t = tileHost:CreateTexture(nil, "ARTWORK")
            tiles[used] = t
        end
        if t.mask then -- left over from a combined map
            t:RemoveMaskTexture(t.mask)
            t.mask = nil
        end
        t:SetTexCoord(0, 1, 0, 1)
        t:ClearAllPoints()
        t:Show()
        return t
    end
    if floor.combined then
        -- one big map made of cropped pieces of the dungeon's own floor art; the pieces have soft edges (mask) so they blend into the parchment
        local c = floor.data
        local FEATHER = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\feather"
        if c.bg then
            local sf = ns.CombinedSource(floor.instanceID, c.bg.floor)
            if sf then
                local col, row = math.floor(c.bg.x0 / sf.tile) + 1, math.floor(c.bg.y0 / sf.tile) + 1
                local t = tileTex()
                local fid = sf.tiles[row] and sf.tiles[row][col]
                local tx0, ty0 = (col - 1) * sf.tile, (row - 1) * sf.tile
                t:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
                t:SetSize(floor.w * s, floor.h * s)
                t:SetTexture(fid)
                t:SetTexCoord((c.bg.x0 - tx0) / sf.tile, (c.bg.x1 - tx0) / sf.tile, (c.bg.y0 - ty0) / sf.tile, (c.bg.y1 - ty0) / sf.tile)
            end
        end
        floor.masks = floor.masks or {}
        for pi, p in ipairs(c.pieces) do
            local sf = ns.CombinedSource(floor.instanceID, p.floor)
            if sf then
                local mask = floor.masks[pi]
                if not mask then
                    mask = tileHost:CreateMaskTexture()
                    mask:SetTexture(FEATHER, "CLAMPTOWHITE", "CLAMPTOWHITE")
                    floor.masks[pi] = mask
                end
                mask:ClearAllPoints()
                mask:SetPoint("TOPLEFT", tileHost, "TOPLEFT", p.dx * s, -p.dy * s)
                mask:SetSize((p.x1 - p.x0) * p.s * s, (p.y1 - p.y0) * p.s * s)
                for r, rowTiles in ipairs(sf.tiles) do
                    for col, fid in ipairs(rowTiles) do
                        local tx0, ty0 = (col - 1) * sf.tile, (r - 1) * sf.tile
                        local ix0, ix1 = math.max(tx0, p.x0), math.min(tx0 + sf.tile, p.x1, sf.w)
                        local iy0, iy1 = math.max(ty0, p.y0), math.min(ty0 + sf.tile, p.y1, sf.h)
                        if ix1 > ix0 and iy1 > iy0 then
                            local t = tileTex()
                            t:SetTexture(fid)
                            t:SetTexCoord((ix0 - tx0) / sf.tile, (ix1 - tx0) / sf.tile, (iy0 - ty0) / sf.tile, (iy1 - ty0) / sf.tile)
                            t:SetSize((ix1 - ix0) * p.s * s + 0.5, (iy1 - iy0) * p.s * s + 0.5)
                            t:SetPoint("TOPLEFT", art, "TOPLEFT", (p.dx + (ix0 - p.x0) * p.s) * s, -(p.dy + (iy0 - p.y0) * p.s) * s)
                            t:AddMaskTexture(mask)
                            t.mask = mask
                        end
                    end
                end
            end
        end
    elseif floor.yards then
        -- Forever-new dungeons: tiles positioned in yards (128 yd per tile)
        for _, tl in ipairs(floor.tiles) do
            local size = (tl[4] or 128) * s
            local t = tileTex()
            t:SetSize(size + 0.6, size + 0.6) -- tiny overlap hides hairline seams between large outdoor tiles
            t:SetPoint("TOPLEFT", art, "TOPLEFT", tl[2] * s, -tl[3] * s)
            t:SetTexture(tl[1])
        end
    else
        local tw = floor.tile * s
        for r, row in ipairs(floor.tiles) do
            for c, fileID in ipairs(row) do
                local t = tileTex()
                t:SetSize(tw + 0.5, tw + 0.5) -- tiny overlap hides hairline seams
                t:SetPoint("TOPLEFT", art, "TOPLEFT", (c - 1) * tw, -(r - 1) * tw)
                t:SetTexture(fileID)
            end
        end
    end
    for i = used + 1, #tiles do tiles[i]:Hide() end
    layoutGhost(floor)
end

-- Breadcrumb ------------------------------------------------------------------------------------
-- Preferred: append our dungeon button to the world map's own navigation bar (World > Kalimdor > Orgrimmar > Dungeon),
-- with a floor dropdown when the dungeon has several floors. Fallback: an overlay bar that imitates it.

local function floorMenu()
    local list = {}
    for i, fl in ipairs(ns.GetFloors(state.instanceID, state.wing) or {}) do
        list[#list + 1] = {
            text = fl.name or ("Floor " .. i),
            func = function() state.floorIndex = i; ns.RefreshMap() end,
        }
    end
    return list
end

local nativeCrumb

-- Size the crumb to its text. Blizzard sizes a nav button once, when it is added; changing the text later (switching wings, e.g.
-- Lower -> Upper Blackrock Spire) leaves the old width, and a dropdown arrow squeezed onto the text does not respond. The arrow
-- is shown only when there is a floor list, and the button gets room for it.
local function fitCrumb(btn, hasList)
    if not btn then return end
    local fs = (type(btn.text) == "table" and btn.text) or (btn.GetFontString and btn:GetFontString())
    if type(fs) == "table" and fs.GetStringWidth then
        btn:SetWidth(fs:GetStringWidth() + (hasList and 53 or 30))
    end
    local arrow = btn.MenuArrowButton
    if type(arrow) == "table" and arrow.SetShown then arrow:SetShown(hasList and true or false) end
end

local function addNativeCrumb()
    local nav = WorldMapFrame and WorldMapFrame.NavBar
    if not (nav and NavBar_AddButton) then return false end
    local dungeon = ns.Dungeons[state.instanceID]
    local floors = ns.GetFloors(state.instanceID, state.wing)
    local title = ns.DungeonTitle(state.instanceID, state.wing)
    local data = { name = title, id = -state.instanceID, OnClick = function() end }
    if floors and #floors > 1 then data.listFunc = floorMenu end
    local list = nav.navList
    if nativeCrumb and list and list[#list] == nativeCrumb then
        -- already our button: update it in place
        nativeCrumb.data = data
        nativeCrumb:SetText(title)
        fitCrumb(nativeCrumb, data.listFunc ~= nil)
        if NavBar_CheckLength then pcall(NavBar_CheckLength, nav) end
        return true
    end
    local ok = pcall(NavBar_AddButton, nav, data)
    if not ok then return false end
    list = nav.navList
    nativeCrumb = list and list[#list]
    if nativeCrumb then
        fitCrumb(nativeCrumb, data.listFunc ~= nil)
        if NavBar_CheckLength then pcall(NavBar_CheckLength, nav) end
    end
    return nativeCrumb ~= nil
end

-- The buttons copy Blizzard's nav bar exactly (NavigationBar.xml/.lua): width = text + 30, text 20 from the left, each button starts where the
-- previous one ends (the home button overlaps by 15), later buttons sit above earlier ones, the last one (where you are) is red and disabled.
-- NavButtonTemplate sets up a dropdown menu from the button's listFunc whenever it is shown, so ours get an empty one.
local HOME_TEX = "Interface\\HelpFrame\\CS_HelpTextures"

local function crumbButton(i)
    local b = crumbs.buttons[i]
    if b then return b end
    local btn
    if i == 1 then
        -- the home button is not a template in Blizzard's XML either: a plain button with the home textures
        btn = CreateFrame("Button", nil, crumbs)
        btn:SetHeight(30)
        btn:SetNormalTexture(HOME_TEX)
        btn:SetPushedTexture(HOME_TEX)
        btn:SetHighlightTexture(HOME_TEX, "ADD")
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetJustifyH("LEFT")
        btn.text:SetPoint("LEFT", 10, 0)
        btn.text:SetPoint("RIGHT", -30, 0)
        btn.SetText = function(self, t) self.text:SetText(t) end
        local shade = btn:CreateTexture(nil, "OVERLAY")
        shade:SetTexture("Interface\\Common\\ShadowOverlay-Left")
        shade:SetSize(30, 30)
        shade:SetPoint("LEFT")
    else
        local ok, made = pcall(CreateFrame, "Button", nil, crumbs, "NavButtonTemplate")
        if ok and made then
            btn = made
            btn:Hide()
            btn.listFunc = function() return nil end
            if type(btn.MenuArrowButton) == "table" then btn.MenuArrowButton:Hide() end
        else
            btn = CreateFrame("Button", nil, crumbs)
            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.label:SetPoint("CENTER")
            btn.SetText = function(self, t) self.label:SetText(t) end
        end
    end
    btn.fit = function(self, text, home)
        self:SetText(text)
        local w = (self.GetTextWidth and self:GetTextWidth()) or (self.label and self.label:GetStringWidth()) or 80
        if type(self.text) == "table" and self.text.GetStringWidth then w = self.text:GetStringWidth() end
        if home then
            local width = math.min(128, w + 50)
            self:SetWidth(width)
            self.xoffset = -15
            local off = (width / 128) * 0.25
            local n, pu, h = self:GetNormalTexture(), self:GetPushedTexture(), self:GetHighlightTexture()
            if n then n:SetTexCoord(0.703125 - off, 0.703125, 0.0078125, 0.2421875) end
            if pu then pu:SetTexCoord(0.703125 - off, 0.703125, 0.2578125, 0.4921875) end
            if h then h:SetTexCoord(0.703125 - off, 0.713125, 0.5078125, 0.7421875) end
        else
            self:SetWidth(w + 30)
            self.xoffset = 0
        end
    end
    crumbs.buttons[i] = btn
    return btn
end

local function overlayBreadcrumb()
    local nav = WorldMapFrame and WorldMapFrame.NavBar
    if not nav then return end
    if not crumbs then
        crumbs = CreateFrame("Frame", nil, WorldMapFrame)
        crumbs:SetAllPoints(nav)
        crumbs:SetFrameLevel(nav:GetFrameLevel() + 20)
        crumbs.bg = crumbs:CreateTexture(nil, "BACKGROUND")
        crumbs.bg:SetAllPoints()
        crumbs.bg:SetColorTexture(0.03, 0.03, 0.03, 1)
        crumbs.buttons = {}
        crumbs:EnableMouse(true)
    end
    local chain, id, guard = {}, ns.EntranceZoneFor and ns.EntranceZoneFor(state.instanceID), 0
    while id and id ~= 0 and guard < 6 do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        table.insert(chain, 1, { name = info.name, mapID = id })
        id = info.parentMapID
        guard = guard + 1
    end
    local items = { { name = "World", mapID = 947 } }
    for _, c in ipairs(chain) do
        if c.mapID ~= 947 then items[#items + 1] = c end
    end
    items[#items + 1] = { name = ns.DungeonTitle(state.instanceID, state.wing), current = true }
    for i, it in ipairs(items) do
        local b = crumbButton(i)
        b:fit(it.name, i == 1)
        b:ClearAllPoints()
        -- like Blizzard's bar: each button starts where the previous one ends, and EARLIER buttons sit above later ones
        -- (the arrow at a button's right edge is drawn over the start of the next one)
        b:SetFrameLevel(crumbs:GetFrameLevel() + 1 + (#items - i))
        if i == 1 then
            b:SetPoint("LEFT", crumbs, "LEFT", 0, 0)
        else
            local prev = crumbs.buttons[i - 1]
            b:SetPoint("LEFT", prev, "RIGHT", prev.xoffset or 0, 0)
        end
        if type(b.selected) == "table" then b.selected:SetShown(it.current == true) end
        if it.current then
            if b.SetButtonState then b:SetButtonState("NORMAL") end
            if b.Disable then b:Disable() end
        elseif b.Enable then
            b:Enable()
        end
        b:SetScript("OnClick", function()
            if it.current then return end
            ns.HideView()
            if it.mapID then WorldMapFrame:SetMapID(it.mapID) end
        end)
        b:Show()
    end
    for i = #items + 1, #crumbs.buttons do crumbs.buttons[i]:Hide() end
    crumbs:Show()
end

-- Blizzard rebuilds its nav bar for the new zone a moment after SetMapID. Adding our button before that lands it
-- on the old chain (e.g. World > Eastern Kingdoms > Stratholme), so wait until the bar's last button is the zone.
local crumbToken = 0

local function barShowsZone(zone)
    local nav = WorldMapFrame and WorldMapFrame.NavBar
    local list = nav and nav.navList
    if not list then return true end
    local last = list[#list]
    if nativeCrumb and last == nativeCrumb then return true end
    if zone == 947 then return #list == 0 end
    local info = C_Map.GetMapInfo(zone)
    return last ~= nil and info ~= nil and last.GetText and last:GetText() == info.name
end

local function updateBreadcrumb()
    -- Our own bar over the world map's navigation bar. (Adding a button to Blizzard's bar with NavBar_AddButton made a click on the zone
    -- crumb do nothing and crashed the client once Blizzard rebuilt the bar's dropdowns, so Blizzard's bar is left alone.)
    crumbToken = crumbToken + 1
    if view and view:IsShown() then overlayBreadcrumb() end
end

-- Side panel (title, dungeon picker, floors, boss list) ---------------------------------------------

-- Boss cards (top) and the selected boss's loot (below); on a wide sidebar they sit side by side.
local CARD_H, ITEM_H, GAP = 40, 40, 3
local BRONZE = { 0.55, 0.41, 0.21 }
local S = 1 -- interface scale of the sidebar: 1.6 in wide mode (bigger rows, buttons and text)

local function styleCard(r)
    local big = S > 1
    r:SetHeight(CARD_H * S)
    r.rim:SetSize(34 * S, 34 * S)
    r.back:SetSize(30 * S, 30 * S)
    r.icon:SetSize(30 * S, 30 * S)
    r.check:SetSize(16 * S, 16 * S)
    r.bar:SetWidth(3 * S)
    r.text:SetFontObject(big and "GameFontHighlightLarge" or "GameFontHighlight")
end

local function styleItem(r)
    local big = S > 1
    r:SetHeight(ITEM_H * S)
    r.iconBack:SetSize(34 * S, 34 * S)
    r.icon:SetSize(30 * S, 30 * S)
    r.pct:SetFontObject(big and "GameFontNormalLarge" or "GameFontNormal")
    r.text:SetFontObject(big and "GameFontHighlightLarge" or "GameFontHighlight")
    r.sub:SetFontObject(big and "GameFontHighlight" or "GameFontHighlightSmall")
    r.sub:SetTextColor(0.7, 0.7, 0.7)
end

local function createRow(i)
    local r = CreateFrame("Button", nil, panel.bossContent)
    r:SetHeight(CARD_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1) -- selected card: warm tint and a bronze bar on the left edge
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.78, 0.3, 0.16)
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(3)
    r.bar:SetColorTexture(0.86, 0.68, 0.22, 1)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.rim = r:CreateTexture(nil, "BORDER")
    r.rim:SetSize(34, 34)
    r.rim:SetPoint("LEFT", 8, 0)
    r.rim:SetColorTexture(0.86, 0.68, 0.22, 1)
    addMask(r, r.rim)
    r.back = r:CreateTexture(nil, "BORDER", nil, 1)
    r.back:SetSize(30, 30)
    r.back:SetPoint("CENTER", r.rim)
    r.back:SetColorTexture(0.08, 0.07, 0.06, 1)
    addMask(r, r.back)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("CENTER", r.rim)
    addMask(r, r.icon)
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(16, 16)
    r.check:SetPoint("RIGHT", -8, 0)
    r.check:SetAtlas("common-icon-checkmark")
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("LEFT", r.rim, "RIGHT", 10, 0)
    r.text:SetPoint("RIGHT", r.check, "LEFT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    -- + / - for encounters that contain several opponents (Ring of Law): shows or hides the indented entries below
    r.expand = CreateFrame("Button", nil, r)
    r.expand:SetSize(18, 18)
    r.expand:SetPoint("RIGHT", -6, 0)
    r.expand:SetScript("OnClick", function(self)
        local b = self:GetParent().boss
        state.expandedGroups = state.expandedGroups or {}
        state.expandedGroups[b.id] = not state.expandedGroups[b.id]
        if not state.expandedGroups[b.id] and state.selectedParent == b.id then state.selected = b.id end -- a hidden entry cannot stay selected
        ns.RefreshMap()
    end)
    r.expand:Hide()
    r:SetScript("OnClick", function(self)
        -- clicking an encounter with several opponents (Ring of Law) selects it, jumps to its marker, and opens / closes its list
        if self.hasKids then
            state.expandedGroups = state.expandedGroups or {}
            state.expandedGroups[self.boss.id] = not state.expandedGroups[self.boss.id]
        end
        selectBoss(self.boss, true)
    end)
    r:SetScript("OnDoubleClick", function(self) -- double click: open this boss in the wide view
        selectBoss(self.boss, true)
        if sideMode() ~= "wide" and not ns.editing then ns.SetSideMode("wide", true) end
    end)
    return r
end

-- second line of a loot row: "Chest, Leather" / "One-Hand, Swords"
local function itemSubText(id)
    if not (C_Item and C_Item.GetItemInfo) then return "" end
    local ok, a, _, _, _, _, _, subType, _, equipLoc = pcall(C_Item.GetItemInfo, id)
    if not ok then return "" end
    if type(a) == "table" then subType, equipLoc = a.itemSubType or a.subType, a.itemEquipLoc or a.equipLoc end
    local slot = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc] or nil
    if slot and subType and subType ~= "" and subType ~= slot then return slot .. ", " .. subType end
    return slot or (type(subType) == "string" and subType) or ""
end

local function showItem(row, entry)
    local id = entry[1]
    row.itemID = id
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.iconBack:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
    row.text:SetText("Item " .. id)
    row.text:SetTextColor(0.6, 0.6, 0.6)
    row.sub:SetText("")
    row.pct:SetText((entry[3] and DungeonMapDB.showDropRates ~= false) and format("%g%%", entry[3]) or "")
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(id)
        item:ContinueOnItemLoad(function()
            if row.itemID ~= id then return end -- the row was reused for another item meanwhile
            row.icon:SetTexture(item:GetItemIcon())
            row.text:SetText(item:GetItemName())
            -- Forever returns a colour table here (r, g, b, hex, color); older clients return r, g, b
            local c1, c2, c3 = item:GetItemQualityColor()
            local r, g, b
            if type(c1) == "table" then
                r, g, b = c1.r, c1.g, c1.b
                if not r and c1.color and c1.color.GetRGB then r, g, b = c1.color:GetRGB() end
            else
                r, g, b = c1, c2, c3
            end
            if type(r) == "number" then
                row.text:SetTextColor(r, g, b)
                row.iconBack:SetColorTexture(r, g, b, 1)
            end
            row.sub:SetText(itemSubText(id))
            row.link = item:GetItemLink()
        end)
    end
end

local function createItemRow()
    local r = CreateFrame("Button", nil, panel.lootContent)
    r:SetHeight(ITEM_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.045)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.iconBack = r:CreateTexture(nil, "BORDER") -- thin frame in the item's quality colour
    r.iconBack:SetSize(34, 34)
    r.iconBack:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("CENTER", r.iconBack)
    r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.pct:SetPoint("RIGHT", -8, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetPoint("TOPLEFT", r.iconBack, "TOPRIGHT", 8, -1)
    r.text:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("BOTTOMLEFT", r.iconBack, "BOTTOMRIGHT", 8, 1)
    r.sub:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.sub:SetTextColor(0.7, 0.7, 0.7)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.itemID then GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            HandleModifiedItemClick(self.link) -- shift: link in chat, ctrl: dressing room
        end
    end)
    return r
end

-- Abilities (wide mode, middle panel): one block per spell: icon, name, cast time, description. Everything is read from the client.
local ABIL_ICON = 40
local ABIL_COMPACT_H = 34 -- narrow sidebar: one line per ability, the description is in the tooltip
local abilRows = {}

local function layoutAbilities()
    local y, w = 0, panel.abilContent:GetWidth()
    for _, r in ipairs(abilRows) do
        if r:IsShown() then
            if r.compact then
                r:SetHeight(ABIL_COMPACT_H)
            else
                r.desc:SetWidth(math.max(60, w - ABIL_ICON * S - 22))
                local textH = r.name:GetStringHeight() + 4 + r.desc:GetStringHeight()
                r:SetHeight(math.max(ABIL_ICON * S + 8, textH + 12))
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel.abilContent, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", panel.abilContent, "TOPRIGHT", 0, -y)
            y = y + r:GetHeight() + GAP
        end
    end
    panel.abilContent:SetHeight(math.max(y, 10))
end

local function createAbilityRow()
    local r = CreateFrame("Button", nil, panel.abilContent)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.045)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.iconBack = r:CreateTexture(nil, "BORDER")
    r.iconBack:SetPoint("TOPLEFT", 6, -6)
    r.iconBack:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("CENTER", r.iconBack)
    r.meta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.meta:SetPoint("TOPRIGHT", -8, -8)
    r.meta:SetTextColor(0.7, 0.7, 0.7)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.iconBack, "TOPRIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.meta, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetJustifyV("TOP")
    r.desc:SetWordWrap(true)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.spellID then pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    return r
end

local function showAbility(row, id, compact)
    local big = S > 1
    row.spellID = id
    row.compact = compact
    local isz = compact and 26 or ABIL_ICON * S
    row.iconBack:SetSize(isz + 4, isz + 4)
    row.icon:SetSize(isz, isz)
    row.desc:SetShown(not compact)
    row.iconBack:ClearAllPoints()
    row.iconBack:SetPoint(compact and "LEFT" or "TOPLEFT", 6, compact and 0 or -6)
    row.name:ClearAllPoints()
    row.name:SetPoint(compact and "LEFT" or "TOPLEFT", row.iconBack, compact and "RIGHT" or "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.meta, "LEFT", -6, 0)
    row.meta:ClearAllPoints()
    row.meta:SetPoint(compact and "RIGHT" or "TOPRIGHT", -8, compact and 0 or -8)
    row.name:SetFontObject(big and "GameFontNormalLarge" or "GameFontNormal")
    row.desc:SetFontObject(big and "GameFontHighlight" or "GameFontHighlightSmall")
    row.meta:SetFontObject(big and "GameFontHighlight" or "GameFontHighlightSmall")
    row.meta:SetTextColor(0.7, 0.7, 0.7)
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText("Spell " .. id)
    row.desc:SetText("")
    row.meta:SetText("")
    if not (Spell and Spell.CreateFromSpellID) then return end
    local ok, spell = pcall(Spell.CreateFromSpellID, Spell, id)
    if not (ok and spell) then return end
    spell:ContinueOnSpellLoad(function() -- spell data loads asynchronously, like items
        if row.spellID ~= id then return end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        local name = (type(info) == "table" and info.name) or spell:GetSpellName()
        if type(name) == "string" then row.name:SetText(name) end
        local icon = (type(info) == "table" and info.iconID) or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
        if icon then row.icon:SetTexture(icon) end
        local desc = spell:GetSpellDescription()
        row.desc:SetText(type(desc) == "string" and desc or "")
        local ct = type(info) == "table" and info.castTime
        row.meta:SetText(type(ct) == "number" and (ct > 0 and format("%.1f sec cast", ct / 1000) or "Instant") or "")
        layoutAbilities()
        if ns.UpdateScrollbars then ns.UpdateScrollbars() end
    end)
end

local function createFloorButton(i)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(28, 22)
    b:SetText(i)
    b:SetScript("OnClick", function() state.floorIndex = i; ns.RefreshMap() end)
    return b
end

local levelLabel = function(d) return ns.LevelLabel(d) end

local function buildDungeonList()
    local p = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    p:SetSize(PANEL_W + 20, 430)
    p:SetFrameStrata("DIALOG")
    p:SetPoint("TOPRIGHT", panel.dungeonButton, "BOTTOMRIGHT", 0, -2)
    p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0, 0, 0, 0.94)
    p:EnableMouse(true)
    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_W - 14, 10)
    scroll:SetScrollChild(content)
    local list = ns.GetDungeonList()
    local y, group = 0, nil
    for _, d in ipairs(list) do
        if d.raid ~= group then -- section header: Dungeons / Raids
            group = d.raid
            local h = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            h:SetPoint("TOPLEFT", 4, -(y + 4))
            h:SetText(group and "Raids" or "Dungeons")
            h:SetTextColor(1, 0.82, 0)
            y = y + 24
        end
        local b = CreateFrame("Button", nil, content)
        b:SetSize(PANEL_W - 14, 22)
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local lv = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lv:SetPoint("LEFT", 6, 0)
        lv:SetWidth(46)
        lv:SetJustifyH("LEFT")
        lv:SetText(d.raid and "Raid" or (d.level or ""))
        if d.raid then lv:SetTextColor(0.9, 0.55, 0.2) else lv:SetTextColor(ns.LevelColor(d.data)) end
        local fs = b:CreateFontString(nil, "OVERLAY", d.hasArt and "GameFontHighlight" or "GameFontDisable")
        fs:SetPoint("LEFT", lv, "RIGHT", 2, 0)
        fs:SetText(d.name)
        if d.status == "classic" then -- classic data, not confirmed for Forever
            local tag = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tag:SetPoint("RIGHT", -6, 0)
            tag:SetText("classic data")
            tag:SetTextColor(0.8, 0.5, 0.2)
        end
        b:SetScript("OnClick", function()
            p:Hide()
            ns.ShowInstance(d.id, nil, true, d.wing)
        end)
        y = y + 22
    end
    content:SetHeight(y + 4)
    p:Hide()
    return p
end

-- A framed, inset section of the sidebar: thin bronze outline with tapered (45 degree cut) corners on a dark fill, gold title
-- (like Blizzard's own frames). b:SetCut(size) sets how deep the corners are cut.
local function createBox(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetFrameLevel(parent:GetFrameLevel() + 5)
    b.fill, b.edges, b.cuts = {}, {}, {}
    for i = 1, 3 do -- the fill is a cross of three bands, so the cut corners stay empty
        b.fill[i] = b:CreateTexture(nil, "BACKGROUND")
        b.fill[i]:SetColorTexture(0, 0, 0, 0.35)
    end
    for i = 1, 4 do
        b.edges[i] = b:CreateTexture(nil, "BORDER")
        b.edges[i]:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
        b.cuts[i] = b:CreateLine(nil, "BORDER")
        b.cuts[i]:SetThickness(1.2)
        b.cuts[i]:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
    end
    function b:SetCut(c)
        local f, e, l = self.fill, self.edges, self.cuts
        f[1]:ClearAllPoints(); f[1]:SetPoint("TOPLEFT", 0, -c); f[1]:SetPoint("BOTTOMRIGHT", 0, c)
        f[2]:ClearAllPoints(); f[2]:SetPoint("TOPLEFT", c, 0); f[2]:SetPoint("TOPRIGHT", -c, 0); f[2]:SetHeight(c)
        f[3]:ClearAllPoints(); f[3]:SetPoint("BOTTOMLEFT", c, 0); f[3]:SetPoint("BOTTOMRIGHT", -c, 0); f[3]:SetHeight(c)
        e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", c, 0); e[1]:SetPoint("TOPRIGHT", -c, 0); e[1]:SetHeight(1)
        e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", c, 0); e[2]:SetPoint("BOTTOMRIGHT", -c, 0); e[2]:SetHeight(1)
        e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", 0, -c); e[3]:SetPoint("BOTTOMLEFT", 0, c); e[3]:SetWidth(1)
        e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", 0, -c); e[4]:SetPoint("BOTTOMRIGHT", 0, c); e[4]:SetWidth(1)
        l[1]:SetStartPoint("TOPLEFT", self, 0, -c); l[1]:SetEndPoint("TOPLEFT", self, c, 0)
        l[2]:SetStartPoint("TOPRIGHT", self, -c, 0); l[2]:SetEndPoint("TOPRIGHT", self, 0, -c)
        l[3]:SetStartPoint("BOTTOMLEFT", self, 0, c); l[3]:SetEndPoint("BOTTOMLEFT", self, c, 0)
        l[4]:SetStartPoint("BOTTOMRIGHT", self, -c, 0); l[4]:SetEndPoint("BOTTOMRIGHT", self, 0, c)
    end
    b:SetCut(7)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", 12, -8)
    return b
end
ns.CreateBox = createBox

local ARROW = "Interface\\Buttons\\UI-SpellbookIcon-"

local function buildPanel()
    local base = view:GetFrameLevel() + 100 -- above the art and its pins
    panel = CreateFrame("Frame", nil, view)
    panel:SetFrameLevel(base)
    panel:SetWidth(SIDE_W)
    panel:SetPoint("TOPRIGHT", view, "TOPRIGHT", -6, -6)
    panel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -6, 6)
    panel:EnableMouse(true)
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAtlas("heavybronze-frame-background") -- Forever's brown grainy panel texture
    panel.bg:SetPoint("TOPLEFT", 3, -3)
    panel.bg:SetPoint("BOTTOMRIGHT", -3, 3)
    -- thin golden-bronze outer border around the whole sidebar (the game's tooltip border; plain backdrop as fallback)
    local ok, ob = pcall(CreateFrame, "Frame", nil, panel, "TooltipBorderBackdropTemplate")
    if not (ok and ob) then
        ob = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        pcall(ob.SetBackdrop, ob, { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    end
    ob:SetAllPoints(panel)
    ob:SetFrameLevel(base + 1)
    pcall(ob.SetBackdropColor, ob, 0, 0, 0, 0)
    pcall(ob.SetBackdropBorderColor, ob, 0.78, 0.6, 0.32, 1)
    panel.border = ob

    -- expand / shrink arrow (top left) and the dungeon title, which also opens the dungeon list
    panel.wideButton = CreateFrame("Button", nil, panel)
    panel.wideButton:SetFrameLevel(base + 5)
    panel.wideButton:SetSize(26, 26)
    panel.wideButton:SetPoint("TOPLEFT", 14, -12)
    panel.wideButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    panel.wideButton:SetScript("OnClick", function()
        if sideMode() == "wide" then ns.LeaveWide() else ns.SetSideMode("wide", true) end
    end)
    panel.wideButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(sideMode() == "wide" and "Show the map" or "Wide view: hide the map")
        GameTooltip:Show()
    end)
    panel.wideButton:SetScript("OnLeave", GameTooltip_Hide)

    -- close (X) inside the sidebar, wide mode only: goes back to the map view, it does not close the world map
    local okc, close = pcall(CreateFrame, "Button", nil, panel, "UIPanelCloseButton")
    if not (okc and close) then
        close = CreateFrame("Button", nil, panel)
        close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    end
    close:SetFrameLevel(base + 6)
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() ns.LeaveWide() end)
    close:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Back to the map")
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", GameTooltip_Hide)
    close:Hide()
    panel.close = close

    panel.dungeonButton = CreateFrame("Button", nil, panel)
    panel.dungeonButton:SetFrameLevel(base + 5)
    panel.dungeonButton:SetHeight(26)
    panel.dungeonButton:SetPoint("TOPLEFT", panel.wideButton, "TOPRIGHT", 6, 0)
    panel.dungeonButton:SetPoint("TOPRIGHT", -54, -12) -- leaves room for the gear button
    panel.dungeonButton.label = panel.dungeonButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.dungeonButton.label:SetPoint("LEFT")
    panel.dungeonButton.label:SetJustifyH("LEFT")
    panel.dungeonButton.arrow = panel.dungeonButton:CreateTexture(nil, "OVERLAY")
    panel.dungeonButton.arrow:SetSize(16, 16)
    panel.dungeonButton.arrow:SetPoint("LEFT", panel.dungeonButton.label, "RIGHT", 4, -1)
    panel.dungeonButton.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    panel.dungeonButton:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
    panel.dungeonButton:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 0.82, 0) end)
    panel.dungeonButton:SetScript("OnClick", function()
        dungeonList = dungeonList or buildDungeonList()
        dungeonList:SetShown(not dungeonList:IsShown())
    end)

    -- Options: opens this addon's page in the game's settings without leaving the dungeon map first (gear button, right end of the title row)
    panel.optionsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.optionsButton:SetFrameLevel(base + 6)
    panel.optionsButton:SetSize(34, 26) -- a red button with a gear, on the title row at the right
    panel.optionsButton:SetPoint("TOPRIGHT", -14, -12)
    panel.optionsButton.icon = panel.optionsButton:CreateTexture(nil, "OVERLAY")
    panel.optionsButton.icon:SetSize(18, 18)
    panel.optionsButton.icon:SetPoint("CENTER", 0, 0)
    panel.optionsButton.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    panel.optionsButton:SetScript("OnClick", function() ns.OpenOptions() end)
    panel.optionsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Dungeon Crawler Forever options")
        GameTooltip:AddLine("Opens the options page in the game's settings.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.optionsButton:SetScript("OnLeave", GameTooltip_Hide)

    panel.level = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.level:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -44)
    panel.wingButtons = {}
    panel.lock = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.lock:SetPoint("TOPLEFT", panel.level, "BOTTOMLEFT", 0, -4)
    panel.lock:SetTextColor(0.55, 0.8, 1)
    panel.floorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.floorLabel:SetPoint("TOPLEFT", panel.lock, "BOTTOMLEFT", 0, -8)
    panel.listTop = 100

    -- boss cards
    panel.bossBox = createBox(panel)
    panel.bossScroll = CreateFrame("ScrollFrame", nil, panel.bossBox, "UIPanelScrollFrameTemplate")
    panel.bossScroll:SetPoint("TOPLEFT", 6, -26)
    panel.bossScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    panel.bossContent = CreateFrame("Frame", nil, panel.bossScroll)
    panel.bossContent:SetSize(10, 10)
    panel.bossScroll:SetScrollChild(panel.bossContent)

    -- loot of the selected boss: header (portrait, name, status) and a scrolling list
    panel.lootBox = createBox(panel)
    local lb = panel.lootBox
    local hf = CreateFrame("Frame", nil, lb) -- boss header (portrait, name, status): in the loot box, or the abilities box in wide mode
    hf:SetHeight(72)
    panel.hf = hf
    lb.rim = hf:CreateTexture(nil, "BORDER")
    lb.rim:SetSize(52, 52)
    lb.rim:SetPoint("TOPLEFT", 10, -10)
    lb.rim:SetColorTexture(0.86, 0.68, 0.22, 1)
    addMask(hf, lb.rim)
    lb.back = hf:CreateTexture(nil, "BORDER", nil, 1)
    lb.back:SetSize(46, 46)
    lb.back:SetPoint("CENTER", lb.rim)
    lb.back:SetColorTexture(0.08, 0.07, 0.06, 1)
    addMask(hf, lb.back)
    lb.portrait = hf:CreateTexture(nil, "ARTWORK")
    lb.portrait:SetSize(46, 46)
    lb.portrait:SetPoint("CENTER", lb.rim)
    addMask(hf, lb.portrait)
    lb.name = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lb.name:SetPoint("TOPLEFT", lb.rim, "TOPRIGHT", 12, -4)
    lb.name:SetPoint("RIGHT", hf, "RIGHT", -10, 0)
    lb.name:SetJustifyH("LEFT")
    lb.name:SetWordWrap(false)
    lb.status = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lb.status:SetPoint("TOPLEFT", lb.name, "BOTTOMLEFT", 0, -4)
    lb.status:SetPoint("RIGHT", hf, "RIGHT", -10, 0)
    lb.status:SetJustifyH("LEFT")
    panel.lootScroll = CreateFrame("ScrollFrame", nil, lb, "UIPanelScrollFrameTemplate")
    panel.lootScroll:SetPoint("TOPLEFT", 6, -76)
    panel.lootScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    panel.lootContent = CreateFrame("Frame", nil, panel.lootScroll)
    panel.lootContent:SetSize(10, 10)
    panel.lootScroll:SetScrollChild(panel.lootContent)

    -- abilities (wide mode only): the data comes in a later update (D-032), the panel and its title are ready
    panel.abilBox = createBox(panel)
    panel.abilBox.title:SetText("Abilities")
    panel.abilBox.note = panel.abilBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.abilBox.note:SetText("Boss abilities will be added in a later update.")
    panel.abilBox.note:SetJustifyH("LEFT")
    panel.abilBox.note:SetWordWrap(true)
    panel.abilScroll = CreateFrame("ScrollFrame", nil, panel.abilBox, "UIPanelScrollFrameTemplate")
    panel.abilScroll:SetPoint("TOPLEFT", 6, -100)
    panel.abilScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    panel.abilContent = CreateFrame("Frame", nil, panel.abilScroll)
    panel.abilContent:SetSize(10, 10)
    panel.abilScroll:SetScrollChild(panel.abilContent)
    panel.abilBox:Hide()

    -- "Find" button: a secure macro button (/target <name>), the same thing you would type, and a result message afterwards
    panel.find = CreateFrame("Button", nil, panel.lootContent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    panel.find:SetHeight(22)
    panel.find:SetText("Find this rare (target it)")
    panel.find:RegisterForClicks("AnyUp", "AnyDown")
    panel.find:SetScript("PostClick", function(self)
        local name = self.bossName
        C_Timer.After(0.3, function()
            if not UnitExists("target") then
                ns.Print(name .. ": not found nearby (not spawned, or out of range).")
                return
            end
            local tn = UnitName("target")
            if issecretvalue and issecretvalue(tn) then
                ns.Print("Target acquired.")
            elseif tn == name then
                ns.Print("|cff66ff66" .. name .. " is up!|r")
            else
                ns.Print(name .. ": not found nearby (target is " .. tostring(tn) .. ").")
            end
        end)
    end)
    panel.find:Hide()
    panel.noLoot = panel.lootContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.noLoot:SetText("No loot data for this boss yet.")
    panel.noLoot:Hide()

    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.footer:SetPoint("BOTTOMLEFT", 16, 14)
    panel.footer:SetPoint("BOTTOMRIGHT", -16, 14)
    panel.footer:SetJustifyH("LEFT")
    panel.footer:SetTextColor(0.75, 0.75, 0.75)
    panel.footer:SetWordWrap(true)
end

-- Sidebar geometry for the current mode; returns the widths available for boss cards and for loot rows.
-- Scrollbars only where the list is longer than its box; without a bar the rows use the freed gutter.
local scrollPending
local function updateScrollbars()
    if scrollPending then return end
    scrollPending = true
    C_Timer.After(0.03, function()
        scrollPending = false
        if not (panel and panel:IsShown()) then return end
        for _, e in ipairs({ { panel.bossScroll, panel.bossContent, panel.bossBox }, { panel.abilScroll, panel.abilContent, panel.abilBox },
                             { panel.lootScroll, panel.lootContent, panel.lootBox }, { panel.questScroll, panel.questContent, panel.questBox } }) do
            local sc, content, box = e[1], e[2], e[3]
            if sc and box:IsShown() then
                local need = (sc:GetVerticalScrollRange() or 0) > 1
                local bar = sc.ScrollBar
                if type(bar) == "table" and bar.SetShown then bar:SetShown(need) end
                local right = need and -26 or -8
                sc:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", right, 6)
                content:SetWidth(math.max(40, box:GetWidth() - 6 + right))
            end
        end
        layoutAbilities()
    end)
end

ns.UpdateScrollbars = updateScrollbars

local function layoutPanel(nBosses, nAbil)
    local mode = sideMode()
    local wide = mode == "wide"
    local pw = wide and (view:GetWidth() - 12) or SIDE_W
    local ph = view:GetHeight() - 12
    panel:SetWidth(pw)
    panel:SetShown(mode ~= "hidden")
    local dir = wide and "NextPage" or "PrevPage" -- "<" widens the sidebar over the map, ">" gives the map back
    panel.wideButton:SetNormalTexture(ARROW .. dir .. "-Up")
    panel.wideButton:SetPushedTexture(ARROW .. dir .. "-Down")
    view.collapse:SetShown(mode == "side")
    view.sideTab:SetShown(mode == "hidden")
    local top = panel.listTop
    local bodyH = ph - top - 42
    local titleH = wide and 38 or 26
    local hfH = 72 * S
    local bossBox, abilBox, lootBox, hf = panel.bossBox, panel.abilBox, panel.lootBox, panel.hf
    for _, b in ipairs({ bossBox, abilBox, lootBox }) do
        b:ClearAllPoints()
        b:SetCut(wide and 11 or 7)
        b.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")
    end
    panel.bossScroll:ClearAllPoints()
    panel.bossScroll:SetPoint("TOPLEFT", 6, -titleH)
    panel.bossScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    abilBox:Show()
    hf:ClearAllPoints()
    -- boss header sizes
    lootBox.rim:SetSize(52 * S, 52 * S)
    lootBox.back:SetSize(46 * S, 46 * S)
    lootBox.portrait:SetSize(46 * S, 46 * S)
    lootBox.name:SetFontObject(wide and "GameFontNormalHuge" or "GameFontNormalLarge")
    lootBox.status:SetFontObject(wide and "GameFontHighlight" or "GameFontHighlightSmall")
    hf:SetHeight(hfH)
    panel.lootScroll:ClearAllPoints()
    local bossW, lootW
    if wide then
        -- three columns: bosses | abilities | loot
        local avail = pw - 28 - 16
        local bw = math.floor(avail * 0.27)
        local aw = math.floor(avail * 0.31)
        local lw = avail - bw - aw
        bossBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        bossBox:SetSize(bw, bodyH)
        abilBox:SetPoint("TOPLEFT", bossBox, "TOPRIGHT", 8, 0)
        abilBox:SetSize(aw, bodyH)
        lootBox:SetPoint("TOPLEFT", abilBox, "TOPRIGHT", 8, 0)
        lootBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
        hf:SetParent(abilBox)
        hf:SetPoint("TOPLEFT", abilBox, "TOPLEFT", 0, -titleH)
        hf:SetPoint("TOPRIGHT", abilBox, "TOPRIGHT", 0, -titleH)
        abilBox.note:ClearAllPoints()
        abilBox.note:SetPoint("TOPLEFT", abilBox, "TOPLEFT", 14, -(titleH + hfH + 12))
        abilBox.note:SetWidth(aw - 28)
        panel.abilScroll:ClearAllPoints()
        panel.abilScroll:SetPoint("TOPLEFT", 6, -(titleH + hfH + 4))
        panel.abilScroll:SetPoint("BOTTOMRIGHT", -26, 6)
        panel.abilContent:SetWidth(aw - 34)
        lootBox.title:SetText("Loot")
        panel.lootScroll:SetPoint("TOPLEFT", 6, -titleH)
        bossW, lootW = bw - 34, lw - 34
    else
        -- narrow sidebar, stacked: bosses, then abilities (boss header + compact list), then loot
        local bh = math.max(96, math.min(nBosses * (CARD_H + GAP) + 36, math.floor(bodyH * 0.34)))
        local rest = bodyH - bh - 16
        local want = titleH + hfH + (nAbil > 0 and (nAbil * (ABIL_COMPACT_H + GAP)) or 34) + 12
        local ah = math.max(titleH + hfH + 40, math.min(want, math.floor(rest * 0.5)))
        bossBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        bossBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -top)
        bossBox:SetHeight(bh)
        abilBox:SetPoint("TOPLEFT", bossBox, "BOTTOMLEFT", 0, -8)
        abilBox:SetPoint("TOPRIGHT", bossBox, "BOTTOMRIGHT", 0, -8)
        abilBox:SetHeight(ah)
        lootBox:SetPoint("TOPLEFT", abilBox, "BOTTOMLEFT", 0, -8)
        lootBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
        hf:SetParent(abilBox)
        hf:SetPoint("TOPLEFT", abilBox, "TOPLEFT", 0, -titleH)
        hf:SetPoint("TOPRIGHT", abilBox, "TOPRIGHT", 0, -titleH)
        abilBox.note:ClearAllPoints()
        abilBox.note:SetPoint("TOPLEFT", abilBox, "TOPLEFT", 14, -(titleH + hfH + 8))
        abilBox.note:SetWidth(pw - 28 - 28)
        panel.abilScroll:ClearAllPoints()
        panel.abilScroll:SetPoint("TOPLEFT", 6, -(titleH + hfH + 4))
        panel.abilScroll:SetPoint("BOTTOMRIGHT", -26, 6)
        panel.abilContent:SetWidth(pw - 28 - 34)
        lootBox.title:SetText("Loot")
        panel.lootScroll:SetPoint("TOPLEFT", 6, -titleH)
        bossW, lootW = pw - 28 - 34, pw - 28 - 34
    end
    panel.lootScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    hf:SetFrameLevel(hf:GetParent():GetFrameLevel() + 3)
    panel.bossContent:SetWidth(bossW)
    panel.lootContent:SetWidth(lootW)
    return bossW, lootW
end

-- mode: "side" | "hidden" | "wide". temporary = only for this opening of the map (boss click, wide view); otherwise the choice is
-- remembered for the current window size.
function ns.SetSideMode(mode, temporary)
    if temporary then
        state.tempMode = mode
    else
        state.tempMode = nil
        DungeonMapDB.sideChoice = DungeonMapDB.sideChoice or {}
        DungeonMapDB.sideChoice[windowMode()] = mode
    end
    resetZoom()
    ns.RefreshMap()
end

-- back from the wide view to whatever the sidebar was before (the remembered choice or the default)
function ns.LeaveWide()
    state.tempMode = nil
    resetZoom()
    ns.RefreshMap()
end

-- View ------------------------------------------------------------------------------------------

local function buildView()
    local c = container()
    view = CreateFrame("Frame", "DungeonMapView", WorldMapFrame)
    view:SetPoint("TOPLEFT", c, "TOPLEFT")
    view:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT")
    view:SetFrameStrata(WorldMapFrame:GetFrameStrata())
    view:SetFrameLevel(_G.OpenMapAPI and ns.OPENMAP_LEVEL or (WorldMapFrame:GetFrameLevel() + 3000)) -- (over OpenMap's frames when it is loaded)
    view:SetClipsChildren(true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta > 0 and 1.25 or 0.8) end)
    view.bg = view:CreateTexture(nil, "BACKGROUND")
    view.bg:SetAllPoints()
    view.bg:SetColorTexture(0.06, 0.05, 0.03, 1)

    art = CreateFrame("Frame", nil, view)
    art:SetFrameLevel(view:GetFrameLevel() + 1)
    tileHost = CreateFrame("Frame", nil, art) -- map tiles live here so the art is cropped to its own edges, pins stay unclipped
    tileHost:SetAllPoints(art)
    tileHost:SetFrameLevel(art:GetFrameLevel())
    tileHost:SetClipsChildren(true)
    art:EnableMouse(true)
    art:EnableMouseWheel(true)
    art:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta > 0 and 1.25 or 0.8) end)
    local drag
    art:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and ns.RouteTool() and not IsShiftKeyDown() and not IsControlKeyDown() then
            -- a point of the route under the mouse: click selects it, dragging moves it
            local idx = ns.RouteHitPoint(self, state)
            if idx then
                local cx, cy = GetCursorPosition()
                drag = { point = idx, cx = cx, cy = cy, moved = false, snap = ns.RouteSnapshot(state.instanceID, state.wing), last = 0 }
                return
            end
        end
        if button == "LeftButton" and canPan() then
            local cx, cy = GetCursorPosition()
            drag = { cx = cx, cy = cy, x = zoom.x, y = zoom.y, moved = false }
        end
    end)
    art:SetScript("OnUpdate", function(self)
        if not drag then return end
        if not IsMouseButtonDown("LeftButton") then drag = nil return end
        if drag.point then
            local cx, cy = GetCursorPosition()
            local scale = view:GetEffectiveScale()
            if not drag.moved and math.abs(cx - drag.cx) / scale + math.abs(cy - drag.cy) / scale < 4 then return end
            local route = ns.GetRoute(state.instanceID, state.wing)
            local p = route and route[drag.point]
            if not p or p.boss or p.kind then return end -- stops and steps sit on their boss / marker: they are not moved
            drag.moved = true
            local now = GetTime()
            if now - drag.last >= 0.03 and ns.RouteMoveTo(self, state, drag.point) then
                drag.last = now
                ns.RefreshMap()
            end
            return
        end
        local scale = view:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local dx, dy = (cx - drag.cx) / scale, (cy - drag.cy) / scale
        if not drag.moved and math.abs(dx) + math.abs(dy) < 4 then return end
        drag.moved = true
        zoom.x, zoom.y = drag.x + dx, drag.y + dy
        relayout()
    end)
    art:SetScript("OnMouseUp", function(self, button)
        local d = drag
        if d and d.point then
            drag = nil
            if button ~= "LeftButton" then return end
            if d.moved then
                ns.RouteMoveTo(self, state, d.point)
                ns.RouteCommit(state.instanceID, state.wing, d.snap)
                ns.routeAt = d.point
            else
                local g = ns.RouteGap(state.instanceID, state.wing)
                if g and d.point >= g then
                    local dropped = ns.RouteConnect(state.instanceID, state.wing, d.point)
                    if dropped and #dropped > 0 then ns.Print("Joined up. Removed the stops: " .. table.concat(dropped, ", ") .. " (Undo brings them back).") end
                else
                    ns.routeAt = (ns.routeAt == d.point) and nil or d.point
                end
            end
            ns.RefreshMap()
            return
        end
        local moved = d and d.moved
        drag = nil
        if button == "RightButton" then
            ns.GoUp()
        elseif (ns.editing or ns.routeDraw) and button == "LeftButton" and not moved then
            if ns.RouteTool() then
                ns.EditRouteClick(self, state, IsShiftKeyDown())
            elseif ns.editKind == "__link" then
                return -- the link tool works on markers, a click on empty map does nothing
            elseif ns.editKind ~= "boss" then
                ns.EditPlaceMarker(self, state)
            else
                ns.EditPlaceAtCursor(self, state)
            end
        end
    end)
    tiles, pins, rows, floorButtons, itemRows = {}, {}, {}, {}, {}

    view.credit = CreateFrame("Button", nil, view)
    view.credit:SetFrameLevel(view:GetFrameLevel() + 100)
    view.credit:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 184, 8)
    view.credit.text = view.credit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.credit.text:SetPoint("LEFT")
    view.credit.text:SetTextColor(0.95, 0.85, 0.55)
    view.credit:SetScript("OnClick", function(self) if self.url and self.url ~= "" then ns.ShowLink(self.url) end end)
    view.credit:SetScript("OnEnter", function(self)
        if self.url and self.url ~= "" then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.url)
            GameTooltip:AddLine("Click to copy the link", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    view.credit:SetScript("OnLeave", GameTooltip_Hide)
    view.credit:Hide()

    view.editBanner = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.editBanner:SetPoint("TOP", view, "TOP", -(PANEL_W + 24) / 2, -12)
    view.editBanner:SetText("EDIT MODE: pick what to place (button below), then click the map")
    view.editBanner:SetTextColor(1, 0.82, 0)
    view.editBanner:Hide()
    view.routeInfo = CreateFrame("Button", nil, view) -- one line at the top of the map while a route is shown: the next boss; click to go there
    view.routeInfo:SetFrameLevel(view:GetFrameLevel() + 250)
    view.routeInfo:SetHeight(26)
    view.routeInfo.bg = view.routeInfo:CreateTexture(nil, "BACKGROUND")
    view.routeInfo.bg:SetAllPoints()
    view.routeInfo.bg:SetColorTexture(0, 0, 0, 0.7)
    view.routeInfo.text = view.routeInfo:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.routeInfo.text:SetPoint("CENTER")
    view.routeInfo:SetScript("OnClick", function(self)
        local p = self.target
        if p then ns.TravelToFloor(p.f, p.x, p.y) end
    end)
    view.routeInfo:Hide()
    view.toast = CreateFrame("Frame", nil, view) -- the link tool's prompt and confirmation: big, on a dark strip, above everything on the map
    view.toast:SetFrameLevel(view:GetFrameLevel() + 300)
    view.toast:SetHeight(36)
    view.toast.bg = view.toast:CreateTexture(nil, "BACKGROUND")
    view.toast.bg:SetAllPoints()
    view.toast.bg:SetColorTexture(0, 0, 0, 0.78)
    view.toast.text = view.toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.toast.text:SetPoint("CENTER")
    view.toast:Hide()

    view.empty = view:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    view.empty:SetPoint("CENTER", -PANEL_W / 2, 0)
    view.empty:SetText("No map art for this dungeon yet")
    view.empty:SetTextColor(0.8, 0.7, 0.5)

    local function zoomButton(label, x, onClick)
        local b = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        b:SetFrameLevel(view:GetFrameLevel() + 100)
        b:SetSize(26, 22)
        b:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", x, 10)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    view.zoomButtons = {
        zoomButton("+", 10, function() zoomAt(1.5) end),
        zoomButton("-", 38, function() zoomAt(1 / 1.5) end),
        zoomButton("0", 66, function() resetZoom(); relayout() end),
    }
    view.allButton = zoomButton("All floors", 94, function() ns.SetOverview(not state.overview) end)
    view.allButton:SetSize(80, 22)
    view.allButton:Hide()
    -- edit mode: what a click on the map places (boss / entrance / exit / stairs / portal)
    view.modeButton = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.modeButton:SetFrameLevel(view:GetFrameLevel() + 100)
    view.modeButton:SetSize(150, 22)
    view.modeButton:SetPoint("TOP", view, "TOP", -(PANEL_W + 24) / 2, -40)
    view.modeButton:SetScript("OnClick", function()
        local order = { "boss", unpack(ns.MARKER_ORDER) }
        for i, k in ipairs(order) do
            if k == ns.editKind then ns.editKind = order[i % #order + 1] break end
        end
        ns.RefreshMap()
    end)
    view.modeButton:Hide()
    -- edit mode: one button per thing a click on the map places (replaces cycling through "Placing: ...")
    view.kindButtons = {}
    local order = { "boss", unpack(ns.MARKER_ORDER) }
    order[#order + 1] = "__ref" -- toggles the developer reference layer (landmarks from the game data)
    order[#order + 1] = "__route" -- draw the route (developer tool)
    order[#order + 1] = "__link" -- link two markers on different floors (any icon)
    order[#order + 1] = "__ghost" -- cycles the floor overlay
    for i, kind in ipairs(order) do
        local b = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        b:SetFrameLevel(view:GetFrameLevel() + 100)
        b:SetSize(96, 22)
        b:SetText(kind == "boss" and "Boss" or kind == "__ref" and "Landmarks" or kind == "__route" and "Route" or kind == "__link" and "Link markers" or kind == "__ghost" and "Overlay: off" or ns.MARKER_KINDS[kind].label)
        b.kind = kind
        b:SetScript("OnClick", function(self)
            if self.kind == "__ref" then
                ns.showReference = not ns.showReference
            elseif self.kind == "__route" then
                ns.routeAt = nil
                ns.editKind = "__route"
            elseif self.kind == "__link" then
                ns.editKind = "__link"
                ns.linkFrom = nil
            elseif self.kind == "__ghost" then
                -- off -> each other floor with world bounds in turn -> off
                local list = {}
                for _, fl in ipairs(ns.GetFloors(state.instanceID, state.wing) or {}) do
                    if fl.bounds and not fl.yards and state.floor and fl.uiMapID ~= state.floor.uiMapID then list[#list + 1] = fl end
                end
                local nextFloor
                if not state.ghostID then
                    nextFloor = list[1]
                else
                    for i, fl in ipairs(list) do if fl.uiMapID == state.ghostID then nextFloor = list[i + 1] end end
                end
                state.ghostID = nextFloor and nextFloor.uiMapID or nil
                state.ghostName = nextFloor and (nextFloor.name or ("floor " .. nextFloor.uiMapID)) or nil
            else
                if ns.editKind == "__route" and ns.EndRouteDrawing then ns.EndRouteDrawing() end -- leaving the route tool: a cut left open is joined up
                ns.editKind = self.kind
            end
            ns.RefreshMap()
        end)
        b:Hide()
        view.kindButtons[i] = b
    end

    buildPanel()
    -- collapse arrow on the divider (sidebar open) and the tab that brings it back (sidebar hidden)
    local function arrowButton(dir, tip, onClick)
        local b = CreateFrame("Button", nil, view)
        b:SetFrameLevel(view:GetFrameLevel() + 110)
        b:SetSize(30, 30) -- square, same page-arrow icons as the wide button
        b:SetNormalTexture(ARROW .. dir .. "-Up")
        b:SetPushedTexture(ARROW .. dir .. "-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        return b
    end
    view.collapse = arrowButton("NextPage", "Hide the sidebar", function() ns.SetSideMode("hidden") end)
    view.collapse:SetPoint("RIGHT", panel, "LEFT", 6, 0)
    view.sideTab = arrowButton("PrevPage", "Show the sidebar", function() ns.SetSideMode("side") end)
    view.sideTab:SetPoint("RIGHT", view, "RIGHT", -6, 0)
    view.sideTab:Hide()
    view:SetScript("OnSizeChanged", function() ns.RefreshMap() end)
    -- Leaving the dungeon view when the player navigates the world map elsewhere: compare the map id a few times a second
    -- (only while the view is shown).
    local sinceCheck = 0
    view:SetScript("OnUpdate", function(_, dt)
        sinceCheck = sinceCheck + dt
        if sinceCheck < 0.25 then return end
        sinceCheck = 0
        if ns.viewMapID and not ns.internalNav and not ns.OpenMapAPI() and WorldMapFrame:GetMapID() ~= ns.viewMapID then ns.HideView() end
    end)
    view:SetScript("OnHide", function()
        if ns.OpenMapRestoreButtons then ns.OpenMapRestoreButtons() end
        if ns.EndRouteDrawing then ns.EndRouteDrawing() end
        state.tempMode = nil
        if dungeonList then dungeonList:Hide() end
        if crumbs then crumbs:Hide() end
    end)
    view:Hide()
end

-- Where a point of a floor's art (srcFloorID, x, y) is drawn on the shown floor: x, y fractions of the art frame, or nil if it is not on it.
-- On a combined map the point is looked up in the pieces.
local function toDisplay(floor, srcFloorID, x, y)
    if floor.combined then return ns.CombinedPoint(floor, srcFloorID, x, y) end
    if srcFloorID == floor.uiMapID then return x, y end
end

local linkLines = {}
local function positionMarkers()
    local floor = state.floor
    local list = {} -- { mk, x, y }: the marker and where it is drawn
    if floor and not state.overview then
        local srcFloors = { floor.uiMapID }
        if floor.combined then
            srcFloors = {}
            local seen = {}
            for _, p in ipairs(floor.data.pieces) do
                if not seen[p.floor] then seen[p.floor] = true; srcFloors[#srcFloors + 1] = p.floor end
            end
        end
        for _, fid in ipairs(srcFloors) do
            for _, mk in ipairs(ns.GetMarkers(state.instanceID, fid)) do
                local dx, dy = toDisplay(floor, fid, mk.x, mk.y)
                if dx then list[#list + 1] = { mk = mk, x = dx, y = dy } end
            end
        end
    end
    local size = math.max(18, (DungeonMapDB.pinSize or PIN_SIZE) * 0.65)
    for i, e in ipairs(list) do
        local m = markerFrames[i] or createMarker(art)
        markerFrames[i] = m
        fillMarker(m, e.mk, size)
        m:ClearAllPoints()
        m:SetPoint("CENTER", art, "TOPLEFT", e.x * art:GetWidth(), -e.y * art:GetHeight())
        m:Show()
    end
    for i = #list + 1, #markerFrames do markerFrames[i]:Hide() end
    -- combined map: a thin line joins the two ends of every floor link
    local nl = 0
    if floor and floor.combined and not state.overview then
        for _, l in ipairs(ns.GetLinks(state.instanceID)) do
            local ax, ay = toDisplay(floor, l.fa, l.xa, l.ya)
            local bx, by = toDisplay(floor, l.fb, l.xb, l.yb)
            if ax and bx then
                nl = nl + 1
                local line = linkLines[nl]
                if not line then
                    line = tileHost:CreateLine(nil, "ARTWORK", nil, 7)
                    line:SetThickness(2)
                    linkLines[nl] = line
                end
                local W, H = art:GetWidth(), art:GetHeight()
                line:SetColorTexture(0.55, 0.85, 1, 0.75)
                line:SetStartPoint("TOPLEFT", tileHost, ax * W, -ay * H)
                line:SetEndPoint("TOPLEFT", tileHost, bx * W, -by * H)
                line:Show()
            end
        end
    end
    for i = nl + 1, #linkLines do linkLines[i]:Hide() end
    ns.RenderRoute(tileHost, art, state.instanceID, state.wing, floor, toDisplay, floor and ns.GetBosses(state.instanceID, state.diff, state.wing) or {},
        floor ~= nil and not state.overview)
    ns.RenderReference(art, state.instanceID, floor and not floor.combined and floor.uiMapID, ns.editing and ns.showReference and not state.overview and floor ~= nil and not floor.combined)
end

function positionPins()
    positionMarkers()
    for _, p in ipairs(pins) do
        if p:IsShown() and p.boss then
            p:ClearAllPoints()
            p:SetPoint("CENTER", art, "TOPLEFT", (p.dx or p.boss.x) * art:GetWidth(), -(p.dy or p.boss.y) * art:GetHeight())
        end
    end
end

function relayout()
    if state.floor then layoutArt(state.floor) end
    clampPan()
    if state.floor then layoutArt(state.floor) end -- second pass after the pan was clamped to the new size
    positionPins()
end

function zoomAt(factor)
    local old = zoom.k
    local nk = math.max(1, math.min(MAX_ZOOM, old * factor))
    if nk == old or not state.floor then return end
    local scale = view:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local left, top, w, h = art:GetLeft(), art:GetTop(), art:GetWidth(), art:GetHeight()
    local vl, vt, vr, vb = view:GetLeft(), view:GetTop(), view:GetRight(), view:GetBottom()
    if not (left and vl and w > 0 and h > 0) then return end
    if cx < vl or cx > vr or cy > vt or cy < vb then cx, cy = (vl + vr) / 2, (vt + vb) / 2 end -- not over the map: zoom to centre
    local u = math.max(0, math.min(1, (cx - left) / w))
    local v = math.max(0, math.min(1, (top - cy) / h))
    local k = nk / old
    local nw, nh = w * k, h * k
    local nleft, ntop = cx - u * nw, cy + v * nh
    zoom.k = nk
    zoom.x = (nleft + nw / 2) - (vl + vr) / 2 - (art.baseX or 0)
    zoom.y = (ntop - nh / 2) - (vt + vb) / 2
    relayout()
end

-- Zoom in on the entrance of an overview map (a tall map of the whole dungeon is small when shown whole). Needs an Entrance marker on that floor.
-- Pan (and zoom in if needed) so that the point (fx, fy) of the map is in the middle of the map area.
local function centerOn(floor, fx, fy, minZoom)
    if zoom.k < minZoom then zoom.k = minZoom end
    layoutArt(floor)
    local W, H = art:GetWidth(), art:GetHeight()
    zoom.x = -(fx - 0.5) * W
    zoom.y = (fy - 0.5) * H
    clampPan()
    layoutArt(floor)
end
ns.CenterOn = function(fx, fy, minZoom) if state.floor then centerOn(state.floor, fx, fy, minZoom or 2.4) end end

-- An overview map fills the window, so most of it is off screen: start on the entrance (or at the top until an Entrance marker exists).
-- Selecting a boss in the list: if its pin is not in view (zoomed in, or an overview map that fills the window), pan the map to it.
-- Nothing happens when the boss is already visible, so the map only moves when it has to.
function ns.EnsureBossVisible(b)
    local floor = state.floor
    if not (floor and b and b.x and art and not state.overview and sideMode() ~= "wide") then return end
    local dx, dy = toDisplay(floor, tonumber(b.floor), b.x, b.y)
    local left, top = art:GetLeft(), art:GetTop()
    if not (dx and left and top) then return end
    local px, py = left + dx * art:GetWidth(), top - dy * art:GetHeight()
    local m = 70 -- keep the pin this far from the edges
    local vl, vr, vt, vb = view:GetLeft(), view:GetRight() - reserved(), view:GetTop(), view:GetBottom()
    if px >= vl + m and px <= vr - m and py <= vt - m and py >= vb + m then return end
    centerOn(floor, dx, dy, zoom.k)
    ns.RefreshMap()
end

local function focusEntrance(floor)
    local ent
    for _, mk in ipairs(ns.GetMarkers(state.instanceID, floor.uiMapID)) do
        if mk.kind == "entrance" then ent = mk break end
    end
    if ent then
        centerOn(floor, ent.x, ent.y, 1)
    else
        local _, ly = panLimits()
        zoom.y = -ly
        clampPan()
        layoutArt(floor)
    end
end

-- Our view covers Blizzard's quest panel when it is open (its side panel to the right of the map): the quest log and our Quests tab would be two lists
-- side by side. The panel is not closed or changed, only drawn over; when it closes the view goes back to the map's own width.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local function coverQuestLog()
    if not view then return end
    local c = container()
    local ql = WorldMapFrame and WorldMapFrame.QuestLog
    local right = c
    local open = type(ql) == "table" and ql.IsShown and ql:IsShown()
    if open then right = ql end
    -- Drawn over it, not under it: the panel's frame strata decides first (a frame on a higher strata is above any frame level), so while it is open our view
    -- takes the strata just above it (never past FULLSCREEN: our dialogs and tooltips stay above the view), and goes back to the map's own after.
    view.baseStrata = view.baseStrata or view:GetFrameStrata()
    local want = view.baseStrata
    if open and ql.GetFrameStrata then
        local qi, bi
        for i, name in ipairs(STRATA) do
            if name == ql:GetFrameStrata() then qi = i end
            if name == view.baseStrata then bi = i end
        end
        if qi and bi and qi >= bi and qi < 6 then want = STRATA[qi + 1] end
    end
    if view:GetFrameStrata() ~= want then view:SetFrameStrata(want) end
    if view.coverRight ~= right then
        view.coverRight = right
        view:ClearAllPoints()
        view:SetPoint("TOPLEFT", c, "TOPLEFT")
        view:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
    end
end
ns.CoverQuestLog = coverQuestLog

function ns.RefreshMap()
    if not view or not view:IsShown() or not state.instanceID then return end
    coverQuestLog()
    local id = state.instanceID
    local dungeon = ns.Dungeons[id]
    local floors = ns.GetFloors(id, state.wing)
    local artFloors = floors -- the floors that have their own art (not the combined map): overview and strip show these
    if floors and floors[#floors].combined then
        artFloors = {}
        for i = 1, #floors - 1 do artFloors[i] = floors[i] end
    end
    if floors and state.floorIndex > #floors then state.floorIndex = 1 end
    local floor = floors and floors[state.floorIndex]
    if state.floor ~= floor then
        resetZoom()
        state.pendingFocus = floor and floor.overview and floor or nil -- an overview map opens zoomed in on the entrance
    end
    state.floor = floor
    local mode = sideMode()
    local showMap = mode ~= "wide"
    S = showMap and 1 or 1.6 -- wide mode: everything in the sidebar is 60 % bigger

    -- header: title (opens the dungeon list), wing row, level, saved line, floor row; rows without content take no space
    panel.wideButton:SetSize(26 * S, 26 * S)
    panel.close:SetShown(not showMap)
    -- the gear sits left of the close X in wide view (where the X is shown)
    panel.optionsButton:ClearAllPoints()
    panel.optionsButton:SetPoint("TOPRIGHT", showMap and -14 or -44, -12)
    panel.dungeonButton:ClearAllPoints()
    panel.dungeonButton:SetPoint("TOPLEFT", panel.wideButton, "TOPRIGHT", 6, 0)
    panel.dungeonButton:SetPoint("TOPRIGHT", showMap and -54 or -84, -12)
    panel.dungeonButton:ClearAllPoints()
    panel.dungeonButton:SetPoint("TOPLEFT", panel.wideButton, "TOPRIGHT", 6, 0)
    panel.dungeonButton:SetPoint("TOPRIGHT", showMap and -14 or -48, -12)
    panel.dungeonButton:SetHeight(26 * S)
    panel.dungeonButton.arrow:SetSize(16 * S, 16 * S)
    panel.dungeonButton.label:SetFontObject(S > 1 and "GameFontNormalHuge" or "GameFontNormalLarge")
    panel.dungeonButton.label:SetText(ns.DungeonTitle(id, state.wing))
    panel.dungeonButton.label:SetTextColor(1, 0.82, 0)
    local pw = (mode == "wide") and (view:GetWidth() - 12) or SIDE_W
    local y = 12 + 26 * S + 8
    panel.level:SetFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
    panel.lock:SetFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
    panel.lock:SetTextColor(0.55, 0.8, 1)
    panel.floorLabel:SetFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
    for _, b in ipairs(panel.wingButtons) do b:Hide() end
    local wings = ns.GetWings(id)
    if wings and #wings > 1 then -- wing switch (Lower / Upper Blackrock Spire, Dire Maul wings, Scarlet Monastery wings)
        local n = #wings
        local bw = math.floor((pw - 28 - (n - 1) * 2) / n)
        for i, w in ipairs(wings) do
            local b = panel.wingButtons[i]
            if not b then
                b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
                b:SetFrameLevel(panel:GetFrameLevel() + 5)
                panel.wingButtons[i] = b
            end
            b:SetSize(bw, 20 * S)
            b:SetNormalFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
            b:SetHighlightFontObject(S > 1 and "GameFontHighlightLarge" or "GameFontHighlight")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (i - 1) * (bw + 2), -y)
            b:SetText(w.name:match("%- (.+)$") or w.name:match("^(%a+)") or w.name)
            b:SetEnabled(w.wing ~= state.wing)
            b:SetScript("OnClick", function()
                state.wing, state.selected, state.floorIndex = w.wing, nil, 1
                DungeonMapDB.lastWing[id] = w.wing
                ns.RefreshMap()
            end)
            b:Show()
        end
        y = y + 26 * S
    end
    if dungeon.status == "classic" then
        panel.level:SetText("Classic data - not confirmed for Forever yet")
        panel.level:SetTextColor(0.9, 0.55, 0.2)
    else
        local lv = levelLabel(ns.LevelData(id, state.wing))
        panel.level:SetText(dungeon.raid and (lv ~= "" and ("Raid, level " .. lv) or "Raid") or (lv ~= "" and ("Level " .. lv) or ""))
        panel.level:SetTextColor(ns.LevelColor(ns.LevelData(id, state.wing)))
    end
    panel.level:ClearAllPoints()
    panel.level:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -y)
    y = y + 18 * S
    local lock = ns.GetLockout(id)
    if lock then
        local when = SecondsToTime and SecondsToTime(lock.reset) or (lock.reset .. "s")
        panel.lock:SetText(format("Saved: %d/%d defeated - resets in %s", lock.killed, lock.total, when))
        panel.lock:ClearAllPoints()
        panel.lock:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -y)
        y = y + 18 * S
    else
        panel.lock:SetText("") -- no lockout reported (dungeons may not have one on Forever)
    end
    for _, b in ipairs(floorButtons) do b:Hide() end
    if floors and #floors > 1 then
        panel.floorLabel:SetText("Floor")
        panel.floorLabel:ClearAllPoints()
        panel.floorLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -(y + 3 * S))
        for i = 1, #floors do
            local b = floorButtons[i] or createFloorButton(i)
            floorButtons[i] = b
            b:ClearAllPoints()
            b:SetSize((floors[i].combined and 38 or 28) * S, 22 * S)
            b:SetText(floors[i].combined and "All" or i)
            b:SetNormalFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
            b:SetHighlightFontObject(S > 1 and "GameFontHighlightLarge" or "GameFontHighlight")
            b:SetPoint("LEFT", panel.floorLabel, "RIGHT", 8 * S + (i - 1) * 30 * S, 0)
            b:SetEnabled(i ~= state.floorIndex)
            b:Show()
        end
        y = y + 28 * S
    else
        panel.floorLabel:SetText("")
    end
    local hasQuests = ns.HasQuests and ns.HasQuests(id)
    if state.questInstance ~= id then
        state.questInstance = id
        state.questSel = nil
        if panel.questScroll then panel.questScroll:SetVerticalScroll(0) end
    end
    local _, qcounts = ns.GetQuestEntries(id)
    -- the tabs: Bosses and Quests (where the dungeon has quests); edit mode records bosses, so it keeps the boss list only
    local tabs = { { key = "bosses", label = "Bosses" } }
    if hasQuests and not ns.editing then tabs[#tabs + 1] = { key = "quests", label = format("Quests (%d)", qcounts and qcounts.open or 0) } end
    local known = false
    for _, t in ipairs(tabs) do if t.key == state.tab then known = true end end
    if not known then state.tab = nil end
    y = y + ns.QuestsUI.LayoutTabs(panel, y, S, pw, tabs, state.tab or "bosses")
    panel.listTop = y + 6

    local bosses = ns.GetBosses(id, state.diff, state.wing)
    local found -- the boss shown in the loot area: the selected one, else the first
    for _, b in ipairs(bosses) do if b.id == state.selected then found = b end end
    if not found then
        found = bosses[1]
        state.selected = found and found.id or nil
    end
    state.selectedName = found and found.name or nil
    local abilList = found and ns.GetAbilities and ns.GetAbilities(id, found.name) or nil
    -- encounters that contain several opponents (Ring of Law champions) are one collapsible entry: the opponents show only when open
    state.expandedGroups = state.expandedGroups or {}
    local kids, topCount = {}, 0
    for _, b in ipairs(bosses) do
        if b.sub then kids[b.parent] = (kids[b.parent] or 0) + 1 elseif not b.trash then topCount = topCount + 1 end
    end
    if found and found.sub then
        state.expandedGroups[found.parent] = true -- the selected opponent is always visible
        state.selectedParent = found.parent
    else
        state.selectedParent = nil
    end
    state.groupKids = kids
    local visible = {}
    for _, b in ipairs(bosses) do
        if not b.sub or state.expandedGroups[b.parent] then visible[#visible + 1] = b end
    end
    layoutPanel(#visible, abilList and #abilList or 0)
    local qmode = hasQuests and state.tab == "quests"
    panel.bossBox:SetShown(not qmode)
    panel.abilBox:SetShown(not qmode)
    panel.lootBox:SetShown(not qmode)
    ns.QuestsUI.Update(panel, id, qmode and true or false, mode == "wide", S, panel.listTop)

    -- map
    local reserve = reserved()
    view.editBanner:ClearAllPoints()
    view.editBanner:SetPoint("TOP", view, "TOP", -reserve / 2, -12)
    view.modeButton:ClearAllPoints()
    view.modeButton:SetPoint("TOP", view, "TOP", -reserve / 2, -40)
    view.empty:ClearAllPoints()
    view.empty:SetPoint("CENTER", view, "CENTER", -reserve / 2, 0)
    layoutArt(floor)
    if floor and state.pendingFocus == floor and showMap then
        state.pendingFocus = nil
        focusEntrance(floor)
    end
    view.empty:SetShown(floor == nil and showMap)
    art:SetShown(floor ~= nil and showMap)

    local used = 0
    for idx, b in ipairs(bosses) do
        local dx, dy
        if showMap and floor and b.x then dx, dy = toDisplay(floor, tonumber(b.floor), b.x, b.y) end
        if dx then
            used = used + 1
            local p = pins[used] or createPin()
            pins[used] = p
            sizePin(p, DungeonMapDB.pinSize or PIN_SIZE)
            fillPin(p, b, idx)
            p.dx, p.dy = dx, dy
            p:Show()
        end
    end
    for i = used + 1, #pins do pins[i]:Hide() end
    positionPins()

    -- boss cards
    local placed, y = 0, 0
    panel.bossBox.title:SetText(format("Bosses (%d)", topCount))
    for i, b in ipairs(visible) do
        local r = rows[i] or createRow(i)
        rows[i] = r
        styleCard(r)
        r.boss = b
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel.bossContent, "TOPLEFT", b.sub and 22 or 0, -y) -- opponents inside an encounter are indented
        r:SetPoint("TOPRIGHT", panel.bossContent, "TOPRIGHT", 0, -y)
        r.y = y
        local hasKids = kids[b.id] ~= nil
        r.hasKids = hasKids
        r.expand:SetShown(hasKids)
        if hasKids then
            local open = state.expandedGroups[b.id]
            r.expand:SetNormalTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            r.expand:SetPushedTexture(open and "Interface\\Buttons\\UI-MinusButton-Down" or "Interface\\Buttons\\UI-PlusButton-Down")
            r.expand:SetSize(18 * S, 18 * S)
        end
        r.check:ClearAllPoints()
        r.check:SetPoint("RIGHT", hasKids and -(30 * S) or -8, 0)
        local rare = DungeonMapDB.markRares ~= false and ns.IsRare(id, b.name)
        local label = b.num and format("|cff9a9a9a%d.|r ", b.num) or "" -- numbers only where set by hand (data/manual/boss_order.csv)
        local tag = b.summoned and " |cffc79bff(summoned)|r" or (rare and " |cffc7cde0(rare)|r" or "")
        r.text:SetText(label .. b.name .. tag .. (kids[b.id] and format(" |cff9a9a9a(%d)|r", kids[b.id]) or ""))
        local rc = b.summoned and PURPLE or (rare and SILVER or GOLD) -- rares get the same silver ring here as on the map pins
        r.rim:SetColorTexture(rc[1], rc[2], rc[3], 1)
        setPortrait(r.icon, b)
        local sel = found and found.id == b.id
        r.hl:SetShown(sel)
        r.bar:SetShown(sel)
        local killed = ns.IsKilled(b, id)
        r.check:SetShown(killed)
        local grey = killed and DungeonMapDB.greyDefeated ~= false
        r.icon:SetDesaturated(grey)
        local on = b.x ~= nil or b.sub -- an opponent inside an encounter has no pin of its own, it is not "unplaced"
        if b.x and not b.trash then placed = placed + 1 end
        if grey then
            r.text:SetTextColor(0.5, 0.5, 0.5) -- defeated: greyed out
        else
            r.text:SetTextColor(on and 1 or 0.65, on and 1 or 0.65, on and 1 or 0.65)
        end
        r:Show()
        y = y + CARD_H * S + GAP
    end
    for i = #visible + 1, #rows do rows[i]:Hide() end
    panel.bossContent:SetHeight(math.max(y, 10))

    -- loot of the selected boss
    local ly, usedItems = 0, 0
    panel.noLoot:Hide()
    -- panel.find is a secure button: the client blocks hiding, showing or moving it in combat (and flags our addon). The layout below
    -- still leaves room for it; the button itself catches up when combat ends (PLAYER_REGEN_ENABLED redraws the map).
    local combat = InCombatLockdown()
    if combat then ns.findPending = true else panel.find:Hide() end
    local lb = panel.lootBox
    if found then
        local rare = DungeonMapDB.markRares ~= false and ns.IsRare(id, found.name)
        setPortrait(lb.portrait, found)
        local killed = ns.IsKilled(found, id)
        lb.portrait:SetDesaturated(killed and DungeonMapDB.greyDefeated ~= false)
        lb.name:SetText(found.name)
        local where = ""
        if found.floor and floors then
            for _, fl in ipairs(floors) do
                if fl.uiMapID == tonumber(found.floor) and #floors > 1 then where = "  |cff9a9a9a" .. (fl.name or "") .. "|r" end
            end
        end
        local fc = found.summoned and PURPLE or (rare and SILVER or GOLD)
        lb.rim:SetColorTexture(fc[1], fc[2], fc[3], 1)
        if found.trash then
            lb.status:SetText("Dropped by the regular monsters here")
        elseif found.summoned then
            lb.status:SetText((killed and "|cff00ff00Defeated|r" or "Not defeated") .. " |cffc79bff- summoned" .. (found.how and (": " .. found.how) or " boss") .. "|r" .. where)
        elseif found.sub then -- an opponent inside another encounter (Ring of Law): kills are tracked on the parent
            local parentName
            for _, pb in ipairs(bosses) do if pb.id == found.parent then parentName = pb.name end end
            lb.status:SetText("Appears in: " .. (parentName or "another encounter"))
        else
            local best = ns.GetBestTime and ns.GetBestTime(id, found.name)
            lb.status:SetText((killed and "|cff00ff00Defeated|r" or "Not defeated") .. where .. (best and ("|cff9a9a9a - best kill " .. ns.FormatTime(best) .. "|r") or "") .. (found.how and ("|cff9a9a9a - " .. (ns.IsRare(id, found.name) and "" or "how to start: ") .. found.how .. "|r") or ""))
        end
        if rare then -- one-click /target to see whether this rare is up (needs to be near it)
            if not combat then
                panel.find:ClearAllPoints()
                panel.find:SetPoint("TOPLEFT", panel.lootContent, "TOPLEFT", 0, 0)
                panel.find:SetPoint("TOPRIGHT", panel.lootContent, "TOPRIGHT", 0, 0)
                panel.find.bossName = found.name
                panel.find:SetAttribute("type", "macro")
                panel.find:SetAttribute("macrotext", "/target " .. found.name)
                panel.find:SetHeight(22 * S)
                panel.find:Show()
            end
            ly = ly + 28 * S
        end
        local loot = ns.GetLoot and ns.GetLoot(id, found.name)
        if loot and #loot > 0 then
            for _, entry in ipairs(loot) do
                usedItems = usedItems + 1
                local it = itemRows[usedItems] or createItemRow()
                itemRows[usedItems] = it
                styleItem(it)
                it:ClearAllPoints()
                it:SetPoint("TOPLEFT", panel.lootContent, "TOPLEFT", 0, -ly)
                it:SetPoint("TOPRIGHT", panel.lootContent, "TOPRIGHT", 0, -ly)
                showItem(it, entry)
                it:Show()
                ly = ly + ITEM_H * S + GAP
            end
        else
            panel.noLoot:ClearAllPoints()
            panel.noLoot:SetPoint("TOPLEFT", panel.lootContent, "TOPLEFT", 4, -(ly + 4))
            panel.noLoot:Show()
            ly = ly + 24
        end
        if state.lootShown ~= found.id then
            state.lootShown = found.id
            panel.lootScroll:SetVerticalScroll(0)
        end
    else
        lb.name:SetText("")
        lb.status:SetText("")
    end
    for i = usedItems + 1, #itemRows do itemRows[i]:Hide() end
    panel.lootContent:SetHeight(math.max(ly, 10))

    -- abilities of the selected boss (wide mode); fallback text when none are known
    local list = abilList
    local nAbil = 0
    if list then
        for _, spellID in ipairs(list) do
            nAbil = nAbil + 1
            local ar = abilRows[nAbil] or createAbilityRow()
            abilRows[nAbil] = ar
            showAbility(ar, spellID, showMap)
            ar:Show()
        end
    end
    for i = nAbil + 1, #abilRows do abilRows[i]:Hide() end
    if nAbil > 0 then
        panel.abilBox.note:Hide()
        layoutAbilities()
    else
        panel.abilContent:SetHeight(10)
        panel.abilBox.note:SetText(found and (dungeon.status == "classic" and "No ability information for this boss." or
            "No ability information for this boss yet. Abilities of new Forever fights are added as they are documented.") or "")
        panel.abilBox.note:SetShown(true)
    end
    if found and state.abilShown ~= found.id then
        state.abilShown = found.id
        panel.abilScroll:SetVerticalScroll(0)
    end
    if state.scrollTo then -- a pin on the map was clicked: bring its card into view in the list
        local target = state.scrollTo
        state.scrollTo = nil
        C_Timer.After(0, function()
            for _, r in ipairs(rows) do
                if r:IsShown() and r.boss and r.boss.id == target then
                    local range = panel.bossScroll:GetVerticalScrollRange() or 0
                    panel.bossScroll:SetVerticalScroll(math.max(0, math.min(range, r.y - 4)))
                end
            end
        end)
    end

    local msg = ""
    if placed < topCount and not qmode then
        msg = format("%d of %d boss locations known.", placed, topCount)
    end
    if ns.editing then msg = "|cffffd100EDIT MODE|r select a boss, click the map. " .. msg end
    panel.footer:SetText(msg)
    local banner, bc = "EDIT MODE: pick what to place (button below), then click the map", { 1, 0.82, 0 }
    if ns.editKind == "__link" then -- the link tool tells you what to do next, right on the map (chat is hidden behind the map)
        if ns.linkFrom then
            banner = "LINK: now click the matching marker"
        else
            banner = "LINK: click a marker, then its match (shift-click a linked marker to unlink it)"
        end
        if state.linkMsg and GetTime() < state.linkMsg.untilTime then banner, bc = state.linkMsg.text, { 0.5, 1, 0.5 } end
    end
    view.editBanner:SetText(banner)
    view.editBanner:SetTextColor(bc[1], bc[2], bc[3])
    view.editBanner:SetShown(ns.editing and showMap and ns.editKind ~= "__link" and ns.editKind ~= "__route")
    if ns.RouteTool() then
        local r = ns.GetRoute(state.instanceID, state.wing) or {}
        local stops = 0
        for _, p in ipairs(r) do if p.boss then stops = stops + 1 end end
        banner, bc = format("ROUTE: click the map for a point, a boss for a stop, a marker for a step; click a dot to select it, drag to move it  (%d points, %d stops)", #r, stops), { 1, 0.82, 0 }
    end
    -- route: the editor bar while one is drawn, and the next boss on top of the map
    ns.RouteUI.UpdateBar(view, showMap and ns.RouteTool() and not state.overview and true or false, reserve)
    ns.RouteUI.UpdateCorner(view, showMap and not state.overview and true or false)
    local ri = view.routeInfo
    local rprog = ns.RouteVisible() and ns.GetRoute(id, state.wing) and ns.RouteProgress(id, state.wing, bosses) or nil
    if rprog and rprog.total > 0 and showMap and not state.overview and not ns.editing and not ns.routeDraw then
        local route = ns.GetRoute(id, state.wing)
        if rprog.nextStop then
            local st = rprog.stops[rprog.nextStop]
            ri.text:SetText(format("Route: next boss |cffffd100%d/%d %s|r", rprog.nextStop, rprog.total, st.boss))
            ri.target = route[st.index]
        else
            ri.text:SetText("|cff66ff66Route complete|r" .. (rprog.skipped > 0 and format(" |cff9a9a9a(%d skipped)|r", rprog.skipped) or ""))
            ri.target = nil
        end
        ri:SetWidth(ri.text:GetStringWidth() + 30)
        ri:ClearAllPoints()
        ri:SetPoint("TOP", view, "TOP", -reserved() / 2, -12)
        ri:Show()
    else
        ri:Hide()
    end
    local tShow = ns.editing and showMap and ns.editKind == "__link"
    view.toast:SetShown(tShow and true or false)
    if tShow then
        view.toast.text:SetText(banner)
        view.toast.text:SetTextColor(bc[1], bc[2], bc[3])
        view.toast:SetWidth(math.min(view:GetWidth() - reserve - 20, view.toast.text:GetStringWidth() + 48))
        view.toast:ClearAllPoints()
        view.toast:SetPoint("TOP", view, "TOP", -reserve / 2, -76)
    end
    view.modeButton:Hide()
    local nk = #view.kindButtons
    local bw = math.max(60, math.min(96, math.floor((view:GetWidth() - reserve - 24) / nk) - 2)) -- all of them must fit above the map
    for i, b in ipairs(view.kindButtons) do
        b:ClearAllPoints()
        b:SetSize(bw, 22)
        b:SetPoint("TOP", view, "TOP", -reserve / 2 + (i - (nk + 1) / 2) * (bw + 2), -40)
        b:SetEnabled(b.kind ~= ns.editKind) -- the active type is greyed
        if b.kind == "__ref" then b:SetText(ns.showReference and "Landmarks: on" or "Landmarks") end
        if b.kind == "__ghost" then b:SetText(state.ghostName and ("Overlay: " .. state.ghostName) or "Overlay: off") end
        b:SetShown(ns.editing and showMap and true or false)
    end
    -- overview (all floors at once) / floor strip; none of it while the map is hidden (wide sidebar)
    local multi = floors and #floors > 1
    if state.overview and not multi then state.overview = false end
    local hasOverview = floors and floors[1] and floors[1].overview -- such a dungeon has its overview map as a floor: no "All floors" grid
    if hasOverview and state.overview then state.overview = false end
    view.allButton:SetShown(multi and showMap and not hasOverview and true or false)
    view.allButton:SetText(state.overview and "Back" or "All floors")
    for _, b in ipairs(view.zoomButtons) do b:SetShown(showMap and not state.overview) end
    if not showMap then
        art:Hide()
        for _, p in ipairs(pins) do p:Hide() end
        for _, m in ipairs(markerFrames) do m:Hide() end
        ns.HideOverview()
        ns.HideStrip()
    elseif state.overview then
        art:Hide()
        for _, p in ipairs(pins) do p:Hide() end
        for _, m in ipairs(markerFrames) do m:Hide() end
        view.empty:Hide()
        ns.HideStrip()
        ns.RenderOverview({ view = view, instanceID = id, panelW = reserve - 24, floors = artFloors, bosses = bosses, pinFactory = createPin, sizePin = sizePin,
            fillPin = fillPin, markerFactory = createMarker, fillMarker = fillMarker, markers = function(fid) return ns.GetMarkers(id, fid) end })
    else
        ns.HideOverview()
        positionMarkers()
        ns.RenderStrip({ view = view, floors = artFloors or {}, bosses = bosses, floorIndex = state.floorIndex, hidden = DungeonMapDB.showFloorStrip == false })
    end
    local credit = showMap and floor and floor.custom and ns.ArtCredits and ns.ArtCredits[id]
    if credit then
        view.credit.text:SetText(credit.text)
        view.credit.url = credit.url
        view.credit:SetSize(view.credit.text:GetStringWidth() + 4, 16)
        view.credit:Show()
    else
        view.credit:Hide()
    end
    updateScrollbars()
    updateBreadcrumb()
end

local function showWorldMap()
    if WorldMapFrame and not WorldMapFrame:IsShown() then
        ns.internalNav = true
        pcall(ToggleWorldMap)
        ns.internalNav = false
    end
end

-- Show a dungeon inside the world map. `browsing` = chosen from the list/entrance, not the current instance.
function ns.ShowInstance(instanceID, difficultyID, browsing, wing)
    if not instanceID or not ns.Dungeons[instanceID] or not WorldMapFrame then return end
    if not view then buildView() end
    local fresh = state.instanceID ~= instanceID
    if fresh then state.floorIndex, state.selected = 1, nil; if ns.EndRouteDrawing then ns.EndRouteDrawing() end end
    local newWing = wing or ns.PickWing(instanceID)
    if newWing ~= state.wing then fresh, state.selected, state.floorIndex = true, nil, 1 end
    state.wing = newWing
    if fresh then -- a dungeon with a combined map opens on it
        local fl = ns.GetFloors(instanceID, newWing)
        if fl and fl[#fl].combined then state.floorIndex = #fl end
    end
    if newWing then
        DungeonMapDB.lastWing = DungeonMapDB.lastWing or {}
        DungeonMapDB.lastWing[instanceID] = newWing
    end
    state.instanceID = instanceID
    if browsing then
        state.diff = difficultyID
    else
        local _, diff = ns.GetCurrentInstance()
        state.diff = difficultyID or diff
    end
    showWorldMap()
    local zone = (ns.EntranceZoneFor and ns.EntranceZoneFor(instanceID)) or 947
    if WorldMapFrame:GetMapID() ~= zone and not ns.OpenMapAPI() then -- (OpenMap keeps the map under its view on what you look at: not ours to switch)
        ns.internalNav = true
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, zone)
        ns.internalNav = false
    end
    ns.viewMapID = WorldMapFrame:GetMapID()
    view:Show()
    if ns.OpenMapHideButtons then ns.OpenMapHideButtons() end -- (OpenMap's buttons and tabs would sit around our map)
    ns.RefreshMap()
end

-- Right click: leave the dungeon and return to the zone it belongs to (like leaving a zone on the regular map).
function ns.GoUp()
    local zone = state.instanceID and ns.EntranceZoneFor and ns.EntranceZoneFor(state.instanceID)
    local id, wing = state.instanceID, state.wing
    ns.HideView()
    local api = ns.OpenMapAPI()
    if api then
        -- OpenMap's stitched map: glide to the entrance of the dungeon we left, keeping the zoom
        local z, x, y = ns.EntrancePosition(id, wing)
        local u, v = z and api.WorldFromMap(z, x, y)
        if u then api.ShowWorld(u, v) end
        return
    end
    if zone and WorldMapFrame then WorldMapFrame:SetMapID(zone) end
end

function ns.HideView()
    if ns.EndRouteDrawing then ns.EndRouteDrawing() end
    if view then view:Hide() end
    if ns.OpenMapRestoreButtons then ns.OpenMapRestoreButtons() end
    if crumbs then crumbs:Hide() end
end

function ns.RouteDrawStart()
    if not state.instanceID or ns.editing then return end
    ns.routeAt = nil
    ns.routeDraw = true
    ns.routeShow = true
    ns.RefreshMap()
end

-- Drawing ends (Save route, closing the map, another dungeon): a cut that was left open is joined up (the new section to the first grey point).
local function endDrawing()
    if state.instanceID and ns.RouteCloseGap(state.instanceID, state.wing) then
        ns.Print("The new section was joined to the rest of the route.")
    end
    ns.routeDraw = false
    ns.routeAt = nil
end

ns.EndRouteDrawing = endDrawing

function ns.RouteDrawStop()
    endDrawing()
    ns.RefreshMap()
end

function ns.ViewShown()
    return view and view:IsShown()
end

function ns.Toggle()
    if view and view:IsShown() and WorldMapFrame:IsShown() then
        WorldMapFrame:Hide()
        return
    end
    local id, diff = ns.GetCurrentInstance()
    if id then
        ns.ShowInstance(id, diff)
    else
        local list = ns.GetDungeonList()
        ns.ShowInstance(state.instanceID or (list[1] and list[1].id), nil, true)
    end
end

function ns.GetState() return state end

-- All-floors overview on/off, and opening one floor from the overview or the floor strip.
function ns.SetOverview(flag)
    state.overview = flag and true or false
    ns.RefreshMap()
end

function ns.OpenFloor(index)
    state.floorIndex = index
    state.overview = false
    ns.RefreshMap()
end

-- Following the world map. Nothing is hooked on Blizzard's map: hooks on WorldMapFrame methods and scripts (SetMapID, OnShow, ...) broke the map's own
-- OnShow on this client ("attempt to call a nil value" from the second open). Instead a small frame of ours sits on the map: it shows and hides with it,
-- reports size changes, and while the map is open it compares the map id, zoom and maximised state a few times a second.
local function hookMap()
    if not WorldMapFrame or ns.mapHooked then return end
    ns.mapHooked = true
    local watch = CreateFrame("Frame", nil, WorldMapFrame)
    watch:SetAllPoints(WorldMapFrame)
    -- Size/scale changes (maximize/minimize, scale addons): Blizzard rebuilds its nav bar and re-lays out the canvas, so
    -- re-apply our layout and breadcrumb shortly afterwards (twice: layout settles over a couple of frames).
    local function resynced()
        if not (view and view:IsShown()) then return end
        for _, delay in ipairs({ 0.05, 0.4 }) do
            C_Timer.After(delay, function()
                if view and view:IsShown() then ns.RefreshMap() end
            end)
        end
    end
    local lastMap, lastZoom, lastMax, lastScale, lastQL
    local function snapshot()
        lastMap = WorldMapFrame:GetMapID()
        lastZoom = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or nil
        lastMax = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() or false
        lastScale = WorldMapFrame:GetScale()
    end
    watch:SetScript("OnShow", function()
        snapshot()
        C_Timer.After(0, function()
            if ns.RefreshEntrances then ns.RefreshEntrances() end
            if not DungeonMapDB.hookWorldMap then return end
            local id, diff = ns.GetCurrentInstance()
            if id and not ns.ViewShown() and not ns.internalNav then ns.ShowInstance(id, diff) end
        end)
    end)
    watch:SetScript("OnHide", function() ns.HideView() end)
    watch:SetScript("OnSizeChanged", resynced)
    local since = 0
    watch:SetScript("OnUpdate", function(_, dt)
        since = since + dt
        if since < 0.2 then return end
        since = 0
        local map = WorldMapFrame:GetMapID()
        local zoom = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or nil
        local maxed = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() or false
        local scale = WorldMapFrame:GetScale()
        local ql = WorldMapFrame.QuestLog and WorldMapFrame.QuestLog.IsShown and WorldMapFrame.QuestLog:IsShown() or false
        if ql ~= lastQL then
            lastQL = ql
            if view and view:IsShown() then ns.RefreshMap() end -- the quest panel opened or closed: the view covers it or goes back to the map's width
        end
        if map ~= lastMap or zoom ~= lastZoom then
            lastMap, lastZoom = map, zoom
            if ns.RefreshEntrances then ns.RefreshEntrances() end
        end
        if maxed ~= lastMax or scale ~= lastScale then
            lastMax, lastScale = maxed, scale
            resynced()
        end
    end)
    if WorldMapFrame:IsShown() then snapshot() end
end
ns.HookMap = hookMap
