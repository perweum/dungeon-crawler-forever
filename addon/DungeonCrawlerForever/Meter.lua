-- Combat stats of a run (D-080): what each player in the group did, read from the game's own damage meter (C_DamageMeter, probe 2026-11-25: it is there on
-- Forever, its numbers are plain numbers, and it lists every group member). Display only: time stays the only ranking factor, and the numbers are honour
-- system like the rest of a shared run.
--
-- The meter's "Overall" session is not the run (it holds every fight since it was last reset), so a run is the DIFFERENCE between two readings:
--   begin  (the first engagement)  -> v.meterBase = reading
--   sample (every boss kill)       -> v.meterLast = the newest reading of each player (a player who left keeps what he had at the last sample)
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
                any = true
                for _, src in ipairs(s.combatSources) do
                    local name, total = src.name, src.totalAmount
                    if type(name) == "string" and readable(name) and type(total) == "number" and readable(total) then
                        local k = ns.NormName(name)
                        out[k] = out[k] or { dmg = 0, heal = 0 }
                        out[k][def[1]] = math.floor(total + 0.5)
                    end
                end
            end
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
    v.meterBase = ns.MeterRead()
    v.meterLast = nil
end

-- A boss fell (or any good moment): remember the newest numbers of everybody, so a player who leaves is not lost.
function ns.MeterSample(v)
    if not (v and v.meterBase) then return end
    local cur = ns.MeterRead()
    if cur then v.meterLast = merge(v.meterLast, cur) end
end

-- The stats of the run so far: { [normalised name] = { dmg, heal } }, partial = true when the meter was reset during the run; nil when there is nothing.
function ns.MeterStats(v)
    if not (v and v.meterBase) then return nil end
    local last = merge(v.meterLast, ns.MeterRead())
    local out, partial, any = {}, false, false
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

-- Calls done(stats, partial) once the fight is over (the last boss's numbers are final then): at once outside combat, else after it ends (20 s at most).
function ns.MeterFinish(v, done)
    if not (v and v.meterBase and ns.MeterAvailable()) then done(nil, false) return end
    local tries = 0
    local function poll()
        tries = tries + 1
        if InCombatLockdown and InCombatLockdown() and tries < 20 then C_Timer.After(1, poll) return end
        local function final() local s, partial = ns.MeterStats(v); done(s, partial) end
        if tries > 1 and C_Timer and C_Timer.After then C_Timer.After(1.5, final) else final() end
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
