-- Options page in the game's own settings (Esc > Options > AddOns > Dungeon Crawler Forever), in sections by feature.
-- Uses the Settings API of the Mainline UI family; everything is wrapped so a changed API can never break the addon.
local _, ns = ...

local function applyChange()
    if ns.RefreshMap then ns.RefreshMap() end
    if ns.RefreshEntrances then ns.RefreshEntrances() end
    if ns.UpdateJournalButton then ns.UpdateJournalButton() end
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
end

-- the game's keybinding page (the bindings of this addon are under AddOns there)
function ns.OpenKeybindings()
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        if pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID) then return end
    end
    ns.Print("Esc > Options > Keybindings > AddOns > Dungeon Crawler Forever.")
end

-- The page is a short landing page with the buttons, and one sub-page per area (Esc > Options > AddOns > Dungeon Crawler Forever): Map, Dungeons and
-- loot, Runs and highscore. A client without sub-categories gets everything on the one page.
function ns.RegisterOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then
        ns.optionsError = "Settings API not available"
        return
    end
    local ok, err = pcall(function()
        local main, mainLayout = Settings.RegisterVerticalLayoutCategory("Dungeon Crawler Forever")
        local db = DungeonMapDB

        -- one page: its own category and layout, with the controls that write into it
        local function page(name)
            local category, layout = main, mainLayout
            if name and Settings.RegisterVerticalLayoutSubcategory then
                local okS, c, l = pcall(Settings.RegisterVerticalLayoutSubcategory, main, name)
                if okS and c then category, layout = c, l end
            end
            local P = {}
            function P.register(key, label, default, varType, onChange)
                local variable = "DUNGEONMAP_" .. key
                local setting = Settings.RegisterAddOnSetting(category, variable, key, db, varType, label, default)
                if setting and setting.SetValueChangedCallback then setting:SetValueChangedCallback(onChange or applyChange) end
                return setting
            end
            -- a section header in the list (skipped quietly when this client has no such initializer)
            function P.section(title)
                if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
                    pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title)) end)
                end
            end
            function P.checkbox(key, label, tooltip, default)
                Settings.CreateCheckbox(category, P.register(key, label, default, Settings.VarType.Boolean), tooltip)
            end
            function P.slider(key, label, tooltip, default, min, max, step)
                local options = Settings.CreateSliderOptions(min, max, step)
                if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
                end
                Settings.CreateSlider(category, P.register(key, label, default, Settings.VarType.Number), options, tooltip)
            end
            -- a drop-down of { value, label, tooltip } choices, stored as a string; skipped quietly when this client has none
            function P.dropdown(key, label, tooltip, default, choices, onChange)
                if not (Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
                pcall(function()
                    local function opts()
                        local c = Settings.CreateControlTextContainer()
                        for _, ch in ipairs(choices) do c:Add(ch[1], ch[2], ch[3]) end
                        return c:GetData()
                    end
                    Settings.CreateDropdown(category, P.register(key, label, default, Settings.VarType.String, onChange), opts, tooltip)
                end)
            end
            function P.button(label, buttonText, fn, tooltip)
                if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
                    pcall(function() layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, fn, tooltip, true)) end)
                end
            end
            return P
        end

        -- landing page: where things are, the journal and the keys
        local home = page(nil)
        home.section("Settings are on the pages below this one")
        home.section("Getting around")
        home.button("Browse every dungeon and raid", "Open the list", function() ns.ShowJournal() end,
            "A page with a card for every dungeon and raid, with search. Also /dm list.")
        home.button("Key for the dungeon journal", "Set key", function() ns.CaptureJournalKey() end,
            "Press the key you want for the journal. Esc cancels. Also /dm key.")
        home.button("Other keys (dungeon map, ...)", "Open keybindings", function() ns.OpenKeybindings() end,
            "Opens the game's keybindings: Dungeon Crawler Forever is under AddOns. Also /dm keys.")
        home.button("The welcome window shown the first time", "Show welcome", function() if ns.ShowWelcome then ns.ShowWelcome() end end,
            "Shows the introduction again: how to open the maps and the journal. Also /dm welcome.")
        home.section("Help improve the maps")
        home.button("Boss positions and portraits you recorded in game", "Share my recordings", function() ns.ShowReport() end,
            "Shows a short text to copy and paste into an issue on GitHub, so what you recorded (/dm dev, then /dm edit) reaches the maps. Also /dm report.")

        local map = page("Map and entrances")
        map.section("Map")
        map.checkbox("showJournalButton", "Show the Journal button on the map", "A Journal button at the right end of the world map's top bar. The journal is also in the bar when a dungeon is open, under /dm list, and under a key of your choice.", true)
        map.checkbox("showSharingStatus", "Show whether I am sharing on the map", "A small dot with \"Sharing On\" (green), \"Sharing Off\" (grey) or \"Sharing not set\" (yellow) next to the Journal button. Click it to change who gets your highscore runs. Also /dm sharing.", true)
        map.checkbox("showMinimapButton", "Show a minimap button for the journal", "Left click opens the dungeon journal, right click the options; drag it to move it around the minimap. On for new players; switch it on here if you had the addon before.", true)
        map.checkbox("autoOpen", "Open the map when I enter a dungeon", "Otherwise press the map key (or /dm) inside the dungeon.", false)
        map.checkbox("hookWorldMap", "Map key shows the dungeon map inside a dungeon", "Inside an instance the normal map key opens the dungeon map instead of the world map.", true)
        map.checkbox("openFullscreen", "Open the journal and dungeon maps in the full-size map", "Off (default): the map keeps the size it has, small or full. On: the world map is switched to its full-size window when the journal or a dungeon map opens (not in combat, and not with a controller, where the map's own size button is used).", false)
        map.checkbox("showFloorStrip", "Show the floor strip", "Small thumbnails of every floor on the left edge of multi-floor maps. There is also an All floors button.", true)
        map.slider("pinSize", "Boss pin size", "Size of the boss portraits on the dungeon map.", 34, 24, 56, 2)
        map.section("World map entrances")
        map.checkbox("showEntrances", "Show entrance pins on the world map", "Dungeon and raid entrances on zone and continent maps. Click one to open its map.", true)
        map.checkbox("showEntranceLevels", "Show level range under the entrance pins", "The recommended levels under each entrance on zone maps, coloured like quests for your level (orange: you are in the range). Where several dungeons share an entrance, one combined range.", true)
        map.checkbox("openMapTakeOver", "Open this addon's map from OpenMap's dungeon icons", "Only if the OpenMap addon is loaded. Its dungeon icons are on top of ours, so a click on one opens Dungeon Crawler's dungeon map. Off: OpenMap's own dungeon view.", true)
        map.slider("entranceSize", "Entrance pin size", "Size on zone maps; continent maps use smaller pins.", 48, 24, 72, 2)

        local content = page("Dungeons and loot")
        content.section("Dungeons and raids")
        content.checkbox("showRaids", "Show raids", "Include raids in the dungeon list and on the map.", true)
        content.checkbox("showClassicRaids", "Show raids with classic data", "Raids that are not confirmed for Forever yet.", true)
        content.section("Bosses and loot")
        content.checkbox("greyDefeated", "Grey out defeated bosses", "Defeated bosses get a checkmark either way.", true)
        content.checkbox("markRares", "Mark rare bosses", "Silver border on the map and a (rare) tag in the list.", true)
        content.checkbox("showDropRates", "Show loot drop chances", "The percentage next to each item, where known.", true)
        content.section("Routes")
        content.checkbox("routesDefault", "Show the dungeon route by default", "Routes through the bosses of a dungeon, shown when the map opens. Off: use Show route in the map's bottom-left corner when you want it. Hide route there hides it until you log out. Draw your own with Edit route under it (or /dm route edit).", true)

        local shareWas = { asked = db.shareAsked, scope = db.shareScope } -- the sharing choice before the last change (for the warning)
        local runs = page("Runs and highscore")
        runs.section("Highscore")
        runs.dropdown("shareScope", "Share my runs with", "Finished runs on an official route go to others so the highscores fill up: character name, class, level, time and group.", "everyone", {
            { "everyone", "Everyone with the addon", "The people you group with, your guild and friends, and others with the addon you meet, wherever the game lets an addon send." },
            { "guild", "Guild and friends only", "Your party at the end of a run (needed to confirm it), your guild and your friends. Nobody else." },
            { "none", "Don't share my own", "Your own runs stay on this computer. You still see runs that other people share, and you pass those on to your guild and friends (never yours), so the best times reach everyone." },
        }, function(setting)
            local was = shareWas
            shareWas = { asked = DungeonMapDB.shareAsked, scope = DungeonMapDB.shareScope }
            local wasSharing = was.asked and was.scope ~= "none"
            DungeonMapDB.shareAsked = true
            local n = ns.CommsBacklogCount and ns.CommsBacklogCount() or 0
            if DungeonMapDB.shareScope ~= "none" and not wasSharing and n > 0 and ns.ConfirmShareBacklog then
                local chosen = DungeonMapDB.shareScope
                ns.ConfirmShareBacklog(n, function() if ns.CommsShareBacklog then ns.CommsShareBacklog() end end, function()
                    DungeonMapDB.shareAsked, DungeonMapDB.shareScope = true, "none" -- kept private
                    shareWas = { asked = true, scope = "none" }
                    if setting and setting.SetValue then pcall(setting.SetValue, setting, "none") end
                    ns.Print("Your earlier runs stay private (sharing set to Don't share mine).")
                end)
            elseif ns.CommsShareBacklog then
                ns.CommsShareBacklog()
            end
        end)
        runs.dropdown("runSummaryMode", "Run summary window", "The window with your time, rank and the time at each boss when a run is complete.", "notable", {
            { "notable", "When something is new", "A first time, a personal best or a top three place. Other runs only get a line in chat." },
            { "always", "After every run", "" },
            { "never", "Never", "Only the line in chat." },
        })
        runs.button("Who the highscores are shared with", "Show the explanation", function() if ns.ShowIntro then ns.ShowIntro() end end,
            "Shows the highscore introduction and the sharing choice again. Also /dm sharing reset.")
        runs.section("Time in dungeon window")
        runs.checkbox("showSplits", "Show the time in dungeon window", "The run clock, which starts with the first fight in the dungeon, with the time at each boss compared with your best run on the official route. Runs are recorded whether or not this window is shown. Also /dm timer, or the X on the window.", true)
        runs.checkbox("splitDeltas", "Show +/- and the pace line", "In the time window: the difference at each boss (green faster, red slower, yellow equal) and where the run is heading. Also the +/- button on the window.", true)
        runs.checkbox("splitCompareLast", "Compare with my last run", "Instead of your best run on the route.", false)
        runs.section("Other timers")
        runs.checkbox("announceKills", "Print boss kill times in chat", "Shows how long the fight took and your best time when a boss is defeated.", true)
        runs.checkbox("showClearTimes", "Show typical clear times", "How long a full clear (and a quest run, or a side of Stratholme) usually takes, under the dungeon's level and on its entrance. Hover it for every kind of run.", true)

        Settings.RegisterAddOnCategory(main)
        ns.optionsCategory = main
    end)
    if not ok then ns.optionsError = tostring(err) end
end

-- Set the key of the journal (or any of our bindings) without leaving the page: a small window that takes the next key you press.
-- Escape cancels, a bound key is replaced (and the old use of that key is named in chat). Not possible in combat.
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true }

local function saveBindings()
    local set = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    SaveBindings(set)
end

function ns.BindKey(key, action)
    if InCombatLockdown and InCombatLockdown() then ns.Print("Keys cannot be changed in combat.") return false end
    local old = GetBindingAction and GetBindingAction(key, true)
    local previous = { GetBindingKey(action) }
    if not SetBinding(key, action) then ns.Print("That key cannot be used.") return false end
    for _, k in ipairs(previous) do if k ~= key then SetBinding(k) end end
    pcall(saveBindings)
    local what = _G["BINDING_NAME_" .. action] or action
    local text = GetBindingText and GetBindingText(key) or key
    ns.Print(format("|cffffd100%s|r is now |cffffd100%s|r.", what, text))
    if old and old ~= "" and old ~= action then
        ns.Print(format("It was %s before: that key no longer does it.", _G["BINDING_NAME_" .. old] or old))
    end
    return true
end

function ns.CaptureKey(action, title)
    if InCombatLockdown and InCombatLockdown() then ns.Print("Keys cannot be changed in combat.") return end
    local f = DungeonMapKeyCapture
    if not f then
        f = ns.NewWindow("DungeonMapKeyCapture")
        f:SetSize(340, 140)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetTitle then f:SetTitle("Set a key") end
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -40)
        f.text:SetPoint("TOPRIGHT", -16, -40)
        f.text:SetJustifyH("CENTER")
        f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.cancel:SetSize(90, 24)
        f.cancel:SetPoint("BOTTOM", 50, 14)
        f.cancel:SetText("Cancel")
        f.cancel:SetScript("OnClick", function() f:Hide() end)
        f.unbind = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.unbind:SetSize(90, 24)
        f.unbind:SetPoint("BOTTOM", -50, 14)
        f.unbind:SetText("Remove key")
        f.unbind:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then ns.Print("Keys cannot be changed in combat.") return end
            for _, k in ipairs({ GetBindingKey(f.action) }) do SetBinding(k) end
            pcall(saveBindings)
            ns.Print(format("|cffffd100%s|r has no key now.", _G["BINDING_NAME_" .. f.action] or f.action))
            f:Hide()
        end)
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(false)
        if f.EnableGamePadButton then f:EnableGamePadButton(true) end
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:SetScript("OnEvent", function(self) self:Hide() end)
        f:SetScript("OnKeyDown", function(self, key)
            if MODIFIER_KEYS[key] then return end -- wait for the key itself (Shift, Ctrl and Alt count as part of it)
            if key == "ESCAPE" then self:Hide() return end
            local prefix = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
            if ns.BindKey(prefix .. key, self.action) then self:Hide() end
        end)
    end
    if f.EnableGamePadButton then
        f:SetScript("OnGamePadButtonDown", f:GetScript("OnKeyDown"))
    end
    f.action = action
    local k = GetBindingKey(action)
    f.text:SetText(format("Press a key or controller button for\n|cffffd100%s|r\n%s\nEsc cancels.", title or action,
        k and ("(now: " .. (GetBindingText and GetBindingText(k) or k) .. ")") or "(no key set now)"))
    f:Show()
end

function ns.CaptureJournalKey() ns.CaptureKey("DUNGEONMAP_JOURNAL", "Toggle dungeon journal") end

function ns.OpenOptions()
    if ns.optionsCategory and Settings and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, ns.optionsCategory:GetID())
        if ok then return end
    end
    ns.Print("Options page unavailable" .. (ns.optionsError and (": " .. ns.optionsError) or "") ..
        ". Commands: /dm auto, /dm hook, /dm edit.")
end
