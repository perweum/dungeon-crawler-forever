-- Clear times: how long a kind of run usually takes (full clear, quest run, Stratholme's sides ...), shown like a map app's "people typically
-- spend". The ranges come from Data/ClearTimes.lua (tools/gen_clear_times.py: an estimate from the dungeon's size, monsters and bosses, or
-- set by hand). Later they learn from recorded runs; until then every range says where it comes from.
local _, ns = ...

local ORDER = { full = 1, questH = 3, questA = 3 } -- named kinds (Living side ...) sit between the full clear and the quest run

local function faction()
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and f == "Horde" then return "H" end
    if ok and f == "Alliance" then return "A" end
end

-- The ranges for a dungeon (a wing of it, when it has wings), in display order: full clear, named kinds, then the quest run of the player's
-- faction. Each: { kind, label, min, max, basis } (minutes). Empty when the option is off or there is no data.
function ns.ClearTimeList(instanceID, wing)
    local out = {}
    if DungeonMapDB and DungeonMapDB.showClearTimes == false then return out end
    local all = ns.ClearTimes and ns.ClearTimes[instanceID]
    if not all then return out end
    local w = wing or 0
    local fac = faction()
    for _, e in ipairs(all) do
        local q = e.kind:match("^quest([HA])$")
        if e.wing == w and (not q or q == fac) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b)
        local oa, ob = ORDER[a.kind] or 2, ORDER[b.kind] or 2
        if oa ~= ob then return oa < ob end
        return a.label < b.label
    end)
    return out
end

-- 35 -> "35 min", 90 -> "1 h 30", 120 -> "2 h"
local function clock(m)
    if m < 60 then return m .. " min" end
    local h, r = math.floor(m / 60), m % 60
    return r == 0 and (h .. " h") or format("%d h %02d", h, r)
end

-- "35-55 min", "1 h 10 - 1 h 45", "50 min - 1 h 15"
function ns.FormatClearTime(lo, hi)
    if hi < 60 then return format("%d-%d min", lo, hi) end
    return clock(lo) .. " - " .. clock(hi)
end

local BASIS = {
    model = "Estimated from the dungeon's size, monsters and bosses.",
    bosses = "A rough guess from the number of bosses.",
    manual = "Set by hand from players' experience.",
}

-- Tooltip lines for the ranges: every kind, then where the numbers come from. `tt` is GameTooltip (already owned and titled).
function ns.ClearTimeTooltip(tt, list)
    local seen = {}
    for _, e in ipairs(list) do
        tt:AddDoubleLine(e.label, ns.FormatClearTime(e.min, e.max), 1, 0.82, 0, 1, 1, 1)
    end
    for _, e in ipairs(list) do
        if not seen[e.basis] and BASIS[e.basis] then
            seen[e.basis] = true
            tt:AddLine(BASIS[e.basis], 0.6, 0.6, 0.6, true)
        end
    end
    tt:AddLine("For a group at the recommended level. Real runs will refine it.", 0.6, 0.6, 0.6, true)
end

-- The one line for the dungeon header: the full clear (or the first kind there is), e.g. "Full clear: usually 35-55 min".
function ns.ClearTimeLine(instanceID, wing)
    local list = ns.ClearTimeList(instanceID, wing)
    local e = list[1]
    if not e then return nil, list end
    return format("%s: usually %s", e.label, ns.FormatClearTime(e.min, e.max)), list
end
