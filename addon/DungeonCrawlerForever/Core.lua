-- Dungeon Crawler Forever core: namespace, saved variables, instance detection, auto-open.
local ADDON, ns = ...
ns.name = ADDON

-- Forever builds report an interface version of 16xxx. The TOC no longer restricts the game type (its internal name "camelot"
-- is due to change at launch and a rename would stop the addon loading), so we guard at runtime instead.
local interfaceVersion = select(4, GetBuildInfo()) or 0
ns.isForever = interfaceVersion >= 16000 and interfaceVersion < 20000

-- Calls into Blizzard's own map/UI code go through here. NOTE: this does NOT make them run untainted (taint of the calling code carries into what it
-- calls). It only stops the callee's errors/taint from propagating back out into this addon's own code.
-- What does help is not calling Blizzard's map code at all while a controller is used (see OpenDungeonFullscreen).
function ns.Secure(fn, ...)
    if type(fn) ~= "function" then return false end
    if securecallfunction then return pcall(securecallfunction, fn, ...) end
    return pcall(fn, ...)
end

-- Opening / closing the map from our own code. This is the TAINTED path: ToggleWorldMap called from our code (also from a timer: a timer callback
-- keeps the taint of whoever scheduled it) taints the whole gamepad binding set, and the radial, chat and navigation are
-- then "blocked". Keys and macros therefore open the map through secure buttons (UI/Opener.lua) and this path only remains as the fallback when no
-- game button to click was found. With Gamepad UI on we never close the map ourselves: only our own views are hidden, the player closes the map.
function ns.OpenMapThen(fn)
    local W = _G.WorldMapFrame
    if W and not W:IsShown() and _G.ToggleWorldMap then
        -- (logged: this is the tainted path; it should only happen when no secure button opened the map first)
        ns.openerLog = ns.openerLog or {}
        ns.openerLog[#ns.openerLog + 1] = format("%s FALLBACK tainted ToggleWorldMap", date("%H:%M:%S"))
        while #ns.openerLog > 12 do table.remove(ns.openerLog, 1) end
        if DungeonMapDB then DungeonMapDB.openerLog = ns.openerLog end
        if ns.ControllerEnabled and ns.ControllerEnabled() and not ns.hintedTaintedOpen then
            ns.hintedTaintedOpen = true
            ns.Print("A typed command (or a macro line like /dm journal) opens the map from addon code; the game then blocks some controller actions after it closes. Use the macros from /dm macros (they use /click), or the key binding.")
        end
        ns.internalNav = true
        ns.Secure(_G.ToggleWorldMap)
        ns.internalNav = false
    end
    fn()
end
function ns.CloseMap()
    local W = _G.WorldMapFrame
    if ns.ControllerEnabled and ns.ControllerEnabled() then
        if ns.HideView then ns.HideView() end
        if ns.HideJournal then ns.HideJournal() end
        return
    end
    if W and W:IsShown() then ns.Secure(W.Hide, W) end
end

BINDING_HEADER_DUNGEONMAP = "Dungeon Crawler Forever"
BINDING_NAME_HEADER_DUNGEONMAP = "Dungeon Crawler Forever" -- (the keybinding page of this client labels the header row with this one)
BINDING_NAME_DUNGEONMAP_TOGGLE = "Toggle dungeon map"
BINDING_NAME_DUNGEONMAP_JOURNAL = "Toggle dungeon journal"

local DEFAULTS = {
    showEntrances = true, -- dungeon/raid entrance pins on zone and continent maps
    openMapTakeOver = true, -- with OpenMap loaded: its dungeon icons open our dungeon map
    showEntranceLevels = true, -- the level range under each entrance pin on zone maps
    entranceSize = 48,    -- entrance pin size on zone maps (continent maps use 40% of it)
    pinSize = 34,         -- boss pin size
    showRaids = true,
    showMinimapButton = true, -- the journal button on the minimap (new players: on, set in the welcome window; players from before 0.3.6: off, see ADDON_LOADED)
    minimapAngle = 225,   -- where it sits on the minimap's edge, in degrees
    showJournalButton = true, -- the Journal button at the right end of the world map's navigation bar
    welcomed = false,     -- the first-run welcome window has been shown
    showClassicRaids = true, -- raids whose Forever status is unconfirmed ("classic data")
    greyDefeated = true,
    announceKills = true, -- print the fight time in chat when a boss is defeated
    routesDefault = true, -- show the dungeon route when the map opens (off in the options: tick "Show route" on the map when you want it)
    showClearTimes = true, -- the usual clear time under the dungeon's level and on its entrance
    showSplits = false,   -- the time in dungeon window (opt-in)
    splitCompareLast = false, -- compare splits with the last run instead of the best
    splitDeltas = true,   -- the +/- against the reference run and the pace line in the time window (the +/- button hides them)
    runs = {},            -- finished runs on official routes (see Runs.lua)
    board = {},           -- runs received from other players (see Comms.lua)
    runSummaryMode = "notable", -- the run complete window: "notable" (first time, personal best, top three), "always" or "never"
    introShown = false,   -- the highscore intro (UI/RunDone.lua) has been shown once
    shareAsked = false,   -- the sharing question (UI/RunDone.lua) has been answered
    shareScope = "everyone", -- "everyone" (everyone with the addon you meet, where the game allows it) or "guild" (guild and friends only)
    splits = {},          -- split records per dungeon (see UI/Splits.lua)
    bestTimes = {},       -- fastest kills: bestTimes[instanceID][normalised boss name] = seconds
    showDropRates = true,
    showFloorStrip = true, -- floor thumbnails on the left edge of multi-floor maps
    markerRemovals = {},  -- shipped markers removed in game (edit mode): { {instance, floor, kind, x, y}, ... }; applied to data/manual by tools/import_manual.py
    markers = {},         -- floor markers recorded in game: markers[instanceID][floorUiMapID] = { {kind, x, y}, ... }
    markRares = true,     -- silver border + "(rare)" tag for rare bosses
    autoOpen = false,     -- open the map automatically when entering a dungeon (off: the map key opens it)
    openFullscreen = false, -- switch the world map to its full-size window when the journal or a dungeon opens (off: keep the map the size it is)
    hookWorldMap = true,  -- the world map key shows the dungeon map while inside a dungeon
    manual = {},          -- boss positions recorded in-game: manual[instanceID][bossName] = { floor, x, y }
    unknown = {},         -- dungeons we have no data for yet: unknown[instanceID] = name (shown with /dm unknown)
    lastWing = {},        -- wing last viewed per instance: lastWing[instanceID] = n
    kills = {},           -- bosses defeated in the current run: kills[instanceID] = { ids = {}, names = {}, last = time() }
    portraits = {},       -- creature display IDs recorded in-game: portraits[instanceID][bossName] = displayID
}

-- Window with the standard Blizzard frame look; falls back to a plain backdrop if the template is missing.
-- OpenMap (a world-map addon that stitches every zone into one map and draws its own dungeon icons and view) is looked after in a few places:
-- ns.OpenMapAPI() is its public API while its stitched map is up, else nil. Its frames reach frame level 9950, so ours sit above them; the map id under
-- its view follows what you look at, so a change of id does not mean you left our dungeon view; and our entrance pins are placed with its API.
function ns.OpenMapAPI()
    local api = _G.OpenMapAPI
    if type(api) == "table" and api.IsStitched then
        local ok, stitched = pcall(api.IsStitched)
        if ok and stitched then return api end
    end
end
ns.OPENMAP_LEVEL = 9690 -- the base frame level of our view next to OpenMap (children go up to +300; the limit is 10000)

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

-- Kill times --------------------------------------------------------------------------------------------------------------------
-- ENCOUNTER_START / ENCOUNTER_END give the fight length (no combat log needed). A kill prints "Boss defeated after 2:41" in chat, with the
-- personal best; the time in the dungeon since you came in is added. Best times are kept per boss in DungeonMapDB.bestTimes.
local function clock(sec)
    sec = math.floor((sec or 0) + 0.5)
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60) -- no // in the game's Lua 5.1
    if h > 0 then return format("%d:%02d:%02d", h, m, sec % 60) end
    return format("%d:%02d", math.floor(sec / 60), sec % 60)
end
ns.FormatTime = clock

function ns.GetBestTime(instanceID, bossName)
    local t = DungeonMapDB and DungeonMapDB.bestTimes and DungeonMapDB.bestTimes[instanceID]
    return t and t[normName(bossName)]
end

local fight -- the encounter in progress: { id, name, start }

function ns.AnnounceKill(bossName, seconds)
    local instanceID = ns.GetCurrentInstance()
    if not (instanceID and type(seconds) == "number" and seconds >= 3) then return end
    DungeonMapDB.bestTimes = DungeonMapDB.bestTimes or {}
    local bt = DungeonMapDB.bestTimes[instanceID] or {}
    DungeonMapDB.bestTimes[instanceID] = bt
    local key = normName(bossName)
    local prev = bt[key]
    local text = format("|cffffd100%s|r defeated after |cffffffff%s|r", bossName, clock(seconds))
    if not prev then
        text = text .. " |cff9a9a9a(first kill time recorded)|r"
    elseif seconds < prev then
        text = text .. format(" |cff66ff66(new best, was %s)|r", clock(prev))
    else
        text = text .. format(" |cff9a9a9a(best %s)|r", clock(prev))
    end
    if not prev or seconds < prev then bt[key] = seconds end
    local spent = ns.TimeInDungeon and ns.TimeInDungeon()
    if spent then text = text .. format(" |cff9a9a9a- time in dungeon %s|r", clock(spent)) end
    ns.Print(DungeonMapDB.announceKills ~= false and text or ("Boss defeated: " .. bossName))
end

function ns.GetRunKills(instanceID)
    local rec = DungeonMapDB and DungeonMapDB.kills and DungeonMapDB.kills[instanceID]
    if rec and (time() - rec.last) <= RESET_AFTER then return rec end
end

-- The name a boss goes by in our data. The client names some encounters differently from the boss (Drowned City: the encounter "Deathless Guardians" is
-- the boss Deathless Marrow; also Baron, Magmatus, Arcanic Enigma ...), and the run clock and the routes use our names, so a kill under the client's name
-- never completed a route (no highscore run was recorded). The encounter id finds the boss; without a match the name is kept.
function ns.BossNameFor(encounterID, name)
    local inst = ns.GetCurrentInstance()
    local d = inst and ns.Dungeons and ns.Dungeons[inst]
    if d and type(encounterID) == "number" then
        for _, b in ipairs(d.bosses or {}) do
            if b.id == encounterID and b.name then return b.name end
        end
    end
    return name
end

function ns.MarkKilled(encounterID, name, quiet)
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
    if type(name) == "string" and not quiet then ns.Print("Boss defeated: " .. name) end
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
-- "You have entered too many instances lately." arrives as a system chat line on Forever (seen 2026-11-25); other clients show it in the error frame
local function noteIfInstanceLimit(msg)
    if type(msg) == "string" and not (issecretvalue and issecretvalue(msg)) and msg:lower():find("too many instances", 1, true) and ns.NoteInstanceLimitHit then
        pcall(ns.NoteInstanceLimitHit)
        return true
    end
end

local function onSystemMessage(msg)
    if noteIfInstanceLimit(msg) then return end
    if type(msg) ~= "string" or not INSTANCE_RESET_SUCCESS then return end
    local pattern = "^" .. INSTANCE_RESET_SUCCESS:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    local name = msg:match(pattern)
    if not name then return end
    for id, d in pairs(ns.Dungeons) do
        if d.name == name then ns.ResetKills(id); if ns.NoteInstanceReset then ns.NoteInstanceReset(id) end end
    end
    if ns.SplitsReset then pcall(ns.SplitsReset) end
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

-- Diagnostics for "an action was blocked because of taint": which fields of Blizzard's map / gamepad tables were last written by an addon, and
-- which addon (issecurevariable). Read-only; it writes nothing into Blizzard's tables.. Saved with each blocked action (DungeonMapDB.blocked).
function ns.TaintScan()
    if not issecurevariable then return "no issecurevariable" end
    local out, seen = {}, {}
    local function scan(name, t, depth)
        if type(t) ~= "table" or seen[t] or #out >= 16 then return end
        seen[t] = true
        local ok = pcall(function()
            for k, v in pairs(t) do
                if type(k) == "string" or type(k) == "number" then
                    local secure, by = issecurevariable(t, k)
                    if not secure and #out < 16 then out[#out + 1] = format("%s.%s<-%s", name, tostring(k), tostring(by)) end
                end
                if depth > 0 and type(v) == "table" and type(k) == "string" and #out < 16 then scan(name .. "." .. k, v, depth - 1) end
            end
        end)
        if not ok then out[#out + 1] = name .. " (scan error)" end
    end
    local gs = _G.GamepadSharedUtility
    scan("WorldMapFrame", _G.WorldMapFrame, 1)
    scan("GamepadMode", _G.GamepadMode, 2)
    scan("GamepadSharedUtility", gs, 3)
    scan("UIParent", _G.UIParent, 0)
    if #out == 0 then return "no tainted fields found" end
    return table.concat(out, "; ")
end

function ns.HandleEvent(event, a, b, c, d, e)
    if DungeonMapDB and DungeonMapDB.debuglog and event ~= "PLAYER_ENTERING_WORLD" and event ~= "ADDON_LOADED" then
        debugLog(event, a, b, c, d, e)
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if a == ADDON and DungeonMapDB then
            local list = DungeonMapDB.blocked or {}
            DungeonMapDB.blocked = list
            -- the date (the log keeps the last 10 across sessions), the situation (combat, controller, map size, version) and the call chain 14 deep: the 6
            -- levels it kept before ended inside Blizzard's map code, before the call that came from this addon
            local pad = _G.InputUtil and _G.InputUtil.IsGamepadUIEnabled and _G.InputUtil.IsGamepadUIEnabled() and "controller" or "mouse"
            local combat = InCombatLockdown and InCombatLockdown() and "combat" or "no combat"
            local size = (WorldMapFrame and WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()) and "full map" or "small map"
            list[#list + 1] = format("%s %s %s %s [%s, %s, %s, v%s] | %s", date("%Y-%m-%d"), date("%H:%M:%S"), event, tostring(b), pad, combat, size,
                tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"),
                (debugstack and debugstack(2, 14, 0) or ""):gsub("\n", " < ") .. " | tainted: " .. ns.TaintScan())
            while #list > 10 do table.remove(list, 1) end
        end
        return
    end
    if event == "ADDON_LOADED" and a == ADDON then
        DungeonMapDB = DungeonMapDB or {}
        -- 0.3.6: the minimap button is on for a new player (the welcome window shows its checkbox) and off for one who already had the addon
        if DungeonMapDB.showMinimapButton == nil then DungeonMapDB.showMinimapButton = not DungeonMapDB.welcomed end
        applyDefaults(DungeonMapDB)
        if ns.RunsMigrate then pcall(ns.RunsMigrate) end -- runs on an old route version that RouteAliases.lua still accepts
        DungeonMapDB.taintFirst, DungeonMapDB.taintScan, DungeonMapDB.stageDiag = nil, nil, nil -- (diagnostic leftovers of the controller work)
        if ns.SetupOpeners then ns.SetupOpeners() end
        if ns.RegisterOptions then ns.RegisterOptions() end
        if (DungeonMapDB.version or 0) < 2 then
            DungeonMapDB.autoOpen = false -- v1 defaulted to true; opening on entry turned out to be intrusive
            DungeonMapDB.version = 2
        end
        if DungeonMapDB.version < 3 then
            DungeonMapDB.routesDefault = true -- 0.1.17: routes on by default; the saved "off" was the old default, which no one chose
            DungeonMapDB.version = 3
        end
        if DungeonMapDB.version < 4 then
            if DungeonMapDB.runSummary == false then DungeonMapDB.runSummaryMode = "never" end -- 0.1.26: the on/off box became a three-way choice
            DungeonMapDB.runSummary = nil
            DungeonMapDB.version = 4
        end
        hookMap()
    elseif event == "PLAYER_LOGOUT" then
        if ns.OpenMapRestoreButtons then pcall(ns.OpenMapRestoreButtons) end
    elseif event == "UPDATE_INSTANCE_INFO" then
        if ns.ViewShown and ns.ViewShown() then C_Timer.After(0.2, function() ns.RefreshMap() end) end -- the lockout line under the clear time
    elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        for _, m in ipairs({ a, b }) do -- (the message is the 2nd value on current clients, the 1st on older ones; may be secret)
            if noteIfInstanceLimit(m) then break end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if ns.NoteInstanceEntry then pcall(ns.NoteInstanceEntry, a, b) end
        if ns.RequestLockouts then ns.RequestLockouts() end
        hookMap()
        if ns.SetupOpenMap then pcall(ns.SetupOpenMap) end
        C_Timer.After(1, autoOpen)
        C_Timer.After(5, function() if ns.MaybeWelcome then pcall(ns.MaybeWelcome) end end)
        C_Timer.After(9, function() if ns.MaybeIntro then pcall(ns.MaybeIntro) end end)
        C_Timer.After(3, function() if ns.CommsRetryNow then pcall(ns.CommsRetryNow) end end) -- messages the game would not take inside the instance
        C_Timer.After(25, function() if ns.CommsLogin then pcall(ns.CommsLogin) end end) -- ask the guild for their runs (once the sharing question is answered)
        C_Timer.After(3, ns.NotifyUnknown)
        if ns.SplitsEntered then pcall(ns.SplitsEntered) end -- the time in dungeon clock starts when you come in
        if ns.SplitsRefresh then pcall(ns.SplitsRefresh) end
    elseif event == "ENCOUNTER_START" then
        -- a = encounterID, b = name. Values may be secret: only keep real ones.
        local okId = type(a) == "number" and not (issecretvalue and issecretvalue(a))
        fight = { id = okId and a or nil, name = isReadable(b) and b or nil, start = GetTime() }
        if ns.SplitsPullEncounter then pcall(ns.SplitsPullEncounter, ns.BossNameFor(fight.id, fight.name)) end -- an encounter start also starts the run clock
    elseif event == "BOSS_KILL" or event == "ENCOUNTER_END" then
        -- BOSS_KILL: a = encounterID, b = name. ENCOUNTER_END: a = id, b = name, c = difficulty, d = group size, e = success (1 = kill).
        -- Forever fires ENCOUNTER_END (not BOSS_KILL) for dungeon bosses. Values may be secret: only accept real ones.
        local okId = type(a) == "number" and not (issecretvalue and issecretvalue(a))
        local okName = isReadable(b)
        local success = (event == "BOSS_KILL") or e == 1 or e == true
        local timed = false
        if event == "ENCOUNTER_END" and fight then
            local same = (okId and fight.id == a) or (okName and fight.name == b) or (not okId and not okName)
            timed = success and same and (GetTime() - fight.start) >= 3
        end
        -- one identity for every consumer: our boss name, found through the encounter id (the client's name only when nothing matches)
        local shown = ns.BossNameFor(okId and a or (fight and fight.id), (okName and b) or (fight and fight.name))
        if success and (okId or okName) then ns.MarkKilled(okId and a or nil, (okName or shown) and shown or nil, timed) end
        if timed then pcall(ns.AnnounceKill, shown or "Boss", GetTime() - fight.start) end
        if event == "ENCOUNTER_END" and ns.SplitsPullEnd then pcall(ns.SplitsPullEnd, shown, success) end
        if success and event == "ENCOUNTER_END" and ns.SplitsKill then pcall(ns.SplitsKill, shown) end
        if event == "ENCOUNTER_END" then fight = nil end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.SplitsPull then pcall(ns.SplitsPull, "combat") end -- first combat in the dungeon starts the run clock (D-063)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.SplitsCalm then pcall(ns.SplitsCalm) end
    elseif event == "PLAYER_DEAD" then
        if ns.SplitsDeath then pcall(ns.SplitsDeath) end
    elseif event == "CHAT_MSG_SYSTEM" then
        pcall(onSystemMessage, a)
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_WATCH_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "GROUP_ROSTER_UPDATE" then
        if event == "GROUP_ROSTER_UPDATE" and ns.CommsRoster then pcall(ns.CommsRoster) end
        -- the Quests list shows completed / in-log state, level requirements and Share buttons (in a group): redraw it when they change
        if ns.ViewShown and ns.ViewShown() and ns.GetState().tab == "quests" then C_Timer.After(0.3, function() ns.RefreshMap() end) end
        -- the quest badges on bosses and loot (UI/View.lua) follow what is in the log
        if ns.ViewShown and ns.ViewShown() and ns.GetState().tab ~= "quests" and (event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED") then C_Timer.After(0.3, function() ns.RefreshMap() end) end
        -- a tracked quest just picked up (or done) leaves the world map
        if event ~= "GROUP_ROSTER_UPDATE" and ns.RefreshEntrances and WorldMapFrame and WorldMapFrame:IsShown() then
            C_Timer.After(0.3, function() pcall(ns.RefreshEntrances) end)
        end
    else
        for _, e in ipairs(DEATH_EVENTS) do
            if e == event then pcall(onDeathMessage, event, a) return end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("BOSS_KILL")
f:RegisterEvent("ENCOUNTER_END")
pcall(f.RegisterEvent, f, "ENCOUNTER_START")
f:RegisterEvent("CHAT_MSG_SYSTEM")
pcall(f.RegisterEvent, f, "UI_INFO_MESSAGE")
pcall(f.RegisterEvent, f, "UI_ERROR_MESSAGE") -- "You have entered too many instances lately" (Model.lua)
pcall(f.RegisterEvent, f, "UPDATE_INSTANCE_INFO") -- the saved lockouts arrived (asked for with RequestRaidInfo, Model.lua)
pcall(f.RegisterEvent, f, "PLAYER_REGEN_DISABLED")
pcall(f.RegisterEvent, f, "PLAYER_DEAD")
pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED") -- recorded so a "blocked from an action" popup can be traced
pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE" }) do pcall(f.RegisterEvent, f, e) end
for _, e in ipairs(DEATH_EVENTS) do pcall(f.RegisterEvent, f, e) end -- unknown events on a client are ignored, never an error
f:SetScript("OnEvent", function(_, event, a, b, c, d, e) ns.HandleEvent(event, a, b, c, d, e) end)

-- Global entry points (keybinding, addon compartment)
function DungeonMap_Toggle()
    ns.Toggle()
end
function DungeonMap_ToggleJournal()
    ns.ToggleJournal()
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
