-- The journal: a landing page for every dungeon and raid (a grid of cards with the dungeon's loading screen), a second way into the maps.
-- It is a frame of its own over the world map's canvas, never part of the dungeon view: opening a card hides it and shows the dungeon in the normal view,
-- the "Journal" button in that view brings it back (search text and scroll position kept). Opens with /dm list, the options, the dungeon picker.
-- Data: ns.Dungeons (what exists), ns.Journal (Data/Journal.lua: loading screen FileDataID + the version that added it), ns.GetDungeonList (hidden rules).
local _, ns = ...

local GAP, MIN_CARD = 10, 230
local HEADER_H = 46
local BAND_H = 26

-- The loading screens are cropped to the painted band (texture coordinates l, r, t, b), so every card shows a clean 2:1 picture. "classic": a 2048x2048
-- texture with the WoW logo on top and a bronze frame; "new": 2992x1684 with transparent bands above and below. Measured on build 1.60.1.70862.
local CROP = { classic = { 0, 1, 0.30, 0.80 }, new = { 0.115, 0.885, 0.158, 0.842 } }

local frame, cards, heads = nil, {}, {}
local tab = "dungeons" -- "dungeons" | "raids" (ignored while something is typed in the search box)

-- "0.1.19" -> 19 (the patch number; the addon is 0.1.x)
local function patchOf(v)
    local n = tostring(v or ""):match("^%d+%.%d+%.(%d+)")
    return n and tonumber(n) or nil
end

local function isNew(id)
    local j = ns.Journal and ns.Journal[id]
    local added = j and patchOf(j.added)
    local ver = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("DungeonCrawlerForever", "Version")
    local cur = patchOf(ver)
    return added and cur and cur - added <= 3 or false -- "New" for the release that added it and the next three
end

local function hasBossPositions(d)
    for _, b in ipairs(d.bosses or {}) do
        if b.x and not b.trash then return true end
    end
    return false
end

-- One entry per dungeon / raid (the dungeon list has one per wing): { id, name, raid, lo, hi, label, color data, bosses = {names}, ... }, sorted.
local function buildEntries()
    local byID, out = {}, {}
    for _, e in ipairs(ns.GetDungeonList()) do
        local it = byID[e.id]
        if not it then
            local d = ns.Dungeons[e.id]
            it = { id = e.id, name = d.name, raid = d.raid, status = d.status, d = d, names = {}, wings = {} }
            byID[e.id] = it
            out[#out + 1] = it
        end
        if e.wing then it.wings[#it.wings + 1] = e.name end
        local lo, hi = e.recMin, e.maxLevel
        if lo and hi then
            it.lo, it.hi = math.min(it.lo or lo, lo), math.max(it.hi or hi, hi)
        elseif e.minLevel and not it.lo then
            it.plus = e.minLevel
        end
    end
    for _, it in ipairs(out) do
        local d = it.d
        if not it.lo and d.recMin and d.recMax then it.lo, it.hi = d.recMin, d.recMax end
        if it.raid then
            it.label = "Raid"
        elseif it.lo then
            it.label = (it.lo == it.hi) and tostring(it.lo) or format("%d-%d", it.lo, it.hi)
        elseif it.plus then
            it.label = it.plus .. "+"
        else
            it.label = ""
        end
        it.sortLevel = it.lo or it.plus or 999
        it.color = { recMin = it.lo, recMax = it.hi, minLevel = it.plus or d.minLevel }
        it.preview = not hasBossPositions(d)
        it.isNew = isNew(it.id)
        it.bossCount = 0
        for _, b in ipairs(d.bosses or {}) do
            if not b.trash then
                it.bossCount = it.bossCount + 1
                it.names[#it.names + 1] = ns.NormName(b.name)
            end
        end
        it.nameKey = ns.NormName(it.name)
        for _, w in ipairs(it.wings) do it.names[#it.names + 1] = ns.NormName(w) end
    end
    table.sort(out, function(a, b)
        if a.raid ~= b.raid then return not a.raid end
        if a.sortLevel ~= b.sortLevel then return a.sortLevel < b.sortLevel end
        return a.name < b.name
    end)
    return out
end

-- Does the search text match the dungeon, a wing or one of its bosses? Returns true, and the boss that matched (when it was a boss).
local function matches(it, q)
    if q == "" then return true end
    if it.nameKey:find(q, 1, true) then return true end
    for _, n in ipairs(it.names) do
        if n:find(q, 1, true) then return true, n end
    end
    return false
end

local function bossNamed(it, key)
    for _, b in ipairs(it.d.bosses or {}) do
        if ns.NormName(b.name) == key then return b.name end
    end
end

local function newCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c.art = c:CreateTexture(nil, "ARTWORK")
    c.art:SetAllPoints()
    c.shade = c:CreateTexture(nil, "OVERLAY", nil, 1)
    c.shade:SetPoint("BOTTOMLEFT")
    c.shade:SetPoint("BOTTOMRIGHT")
    c.shade:SetColorTexture(0, 0, 0, 0.72)
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.name:SetPoint("LEFT", c.shade, "LEFT", 8, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.level = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.level:SetPoint("RIGHT", c.shade, "RIGHT", -8, 0)
    c.level:SetJustifyH("RIGHT")
    c.name:SetPoint("RIGHT", c.level, "LEFT", -6, 0)
    c.tagBg = c:CreateTexture(nil, "OVERLAY", nil, 1)
    c.tagBg:SetColorTexture(0, 0, 0, 0.7)
    c.tag = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.tag:SetPoint("TOPLEFT", 8, -6)
    c.tagBg:SetPoint("TOPLEFT", c.tag, "TOPLEFT", -4, 3)
    c.tagBg:SetPoint("BOTTOMRIGHT", c.tag, "BOTTOMRIGHT", 4, -3)
    c.note = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.note:SetPoint("TOPRIGHT", -8, -6)
    c.noteBg = c:CreateTexture(nil, "OVERLAY", nil, 1)
    c.noteBg:SetColorTexture(0, 0, 0, 0.7)
    c.noteBg:SetPoint("TOPLEFT", c.note, "TOPLEFT", -4, 3)
    c.noteBg:SetPoint("BOTTOMRIGHT", c.note, "BOTTOMRIGHT", 4, -3)
    c.edge = {}
    for i = 1, 4 do
        local t = c:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetColorTexture(1, 0.82, 0, 1)
        t:Hide()
        c.edge[i] = t
    end
    c.edge[1]:SetPoint("TOPLEFT"); c.edge[1]:SetPoint("TOPRIGHT"); c.edge[1]:SetHeight(2)
    c.edge[2]:SetPoint("BOTTOMLEFT"); c.edge[2]:SetPoint("BOTTOMRIGHT"); c.edge[2]:SetHeight(2)
    c.edge[3]:SetPoint("TOPLEFT"); c.edge[3]:SetPoint("BOTTOMLEFT"); c.edge[3]:SetWidth(2)
    c.edge[4]:SetPoint("TOPRIGHT"); c.edge[4]:SetPoint("BOTTOMRIGHT"); c.edge[4]:SetWidth(2)
    c:SetScript("OnEnter", function(self)
        for _, t in ipairs(self.edge) do t:Show() end
        local it = self.it
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(it.name)
        if it.label ~= "" then GameTooltip:AddLine(it.raid and "Raid" or ("Level " .. it.label), ns.LevelColor(it.color)) end
        if it.bossCount > 0 then GameTooltip:AddLine(format("%d bosses", it.bossCount), 0.8, 0.8, 0.8) end
        if self.hit then GameTooltip:AddLine("Boss: " .. self.hit, 0.5, 0.8, 1) end
        if it.preview then GameTooltip:AddLine("Preview map: boss positions are not known yet", 0.75, 0.75, 0.75, true) end
        GameTooltip:AddLine("Click to open the map", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self)
        for _, t in ipairs(self.edge) do t:Hide() end
        GameTooltip:Hide()
    end)
    c:SetScript("OnClick", function(self)
        if self.it then ns.JournalOpen(self.it.id) end
    end)
    return c
end

local function setTab(key)
    tab = key
    if frame then ns.RefreshJournal() end
end

local function build()
    frame = CreateFrame("Frame", "DungeonMapJournal", WorldMapFrame)
    local c = WorldMapFrame.ScrollContainer or WorldMapFrame
    frame:SetPoint("TOPLEFT", c, "TOPLEFT")
    frame:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT")
    frame:SetFrameStrata(WorldMapFrame:GetFrameStrata())
    frame:SetFrameLevel(_G.OpenMapAPI and ns.OPENMAP_LEVEL or (WorldMapFrame:GetFrameLevel() + 3000)) -- (over OpenMap's frames when it is loaded)
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.06, 0.05, 0.03, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.title:SetPoint("TOPLEFT", 18, -12)
    frame.title:SetText("Dungeons and Raids")
    frame.tabs = {}
    for i, def in ipairs({ { "dungeons", "Dungeons" }, { "raids", "Raids" } }) do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(96, 24)
        b.key = def[1]
        b:SetText(def[2])
        b:SetScript("OnClick", function(self) setTab(self.key) end)
        frame.tabs[i] = b
    end
    frame.tabs[1]:SetPoint("LEFT", frame.title, "RIGHT", 24, 0)
    frame.tabs[2]:SetPoint("LEFT", frame.tabs[1], "RIGHT", 4, 0)

    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(210, 24)
    box:SetPoint("TOPRIGHT", -22, -11)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box:SetScript("OnTextChanged", function(self)
        if frame:IsShown() then ns.RefreshJournal() end
    end)
    box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.search = box
    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.hint:SetPoint("LEFT", box, "LEFT", 6, 0)
    frame.hint:SetText("Search dungeons and bosses")
    box:SetScript("OnEditFocusGained", function() frame.hint:Hide() end)
    box:SetScript("OnEditFocusLost", function(self) frame.hint:SetShown(self:GetText() == "") end)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 14, -HEADER_H - 8)
    frame.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(10, 10)
    frame.scroll:SetScrollChild(frame.content)
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOP", frame.scroll, "TOP", 0, -40)
    frame.empty:SetText("Nothing matches.")
    frame.empty:Hide()

    frame:SetScript("OnSizeChanged", function() if frame:IsShown() then ns.RefreshJournal() end end)
    frame:SetScript("OnHide", function()
        GameTooltip:Hide()
        if frame.keepButtons then frame.keepButtons = nil return end -- (a dungeon view takes over: OpenMap's buttons stay off)
        if not (ns.ViewShown and ns.ViewShown()) and ns.OpenMapRestoreButtons then ns.OpenMapRestoreButtons() end
    end)
    frame:Hide()
end

local function head(i, parent)
    local h = heads[i]
    if not h then
        h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        h:SetTextColor(1, 0.82, 0)
        heads[i] = h
    end
    return h
end

function ns.RefreshJournal()
    if not frame then return end
    local q = ns.NormName(frame.search:GetText())
    local searching = q ~= ""
    for _, b in ipairs(frame.tabs) do b:SetEnabled(searching or b.key ~= tab) end

    local entries, shown = buildEntries(), {}
    for _, it in ipairs(entries) do
        local ok, hit = matches(it, q)
        local want = searching or ((tab == "raids") == (it.raid == true))
        if ok and want then shown[#shown + 1] = { it = it, hit = hit and bossNamed(it, hit) or nil } end
    end

    local W = math.max(120, frame.scroll:GetWidth() - 4)
    local cols = math.max(1, math.floor((W + GAP) / (MIN_CARD + GAP)))
    local cw = math.floor((W - (cols - 1) * GAP) / cols)
    local ch = math.floor(cw / 2)
    local strip = math.max(26, math.floor(ch * 0.2))
    frame.content:SetWidth(W)

    local y, col, ci, hi = 0, 0, 0, 0
    local function endRow()
        if col > 0 then y = y + ch + GAP; col = 0 end
    end
    local function header(text)
        endRow()
        hi = hi + 1
        local h = head(hi, frame.content)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 2, -(y + 4))
        h:SetText(text)
        h:Show()
        y = y + BAND_H + 4
    end

    local lastBand
    for _, s in ipairs(shown) do
        local it = s.it
        local band
        if searching then
            band = it.raid and "Raids" or "Dungeons"
        elseif it.raid then
            band = nil
        elseif it.lo then
            local b = math.floor(it.lo / 10) * 10
            band = b >= 60 and "Level 60" or format("Levels %d-%d", b, b + 9)
        else
            band = "Level unknown"
        end
        if band and band ~= lastBand then header(band) end
        lastBand = band
        ci = ci + 1
        local card = cards[ci]
        if not card then card = newCard(frame.content); cards[ci] = card end
        card.it, card.hit = it, s.hit
        card:SetSize(cw, ch)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame.content, "TOPLEFT", col * (cw + GAP), -y)
        local j = ns.Journal and ns.Journal[it.id]
        if j and j.art then
            local crop = CROP[j.kind] or CROP.new
            card.art:SetTexture(j.art)
            card.art:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
        else
            card.art:SetColorTexture(0.15, 0.12, 0.08, 1) -- no loading screen known: a plain card
        end
        card.shade:SetHeight(strip)
        card.name:SetText(it.name)
        card.name:SetTextColor(1, 1, 1)
        card.level:SetText(it.label)
        if it.raid then card.level:SetTextColor(0.9, 0.55, 0.2) else card.level:SetTextColor(ns.LevelColor(it.color)) end
        card.tag:SetText(it.isNew and "|cffffd100New|r" or "")
        card.tag:SetShown(it.isNew)
        card.tagBg:SetShown(it.isNew)
        local note = it.status == "classic" and "Classic data" or (it.preview and "Preview map" or nil)
        card.note:SetText(note or "")
        card.note:SetTextColor(0.8, 0.8, 0.8)
        card.note:SetShown(note ~= nil)
        card.noteBg:SetShown(note ~= nil)
        card:Show()
        col = col + 1
        if col >= cols then endRow() end
    end
    endRow()
    for i = ci + 1, #cards do cards[i]:Hide() end
    for i = hi + 1, #heads do heads[i]:Hide() end
    frame.content:SetHeight(math.max(y, 10))
    frame.empty:SetShown(#shown == 0)
end

function ns.JournalShown() return frame and frame:IsShown() or false end

function ns.HideJournal(keepButtons)
    if not frame then return end
    if keepButtons and frame:IsShown() then frame.keepButtons = true end
    frame:Hide()
end

-- Show the journal over the world map (opening the map if needed). The dungeon view, if it was up, is closed; it comes back through a card.
function ns.ShowJournal()
    if not WorldMapFrame then return end
    if ns.EndRouteDrawing then ns.EndRouteDrawing() end
    if ns.editing and ns.ToggleEdit then ns.ToggleEdit() end
    if not frame then build() end
    ns.HideView()
    if not WorldMapFrame:IsShown() then
        ns.internalNav = true
        pcall(ToggleWorldMap)
        ns.internalNav = false
    end
    ns.journalMapID = WorldMapFrame:GetMapID()
    frame:Show()
    if ns.OpenMapHideButtons then ns.OpenMapHideButtons() end
    ns.RefreshJournal()
    -- (layout settles a frame later: the scroll area has its size then)
    C_Timer.After(0.05, function() if frame:IsShown() then ns.RefreshJournal() end end)
end

function ns.ToggleJournal()
    if ns.JournalShown() then
        if WorldMapFrame then WorldMapFrame:Hide() end
    else
        ns.ShowJournal()
    end
end

-- A card was chosen: close the journal, open that dungeon's map (the dungeon picker and entrance pins use the same call).
function ns.JournalOpen(instanceID)
    ns.HideJournal(true)
    ns.ShowInstance(instanceID, nil, true)
end
