local _, ns = ...

-- Macros for the controller: the game's controller layout can hold macros but not our key bindings. A macro line is an ordinary slash command.
local MACROS = {
    -- /click goes through our secure buttons (UI/Opener.lua): the map opens untainted, so the radial menu and chat are not "blocked" afterwards.
    -- (A macro line "/dm list" would open the map from our own code, which is the tainted path.)
    { name = "DM Map", body = "/click DungeonMapOpenMap LeftButton 1", what = "the dungeon map (the current dungeon, else the map)" },
    { name = "DM Journal", body = "/click DungeonMapOpenJournal LeftButton 1", what = "the dungeon journal" },
    { name = "DM World Map", body = "/click DungeonMapOpenWorld LeftButton 1", what = "the world map" },
}
function ns.CreateMacros()
    if not (CreateMacro and GetMacroIndexByName) then ns.Print("This client has no macro API; type /dm, /dm list or /dm map in a macro yourself.") return end
    if InCombatLockdown and InCombatLockdown() then ns.Print("Not in combat: try again after the fight.") return end
    local made, kept = {}, {}
    for _, m in ipairs(MACROS) do
        local index = GetMacroIndexByName(m.name) or 0
        if index > 0 then
            -- an older version of this macro ("/dm list" ...): brought up to date
            if GetMacroBody and EditMacro and GetMacroBody(index) ~= m.body and pcall(EditMacro, index, m.name, nil, m.body) then made[#made + 1] = m.name .. " (updated)"
            else kept[#kept + 1] = m.name end
        else
            local ok, err = pcall(CreateMacro, m.name, 134400, m.body, false) -- (account-wide; the question-mark icon can be changed in the macro window)
            if ok and err then made[#made + 1] = m.name else ns.Print("Could not create the macro " .. m.name .. ": " .. tostring(ok and "no free slot?" or err)) end
        end
    end
    -- any macro of the player's own that opens the map with a typed command: it works, but the game blocks controller actions afterwards (a slash
    -- command is insecure code; only /click on our secure buttons opens the map cleanly). Reported, never rewritten.
    if GetNumMacros and GetMacroInfo then
        local account, char = GetNumMacros()
        local function scan(first, count)
            for i = first, first + (count or 0) - 1 do
                local name, _, body = GetMacroInfo(i)
                if name and body and not name:find("^DM ") then
                    for line in body:gmatch("[^\r\n]+") do
                        local l = strtrim(line):lower()
                        local fix = (l == "/dm journal" or l == "/dm list" or l == "/dm dungeons") and "/click DungeonMapOpenJournal LeftButton 1"
                            or (l == "/dm" or l == "/dm toggle") and "/click DungeonMapOpenMap LeftButton 1" or (l == "/dm map") and "/click DungeonMapOpenWorld LeftButton 1" or nil
                        if fix then ns.Print(format("Your macro '%s' runs '%s': change that line to '%s', otherwise the game blocks some controller actions after the map closes.", name, strtrim(line), fix)) end
                    end
                end
            end
        end
        pcall(scan, 1, account)
        pcall(scan, 121, char)
    end
    if #made > 0 then ns.Print("Macros created: " .. table.concat(made, ", ") .. ". Open the macro window (Game Menu > Macros) and put them on your controller layout.") end
    if #kept > 0 then ns.Print("Already there: " .. table.concat(kept, ", ") .. ".") end
end

SLASH_DUNGEONMAP1 = "/dm"
SLASH_DUNGEONMAP2 = "/dungeonmap"
SlashCmdList.DUNGEONMAP = function(msg)
    if not ns.isForever then print("Dungeon Crawler Forever only works on WoW Forever.") return end
    msg = strtrim((msg or ""):lower())
    -- Developer / contributor commands are hidden until `/dm dev` is typed (they only write to the player's own saved variables).
    local DEV = { edit = true, export = true, portrait = true, display = true, debug = true, kills = true, unknown = true, pins = true, nav = true, tiles = true, demo = true, opener = true }
    local cmd = msg:match("^(%S+)")
    if cmd and DEV[cmd] and not DungeonMapDB.dev then
        ns.Print("/dm " .. cmd .. " is a contributor tool. Type /dm dev once to unlock it, then try again.")
        msg = "help"
    end
    if msg == "" or msg == "toggle" then
        ns.Toggle()
    elseif msg == "report" or msg == "share" then
        ns.ShowReport()
    elseif msg == "list" or msg == "journal" or msg == "dungeons" then
        ns.ToggleJournal()
    elseif msg == "opener" then
        -- contributor diagnostics: which game button the key / macro opener clicks, and the last clicks it saw
        ns.Print("opener button: " .. tostring(DungeonMapDB.mapOpener) .. "  last error: " .. tostring(DungeonMapDB.openerError))
        for _, line in ipairs(DungeonMapDB.openerLog or {}) do ns.Print(line) end
    elseif msg == "macros" or msg == "macro" then
        ns.CreateMacros()
    elseif msg == "map" or msg == "worldmap" then
        -- the plain world map (for a macro): toggled like the map key does
        if WorldMapFrame and WorldMapFrame:IsShown() then ns.CloseMap() else ns.OpenMapThen(function() end) end
    elseif msg == "key" then
        ns.CaptureJournalKey()
    elseif msg == "keys" or msg == "keybinds" or msg == "bindings" then
        ns.OpenKeybindings()
    elseif msg == "welcome" or msg == "help me" then
        ns.ShowWelcome()
    elseif msg == "config" or msg == "options" then
        ns.OpenOptions()
    elseif msg == "auto" then
        DungeonMapDB.autoOpen = not DungeonMapDB.autoOpen
        ns.Print("Auto-open in dungeons: " .. (DungeonMapDB.autoOpen and "on" or "off"))
    elseif msg == "hook" then
        DungeonMapDB.hookWorldMap = not DungeonMapDB.hookWorldMap
        ns.Print("World map key opens the dungeon map in dungeons: " .. (DungeonMapDB.hookWorldMap and "on" or "off"))
    elseif msg == "demo" or msg:match("^demo ") then
        -- screenshots: fake players on the highscore, in memory only (never saved, never sent). /dm demo [low|mid|top|summary|off]
        local arg = msg:match("^demo%s+(%S+)")
        if arg == "off" then
            ns.demo = nil
            ns.Print("Demo mode off.")
        elseif arg == "summary" then
            if ns.ShowRunDoneDemo then ns.ShowRunDoneDemo() end
            return
        else
            ns.demo = { mode = (arg == "low" or arg == "top") and arg or "mid" }
            ns.Print("Demo mode on (" .. ns.demo.mode .. "): fake players on the highscore for screenshots. Not saved, never shared. /dm demo off or /reload clears it. Modes: low (you are far down, shows your pinned row), mid, top (you lead).")
        end
        if ns.RefreshMap then ns.RefreshMap() end
    elseif msg == "questtest" then
        if ns.ToggleQuestTest then ns.ToggleQuestTest() end
    elseif msg == "probe meter" then
        if ns.ProbeMeter then ns.ProbeMeter() end
    elseif msg == "icons" or msg:match("^icons ") then
        if ns.ShowIcons then ns.ShowIcons(msg:match("^icons%s+(.*)$")) end
    elseif msg == "runs" or msg == "runs import" then
        if ns.ShowRunsIO then ns.ShowRunsIO(msg == "runs import") end
    elseif msg == "recover" then
        if ns.SplitsRecover then ns.SplitsRecover() end
    elseif msg == "comms" then
        for _, line in ipairs(ns.CommsStatus and ns.CommsStatus() or {}) do ns.Print(line) end
    elseif msg == "sharing" or msg == "sharing reset" then
        if msg == "sharing reset" then
            DungeonMapDB.shareAsked, DungeonMapDB.introShown = false, true
            if ns.ShowIntro then ns.ShowIntro() end
        elseif ns.ShowSharing then ns.ShowSharing() end
    elseif msg == "timer" or msg == "splits" then
        ns.SplitsToggle()
    elseif msg == "route" or msg:match("^route ") then
        local st = ns.GetState()
        local sub = msg:match("^route%s+(%S+)")
        if not st.instanceID then ns.Print("Open a dungeon map first.") return end
        if sub == "clear" then
            ns.RouteClear(st.instanceID, st.wing)
            ns.Print("Route cleared.")
        elseif sub == "edit" or sub == "draw" then
            if ns.routeDraw then ns.RouteDrawStop() else ns.RouteDrawStart() end
            return
        elseif sub == "reset" then
            ns.RouteReset(st.instanceID, st.wing)
            ns.Print("Back to the built-in route of this dungeon (or none, if it has no built-in route).")
        elseif sub == "first" then
            local name, why = ns.RouteMoveFirst(st.instanceID, st.wing)
            ns.Print(name and ("\"" .. name .. "\" is now the first route.") or why)
        elseif sub == "undo" then
            ns.Print(ns.RouteUndo(st.instanceID, st.wing) and "Last point removed." or "The route is empty.")
        else
            ns.SetRouteShown(not ns.RouteVisible())
            ns.Print("Routes " .. (ns.RouteVisible() and "shown" or "hidden") .. ". /dm route edit (draw your own) | undo | clear | reset | first (shown route first in the list).")
        end
        ns.RefreshMap()
    elseif msg == "tiles" then
        -- temporary: floor 1 of the dungeons with a community map drawn from the game's own minimap tiles, to compare locations
        DungeonMapDB.tileView = not DungeonMapDB.tileView
        if DungeonMapDB.tileView and ns.editing then ns.ToggleEdit() end
        ns.Print("Game tiles for floor 1: " .. (DungeonMapDB.tileView and "ON (view only: pins and routes of the community map are hidden here, edit mode is off). /dm tiles switches back." or "off"))
        if ns.ViewShown and ns.ViewShown() then ns.RefreshMap() end
    elseif msg == "dev" then
        DungeonMapDB.dev = not DungeonMapDB.dev
        if not DungeonMapDB.dev and ns.editing then ns.ToggleEdit() end
        ns.Print("Developer commands: " .. (DungeonMapDB.dev and "on (/dm edit, export, portrait, display <id>, debug, kills, unknown, pins)" or "off"))
    elseif msg == "fill" then
        DungeonMapDB.fillMap = (DungeonMapDB.fillMap == false)
        ns.Print("Map fills the whole map area (edges cropped): " .. (DungeonMapDB.fillMap ~= false and "on" or "off - fitted with bars"))
        if ns.ViewShown() then ns.RefreshMap() end
    elseif msg == "edit" then
        ns.ToggleEdit()
    elseif msg == "export" then
        ns.ExportManual()
    elseif msg == "portrait" then
        ns.RecordPortrait()
    elseif msg:match("^display%s+%d+$") then
        ns.SetDisplayID(tonumber(msg:match("%d+")))
    elseif msg == "debug on" or msg == "debug" then
        DungeonMapDB.debuglog = {}
        ns.Print("Debug log ON: death/kill related chat events are recorded. Kill a boss, then /dm debug off and /reload.")
    elseif msg == "debug off" then
        ns.Print(format("Debug log OFF (%d entries kept in the saved variables until the next /dm debug on).", #(DungeonMapDB.debuglog or {})))
        DungeonMapDB.debuglogSaved, DungeonMapDB.debuglog = DungeonMapDB.debuglog, nil
    elseif msg == "resetkills" then
        ns.ResetKills()
        ns.Print("Defeated-boss marks cleared.")
    elseif msg == "kills" then
        local n = 0
        for id, rec in pairs(DungeonMapDB.kills or {}) do
            local names = {}
            for k in pairs(rec.names) do names[#names + 1] = k end
            n = n + 1
            ns.Print(format("%s: %s (last kill %ds ago)", ns.Dungeons[id] and ns.Dungeons[id].name or id, table.concat(names, ", "), time() - rec.last))
        end
        if n == 0 then ns.Print("No defeated bosses recorded for the current run.") end
    elseif msg == "unknown" then
        local any = false
        for id, name in pairs(DungeonMapDB.unknown or {}) do
            any = true
            ns.Print(format("%s (instance %d) has no data yet.", tostring(name), id))
        end
        if not any then ns.Print("No unknown dungeons recorded.") end
        ns.Print("To contribute: /dm edit, place bosses, /reload, then follow CONTRIBUTING.md in the project repository.")
    elseif msg == "pins" then
        ns.DumpPins()
    elseif msg == "nav" then
        -- developer: record how the world map's navigation bar buttons are built (read it back from the saved variables)
        local nav = WorldMapFrame and WorldMapFrame.NavBar
        local d = { buttons = {} }
        for i, b in ipairs(nav and nav.navList or {}) do
            local e = { name = b.GetText and b:GetText(), width = b.GetWidth and b:GetWidth(), keys = {} }
            local fs = type(b.text) == "table" and b.text or (b.GetFontString and b:GetFontString())
            e.textWidth = type(fs) == "table" and fs.GetStringWidth and fs:GetStringWidth() or nil
            local arrow = b.MenuArrowButton
            e.arrowShown = type(arrow) == "table" and arrow.IsShown and arrow:IsShown() or nil
            e.arrowWidth = type(arrow) == "table" and arrow.GetWidth and arrow:GetWidth() or nil
            for k, v in pairs(b) do e.keys[#e.keys + 1] = tostring(k) .. ":" .. type(v) end
            table.sort(e.keys)
            d.buttons[i] = e
        end
        DungeonMapDB.navdump = d
        ns.Print("Navigation bar dump saved (" .. #d.buttons .. " buttons). /reload to write it to the saved variables.")
    elseif msg == "reset" then
        DungeonMapDB.point = nil
        ns.Print("Window position will reset on next /reload.")
    else
        ns.Print("/dm  toggle map   |  /dm config  options   |  /dm auto  auto-open   |  /dm hook  world-map key   |  /dm fill  map fill/fit   |  /dm timer  time in dungeon   |  /dm list  dungeon journal  |  /dm keys  set keys  |  /dm macros  controller macros  |  /dm welcome  intro  |  /dm report  share recordings  |  /dm sharing  who your highscores go to  |  /dm resetkills")
        if DungeonMapDB.dev then ns.Print("Developer: /dm edit  |  /dm export  |  /dm portrait  |  /dm display <id>  |  /dm debug [off]  |  /dm kills  |  /dm unknown  |  /dm pins  |  /dm nav  |  /dm dev (off)") end
    end
end
