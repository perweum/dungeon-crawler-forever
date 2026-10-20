-- Options page in the game's own settings (Esc > Options > AddOns > Dungeon Crawler Forever), in sections by feature.
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
        local category, layout = Settings.RegisterVerticalLayoutCategory("Dungeon Crawler Forever")
        local db = DungeonMapDB

        local function register(key, label, default, varType)
            local variable = "DUNGEONMAP_" .. key
            local setting = Settings.RegisterAddOnSetting(category, variable, key, db, varType, label, default)
            if setting and setting.SetValueChangedCallback then setting:SetValueChangedCallback(applyChange) end
            return setting
        end
        -- a section header in the list (skipped quietly when this client has no such initializer)
        local function section(title)
            if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
                pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title)) end)
            end
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

        section("Map")
        checkbox("autoOpen", "Open the map when I enter a dungeon", "Otherwise press the map key (or /dm) inside the dungeon.", false)
        checkbox("hookWorldMap", "Map key shows the dungeon map inside a dungeon", "Inside an instance the normal map key opens the dungeon map instead of the world map.", true)
        checkbox("showFloorStrip", "Show the floor strip", "Small thumbnails of every floor on the left edge of multi-floor maps. There is also an All floors button.", true)
        slider("pinSize", "Boss pin size", "Size of the boss portraits on the dungeon map.", 34, 24, 56, 2)

        section("World map entrances")
        checkbox("showEntrances", "Show entrance pins on the world map", "Dungeon and raid entrances on zone and continent maps. Click one to open its map.", true)
        checkbox("showEntranceLevels", "Show level range under the entrance pins", "The recommended levels under each entrance on zone maps, coloured like quests for your level (orange: you are in the range). Where several dungeons share an entrance, one combined range.", true)
        checkbox("openMapTakeOver", "Open this addon's map from OpenMap's dungeon icons", "Only if the OpenMap addon is loaded. Its dungeon icons are on top of ours, so a click on one opens Dungeon Crawler's dungeon map. Off: OpenMap's own dungeon view.", true)
        slider("entranceSize", "Entrance pin size", "Size on zone maps; continent maps use smaller pins.", 48, 24, 72, 2)

        section("Dungeons and raids")
        checkbox("showRaids", "Show raids", "Include raids in the dungeon list and on the map.", true)
        checkbox("showClassicRaids", "Show raids with classic data", "Raids that are not confirmed for Forever yet.", true)

        section("Bosses and loot")
        checkbox("greyDefeated", "Grey out defeated bosses", "Defeated bosses get a checkmark either way.", true)
        checkbox("markRares", "Mark rare bosses", "Silver border on the map and a (rare) tag in the list.", true)
        checkbox("showDropRates", "Show loot drop chances", "The percentage next to each item, where known.", true)

        section("Routes")
        checkbox("routesDefault", "Show the dungeon route by default", "Routes through the bosses of a dungeon. Off: tick Show route on the map when you want it. Draw your own with the Edit route button under it (or /dm route edit).", false)

        section("Timers")
        checkbox("announceKills", "Print boss kill times in chat", "Shows how long the fight took and your best time when a boss is defeated.", true)
        checkbox("showSplits", "Show the split timer in dungeons", "A small speedrun-style window: time per boss and how it compares with your best. Also /dm splits, or the X on the window.", false)
        checkbox("splitsAutoStart", "Start the split timer when I enter a dungeon", "Off: the clock starts with the first fight, or when you press Start on the timer window.", true)
        checkbox("splitCompareLast", "Compare splits with my last run", "Instead of your best time at each boss.", false)

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
