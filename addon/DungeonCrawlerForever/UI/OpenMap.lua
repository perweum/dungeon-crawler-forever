-- OpenMap (a world-map addon: every zone stitched into one map, with its own dungeon icons) next to ours.
-- OpenMap's icons are on its stitched map and win every click, so we take the click: a left click on one of its dungeon icons opens OUR dungeon map
-- (one dungeon: straight away; several at one entrance: our chooser under the icon). Its own right-click, dragging and zoom are not touched.
-- How: OpenMap's icons are frames whose `OnClick` field it calls as pin:OnClick(); we wrap that field on its dungeon icons (OpenMap.MapStitch.PinSet("dungeons").pins,
-- each with .instances = { { instanceMapID, name, raid, minLevel, maxLevel }, ... }). This reaches into OpenMap's internals (there is no API for it), so
-- every step is checked and anything unexpected leaves OpenMap's own behaviour as it is. Option: "Open Dungeon Crawler's map from OpenMap's dungeon icons".
local _, ns = ...

-- OpenMap also draws icons from the game's own journal for dungeons it has no entry for: those carry map ID 0 (or none) and a name only. Matched by name
-- ("Shaper's Terrace" = our "The Shaper's Terrace"), so dungeons new to us and to the game's tables still open our map.
local function stripThe(n) return (n:gsub("^the", "")) end
local function idByName(name)
    if type(name) ~= "string" then return nil end
    local want = stripThe(ns.NormName(name))
    if want == "" then return nil end
    for id, d in pairs(ns.Dungeons or {}) do
        if stripThe(ns.NormName(d.name)) == want then return id end
    end
end

-- Which of our dungeons an OpenMap icon entry stands for: by map ID, else by name.
local function instanceOf(inst)
    local id = inst and inst[1]
    if id and ns.Dungeons and ns.Dungeons[id] then return id end
    return idByName(inst and inst[2])
end

-- The set of our dungeons that OpenMap has an icon for (so we draw our own pin only for the others), or nil when its icons cannot be read.
function ns.OpenMapCovered()
    local om = _G.OpenMap
    local S = type(om) == "table" and om.MapStitch
    if type(S) ~= "table" or type(S.PinSet) ~= "function" then return nil end
    local ok, set = pcall(S.PinSet, "dungeons")
    if not ok or type(set) ~= "table" or type(set.pins) ~= "table" then return nil end
    local covered = {}
    for _, pin in ipairs(set.pins) do
        if type(pin) == "table" and type(pin.instances) == "table" then
            for _, inst in ipairs(pin.instances) do
                local id = instanceOf(inst)
                if id then covered[id] = true end
            end
        end
    end
    return covered
end

local function ours(inst)
    local id = instanceOf(inst)
    local d = id and ns.Dungeons and ns.Dungeons[id]
    if not d then return nil end
    local wing
    local wings = ns.GetWings and ns.GetWings(id)
    if wings and inst[2] then
        local want = ns.NormName(inst[2])
        for _, w in ipairs(wings) do
            if ns.NormName(w.name) == want then wing = w.wing end
        end
        if not wing then
            for _, w in ipairs(wings) do -- the name may carry the dungeon's name in front or behind
                local have = ns.NormName(w.name)
                if have:find(want, 1, true) or want:find(have, 1, true) then wing = w.wing break end
            end
        end
        if not wing then return nil end -- a wing we cannot tell apart: leave it to OpenMap
    end
    return { instance = id, wing = wing }
end

-- Takes the click when every instance at the icon is one we have. Returns true when handled.
function ns.OpenMapTakeOver(pin)
    if DungeonMapDB.openMapTakeOver == false or type(pin) ~= "table" or type(pin.instances) ~= "table" or #pin.instances == 0 then return false end
    local group = {}
    for _, inst in ipairs(pin.instances) do
        local e = ours(inst)
        if not e then return false end
        group[#group + 1] = e
    end
    if #group == 1 then
        ns.ShowInstance(group[1].instance, nil, true, group[1].wing)
    else
        ns.ShowEntranceChooser(pin, group)
    end
    return true
end

local function wrapPins()
    if not ns.OpenMapAPI() then return end -- (only while its stitched map is up: its dungeon icons exist then)
    local om = _G.OpenMap
    local S = type(om) == "table" and om.MapStitch
    if type(S) ~= "table" or type(S.PinSet) ~= "function" then return end
    local ok, set = pcall(S.PinSet, "dungeons")
    if not ok or type(set) ~= "table" or type(set.pins) ~= "table" then return end
    for _, pin in ipairs(set.pins) do
        if type(pin) == "table" and pin.instances and pin.OnClick and pin.dcfWrapped ~= pin.OnClick then
            local original = pin.OnClick
            local function wrapped(self, ...)
                local handled = false
                local ok2, res = pcall(ns.OpenMapTakeOver, self)
                if ok2 then handled = res end
                if handled then
                    if GameTooltip then GameTooltip:Hide() end
                    return
                end
                return original(self, ...)
            end
            pin.OnClick = wrapped
            pin.dcfWrapped = wrapped
        end
    end
end
ns.OpenMapWrapPins = wrapPins

local registered
function ns.SetupOpenMap()
    local api = _G.OpenMapAPI
    if registered or type(api) ~= "table" or type(api.RegisterCallback) ~= "function" then return end
    registered = true
    ns.OpenMapRestoreButtons() -- (a previous session ended with them switched off)
    local owner = {}
    pcall(api.RegisterCallback, owner, "OpenMap_StitchedChanged", function() C_Timer.After(0.5, wrapPins) end)
    pcall(api.RegisterCallback, owner, "OpenMap_ViewChanged", function() wrapPins() end) -- icons are (re)made as the view moves: wrap the new ones
    pcall(api.RegisterCallback, owner, "OpenMap_StitchedChanged", function() C_Timer.After(0.6, function() pcall(ns.RefreshEntrances) end) end) -- our pins for dungeons it lacks
    C_Timer.After(1, wrapPins)
    if not DungeonMapDB.openMapNoted then
        DungeonMapDB.openMapNoted = true
        ns.Print("OpenMap found: clicking its dungeon icons now opens Dungeon Crawler's dungeon map (turn this off in the options).")
    end
end

-- OpenMap's buttons (find me, pin, the quill ...) are a row or a rail of tabs around the map: they would sit around our dungeon map too. While our view is up
-- they are switched off with OpenMap's own setting ("OpenMap button on the map", worldmap module: mapButtons + its Refresh, as its menu does it) and put back
-- when the view closes. If the game ends while they are off (logout, crash), the next login puts them back.
local function openMapModule()
    local om = _G.OpenMap
    local mod = type(om) == "table" and type(om.GetModule) == "function" and om:GetModule("worldmap")
    if type(mod) == "table" and type(mod.db) == "table" and type(mod.Refresh) == "function" then return mod end
end

function ns.OpenMapHideButtons()
    if DungeonMapDB.openMapTakeOver == false or not ns.OpenMapAPI() or DungeonMapDB.openMapButtonsHidden then return end
    local mod = openMapModule()
    if not mod or mod.db.mapButtons == false then return end -- not there, or already off by the player's choice: not ours to change
    DungeonMapDB.openMapButtonsHidden = true
    mod.db.mapButtons = false
    pcall(mod.Refresh, mod)
end

function ns.OpenMapRestoreButtons()
    if not DungeonMapDB or not DungeonMapDB.openMapButtonsHidden then return end
    DungeonMapDB.openMapButtonsHidden = nil
    local mod = openMapModule()
    if mod and mod.db.mapButtons == false then
        mod.db.mapButtons = true
        pcall(mod.Refresh, mod)
    end
end
