local _, ns = ...

SLASH_DUNGEONMAP1 = "/dm"
SLASH_DUNGEONMAP2 = "/dungeonmap"
SlashCmdList.DUNGEONMAP = function(msg)
    if not ns.isForever then print("Dungeon Crawler Forever only works on WoW Forever.") return end
    msg = strtrim((msg or ""):lower())
    -- Developer / contributor commands are hidden until `/dm dev` is typed (they only write to the player's own saved variables).
    local DEV = { edit = true, export = true, portrait = true, display = true, debug = true, kills = true, unknown = true, pins = true, nav = true, route = true }
    local cmd = msg:match("^(%S+)")
    if cmd and DEV[cmd] and not DungeonMapDB.dev then
        ns.Print("/dm " .. cmd .. " is a contributor tool. Type /dm dev once to unlock it, then try again.")
        msg = "help"
    end
    if msg == "" or msg == "toggle" then
        ns.Toggle()
    elseif msg == "config" or msg == "options" then
        ns.OpenOptions()
    elseif msg == "auto" then
        DungeonMapDB.autoOpen = not DungeonMapDB.autoOpen
        ns.Print("Auto-open in dungeons: " .. (DungeonMapDB.autoOpen and "on" or "off"))
    elseif msg == "hook" then
        DungeonMapDB.hookWorldMap = not DungeonMapDB.hookWorldMap
        ns.Print("World map key opens the dungeon map in dungeons: " .. (DungeonMapDB.hookWorldMap and "on" or "off"))
    elseif msg == "splits" then
        ns.SplitsToggle()
    elseif msg == "route" or msg:match("^route ") then
        local st = ns.GetState()
        local sub = msg:match("^route%s+(%S+)")
        if not st.instanceID then ns.Print("Open a dungeon map first.") return end
        if sub == "clear" then
            ns.RouteClear(st.instanceID, st.wing)
            ns.Print("Route cleared.")
        elseif sub == "undo" then
            ns.Print(ns.RouteUndo(st.instanceID, st.wing) and "Last point removed." or "The route is empty.")
        else
            ns.routeShow = not ns.RouteVisible()
            ns.Print("Route " .. (ns.routeShow and "shown" or "hidden") .. ". /dm route undo | clear. Draw it with /dm edit, Route button.")
        end
        ns.RefreshMap()
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
        ns.Print("/dm  toggle map   |  /dm config  options   |  /dm auto  auto-open   |  /dm hook  world-map key   |  /dm fill  map fill/fit   |  /dm resetkills")
        if DungeonMapDB.dev then ns.Print("Developer: /dm edit  |  /dm export  |  /dm portrait  |  /dm display <id>  |  /dm debug [off]  |  /dm kills  |  /dm unknown  |  /dm pins  |  /dm nav  |  /dm dev (off)") end
    end
end
