-- Boss level recorder (dev tool, part of the probe addon, never shipped). Always on while the addon is loaded: inside a dungeon or raid it records the
-- level of every elite / boss / rare you target, mouse over or see a nameplate of. Stored in DungeonMapBossLevelsDB (written on /reload or logout):
--   DungeonMapBossLevelsDB.seen[instanceMapID][unitName] = { levels = { [level] = sightings }, class = "elite", npc = npcID, n = sightings, first, last }
-- level -1 is the skull (??). Read it back with tools/import_boss_levels.py. /dmlevels lists what this dungeon has recorded so far.
-- Values can be secret (hidden by the client in some situations): those sightings are counted in DungeonMapBossLevelsDB.secret and skipped.
local KEEP = { worldboss = true, rareelite = true, elite = true, rare = true }

local frame = CreateFrame("Frame")
local lastKey, lastT = nil, 0
local DB

local function ok(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

local function record(unit)
    if not DB or not UnitExists(unit) then return end
    local _, itype, _, _, _, _, _, inst = GetInstanceInfo()
    if (itype ~= "party" and itype ~= "raid") or not ok(inst) or type(inst) ~= "number" then return end
    if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
    local cls = UnitClassification(unit)
    local name, level = UnitName(unit), UnitLevel(unit)
    if not (ok(cls) and ok(name) and ok(level) and type(name) == "string" and type(level) == "number") then
        DB.secret = (DB.secret or 0) + 1
        return
    end
    if not KEEP[cls] then return end
    local key = name .. "|" .. level
    local now = GetTime()
    if key == lastKey and now - lastT < 1 then return end -- mouseover fires many times a second
    lastKey, lastT = key, now
    local byInst = DB.seen[inst]
    if not byInst then byInst = {}; DB.seen[inst] = byInst end
    local e = byInst[name]
    if not e then
        e = { levels = {}, n = 0, first = time() }
        byInst[name] = e
    end
    e.levels[level] = (e.levels[level] or 0) + 1
    e.n = e.n + 1
    e.class = cls
    e.last = time()
    local guid = UnitGUID(unit)
    if ok(guid) and type(guid) == "string" then
        local parts = { strsplit("-", guid) }
        if parts[1] == "Creature" then e.npc = tonumber(parts[6]) end
    end
end

frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= "DungeonMapProbe" then return end
        DungeonMapBossLevelsDB = DungeonMapBossLevelsDB or {}
        DB = DungeonMapBossLevelsDB
        DB.seen = DB.seen or {}
        DB.build = select(4, GetBuildInfo())
        return
    end
    local unit = (event == "PLAYER_TARGET_CHANGED") and "target" or (event == "UPDATE_MOUSEOVER_UNIT") and "mouseover" or arg
    if type(unit) == "string" then
        local good, err = pcall(record, unit)
        if not good and DB then DB.lastError = tostring(err):sub(1, 200) end
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
pcall(frame.RegisterEvent, frame, "NAME_PLATE_UNIT_ADDED")

SLASH_DMLEVELS1 = "/dmlevels"
SlashCmdList.DMLEVELS = function()
    local _, _, _, _, _, _, _, inst = GetInstanceInfo()
    local rows, total = {}, 0
    for i, byInst in pairs((DB and DB.seen) or {}) do
        for name, e in pairs(byInst) do
            total = total + 1
            if i == inst then
                local ls = {}
                for lv, c in pairs(e.levels) do ls[#ls + 1] = (lv == -1 and "??" or tostring(lv)) .. (c > 1 and ("x" .. c) or "") end
                table.sort(ls)
                rows[#rows + 1] = format("  %s (%s): %s", name, e.class or "?", table.concat(ls, ", "))
            end
        end
    end
    table.sort(rows)
    print(format("|cff66ccffBoss levels|r %d recorded in all, %d here (instance %s), %d hidden sightings skipped. /reload writes them to disk.",
        total, #rows, tostring(inst), (DB and DB.secret) or 0))
    for _, r in ipairs(rows) do print(r) end
    if DB and DB.lastError then print("  last error: " .. DB.lastError) end
end
