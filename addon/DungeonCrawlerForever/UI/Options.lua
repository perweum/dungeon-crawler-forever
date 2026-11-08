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

        if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
            pcall(function()
                layout:AddInitializer(CreateSettingsButtonInitializer("Browse every dungeon and raid", "Open the list", function() ns.ShowJournal() end,
                    "A page with a card for every dungeon and raid, with search. Also /dm list.", true))
            end)
        end

        section("Bosses and loot")
        checkbox("greyDefeated", "Grey out defeated bosses", "Defeated bosses get a checkmark either way.", true)
        checkbox("markRares", "Mark rare bosses", "Silver border on the map and a (rare) tag in the list.", true)
        checkbox("showDropRates", "Show loot drop chances", "The percentage next to each item, where known.", true)

        section("Routes")
        checkbox("routesDefault", "Show the dungeon route by default", "Routes through the bosses of a dungeon, shown when the map opens. Off: use Show route in the map's bottom-left corner when you want it. Hide route there hides it until you log out. Draw your own with Edit route under it (or /dm route edit).", true)

        section("Timers")
        checkbox("showClearTimes", "Show typical clear times", "How long a full clear (and a quest run, or a side of Stratholme) usually takes, under the dungeon's level and on its entrance. Hover it for every kind of run.", true)
        checkbox("announceKills", "Print boss kill times in chat", "Shows how long the fight took and your best time when a boss is defeated.", true)
        checkbox("showSplits", "Show the time in dungeon window", "How long you have been in the dungeon, from the moment you came in (buffs, waiting and corpse runs included), with the time at each boss compared with your best visit. Also /dm timer, or the X on the window.", false)
        checkbox("splitCompareLast", "Compare with my last visit", "Instead of your best time at each boss.", false)

        section("Help improve the maps")
        -- a button that opens the "Share my recordings" window (skipped quietly when this client has no button initializer)
        if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
            pcall(function()
                layout:AddInitializer(CreateSettingsButtonInitializer("Boss positions and portraits you recorded in game", "Share my recordings", function() ns.ShowReport() end,
                    "Shows a short text to copy and paste into an issue on GitHub, so what you recorded (/dm dev, then /dm edit) reaches the maps. Also /dm report.", true))
            end)
        end

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
