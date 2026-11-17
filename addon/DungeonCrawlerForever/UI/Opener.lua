-- Opening the world map from a key or a macro without tainting the game's gamepad binding code.
--
-- Evidence (2026-11-17): when our own code calls ToggleWorldMap (directly, from a timer, from a macro line "/dm list"), the
-- map opens in a tainted execution and every binding / footer / canvas value it writes stays tainted; the radial menu, chat and navigation then read
-- them and "an action was blocked". Only a SECURE starting point opens the map cleanly. So the keys and macros go through small secure buttons of
-- ours that "click" the game's own map button (type="click", the same thing as the macro line /click <button>): the click runs in the secure
-- execution and the map opens untainted. Our own work (showing the journal / dungeon view) then runs in PostClick, with the map already open, and
-- calls nothing of Blizzard's.
--   * keyboard / controller keys: the keys of our two bindings are re-bound to these buttons (override bindings, out of combat);
--   * macros: /click DungeonMapOpenMap LeftButton 1 and /click DungeonMapOpenJournal LeftButton 1 (see /dm macros; the " LeftButton 1" is a press).
-- The buttons stand alone on UIParent (never inside the map's frame tree: a protected frame there blocks showing and hiding the map in combat).
-- Which game button opens the map is looked up by name; if none is found the plain (tainted) path of ns.Toggle / ns.ToggleJournal is used.
local ADDON, ns = ...

local CANDIDATES = { "MinimapZoneTextButton", "MinimapCluster.ZoneTextButton", "MiniMapWorldMapButton", "WorldMapMicroButton" }
local ACTIONS = {
    { name = "DungeonMapOpenMap", binding = "DUNGEONMAP_TOGGLE", run = function(justOpened) if justOpened then ns.ShowDungeonMap() else ns.Toggle() end end },
    { name = "DungeonMapOpenJournal", binding = "DUNGEONMAP_JOURNAL", run = function(justOpened) if justOpened then ns.ShowJournal() else ns.ToggleJournal() end end },
    { name = "DungeonMapOpenWorld", run = function() end }, -- just the game's map (for the "DM World Map" macro)
}

local owner, buttons, opener, pending = nil, {}, nil, false

local function find()
    for _, path in ipairs(CANDIDATES) do
        local obj = _G
        for part in path:gmatch("[^%.]+") do obj = type(obj) == "table" and obj[part] or nil end
        if type(obj) == "table" and obj.Click and obj.GetScript and obj:GetScript("OnClick") then return obj, path end
    end
end

local function mapShown() return _G.WorldMapFrame and _G.WorldMapFrame:IsShown() or false end

-- the click target is only set while the map is closed (a click on the game's button toggles: with the map open it would close it).
-- Called when the map shows and hides (never touches the key bindings: that could interrupt the key press being handled).
function ns.RefreshOpenerTarget()
    if not owner then return end
    if InCombatLockdown and InCombatLockdown() then pending = true return end
    local target = (not mapShown()) and opener or nil
    for _, b in ipairs(buttons) do b:SetAttribute("clickbutton", target) end
end

-- the keys of our two bindings go to the secure buttons (out of combat; on login and when the bindings change)
function ns.RefreshOpeners()
    if not owner then return end
    if InCombatLockdown and InCombatLockdown() then pending = true return end
    pending = false
    ns.RefreshOpenerTarget()
    if ClearOverrideBindings and SetOverrideBindingClick then
        ClearOverrideBindings(owner)
        if opener then
            for i, a in ipairs(ACTIONS) do
                if a.binding then
                    for _, key in ipairs({ GetBindingKey(a.binding) }) do SetOverrideBindingClick(owner, true, key, a.name, "LeftButton") end
                end
            end
        end
    end
end

function ns.SetupOpeners()
    if owner or not _G.CreateFrame then return end
    local path
    opener, path = find()
    if DungeonMapDB then DungeonMapDB.mapOpener = path or "none" end
    owner = CreateFrame("Frame", "DungeonMapOpenerOwner", UIParent)
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:RegisterEvent("UPDATE_BINDINGS")
    owner:RegisterEvent("PLAYER_ENTERING_WORLD")
    owner:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not pending then return end
        ns.RefreshOpeners()
    end)
    for _, a in ipairs(ACTIONS) do
        local b = CreateFrame("Button", a.name, UIParent, "SecureActionButtonTemplate")
        b:SetSize(1, 1)
        b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetAttribute("type", "click")
        -- The button acts on the PRESS, whatever the player's ActionButtonUseKeyDown setting is (SecureActionButton_ShouldUseOnKeyDown reads this
        -- attribute first). Without it the action only runs on the phase that setting names, and "/click Name" sends a RELEASE unless the macro line
        -- ends in " LeftButton 1": the generated macros did nothing (openerLog 2026-11-17: pre lines with down=false, never a post line).
        b:SetAttribute("useOnKeyDown", true)
        b:SetScript("PreClick", function(self, _, down)
            if down then self.wasShown = mapShown() end
            ns.openerLog = ns.openerLog or {}
            local log = ns.openerLog
            log[#log + 1] = format("%s pre %s down=%s mapShown=%s target=%s", date("%H:%M:%S"), a.name, tostring(down), tostring(self.wasShown), tostring(self:GetAttribute("clickbutton") and (self:GetAttribute("clickbutton").GetName and self:GetAttribute("clickbutton"):GetName() or "frame")))
            while #log > 12 do table.remove(log, 1) end
            if DungeonMapDB then DungeonMapDB.openerLog = log end
        end)
        b:SetScript("PostClick", function(self, _, down)
            if not down then return end -- (the action ran on the press, see useOnKeyDown above)
            if InCombatLockdown and InCombatLockdown() then return end
            local justOpened = not self.wasShown and mapShown()
            if ns.openerLog then
                ns.openerLog[#ns.openerLog + 1] = format("%s post %s wasShown=%s mapShownNow=%s justOpened=%s", date("%H:%M:%S"), a.name, tostring(self.wasShown), tostring(mapShown()), tostring(justOpened))
                while #ns.openerLog > 12 do table.remove(ns.openerLog, 1) end
            end
            local ok, err = pcall(a.run, justOpened)
            if not ok and DungeonMapDB then DungeonMapDB.openerError = tostring(err) end
        end)
        buttons[#buttons + 1] = b
    end
    ns.openerCount = #buttons
    ns.RefreshOpeners()
end
