-- Combat stats of a run (D-080): what each player in the group did, read from the game's own damage meter (C_DamageMeter, probe 2026-11-25: it is there on
-- Forever, its numbers are readable out of combat, and it lists every group member). Display only: time stays the only ranking factor, and the numbers are honour
-- system like the rest of a shared run.
--
-- The meter's "Overall" session is not the run (it holds every fight since it was last reset), so a run is the DIFFERENCE between two readings:
--   calm   (before the first pull) -> v.meterBase = reading
--   sample (after combat ends)     -> v.meterLast = the newest reading of each player (a player who left keeps what he had at the last sample)
--   finish (the run is recorded)   -> a last reading once the fight is over; stats[player] = { dmg, heal } = newest reading minus the base
-- Players are keyed by ns.NormName of the name the meter shows (the group list uses the same name form).
local _, ns = ...

local function readable(v) return not (issecretvalue and issecretvalue(v)) end

local function meter()
    local dm = _G.C_DamageMeter
    if type(dm) ~= "table" or not (Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then return nil end
    local ok, avail = pcall(dm.IsDamageMeterAvailable)
    if not (ok and avail == true) then return nil end
    return dm
end

function ns.MeterAvailable() return meter() ~= nil end

-- { [normalised name] = { dmg = total, heal = total } } of the Overall session, or nil when the meter cannot be read.
function ns.MeterRead()
    local dm = meter()
    if not dm then return nil end
    local out, any = {}, false
    for _, def in ipairs({ { "dmg", "DamageDone" }, { "heal", "HealingDone" } }) do
        local kind = Enum.DamageMeterType[def[2]]
        if kind ~= nil then
            local ok, s = pcall(dm.GetCombatSessionFromType, Enum.DamageMeterSessionType.Overall, kind)
            if ok and type(s) == "table" and type(s.combatSources) == "table" then
                if not readable(s.durationSeconds) then return nil end
                any = true
                for _, src in ipairs(s.combatSources) do
                    local name, total = src.name, src.totalAmount
                    -- A secret snapshot is unavailable, not an empty meter or a zero baseline.
                    if not readable(name) or not readable(total) then return nil end
                    -- The meter also lists creatures; pet damage is already included in the owner's number.
                    local creature = type(src.sourceCreatureID) == "number" and readable(src.sourceCreatureID)
                    if not creature and type(name) == "string" and type(total) == "number" then
                        local k = ns.NormName(name)
                        out[k] = out[k] or { dmg = 0, heal = 0 }
                        out[k][def[1]] = math.floor(total + 0.5)
                    end
                end
            else
                return nil -- do not replace a complete snapshot with only damage or only healing
            end
        else
            return nil
        end
    end
    return any and out or nil
end

local function merge(into, reading)
    into = into or {}
    for k, v in pairs(reading or {}) do into[k] = { dmg = v.dmg or 0, heal = v.heal or 0 } end
    return into
end

-- The clock started: the numbers before this are not the run's.
function ns.MeterBegin(v)
    if not v then return end
    -- PLAYER_REGEN_DISABLED already hides meter values on Forever. Keep the baseline taken before the pull.
    v.meterBase = ns.MeterRead() or v.meterBase
    v.meterLast = nil
end

-- A boss fell (or any good moment): remember the newest numbers of everybody, so a player who leaves is not lost.
-- Nothing is sampled once the run is done or its numbers are being finished: later fights (quests, trash, the world) are not the run's.
function ns.MeterSample(v)
    if not (v and v.meterBase) or v.done or v.meterFrozen or v.meterStats ~= nil then return end
    local cur = ns.MeterRead()
    if cur then v.meterLast = merge(v.meterLast, cur) end
end

-- Read before the first pull, and after each fight. Never replace a missing baseline with totals from a later fight.
-- The delayed sample gives the client's meter time to publish the completed fight, but must not cross into another pull.
function ns.MeterCalm(v)
    if not v then return end
    local function sample()
        if v.left or v.done or v.meterFrozen or (InCombatLockdown and InCombatLockdown()) then return end
        if not (ns.GetCurrentInstance and ns.GetCurrentInstance() == v.instance) then return end
        if not v.started then
            local reading = ns.MeterRead()
            if reading then v.meterBase = reading end
        else
            ns.MeterSample(v)
        end
    end
    sample()
    if C_Timer and C_Timer.After then C_Timer.After(1.5, sample) end
end

-- You left the dungeon (the run goes on if you come back): keep what the meter held at that moment ...
function ns.MeterLeave(v)
    if not (v and v.meterBase) or v.done or v.meterFrozen then return end
    ns.MeterSample(v)
    v.meterLeave = ns.MeterRead()
end

-- ... and when you are back, what happened outside in between is not the run's: it moves the base up by that much.
function ns.MeterReturn(v)
    if not (v and v.meterBase and v.meterLeave) then return end
    local cur = ns.MeterRead()
    if cur then
        for k, now in pairs(cur) do
            local was = v.meterLeave[k] or { dmg = 0, heal = 0 }
            local b = v.meterBase[k] or { dmg = 0, heal = 0 }
            local outD, outH = now.dmg - was.dmg, now.heal - was.heal
            if outD > 0 or outH > 0 then v.meterBase[k] = { dmg = b.dmg + math.max(0, outD), heal = b.heal + math.max(0, outH) } end
        end
    end
    v.meterLeave = nil
end

-- The stats of the run so far: { [normalised name] = { dmg, heal } }, partial = true when the meter was reset during the run; nil when there is nothing.
-- noRead: use only what was sampled (the player has left the dungeon: no fresh reading, it would hold fights outside)
function ns.MeterStats(v, noRead)
    if not (v and v.meterBase) then return nil end
    local reading
    if not noRead then reading = ns.MeterRead() end
    local last = merge(v.meterLast, reading)
    local out, partial, any = {}, noRead or reading == nil, false
    for k, now in pairs(last) do
        local base = v.meterBase[k] or { dmg = 0, heal = 0 }
        local d, h = now.dmg - base.dmg, now.heal - base.heal
        if d < 0 or h < 0 then -- the meter was reset in between: what it holds now is all we know
            partial = true
            d, h = now.dmg, now.heal
        end
        if d > 0 or h > 0 then out[k] = { dmg = d, heal = h }; any = true end
    end
    return any and out or nil, partial
end

-- Calls done(stats, partial) once the boss fight is over: at once outside combat, else when combat ends. The numbers are FROZEN from here on (nothing
-- later counts: not the trash and quests that follow, not what happens after you leave). The last reading is taken right after the fight ends; if
-- combat does not end within 20 s (you went straight on to the next pull), or you have left the dungeon, the last readable sample is used and marked incomplete.
local waiters = setmetatable({}, { __mode = "k" }) -- callbacks wait here, not in the saved visit
function ns.MeterFinish(v, done)
    if not (v and v.meterBase and ns.MeterAvailable()) then done(nil, false) return end
    if v.meterStats ~= nil then done(v.meterStats or nil, v.meterPartial) return end -- already finished (another route ended at the same kill)
    if waiters[v] then table.insert(waiters[v], done) return end
    waiters[v] = { done }
    v.meterFrozen = true
    local function conclude(noRead)
        local stats, partial = ns.MeterStats(v, noRead)
        v.meterStats, v.meterPartial = stats or false, partial or nil
        local list = waiters[v] or {}
        waiters[v] = nil
        for _, cb in ipairs(list) do cb(stats, partial) end
    end
    local tries = 0
    local function poll()
        tries = tries + 1
        local inside = ns.GetCurrentInstance and ns.GetCurrentInstance() == v.instance
        if not inside then conclude(true) return end -- left the dungeon: only earlier readable samples are safe
        if InCombatLockdown and InCombatLockdown() then
            if tries < 20 then C_Timer.After(1, poll) else conclude(true) end
            return
        end
        if tries > 1 and C_Timer and C_Timer.After then
            C_Timer.After(1.5, function()
                local still = ns.GetCurrentInstance and ns.GetCurrentInstance() == v.instance
                local pulled = InCombatLockdown and InCombatLockdown()
                conclude(not still or pulled) -- a new pull began in the meantime: do not read its numbers
            end)
        else
            conclude(false)
        end
    end
    poll()
end

-- Totals of a record's stats for the highscore row: { dmg, heal, dps, hps } over the run time, or nil without stats.
function ns.RunStatsTotals(rec)
    if not (rec and rec.stats) then return nil end
    local dmg, heal = 0, 0
    for _, s in pairs(rec.stats) do dmg = dmg + (s.dmg or 0); heal = heal + (s.heal or 0) end
    local t = math.max(1, rec.total or 1)
    return { dmg = dmg, heal = heal, dps = dmg / t, hps = heal / t }
end

-- 1234 -> "1.2k", 3310000 -> "3.3M"
function ns.ShortNumber(n)
    n = n or 0
    if n >= 1e6 then return format("%.2fM", n / 1e6) end
    if n >= 1e4 then return format("%.0fk", n / 1e3) end
    if n >= 1e3 then return format("%.1fk", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end
