-- /dm probe meter: does this client have the game's own damage meter (C_DamageMeter), can an addon read it, and are the numbers readable
-- (OQ-024). Run it once after a dungeon fight (or a whole dungeon), then /reload and send DungeonMapDB.probe.meter (or the chat lines) back.
-- Everything is wrapped in pcall; secret values are reported as "secret" and never printed or compared.
local _, ns = ...

local function safe(f, ...)
    if type(f) ~= "function" then return false, "missing" end
    return pcall(f, ...)
end

local function show(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then return tostring(v) end
    return t
end

local function keys(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do out[#out + 1] = tostring(k) end
    table.sort(out)
    return out
end

function ns.ProbeMeter()
    local out = {}
    local function say(s) out[#out + 1] = s; ns.Print("meter: " .. s) end
    local dm = _G.C_DamageMeter
    say("C_DamageMeter is " .. type(dm))
    if type(dm) ~= "table" then DungeonMapDB.probe = DungeonMapDB.probe or {}; DungeonMapDB.probe.meter = out return end
    say("functions: " .. table.concat(keys(dm), ", "))
    local ok, avail = safe(dm.IsDamageMeterAvailable)
    say("IsDamageMeterAvailable: " .. (ok and show(avail) or ("error " .. tostring(avail))))
    say("Enum.DamageMeterType: " .. table.concat(keys(Enum and Enum.DamageMeterType), ", "))
    say("Enum.DamageMeterSessionType: " .. table.concat(keys(Enum and Enum.DamageMeterSessionType), ", "))
    local typ, sess = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
    local ok2, list = safe(dm.GetAvailableCombatSessions)
    say("GetAvailableCombatSessions: " .. (ok2 and (type(list) == "table" and (#list .. " sessions") or show(list)) or ("error " .. tostring(list))))
    local function read(label, f, ...)
        local ok3, s = safe(f, ...)
        if not ok3 then say(label .. ": error " .. tostring(s)) return end
        if type(s) ~= "table" then say(label .. ": " .. show(s)) return end
        say(format("%s: fields %s; duration %s; sources %s", label, table.concat(keys(s), ","), show(s.durationSeconds or s.duration), type(s.combatSources) == "table" and #s.combatSources or "none"))
        for i, src in ipairs(s.combatSources or {}) do
            if i > 6 then break end
            say(format("  %s total %s per second %s (fields: %s)", show(src.name), show(src.totalAmount), show(src.amountPerSecond), table.concat(keys(src), ",")))
        end
    end
    for _, kind in ipairs({ "Damage", "Healing" }) do
        local t = typ and typ[kind .. "Done"] or typ and typ[kind]
        if t == nil and typ then say("no Enum.DamageMeterType." .. kind .. "Done / " .. kind) end
        for _, name in ipairs({ "Overall", "Current" }) do
            local st = sess and sess[name]
            if st ~= nil and t ~= nil then read(kind .. " " .. name .. " (FromType)", dm.GetCombatSessionFromType, st, t) end
        end
        if ok2 and type(list) == "table" then
            for i, info in ipairs(list) do
                if i > 3 then break end
                local id = type(info) == "table" and (info.sessionID or info.id) or info
                if t ~= nil then read(format("%s session %s (FromID)", kind, show(id)), dm.GetCombatSessionFromID, id, t) end
            end
        end
    end
    DungeonMapDB.probe = DungeonMapDB.probe or {}
    DungeonMapDB.probe.meter = out
    ns.Print("meter: done. /reload saves the lines to DungeonMapDB.probe.meter in the SavedVariables file.")
end

-- /dm probe lockouts: what does this client report as saved instances (OQ-028)? Run it where the lockout line says "Not locked" but the game refuses you
-- entry, with that dungeon's map open. Lists every saved instance with all the values the game gives, asks again for them, and says what we make of the open dungeon.
function ns.ProbeLockouts()
    local out = {}
    local function say(s) out[#out + 1] = s; ns.Print("lockouts: " .. s) end
    say("RequestRaidInfo is " .. type(_G.RequestRaidInfo) .. ", GetNumSavedInstances " .. type(_G.GetNumSavedInstances) .. ", GetSavedInstanceInfo " .. type(_G.GetSavedInstanceInfo))
    if type(_G.RequestRaidInfo) == "function" then pcall(_G.RequestRaidInfo) end
    C_Timer.After(1.5, function()
        local ok, n = safe(_G.GetNumSavedInstances)
        say("GetNumSavedInstances: " .. (ok and show(n) or ("error " .. tostring(n))))
        for i = 1, (ok and tonumber(n) or 0) do
            local r = { pcall(_G.GetSavedInstanceInfo, i) }
            local vals = {}
            for k = 2, #r do vals[#vals + 1] = show(r[k]) end
            say(format("#%d: %s", i, table.concat(vals, " | ")))
        end
        local id = ns.GetState and ns.GetState().instanceID
        if id then
            local d = ns.Dungeons[id]
            local lock = ns.GetLockout(id)
            say(format("open dungeon: %s (%s); our lockout reading: %s", d and d.name or "?", tostring(id), lock and format("locked, %d/%d, resets in %ds", lock.killed, lock.total, lock.reset) or "none"))
        else
            say("no dungeon map is open (open the dungeon's map first to see what we make of it)")
        end
        say("order of the values: name | id | reset | difficulty | locked | extended | instanceIDMostSig | isRaid | maxPlayers | difficultyName | numEncounters | encounterProgress | extendDisabled | instanceID")
        DungeonMapDB.probe = DungeonMapDB.probe or {}
        DungeonMapDB.probe.lockouts = out
        ns.Print("lockouts: done. The 'game refused me' message, word for word, helps too. /reload saves these lines to DungeonMapDB.probe.lockouts.")
    end)
end
