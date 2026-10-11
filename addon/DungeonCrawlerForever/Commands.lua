local _, ns = ...

SLASH_DUNGEONMAP1 = "/dm"
SLASH_DUNGEONMAP2 = "/dungeonmap"
SlashCmdList.DUNGEONMAP = function(msg)
    if not ns.isForever then print("Dungeon Crawler Forever only works on WoW Forever.") return end
    msg = strtrim((msg or ""):lower())
    -- Developer / contributor commands are hidden until `/dm dev` is typed (they only write to the player's own saved variables).
    local DEV = { edit = true, export = true, portrait = true, display = true, debug = true, kills = true, unknown = true, pins = true }
    local cmd = msg:match("^(%S+)")
    if cmd and DEV[cmd] and not DungeonMapDB.dev then
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
    elseif msg == "reset" then
        DungeonMapDB.point = nil
        ns.Print("Window position will reset on next /reload.")
    else
        ns.Print("/dm  toggle map   |  /dm config  options   |  /dm auto  auto-open   |  /dm hook  world-map key   |  /dm fill  map fill/fit   |  /dm resetkills")
        if DungeonMapDB.dev then ns.Print("Developer: /dm edit  |  /dm export  |  /dm portrait  |  /dm display <id>  |  /dm debug [off]  |  /dm kills  |  /dm unknown  |  /dm pins  |  /dm dev (off)") end
    end
end
