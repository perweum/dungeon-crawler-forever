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

SLASH_DMPROBE1 = "/dmprobe"
SlashCmdList.DMPROBE = function(msg)
    msg = strtrim(msg or "")
    print("|cff66ccffDungeonMapProbe v0.8|r command: '" .. msg .. "'")
    if msg == "model" then return probeModel() end
    local rareArg = msg:match("^rare%s*(%a*)$")
    if rareArg then return rareProbe(rareArg) end
    local castArg = msg:match("^cast%s*(%a*)$")
    if castArg then return castProbe(castArg) end
    local iconsArg = msg:match("^icons%s*(.*)$")
    if iconsArg then local ok5, e5 = pcall(iconsProbe, iconsArg) if not ok5 then print("|cffff4444icons error:|r " .. tostring(e5)) end return end
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
print("|cff66ccffDungeonMapProbe v0.8 loaded|r (/dmprobe, tiles, atlas <word>, bronze, frames, lfg, icons [words])")

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, _, isLogin, isReload)
    local inInstance = IsInInstance()
    if inInstance then C_Timer.After(3, function() run("auto-instance") end) end
end)
