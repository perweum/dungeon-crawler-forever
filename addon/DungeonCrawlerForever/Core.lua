-- Dungeon Crawler Forever core: namespace, saved variables, instance detection, auto-open.
local ADDON, ns = ...
ns.name = ADDON

-- Forever builds report an interface version of 16xxx. The TOC no longer restricts the game type (its internal name "camelot"
-- is due to change at launch and a rename would stop the addon loading), so we guard at runtime instead.
local interfaceVersion = select(4, GetBuildInfo()) or 0
ns.isForever = interfaceVersion >= 16000 and interfaceVersion < 20000

BINDING_HEADER_DUNGEONMAP = "Dungeon Crawler Forever"
BINDING_NAME_DUNGEONMAP_TOGGLE = "Toggle dungeon map"

local DEFAULTS = {
    showEntrances = true, -- dungeon/raid entrance pins on zone and continent maps
    entranceSize = 48,    -- entrance pin size on zone maps (continent maps use 40% of it)
    pinSize = 34,         -- boss pin size
    showRaids = true,
    showClassicRaids = true, -- raids whose Forever status is unconfirmed ("classic data")
    greyDefeated = true,
    showDropRates = true,
    showFloorStrip = true, -- floor thumbnails on the left edge of multi-floor maps
    markerRemovals = {},  -- shipped markers removed in game (edit mode): { {instance, floor, kind, x, y}, ... }; applied to data/manual by tools/import_manual.py
    markers = {},         -- floor markers recorded in game: markers[instanceID][floorUiMapID] = { {kind, x, y}, ... }
    markRares = true,     -- silver border + "(rare)" tag for rare bosses
    autoOpen = false,     -- open the map automatically when entering a dungeon (off: the map key opens it)
    hookWorldMap = true,  -- the world map key shows the dungeon map while inside a dungeon
    manual = {},          -- boss positions recorded in-game: manual[instanceID][bossName] = { floor, x, y }
    unknown = {},         -- dungeons we have no data for yet: unknown[instanceID] = name (shown with /dm unknown)
    lastWing = {},        -- wing last viewed per instance: lastWing[instanceID] = n
    kills = {},           -- bosses defeated in the current run: kills[instanceID] = { ids = {}, names = {}, last = time() }
    portraits = {},       -- creature display IDs recorded in-game: portraits[instanceID][bossName] = displayID
}

-- Window with the standard Blizzard frame look; falls back to a plain backdrop if the template is missing.
function ns.NewWindow(name)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
    if ok and f then return f end
    f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -10)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

function ns.Print(...)
    print("|cff66ccffDungeon Crawler|r", ...)
end

-- Returns instanceMapID, difficultyID when inside an instance we have data for, else nil.
function ns.GetCurrentInstance()
    local inInstance = IsInInstance()
    if not inInstance then return nil end
    local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceID and ns.Dungeons[instanceID] then
        return instanceID, difficultyID
    end
end

local function applyDefaults(db)
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            db[k] = (type(v) == "table") and {} or v
        end
    end
end

-- Entering a dungeon we have no data for: say so once (ever) per dungeon and remember it, so players can report/contribute.
function ns.NotifyUnknown()
    if not IsInInstance() then return end
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "party" or not instanceID or ns.Dungeons[instanceID] then return end
    DungeonMapDB.unknown = DungeonMapDB.unknown or {}
    local known = DungeonMapDB.unknown
    if not known[instanceID] then
        known[instanceID] = name
        ns.Print(format("No map data for |cffffd100%s|r (instance %d) yet. This dungeon has no map data yet.", tostring(name), instanceID))
    end
end

-- Kill tracking ---------------------------------------------------------------------------------
-- Bosses defeated during a run are remembered (survives /reload) until the run is considered over: the dungeon is reset
-- (system message), `/dm resetkills`, or more than RESET_AFTER seconds pass without a kill. A saved lockout (raids, and
-- dungeons if Forever has lockouts) is read separately in ns.IsKilled.
local RESET_AFTER = 3600
local normName = function(n) return (tostring(n or ""):lower():gsub("[^%w]", "")) end
ns.NormName = normName

function ns.GetRunKills(instanceID)
    local rec = DungeonMapDB and DungeonMapDB.kills and DungeonMapDB.kills[instanceID]
    if rec and (time() - rec.last) <= RESET_AFTER then return rec end
end

function ns.MarkKilled(encounterID, name)
    local id = ns.GetCurrentInstance()
    if not id then return end
    DungeonMapDB.kills = DungeonMapDB.kills or {}
    local rec = ns.GetRunKills(id)
    if not rec then
        rec = { ids = {}, names = {}, last = 0 }
        DungeonMapDB.kills[id] = rec
    end
    if type(encounterID) == "number" then rec.ids[encounterID] = true end
    if type(name) == "string" then rec.names[normName(name)] = true end
    rec.last = time()
    -- a kill tells us which wing of a shared map the group is in (Lower vs Upper Blackrock Spire ...)
    for _, w in ipairs(ns.GetWings(id) or {}) do
        for bossName in pairs(w.bosses) do
            if type(name) == "string" and normName(bossName) == normName(name) then
                DungeonMapDB.lastWing = DungeonMapDB.lastWing or {}
                DungeonMapDB.lastWing[id] = w.wing
            end
        end
    end
    if type(name) == "string" then ns.Print("Boss defeated: " .. name) end
    if ns.RefreshMap then ns.RefreshMap() end
end

function ns.ResetKills(instanceID)
    if instanceID then
        DungeonMapDB.kills[instanceID] = nil
    else
        DungeonMapDB.kills = {}
    end
    if ns.RefreshMap then ns.RefreshMap() end
end

-- "<Dungeon> has been reset." (localised global string)
local function onSystemMessage(msg)
    if type(msg) ~= "string" or not INSTANCE_RESET_SUCCESS then return end
    local pattern = "^" .. INSTANCE_RESET_SUCCESS:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    local name = msg:match(pattern)
    if not name then return end
    for id, d in pairs(ns.Dungeons) do
        if d.name == name then ns.ResetKills(id) end
    end
end

local lastAutoOpened

local function autoOpen()
    local id = ns.GetCurrentInstance()
    if not id then
        lastAutoOpened = nil
        return
    end
    if DungeonMapDB.autoOpen and lastAutoOpened ~= id then
        lastAutoOpened = id
        ns.ShowInstance(id)
    end
end

local hooked
local function hookMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    ns.HookMap()
    ns.HookEntrances()
end

if not ns.isForever then return end -- not WoW Forever: stay inert (no events, no hooks)

-- Boss death detection beyond BOSS_KILL ------------------------------------------------------------
-- Not every dungeon boss fires BOSS_KILL (Oggleflint in Ragefire Chasm did not), but the kill shows up as text in the combat
-- log ("You killed Oggleflint", "Oggleflint dies."). We read those chat events and look for one of this dungeon's boss names
-- together with a death word. Messages can be secret values: those are skipped (see /dm debug).
local DEATH_EVENTS = { "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_MISC_INFO", "CHAT_MSG_COMBAT_FRIENDLY_DEATH" }
local DEATH_WORDS = { "dies", "slain", "killed", "defeated", "destroyed" }

local function isReadable(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) end

local function describe(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return type(v) .. ":<secret>" end
    return type(v) .. ":" .. tostring(v)
end

local function debugLog(event, ...)
    local log = DungeonMapDB.debuglog
    if not log then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = describe((select(i, ...))) end
    log[#log + 1] = { t = time(), event = event, args = table.concat(parts, " | ") }
    if #log > 80 then table.remove(log, 1) end
end

local function onDeathMessage(event, msg)
    if not isReadable(msg) then return end
    local id = ns.GetCurrentInstance()
    if not id then return end
    local lower = msg:lower()
    local death = false
    for _, w in ipairs(DEATH_WORDS) do
        if lower:find(w, 1, true) then death = true break end
    end
    if not death then return end
    for _, b in ipairs(ns.GetBosses(id)) do
        if not b.trash and lower:find(b.name:lower(), 1, true) then
            ns.MarkKilled(b.id, b.name)
        end
    end
end

function ns.HandleEvent(event, a, b, c, d, e)
    if DungeonMapDB and DungeonMapDB.debuglog and event ~= "PLAYER_ENTERING_WORLD" and event ~= "ADDON_LOADED" then
        debugLog(event, a, b, c, d, e)
    end
    if event == "ADDON_LOADED" and a == ADDON then
        DungeonMapDB = DungeonMapDB or {}
        applyDefaults(DungeonMapDB)
        if ns.RegisterOptions then ns.RegisterOptions() end
        if (DungeonMapDB.version or 0) < 2 then
            DungeonMapDB.autoOpen = false -- v1 defaulted to true; opening on entry turned out to be intrusive
            DungeonMapDB.version = 2
        end
        hookMap()
    elseif event == "PLAYER_ENTERING_WORLD" then
        hookMap()
        C_Timer.After(1, autoOpen)
        C_Timer.After(3, ns.NotifyUnknown)
    elseif event == "BOSS_KILL" or event == "ENCOUNTER_END" then
        -- BOSS_KILL: a = encounterID, b = name. ENCOUNTER_END: a = id, b = name, c = difficulty, d = group size, e = success (1 = kill).
        -- Forever fires ENCOUNTER_END (not BOSS_KILL) for dungeon bosses. Values may be secret: only accept real ones.
        local okId = type(a) == "number" and not (issecretvalue and issecretvalue(a))
        local okName = isReadable(b)
        local success = (event == "BOSS_KILL") or e == 1 or e == true
        if success and (okId or okName) then ns.MarkKilled(okId and a or nil, okName and b or nil) end
    elseif event == "CHAT_MSG_SYSTEM" then
        pcall(onSystemMessage, a)
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "PLAYER_LEVEL_UP" then
        -- the Quests list shows completed / in-log state and level requirements: redraw it when they change
        if ns.ViewShown and ns.ViewShown() and ns.GetState().tab == "quests" then C_Timer.After(0.3, ns.RefreshMap) end
    else
        for _, e in ipairs(DEATH_EVENTS) do
            if e == event then pcall(onDeathMessage, event, a) return end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BOSS_KILL")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("CHAT_MSG_SYSTEM")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do pcall(f.RegisterEvent, f, e) end
for _, e in ipairs(DEATH_EVENTS) do pcall(f.RegisterEvent, f, e) end -- unknown events on a client are ignored, never an error
f:SetScript("OnEvent", function(_, event, a, b, c, d, e) ns.HandleEvent(event, a, b, c, d, e) end)

-- Global entry points (keybinding, addon compartment)
function DungeonMap_Toggle()
    ns.Toggle()
end
function DungeonMap_OnCompartmentClick()
    ns.Toggle()
end
function DungeonMap_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Dungeon Crawler Forever")
    GameTooltip:AddLine("Click to open the dungeon map.  /dm config for options.", 1, 1, 1)
    GameTooltip:Show()
end
function DungeonMap_OnCompartmentLeave()
    GameTooltip:Hide()
end
