-- DEVELOPER ONLY, NOT SHIPPED: tools/package.py leaves this file (and its line in the TOC) out of the release zip (D-078).
-- View the quests as the other faction, to test Alliance quests on a Horde character (and the other way round).
-- /dm dropmarkers <questID> deletes the markers recorded in game for a quest; /dm dropboss <name> forgets a boss position recorded in game.
-- A button in edit mode cycles: real faction -> Alliance -> Horde; /dm viewas alliance|horde|off does the same. Kept for this session only (not saved).
local _, ns = ...

local NAME = { A = "Alliance", H = "Horde" }

local function set(f)
    ns.devFaction = f
    ns.Print(f and format("DEV: quests are shown as %s now (this session only; /dm viewas off to go back). Quests you do not have are not marked as started or done.", NAME[f])
        or "DEV: quests are shown for your own faction again.")
    if ns.RefreshMap then ns.RefreshMap() end
end

local function cycle()
    local nextF = { [false] = "A", A = "H", H = false }
    set(nextF[ns.devFaction or false] or nil)
end

-- /dm viewas: wrap the slash handler so Commands.lua (shipped) does not know about it
local orig = SlashCmdList.DUNGEONMAP
SlashCmdList.DUNGEONMAP = function(msg)
    local arg = type(msg) == "string" and msg:match("^%s*viewas%s*(%S*)%s*$")
    if arg then
        arg = arg:lower()
        if arg == "alliance" or arg == "a" then set("A")
        elseif arg == "horde" or arg == "h" then set("H")
        elseif arg == "off" then set(nil)
        else cycle() end
        return
    end
    local dropBoss = type(msg) == "string" and msg:match("^%s*dropboss%s+(.-)%s*$")
    if dropBoss and dropBoss ~= "" then -- /dm dropboss <name>: forget the position recorded in game for that boss (the shipped one comes back)
        local n = 0
        for _, bosses in pairs(DungeonMapDB.manual or {}) do
            if bosses[dropBoss] then bosses[dropBoss] = nil; n = n + 1 end
        end
        ns.Print(format("DEV: %d recorded position(s) of %s removed (the shipped position is used again after /reload).", n, dropBoss))
        if ns.RefreshMap then ns.RefreshMap() end
        return
    end
    local drop = type(msg) == "string" and msg:match("^%s*dropmarkers%s+(%d+)%s*$")
    if drop then -- /dm dropmarkers <questID>: delete the quest markers recorded in game for that quest (a wrong pick that cannot be shift-clicked away)
        local id, n = tonumber(drop), 0
        for _, floors in pairs(DungeonMapDB.markers or {}) do
            for _, list in pairs(floors) do
                for i = #list, 1, -1 do
                    if list[i].quest == id then table.remove(list, i); n = n + 1 end
                end
            end
        end
        ns.Print(format("DEV: %d recorded marker(s) of quest %d removed (shipped markers are not touched).", n, id))
        if ns.RefreshMap then ns.RefreshMap() end
        return
    end
    return orig(msg)
end

-- the edit-mode button, made when the map view exists and shown only in edit mode
local btn
local function update()
    local view = _G.DungeonMapView
    if not view then return end
    if not btn then
        btn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        btn:SetFrameLevel(view:GetFrameLevel() + 100)
        btn:SetSize(170, 22)
        btn:SetPoint("TOPLEFT", view, "TOPLEFT", 8, -8)
        btn:SetScript("OnClick", cycle)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Developer: view quests as")
            GameTooltip:AddLine("Cycles your own faction, Alliance and Horde, to test the quests of the other side. Not saved, not in the release.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
    end
    btn:SetText("View as: " .. (ns.devFaction and NAME[ns.devFaction] or "my faction"))
    btn:SetShown(ns.editing and true or false)
end
hooksecurefunc(ns, "RefreshMap", update)
