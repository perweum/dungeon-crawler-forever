-- DungeonMap Probe: records what the Forever client exposes. Run /dmprobe (town, then inside a dungeon).
-- Output: DungeonMapProbeDB[<timestamp>] in WTF/Account/<ACCOUNT>/SavedVariables/DungeonMapProbe.lua (written on /reload or logout).

local function try(fn, ...)
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return { error = tostring(a) } end
    return { a, b, c, d, e }
end

local function plain(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "table" then
        if depth > 3 then return "<deep>" end
        local out, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 60 then out["..."] = "truncated"; break end
            out[tostring(k)] = plain(x, depth + 1)
        end
        return out
    elseif t == "userdata" or t == "function" then
        return "<" .. t .. ">"
    elseif t == "number" or t == "string" or t == "boolean" or t == "nil" then
        if issecretvalue and issecretvalue(v) then return "<secret>" end
        return v
    end
    return tostring(v)
end

local function exists(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return false end
        cur = cur[part]
        if cur == nil then return false end
    end
    return true
end

local APIS = {
    "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetMapArtID", "C_Map.GetMapArtLayers",
    "C_Map.GetMapArtLayerTextures", "C_Map.GetMapGroupID", "C_Map.GetMapGroupMembersInfo",
    "C_Map.GetMapChildrenInfo", "C_Map.GetPlayerMapPosition", "C_Map.GetMapRectOnMap",
    "C_EncounterJournal.GetEncountersOnMap", "C_EncounterJournal.GetDungeonEntrancesForMap",
    "C_EncounterJournal.GetSectionInfo", "C_EncounterJournal.GetEncounterJournalLinkDetails",
    "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex", "EJ_SelectInstance", "EJ_GetInstanceInfo",
    "EJ_GetEncounterInfoByIndex", "EJ_SelectEncounter", "EJ_GetNumLoot", "EJ_GetLootInfoByIndex",
    "EJ_GetCreatureInfo", "EJ_GetInstanceForMap", "C_Texture.GetAtlasInfo", "C_Spell.GetSpellInfo",
    "C_Item.GetItemInfo", "GetSavedInstanceInfo", "GetNumSavedInstances", "GetInstanceInfo",
    "C_AddOns.GetAddOnMetadata", "C_PlayerInfo", "C_Minimap", "AddonCompartmentFrame",
    "WorldMapFrame", "EncounterJournal", "Enum.UIMapType", "WOW_PROJECT_CAMELOT", "LE_EXPANSION_LEVEL_CURRENT",
    "C_ChallengeMode", "C_PartyInfo.GetActiveCategories", "C_SavedInstances",
}

local function snapshot(label)
    local s = { label = label, time = date("%Y-%m-%d %H:%M:%S") }
    s.build = { GetBuildInfo() }
    s.project = { id = WOW_PROJECT_ID, camelot = WOW_PROJECT_CAMELOT, expansion = LE_EXPANSION_LEVEL_CURRENT }

    s.apis = {}
    for _, p in ipairs(APIS) do s.apis[p] = exists(p) end

    s.instance = plain(try(GetInstanceInfo))
    do
        local n, t, d, dn, mp, dd, ds, instID, ls, lfg = GetInstanceInfo()
        s.instanceFull = { name = n, type = t, diffID = d, maxPlayers = mp, instanceID = instID, lfgDungeonID = lfg }
        s.isInInstance = { IsInInstance() }
        s.unitPosition = plain(try(UnitPosition, "player"))   -- y, x, z, instanceMapID (world coords)
        s.facing = GetPlayerFacing and GetPlayerFacing() or nil
        s.minimapZoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or nil
    end
    s.zone = { zone = GetZoneText(), sub = GetSubZoneText(), real = GetRealZoneText() }

    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        s.mapID = mapID
        if mapID then
            s.mapInfo = plain(try(C_Map.GetMapInfo, mapID))
            s.artID = plain(try(C_Map.GetMapArtID, mapID))
            s.artLayers = plain(try(C_Map.GetMapArtLayers, mapID))
            s.artLayerTextures = plain(try(C_Map.GetMapArtLayerTextures, mapID, 1))
            s.groupID = plain(try(C_Map.GetMapGroupID, mapID))
            local g = C_Map.GetMapGroupID and C_Map.GetMapGroupID(mapID)
            if g then s.groupMembers = plain(try(C_Map.GetMapGroupMembersInfo, g)) end
            s.playerPos = plain(try(function()
                local p = C_Map.GetPlayerMapPosition(mapID, "player")
                if p then return p.x, p.y end
            end))
            if C_EncounterJournal then
                s.encountersOnMap = plain(try(C_EncounterJournal.GetEncountersOnMap, mapID))
                s.entrancesOnMap = plain(try(C_EncounterJournal.GetDungeonEntrancesForMap, mapID))
            end
            s.ejInstanceForMap = plain(try(EJ_GetInstanceForMap or function() end, mapID))
        end
    end

    -- Encounter Journal inventory: every tier, every dungeon+raid, with encounters
    if EJ_GetNumTiers then
        s.ej = {}
        local ok, err = pcall(function()
            for tier = 1, EJ_GetNumTiers() do
                EJ_SelectTier(tier)
                local tierEntry = { tier = tier, instances = {} }
                for _, isRaid in ipairs({ false, true }) do
                    local i = 1
                    while true do
                        local id, name, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceByIndex(i, isRaid)
                        if not id then break end
                        local inst = { id = id, name = name, raid = isRaid, uiMapID = mapID, encounters = {} }
                        EJ_SelectInstance(id)
                        local e = 1
                        while true do
                            local ename, _, eid = EJ_GetEncounterInfoByIndex(e)
                            if not ename then break end
                            inst.encounters[#inst.encounters + 1] = { eid, ename }
                            e = e + 1
                        end
                        tierEntry.instances[#tierEntry.instances + 1] = inst
                        i = i + 1
                        if i > 80 then break end
                    end
                end
                s.ej[#s.ej + 1] = tierEntry
            end
        end)
        if not ok then s.ejError = tostring(err) end
    end

    -- Candidate atlases for native look (existence only)
    s.atlases = {}
    if C_Texture and C_Texture.GetAtlasInfo then
        for _, a in ipairs({
            "Dungeon", "Raid", "DungeonSkull", "Skull", "poi-skull", "poi-door", "poi-door-arrow-up",
            "poi-door-arrow-down", "UI-HUD-Minimap-Arrow", "Warfronts-BaseMapIcons-Empty-Barracks-Minimap",
            "dungeon", "worldquest-icon-dungeon", "Vehicle-Ally-Barrel", "MiniMap-DeadArrow", "groupfinder-icon-class-warrior",
            "Garr_Building-AddFollowerPlus", "common-icon-checkmark", "UI-EJ-BOSS-Default",
        }) do
            s.atlases[a] = C_Texture.GetAtlasInfo(a) ~= nil
        end
    end
    return s
end

local function run(label)
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    local snap = snapshot(label or "manual")
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = snap
    do
        local u = snap.unitPosition or {}
        print(string.format("|cff66ccffProbe|r instanceID=%s zone='%s' sub='%s' UnitPosition y=%s x=%s z=%s map=%s facing=%s",
            tostring(snap.instanceFull and snap.instanceFull.instanceID), tostring(GetRealZoneText()), tostring(GetSubZoneText()),
            tostring(u["1"]), tostring(u["2"]), tostring(u["3"]), tostring(u["4"]), tostring(snap.facing)))
    end
    print("|cff66ccffDungeonMapProbe|r snapshot #" .. #DungeonMapProbeDB .. " saved (" ..
        (snap.instance and snap.instance[1] or "?") .. ", mapID=" .. tostring(snap.mapID) ..
        "). Type /reload to flush to disk.")
end

-- Tile viewer: draws a retail dungeon map (Ragefire Chasm, UiMapArtID 224, 4x3 tiles of 256px) from
-- client FileDataIDs. If you see the map, the Forever client contains retail dungeon art and we can
-- reference it by fileID instead of shipping images.
local RFC_TILES = {{449736,449740,449741,449742},{449743,449744,449745,449746},{449747,449737,449738,449739}}
local viewer
local function showTiles()
    local justCreated = not viewer
    if not viewer then
        viewer = CreateFrame("Frame", "DungeonMapProbeViewer", UIParent, "BackdropTemplate")
        viewer:SetSize(1040, 790)
        viewer:SetScale(math.min(1, (UIParent:GetHeight() - 40) / 790))
        viewer:SetPoint("CENTER")
        viewer:SetFrameStrata("DIALOG")
        viewer:SetMovable(true); viewer:EnableMouse(true)
        viewer:RegisterForDrag("LeftButton")
        viewer:SetScript("OnDragStart", viewer.StartMoving)
        viewer:SetScript("OnDragStop", viewer.StopMovingOrSizing)
        local bg = viewer:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        for r, row in ipairs(RFC_TILES) do
            for c, fid in ipairs(row) do
                local t = viewer:CreateTexture(nil, "ARTWORK")
                t:SetSize(256, 256)
                t:SetPoint("TOPLEFT", 8 + (c - 1) * 256, -8 - (r - 1) * 256)
                t:SetTexture(fid)
            end
        end
        local close = CreateFrame("Button", nil, viewer, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT")
        local fs = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("BOTTOM", 0, 8); fs:SetText("DungeonMapProbe: Ragefire Chasm tiles by fileID (drag to move)")
    end
    if justCreated then viewer:Show() else viewer:SetShown(not viewer:IsShown()) end
    print("|cff66ccffProbe|r tile viewer shown=" .. tostring(viewer:IsShown()))
end

-- /dmprobe new : draws sample minimap files of the Forever-new dungeons (terrain tile, WMO tile, loading screen)
-- /dmprobe fid <id> [id...] : draws arbitrary FileDataIDs side by side.
local fidFrame
local function showFiles(ids)
    if not fidFrame then
        fidFrame = CreateFrame("Frame", "DungeonMapProbeFiles", UIParent)
        fidFrame:SetFrameStrata("DIALOG")
        fidFrame:SetMovable(true); fidFrame:EnableMouse(true); fidFrame:RegisterForDrag("LeftButton")
        fidFrame:SetScript("OnDragStart", fidFrame.StartMoving)
        fidFrame:SetScript("OnDragStop", fidFrame.StopMovingOrSizing)
        fidFrame.bg = fidFrame:CreateTexture(nil, "BACKGROUND"); fidFrame.bg:SetAllPoints(); fidFrame.bg:SetColorTexture(0.1, 0.1, 0.1, 0.92)
        local close = CreateFrame("Button", nil, fidFrame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT")
        fidFrame.items = {}
    end
    for _, it in ipairs(fidFrame.items) do it.tex:Hide(); it.label:Hide() end
    local n = #ids
    local size = 300
    fidFrame:SetSize(n * (size + 10) + 10, size + 50)
    fidFrame:SetPoint("CENTER")
    for i, id in ipairs(ids) do
        local it = fidFrame.items[i]
        if not it then
            it = { tex = fidFrame:CreateTexture(nil, "ARTWORK"), label = fidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") }
            fidFrame.items[i] = it
        end
        it.tex:ClearAllPoints(); it.tex:SetSize(size, size)
        it.tex:SetPoint("TOPLEFT", 10 + (i - 1) * (size + 10), -30)
        it.tex:SetTexture(id); it.tex:Show()
        local path = C_Texture and C_Texture.GetFilePathFromFileID and C_Texture.GetFilePathFromFileID(id)
        it.label:ClearAllPoints(); it.label:SetPoint("BOTTOMLEFT", it.tex, "TOPLEFT", 0, 2)
        it.label:SetText(tostring(id) .. (path and (" " .. path) or "")); it.label:Show()
        print("|cff66ccffProbe|r fileID " .. id .. " path=" .. tostring(path))
    end
    fidFrame:Show()
end

-- /dmprobe model : target any creature, then run. Tries every way we know to identify/render its portrait and
-- shows three live previews: (1) 3D model via SetUnit, (2) 2D portrait texture via SetPortraitTexture, (3) SetCreature(npcID).
local modelWin
-- /dmprobe atlas <word> [word...]: list every atlas name containing any of the words (case-insensitive) into DungeonMapProbeDB (label "atlas").
local function atlasProbe(arg)
    local words = {}
    for w in arg:lower():gmatch("%S+") do words[#words + 1] = w end
    local getAll = C_Texture and C_Texture.GetAtlasElements
    if not getAll then print("|cffff4444C_Texture.GetAtlasElements is not available on this build.|r") return end
    local ok, all = pcall(getAll)
    if not ok or type(all) ~= "table" then print("|cffff4444GetAtlasElements failed: " .. tostring(all) .. "|r") return end
    local hits = {}
    for _, name in ipairs(all) do
        local l = tostring(name):lower()
        for _, w in ipairs(words) do
            if l:find(w, 1, true) then
                local info = C_Texture.GetAtlasInfo(name)
                hits[#hits + 1] = format("%s  [%s x %s, file %s]", name, info and info.width or "?", info and info.height or "?", info and tostring(info.file or info.filename) or "?")
                break
            end
        end
    end
    table.sort(hits)
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "atlas", query = arg, total = #all, hits = hits }
    print(format("|cff66ccffDungeonMapProbe|r atlas '%s': %d of %d atlases match. /reload to write them to the saved variables.", arg, #hits, #all))
    for i = 1, math.min(#hits, 15) do print("  " .. hits[i]) end
end

-- /dmprobe bronze: preview the heavybronze frame atlases (background, sliced frame, corner brackets, fades) and write every atlas
-- that lives in the same texture files to DungeonMapProbeDB (label "bronze").
local function bronzeProbe()
    local files, names = { [8203427] = true, [8216846] = true }, {}
    local ok, all = pcall(C_Texture.GetAtlasElements)
    if ok and type(all) == "table" then
        for _, n in ipairs(all) do
            local info = C_Texture.GetAtlasInfo(n)
            local f = info and (info.file or info.filename)
            if (f and files[f]) or tostring(n):lower():find("heavybronze", 1, true) then
                names[#names + 1] = format("%s [%s x %s, file %s]", n, info and info.width or "?", info and info.height or "?", tostring(f))
            end
        end
    end
    table.sort(names)
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "bronze", names = names }
    print(format("|cff66ccffDungeonMapProbe|r bronze: %d atlases in the heavybronze texture files (written on /reload).", #names))
    if DMProbeBronze then DMProbeBronze:Show() return end
    local f = CreateFrame("Frame", "DMProbeBronze", UIParent)
    f:SetSize(900, 560); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.06, 1)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local function tex(atlas, w, h, x, y, label, layer)
        local t = f:CreateTexture(nil, layer or "ARTWORK"); t:SetAtlas(atlas); t:SetSize(w, h); t:SetPoint("TOPLEFT", x, -y)
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2); l:SetText(label)
        return t
    end
    -- 1) panel: background atlas + sliced frame (margins guessed: 24)
    local panel = CreateFrame("Frame", nil, f); panel:SetSize(420, 300); panel:SetPoint("TOPLEFT", 20, -40)
    local pbg = panel:CreateTexture(nil, "BACKGROUND"); pbg:SetAtlas("heavybronze-frame-background"); pbg:SetPoint("TOPLEFT", 6, -6); pbg:SetPoint("BOTTOMRIGHT", -6, 6)
    local fr = panel:CreateTexture(nil, "BORDER"); fr:SetAtlas("heavybronze-frame-basic"); fr:SetAllPoints()
    local okS = pcall(function() fr:SetTextureSliceMargins(24, 24, 24, 24); fr:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end)
    local pl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); pl:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4)
    pl:SetText("background + frame-basic, slice margins 24 (" .. (okS and "slicing ok" or "slicing FAILED") .. ")")
    -- 2) the same frame with 16 and 32 margins, small
    for i, m in ipairs({ 16, 32 }) do
        local p2 = CreateFrame("Frame", nil, f); p2:SetSize(200, 140); p2:SetPoint("TOPLEFT", 460 + (i - 1) * 220, -40)
        local t2 = p2:CreateTexture(nil, "BORDER"); t2:SetAtlas("heavybronze-frame-basic"); t2:SetAllPoints()
        pcall(function() t2:SetTextureSliceMargins(m, m, m, m); t2:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end)
        local l2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l2:SetPoint("TOPLEFT", p2, "BOTTOMLEFT", 0, -2); l2:SetText("frame-basic, margins " .. m)
    end
    -- 3) corner brackets and fades
    local x = 460
    for _, k in ipairs({ "horz-cornerbracket-TL", "horz-cornerbracket-TR", "horz-cornerbracket-BL", "horz-cornerbracket-BR",
                         "vert-cornerbracket-TL", "vert-cornerbracket-TR", "vert-cornerbracket-BL", "vert-cornerbracket-BR" }) do
        tex("heavybronze-" .. k, 32, 32, x, 240, (k:gsub("cornerbracket", "cb")))
        x = x + 54; if x > 840 then x = 460 end
    end
    tex("heavybronze-frame-top-fade", 192, 96, 460, 340, "top-fade")
    tex("heavybronze-frame-bottom-fade", 192, 96, 680, 340, "bottom-fade")
end

-- /dmprobe frames: preview the game's own frame templates (their Forever skin) and save atlas names for headers/plaques/rows.
local function framesProbe()
    local words = { "category", "header", "stat", "section", "plaque", "titlebar", "listheader", "innerframe", "inset", "panel-background",
        "frame-inner", "tabletop", "row", "stripe" }
    local hits = {}
    local ok, all = pcall(C_Texture.GetAtlasElements)
    if ok and type(all) == "table" then
        for _, n in ipairs(all) do
            local l = tostring(n):lower()
            for _, w in ipairs(words) do
                if l:find(w, 1, true) then
                    local info = C_Texture.GetAtlasInfo(n)
                    hits[#hits + 1] = format("%s [%s x %s, file %s]", n, info and info.width or "?", info and info.height or "?", info and tostring(info.file or info.filename) or "?")
                    break
                end
            end
        end
    end
    table.sort(hits)
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "frames", atlases = hits }
    print(format("|cff66ccffDungeonMapProbe|r frames: %d atlases saved (on /reload); preview window opened.", #hits))
    if DMProbeFrames then DMProbeFrames:Show() return end
    local f = CreateFrame("Frame", "DMProbeFrames", UIParent)
    f:SetSize(1000, 640); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.12, 0.12, 0.14, 1)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local templates = { "InsetFrameTemplate", "InsetFrameTemplate2", "InsetFrameTemplate3", "InsetFrameTemplate4", "ThinBorderTemplate",
        "TooltipBorderBackdropTemplate", "DialogBorderTemplate", "DialogBorderDarkTemplate", "DialogBorderOpaqueTemplate",
        "BasicFrameTemplate", "ButtonFrameTemplate", "PortraitFrameTemplate", "SimplePanelTemplate", "FlatPanelBackgroundTemplate",
        "BackdropTemplate", "ListHeaderThreeSliceTemplate" }
    for i, t in ipairs(templates) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local x, y = 14 + col * 245, -34 - row * 150
        local ok2, fr = pcall(CreateFrame, "Frame", nil, f, t)
        if not ok2 or not fr then
            local l = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); l:SetPoint("TOPLEFT", x, y); l:SetText(t .. ": not available")
        else
            fr:SetSize(225, 110); fr:SetPoint("TOPLEFT", x, y)
            if fr.SetBackdrop and t == "BackdropTemplate" then
                fr:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
            end
            local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l:SetPoint("TOPLEFT", fr, "BOTTOMLEFT", 0, -2); l:SetText(t)
        end
    end
end

-- /dmprobe lfg: read the game's own dungeon-finder data (name, min/max/recommended levels, map) for every dungeon id into
-- DungeonMapProbeDB (label "lfg"). These are the levels Forever itself uses, so they are the reference for the addon's level ranges.
local function lfgProbe()
    local rows = {}
    for id = 1, 3000 do
        local ok, name, typeID, subtype, minL, maxL, recL, minRec, maxRec, expansion, groupID, tex, difficulty, maxPlayers, desc, isHoliday,
              bonus, minPlayers, isTimewalker, name2, minGear, isScaling, mapID = pcall(GetLFGDungeonInfo, id)
        if ok and name and name ~= "" then
            rows[#rows + 1] = format("%d|%s|type %s|min %s|max %s|rec %s|recMin %s|recMax %s|exp %s|players %s|map %s", id, tostring(name),
                tostring(typeID), tostring(minL), tostring(maxL), tostring(recL), tostring(minRec), tostring(maxRec), tostring(expansion),
                tostring(maxPlayers), tostring(mapID))
        end
    end
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "lfg", rows = rows }
    print(format("|cff66ccffDungeonMapProbe|r lfg: %d dungeon-finder entries read (written on /reload).", #rows))
    for i = 1, math.min(#rows, 6) do print("  " .. rows[i]) end
end

-- /dmprobe icons [words]: a scrollable window with every game atlas whose name contains one of the words (default: stairs, ladders,
-- doors, arrows ...), drawn as small icons. Hover for the atlas name, click to print it in chat. Names are also saved (label "icons").
local function iconsProbe(arg)
    local words = {}
    for w in (arg ~= "" and arg or "stair ladder elevator door arrow updown up-arrow down-arrow goto poi-"):lower():gmatch("%S+") do words[#words + 1] = w end
    local ok, all = pcall(C_Texture.GetAtlasElements)
    if not ok or type(all) ~= "table" then print("|cffff4444GetAtlasElements is not available|r") return end
    local hits = {}
    for _, name in ipairs(all) do
        local l = tostring(name):lower()
        for _, w in ipairs(words) do
            if l:find(w, 1, true) then hits[#hits + 1] = name break end
        end
    end
    table.sort(hits)
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "icons", query = arg, names = hits }
    print(format("|cff66ccffDungeonMapProbe|r icons: %d atlases match. Hover for the name, click to print it.", #hits))
    if DMProbeIcons then DMProbeIcons:Hide(); DMProbeIcons = nil end
    local f = CreateFrame("Frame", "DMProbeIcons", UIParent)
    f:SetSize(900, 640); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.55, 0.45, 0.3, 1)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(format("%d atlases matching: %s   (drag to move; scroll)", #hits, table.concat(words, ", ")))
    local sc = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 10, -34); sc:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, sc); content:SetSize(850, 10); sc:SetScrollChild(content)
    local size, gap, cols = 48, 8, 14
    for i, name in ipairs(hits) do
        local b = CreateFrame("Button", nil, content)
        b:SetSize(size, size)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetPoint("TOPLEFT", col * (size + gap), -row * (size + gap))
        local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints()
        pcall(t.SetAtlas, t, name)
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(name); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function() print("|cff66ccffatlas:|r " .. name) end)
    end
    content:SetHeight(math.ceil(#hits / cols) * (size + gap) + 10)
end

-- /dmprobe quests [uiMapID ...]: what does the game itself know about quests? Dumps (label "quests"): which quest APIs exist, which quest pin
-- types the world map has, quest givers / offers / questlines the client reports for the given maps (default: the map open now and the
-- player's map), and tags / titles / completion for some sample quest ids. Open the world map on a dungeon entrance or stand inside a dungeon first.
local function questsProbe(arg)
    -- every section runs on its own (pcall) and the result is stored first, so a failure in one part loses nothing else
    local out = { apis = {}, pins = {}, providers = {}, maps = {}, samples = {}, errors = {} }
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "quests", result = out }
    local function try(name, fn)
        local ok, err = pcall(fn)
        if not ok then out.errors[name] = tostring(err) print("|cffff8844quests section '" .. name .. "' failed:|r " .. tostring(err)) end
    end
    local function safe(f, ...) local ok, r = pcall(f, ...) if ok then return r end return "ERR: " .. tostring(r) end
    local function brief(v, depth)
        depth = depth or 0
        if type(v) ~= "table" then return (issecretvalue and issecretvalue(v)) and "<secret>" or tostring(v) end
        if depth > 2 then return "{...}" end
        local parts = {}
        for k, x in pairs(v) do if #parts < 14 then parts[#parts + 1] = tostring(k) .. "=" .. brief(x, depth + 1) end end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    try("apis", function()
        for _, tname in ipairs({ "C_QuestLog", "C_QuestLine", "C_QuestOffer", "C_QuestInfoSystem", "C_GossipInfo", "C_TaskQuest", "C_AreaPoiInfo", "C_Map" }) do
            local t = _G[tname]
            local names = {}
            if type(t) == "table" then for k, v in pairs(t) do if type(v) == "function" then names[#names + 1] = tostring(k) end end end
            table.sort(names)
            out.apis[tname] = type(t) == "table" and names or "missing"
        end
    end)
    try("pins", function()
        local wm = WorldMapFrame
        if wm and wm.pinPools then for k in pairs(wm.pinPools) do out.pins[#out.pins + 1] = tostring(k) end table.sort(out.pins) end
    end)
    try("providers", function()
        local wm = WorldMapFrame
        if wm and wm.dataProviders then
            for dp in pairs(wm.dataProviders) do
                local nm = "?"
                pcall(function() nm = tostring((type(dp) == "table" and (dp.pinTemplate or dp.PIN_TEMPLATE or dp.template)) or dp) end)
                out.providers[#out.providers + 1] = nm
            end
            table.sort(out.providers)
        end
    end)
    local maps = {}
    for id in (arg or ""):gmatch("%d+") do maps[#maps + 1] = tonumber(id) end
    try("which maps", function()
        if #maps == 0 then
            if WorldMapFrame and WorldMapFrame.GetMapID then maps[#maps + 1] = WorldMapFrame:GetMapID() end
            local best = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            if best and best ~= maps[1] then maps[#maps + 1] = best end
        end
    end)
    local sampleIds = {}
    local function listOf(v, collect)
        if type(v) ~= "table" then return v end
        local l = {}
        for _, q in ipairs(v) do
            l[#l + 1] = brief(q)
            if collect and type(q) == "table" and q.questID then sampleIds[#sampleIds + 1] = q.questID end
        end
        return l
    end
    for _, mid in ipairs(maps) do
        local e = { map = mid }
        out.maps[#out.maps + 1] = e
        try("map name " .. mid, function() e.name = (C_Map.GetMapInfo(mid) or {}).name end)
        try("questsOnMap " .. mid, function() if C_QuestLog and C_QuestLog.GetQuestsOnMap then e.questsOnMap = listOf(safe(C_QuestLog.GetQuestsOnMap, mid), true) else e.questsOnMap = "no such API" end end)
        try("questLines " .. mid, function() if C_QuestLine and C_QuestLine.GetAvailableQuestLines then e.availableQuestLines = listOf(safe(C_QuestLine.GetAvailableQuestLines, mid), true) else e.availableQuestLines = "no such API" end end)
        try("questOffers " .. mid, function() if C_QuestOffer and C_QuestOffer.GetQuestOffersForMap then e.questOffers = listOf(safe(C_QuestOffer.GetQuestOffersForMap, mid), true) else e.questOffers = "no such API" end end)
        try("areaPois " .. mid, function() if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap then local ids = safe(C_AreaPoiInfo.GetAreaPOIForMap, mid) e.areaPois = type(ids) == "table" and #ids or ids else e.areaPois = "no such API" end end)
    end
    try("samples", function()
        for _, id in ipairs({ 5722, 5723, 5724, 5725, 5728, 5761, 5505, 5511, 3802, 166, 7761, 7848, 1013, 99999 }) do sampleIds[#sampleIds + 1] = id end -- the six Ragefire Chasm quests first
        local seen = {}
        for _, id in ipairs(sampleIds) do
            if not seen[id] then
                seen[id] = true
                local row = { id = id }
                if C_QuestLog then
                    if C_QuestLog.GetQuestTagInfo then row.tag = brief(safe(C_QuestLog.GetQuestTagInfo, id)) end
                    if C_QuestLog.IsQuestFlaggedCompleted then row.completed = safe(C_QuestLog.IsQuestFlaggedCompleted, id) end
                    if C_QuestLog.IsOnQuest then row.onQuest = safe(C_QuestLog.IsOnQuest, id) end
                    if C_QuestLog.GetTitleForQuestID then row.title = safe(C_QuestLog.GetTitleForQuestID, id) end
                end
                out.samples[#out.samples + 1] = row
            end
        end
    end)
    local counts = {}
    for t, v in pairs(out.apis) do counts[#counts + 1] = t .. "=" .. (type(v) == "table" and #v or tostring(v)) end
    table.sort(counts)
    local nerr = 0 for _ in pairs(out.errors) do nerr = nerr + 1 end
    print("|cff66ccffDungeonMapProbe|r quests: saved (" .. table.concat(counts, ", ") .. "); " .. #out.pins .. " map pin types, " .. #out.maps .. " map(s), " .. nerr .. " section error(s). /reload to write it to disk.")
    for _, e in ipairs(out.maps) do
        print(format("  map %s (%s): questsOnMap %s, quest lines %s, offers %s", tostring(e.map), tostring(e.name),
            type(e.questsOnMap) == "table" and #e.questsOnMap or tostring(e.questsOnMap), type(e.availableQuestLines) == "table" and #e.availableQuestLines or tostring(e.availableQuestLines),
            type(e.questOffers) == "table" and #e.questOffers or tostring(e.questOffers)))
    end
end

-- /dmprobe qscan: asks the game about every quest id in the Forever client list (QuestIDs.lua): tag, and for tagged quests the title and completion.
-- Result (label "qscan"): counts per tag, and every quest tagged Dungeon / Raid / Group etc. with its title. Runs in slices so the game does not freeze.
local function qscanProbe()
    local ids = DM_PROBE_QUESTIDS
    if not (ids and C_QuestLog and C_QuestLog.GetQuestTagInfo) then print("|cffff4444qscan: no id list or no GetQuestTagInfo|r") return end
    local res = { total = #ids, tagged = 0, byTag = {}, quests = {}, noTag = 0, errors = 0 }
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "qscan", result = res }
    local i, SLICE = 1, 250
    print(format("|cff66ccffDungeonMapProbe|r qscan: scanning %d quest ids ...", #ids))
    local function step()
        local last = math.min(#ids, i + SLICE - 1)
        for k = i, last do
            local id = ids[k]
            local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, id)
            if not ok then res.errors = res.errors + 1
            elseif type(tag) == "table" then
                res.tagged = res.tagged + 1
                local tname = tostring(tag.tagName or tag.tagID)
                res.byTag[tname] = (res.byTag[tname] or 0) + 1
                local okT, title = pcall(C_QuestLog.GetTitleForQuestID, id)
                local okC, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
                res.quests[#res.quests + 1] = format("%d|%s|%s|%s", id, tname, okT and tostring(title) or "?", okC and tostring(done) or "?")
            else
                res.noTag = res.noTag + 1
            end
        end
        i = last + 1
        if i <= #ids then
            C_Timer.After(0.05, step)
        else
            local parts = {}
            for t, n in pairs(res.byTag) do parts[#parts + 1] = t .. "=" .. n end
            table.sort(parts)
            print(format("|cff66ccffDungeonMapProbe|r qscan done: %d tagged of %d (%s), %d without a tag, %d errors. /reload to write it to disk.", res.tagged, res.total, table.concat(parts, ", "), res.noTag, res.errors))
        end
    end
    step()
end

local function probeModel()
    local out = { time = date("%Y-%m-%d %H:%M:%S"), hasTarget = UnitExists("target") and true or false }
    if not out.hasTarget then print("|cff66ccffProbe|r target a creature first.") return end
    local guid = UnitGUID("target")
    out.guidSecret = issecretvalue and issecretvalue(guid) or false
    if not out.guidSecret and type(guid) == "string" then
        out.guid = guid
        local kind, _, _, _, _, npc = strsplit("-", guid)
        out.guidKind, out.npcID = kind, tonumber(npc)
    end
    out.api = {
        SetPortraitTextureFromCreatureDisplayID = SetPortraitTextureFromCreatureDisplayID ~= nil,
        SetPortraitTexture = SetPortraitTexture ~= nil,
        UnitCreatureID = UnitCreatureID ~= nil,
        UnitCreatureDisplayID = UnitCreatureDisplayID ~= nil,
        GetUnitCreatureDisplayID = GetUnitCreatureDisplayID ~= nil,
        C_CreatureInfo = C_CreatureInfo ~= nil,
    }
    if not modelWin then
        modelWin = CreateFrame("Frame", "DungeonMapProbeModel", UIParent)
        modelWin:SetSize(660, 250); modelWin:SetPoint("CENTER", 0, 200); modelWin:SetFrameStrata("DIALOG")
        modelWin:SetMovable(true); modelWin:EnableMouse(true); modelWin:RegisterForDrag("LeftButton")
        modelWin:SetScript("OnDragStart", modelWin.StartMoving); modelWin:SetScript("OnDragStop", modelWin.StopMovingOrSizing)
        local bg = modelWin:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        local close = CreateFrame("Button", nil, modelWin, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT")
        modelWin.m1 = CreateFrame("PlayerModel", nil, modelWin); modelWin.m1:SetSize(200, 200); modelWin.m1:SetPoint("TOPLEFT", 10, -30)
        modelWin.tex = modelWin:CreateTexture(nil, "ARTWORK"); modelWin.tex:SetSize(200, 200); modelWin.tex:SetPoint("TOPLEFT", 225, -30)
        modelWin.m3 = CreateFrame("PlayerModel", nil, modelWin); modelWin.m3:SetSize(200, 200); modelWin.m3:SetPoint("TOPLEFT", 440, -30)
        for i, label in ipairs({ "1: SetUnit(target)", "2: SetPortraitTexture", "3: SetCreature(npcID)" }) do
            local fs = modelWin:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fs:SetPoint("TOPLEFT", 10 + (i - 1) * 215, -10); fs:SetText(label)
        end
    end
    modelWin:Show()
    pcall(function() modelWin.m1:SetUnit("target") end)
    pcall(function() SetPortraitTexture(modelWin.tex, "target") end)
    if out.npcID then pcall(function() modelWin.m3:SetCreature(out.npcID) end) end
    C_Timer.After(1.0, function()
        out.methods, out.values = {}, {}
        for _, name in ipairs({ "GetDisplayInfo", "GetModelFileID", "GetModelPath", "GetModel", "GetDisplayID", "GetCreatureDisplayID", "GetCameraPosition" }) do
            out.methods[name] = modelWin.m1[name] ~= nil
            if modelWin.m1[name] then
                local ok, a, b = pcall(modelWin.m1[name], modelWin.m1)
                out.values[name] = ok and (tostring(a) .. (b ~= nil and (" / " .. tostring(b)) or "")) or ("error: " .. tostring(a))
            end
        end
        out.values.type = modelWin.m1:GetObjectType()
        out.values.m3_modelFileID = modelWin.m3.GetModelFileID and tostring(modelWin.m3:GetModelFileID()) or "n/a"
        DungeonMapProbeDB = DungeonMapProbeDB or {}
        DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "model", model = out }
        print("|cff66ccffProbe|r model probe saved. GUID secret=" .. tostring(out.guidSecret) .. " npcID=" .. tostring(out.npcID))
        for k, v in pairs(out.values) do print("   " .. k .. " = " .. v) end
    end)
end

-- /dmprobe cast on|off : while on, logs enemy spell casts (UNIT_SPELLCAST_* for target / boss1-5 / nameplates) and ENCOUNTER_START/END
-- into DungeonMapProbeDB (label "cast"), noting whether the spell ID is readable or a "secret value". Fight a boss, then /reload.
local castFrame, castLog
local function castEvent(_, event, unit, ...)
    if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        local id, name = unit, ...
        castLog[#castLog + 1] = { event = event, encounterID = (issecretvalue and issecretvalue(id)) and "<secret>" or id,
            name = (issecretvalue and issecretvalue(name)) and "<secret>" or name }
        print("|cff66ccffProbe|r " .. event .. " " .. tostring(castLog[#castLog].encounterID))
        return
    end
    if not unit or unit == "player" or tostring(unit):find("^party") or tostring(unit):find("^raid") then return end
    if #castLog > 300 then return end
    local castGUID, spellID = ...
    local rec = { event = event, unit = unit }
    rec.spellSecret = issecretvalue and issecretvalue(spellID) or false
    if not rec.spellSecret then rec.spellID = spellID end
    rec.unitName = (UnitName and not (issecretvalue and issecretvalue(UnitName(unit)))) and UnitName(unit) or "<secret/none>"
    rec.inCombat = InCombatLockdown() and true or false
    castLog[#castLog + 1] = rec
end
local function castProbe(arg)
    castFrame = castFrame or CreateFrame("Frame")
    if arg == "off" then
        castFrame:UnregisterAllEvents()
        DungeonMapProbeDB = DungeonMapProbeDB or {}
        DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "cast", cast = castLog or {} }
        print("|cff66ccffProbe|r cast logging off, " .. #(castLog or {}) .. " records saved. /reload to flush.")
        return
    end
    castLog = {}
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "ENCOUNTER_START", "ENCOUNTER_END" }) do
        pcall(castFrame.RegisterEvent, castFrame, e)
    end
    castFrame:SetScript("OnEvent", castEvent)
    print("|cff66ccffProbe|r cast logging ON. Fight a boss (target it), then /dmprobe cast off and /reload.")
end

-- /dmprobe rare on|off : can an addon notice a rare in a dungeon by itself? Logs, for every nameplate that appears and for target
-- changes: whether name / GUID / classification are readable (not secret values), plus the list of map "vignettes" (rare icons).
local rareFrame, rareLog
local function readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function logUnit(event, unit)
    if #rareLog > 250 or not unit then return end
    local rec = { event = event, unit = unit }
    local ok = pcall(function()
        local name, guid = UnitName(unit), UnitGUID(unit)
        rec.nameReadable, rec.guidReadable = readable(name), readable(guid)
        if rec.nameReadable then rec.name = name end
        if rec.guidReadable and type(guid) == "string" then
            local kind, _, _, _, _, npc = strsplit("-", guid)
            rec.guidKind, rec.npcID = kind, tonumber(npc)
        end
        local cl = UnitClassification and UnitClassification(unit)
        rec.classification = readable(cl) and cl or "<secret>"
        rec.isEnemy = UnitCanAttack and readable(UnitCanAttack("player", unit)) and UnitCanAttack("player", unit) or "<secret/none>"
    end)
    rec.error = not ok or nil
    rec.inCombat = InCombatLockdown() and true or false
    rareLog[#rareLog + 1] = rec
end
local function rareProbe(arg)
    rareFrame = rareFrame or CreateFrame("Frame")
    if arg == "off" then
        rareFrame:UnregisterAllEvents()
        local vig = {}
        if C_VignetteInfo and C_VignetteInfo.GetVignettes then
            local okv, ids = pcall(C_VignetteInfo.GetVignettes)
            if okv and type(ids) == "table" then
                for _, guid in ipairs(ids) do
                    local oki, info = pcall(C_VignetteInfo.GetVignetteInfo, guid)
                    vig[#vig + 1] = oki and plain(info) or "<error>"
                end
            end
        end
        DungeonMapProbeDB = DungeonMapProbeDB or {}
        DungeonMapProbeDB[#DungeonMapProbeDB + 1] = { label = "rare", rare = rareLog or {}, vignettes = vig,
            vignetteApi = C_VignetteInfo ~= nil, zone = GetRealZoneText(), instance = { GetInstanceInfo() } }
        print("|cff66ccffProbe|r rare probe off: " .. #(rareLog or {}) .. " unit records, " .. #vig .. " vignettes. /reload to flush.")
        return
    end
    rareLog = {}
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do pcall(rareFrame.RegisterEvent, rareFrame, e) end
    rareFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then unit = "target" elseif event == "UPDATE_MOUSEOVER_UNIT" then unit = "mouseover" end
        logUnit(event, unit)
    end)
    print("|cff66ccffProbe|r rare probe ON. Walk through a dungeon (mobs near you, target a few, ideally a rare), then /dmprobe rare off and /reload.")
end

-- /dmprobe compass <label>: does anything tell us which way we face inside an instance? Records the facing / speed / position calls, the minimap's cvars and
-- every frame and texture on the minimap (points, rotation, texcoords). Run it standing still ("a"), turn about 90 degrees and run it again ("b"), then compare.
local function safeStr(v)
    if issecretvalue and issecretvalue(v) then return "<secret " .. type(v) .. ">" end
    if type(v) == "number" then return string.format("%.4f", v) end
    return tostring(v)
end
local function callStr(fn, ...)
    if type(fn) ~= "function" then return "<no function>" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "<error " .. tostring(res[2]) .. ">" end
    local out = {}
    for i = 2, #res do out[#out + 1] = safeStr(res[i]) end
    if #out == 0 then return "<nil>" end
    return table.concat(out, ", ")
end
local function describeRegion(path, r, out)
    local ot = r.GetObjectType and r:GetObjectType() or "?"
    local line = { path, ot }
    if r.IsShown then line[#line + 1] = "shown=" .. safeStr(r:IsShown()) end
    if r.GetAlpha then line[#line + 1] = "alpha=" .. callStr(r.GetAlpha, r) end
    if r.GetRotation then line[#line + 1] = "rot=" .. callStr(r.GetRotation, r) end
    if r.GetAtlas then line[#line + 1] = "atlas=" .. callStr(r.GetAtlas, r) end
    if r.GetTexCoord then line[#line + 1] = "tc=" .. callStr(r.GetTexCoord, r) end
    if r.GetNumPoints then
        local pts = {}
        for i = 1, (r:GetNumPoints() or 0) do pts[#pts + 1] = callStr(r.GetPoint, r, i) end
        line[#line + 1] = "pts=" .. table.concat(pts, " ; ")
    end
    if r.GetSize then line[#line + 1] = "size=" .. callStr(r.GetSize, r) end
    out[#out + 1] = table.concat(line, " | ")
end
local function scanFrame(path, frame, depth, out)
    describeRegion(path, frame, out)
    if frame.GetRegions then
        for i, r in ipairs({ frame:GetRegions() }) do
            local nm = (r.GetName and r:GetName()) or (r.GetDebugName and r:GetDebugName()) or ("region" .. i)
            describeRegion(path .. "/" .. tostring(nm), r, out)
        end
    end
    if depth > 0 and frame.GetChildren then
        for i, c in ipairs({ frame:GetChildren() }) do
            local nm = (c.GetName and c:GetName()) or (c.GetDebugName and c:GetDebugName()) or ("child" .. i)
            scanFrame(path .. "/" .. tostring(nm), c, depth - 1, out)
        end
    end
end
local function compassProbe(label)
    label = (label and label ~= "") and label or "x"
    local rec = {}
    rec[#rec + 1] = "build=" .. select(2, GetBuildInfo())
    rec[#rec + 1] = "instance=" .. tostring(IsInInstance())
    rec[#rec + 1] = "GetPlayerFacing=" .. callStr(GetPlayerFacing)
    rec[#rec + 1] = "UnitPosition=" .. callStr(UnitPosition, "player")
    rec[#rec + 1] = "GetUnitSpeed=" .. callStr(GetUnitSpeed, "player")
    rec[#rec + 1] = "IsFalling/IsSwimming=" .. callStr(IsFalling) .. " / " .. callStr(IsSwimming)
    rec[#rec + 1] = "GetBestMapForUnit=" .. callStr(C_Map and C_Map.GetBestMapForUnit, "player")
    rec[#rec + 1] = "GetPlayerMapPosition=" .. callStr(C_Map and C_Map.GetPlayerMapPosition, (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 0, "player")
    rec[#rec + 1] = "zone/sub/real=" .. tostring(GetZoneText()) .. " / " .. tostring(GetSubZoneText()) .. " / " .. tostring(GetRealZoneText())
    rec[#rec + 1] = "minimapZoneText=" .. tostring(GetMinimapZoneText and GetMinimapZoneText())
    rec[#rec + 1] = "rotateMinimap=" .. tostring(GetCVar("rotateMinimap"))
    rec[#rec + 1] = "Minimap.GetRotation=" .. type(Minimap and Minimap.GetRotation) .. " -> " .. callStr(Minimap and Minimap.GetRotation, Minimap)
    rec[#rec + 1] = "Minimap zoom/radius=" .. callStr(Minimap and Minimap.GetZoom, Minimap) .. " / " .. callStr(C_Minimap and C_Minimap.GetViewRadius)
    local names = {}
    if C_Minimap then for k, v in pairs(C_Minimap) do if type(v) == "function" then names[#names + 1] = k end end end
    table.sort(names)
    rec[#rec + 1] = "C_Minimap functions=" .. table.concat(names, ",")
    local mnames = {}
    if Minimap then for k, v in pairs(getmetatable(Minimap) and getmetatable(Minimap).__index or {}) do if type(v) == "function" then mnames[#mnames + 1] = k end end end
    table.sort(mnames)
    rec[#rec + 1] = "Minimap methods=" .. table.concat(mnames, ",")
    for _, nm in ipairs({ "Minimap", "MinimapCluster", "MinimapBackdrop", "MinimapCompassTexture", "MiniMapNorthTag", "MinimapNorthTag", "MiniMapTracking", "MinimapBorder" }) do
        local fr = _G[nm]
        if fr then scanFrame(nm, fr, 3, rec) else rec[#rec + 1] = nm .. " | missing" end
    end
    DungeonMapProbeDB = DungeonMapProbeDB or {}
    DungeonMapProbeDB.compass = DungeonMapProbeDB.compass or {}
    DungeonMapProbeDB.compass[label] = rec
    print(string.format("|cff66ccffProbe|r compass '%s' saved (%d lines). facing=%s speed=%s rotateMinimap=%s. Turn about 90 degrees and run it again with another label, then /reload.",
        label, #rec, callStr(GetPlayerFacing), callStr(GetUnitSpeed, "player"), tostring(GetCVar("rotateMinimap"))))
end

SLASH_DMPROBE1 = "/dmprobe"
SlashCmdList.DMPROBE = function(msg)
    msg = strtrim(msg or "")
    print("|cff66ccffDungeonMapProbe v0.8|r command: '" .. msg .. "'")
    if msg == "model" then return probeModel() end
    if msg == "compass" or msg:match("^compass ") then local ok9, e9 = pcall(compassProbe, msg:match("^compass%s+(%S+)")) if not ok9 then print("|cffff4444compass error:|r " .. tostring(e9)) end return end
    local rareArg = msg:match("^rare%s*(%a*)$")
    if rareArg then return rareProbe(rareArg) end
    local castArg = msg:match("^cast%s*(%a*)$")
    if castArg then return castProbe(castArg) end
    local iconsArg = msg:match("^icons%s*(.*)$")
    if iconsArg then local ok5, e5 = pcall(iconsProbe, iconsArg) if not ok5 then print("|cffff4444icons error:|r " .. tostring(e5)) end return end
    if msg == "qscan" then local ok7, e7 = pcall(qscanProbe) if not ok7 then print("|cffff4444qscan error:|r " .. tostring(e7)) end return end
    local questsArg = msg:match("^quests%s*(.*)$")
    if questsArg then local ok6, e6 = pcall(questsProbe, questsArg) if not ok6 then print("|cffff4444quests error:|r " .. tostring(e6)) end return end
    if msg == "lfg" then local ok4, e4 = pcall(lfgProbe) if not ok4 then print("|cffff4444lfg error:|r " .. tostring(e4)) end return end
    if msg == "frames" then local ok3, e3 = pcall(framesProbe) if not ok3 then print("|cffff4444frames error:|r " .. tostring(e3)) end return end
    if msg == "bronze" then local ok2, e2 = pcall(bronzeProbe) if not ok2 then print("|cffff4444bronze error:|r " .. tostring(e2)) end return end
    local atlasArg = msg:match("^atlas%s+(.+)$")
    if atlasArg then return atlasProbe(atlasArg) end
    if msg == "new" then return showFiles({ 7725792, 8113201, 7963781 }) end
    local ids = msg:match("^fid%s+(.+)$")
    if ids then
        local list = {}
        for n in ids:gmatch("%d+") do list[#list + 1] = tonumber(n) end
        return showFiles(list)
    end
    if msg == "tiles" then
        local ok, err = pcall(showTiles)
        if not ok then print("|cffff4444tiles error:|r " .. tostring(err)) end
        return
    end
    local ok, err = pcall(run, msg ~= "" and msg or "manual")
    if not ok then print("|cffff4444probe error:|r " .. tostring(err)) end
end
print("|cff66ccffDungeonMapProbe v0.8 loaded|r (/dmprobe, tiles, atlas <word>, bronze, frames, lfg, icons [words], quests [mapIDs], qscan, compass <label>)")

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, _, isLogin, isReload)
    local inInstance = IsInInstance()
    if inInstance then C_Timer.After(3, function() run("auto-instance") end) end
end)
