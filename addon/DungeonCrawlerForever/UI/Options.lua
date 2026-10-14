-- Options page in the game's own settings (Esc > Options > AddOns > Dungeon Crawler Forever). Deliberately short: nine settings.
-- Uses the Settings API of the Mainline UI family; everything is wrapped so a changed API can never break the addon.
local _, ns = ...

local function applyChange()
    if ns.RefreshMap then ns.RefreshMap() end
    if ns.RefreshEntrances then ns.RefreshEntrances() end
end

function ns.RegisterOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then
        ns.optionsError = "Settings API not available"
        return
    end
    local ok, err = pcall(function()
        local category = Settings.RegisterVerticalLayoutCategory("Dungeon Crawler Forever")
        local db = DungeonMapDB

        local function register(key, label, default, varType)
            local variable = "DUNGEONMAP_" .. key
            local setting = Settings.RegisterAddOnSetting(category, variable, key, db, varType, label, default)
            if setting and setting.SetValueChangedCallback then setting:SetValueChangedCallback(applyChange) end
            return setting
        end
        local function checkbox(key, label, tooltip, default)
            Settings.CreateCheckbox(category, register(key, label, default, Settings.VarType.Boolean), tooltip)
        end
        local function slider(key, label, tooltip, default, min, max, step)
            local options = Settings.CreateSliderOptions(min, max, step)
            if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            end
            Settings.CreateSlider(category, register(key, label, default, Settings.VarType.Number), options, tooltip)
        end

        checkbox("autoOpen", "Open the map when I enter a dungeon", "Otherwise press the map key (or /dm) inside the dungeon.", false)
        checkbox("hookWorldMap", "Map key shows the dungeon map inside a dungeon", "Inside an instance the normal map key opens the dungeon map instead of the world map.", true)
        checkbox("showEntrances", "Show entrance pins on the world map", "Dungeon and raid entrances on zone and continent maps. Click one to open its map.", true)
        slider("entranceSize", "Entrance pin size", "Size on zone maps; continent maps use smaller pins.", 48, 24, 72, 2)
        slider("pinSize", "Boss pin size", "Size of the boss portraits on the dungeon map.", 34, 24, 56, 2)
        checkbox("showRaids", "Show raids", "Include raids in the dungeon list and on the map.", true)
        checkbox("showClassicRaids", "Show raids with classic data", "Raids that are not confirmed for Forever yet.", true)
        checkbox("showFloorStrip", "Show the floor strip", "Small thumbnails of every floor on the left edge of multi-floor maps. There is also an All floors button.", true)
        checkbox("greyDefeated", "Grey out defeated bosses", "Defeated bosses get a checkmark either way.", true)
        checkbox("showDropRates", "Show loot drop chances", "The percentage next to each item, where known.", true)
        checkbox("routesDefault", "Show the dungeon route by default", "Routes through the bosses of a dungeon. Off: tick Show route on the map when you want it.", false)
        checkbox("showSplits", "Show the split timer in dungeons", "A small speedrun-style window: time per boss and how it compares with your best. Starts with the first fight. Also /dm splits, or the X on the window.", false)
        checkbox("splitCompareLast", "Compare splits with my last run", "Instead of your best time at each boss.", false)
        checkbox("announceKills", "Print boss kill times in chat", "Shows how long the fight took and your best time when a boss is defeated.", true)
        checkbox("markRares", "Mark rare bosses", "Silver border on the map and a (rare) tag in the list.", true)

        Settings.RegisterAddOnCategory(category)
        ns.optionsCategory = category
    end)
    if not ok then ns.optionsError = tostring(err) end
end

function ns.OpenOptions()
    if ns.optionsCategory and Settings and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, ns.optionsCategory:GetID())
        if ok then return end
    end
    ns.Print("Options page unavailable" .. (ns.optionsError and (": " .. ns.optionsError) or "") ..
        ". Commands: /dm auto, /dm hook, /dm edit.")
end
