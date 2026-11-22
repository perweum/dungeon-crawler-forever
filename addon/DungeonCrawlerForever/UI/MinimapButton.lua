-- A minimap button for the journal: left click opens the journal, right click the options, drag moves it around the minimap's edge.
-- It is one of the secure opener buttons (UI/Opener.lua, a plain click handler calling ns.ToggleJournal would be the tainted path that blocks
-- controller actions), standalone on UIParent and only anchored to the Minimap. On for new players (the welcome window has the checkbox), off for
-- players who had the addon before it existed: they switch it on under Esc > Options > AddOns > Dungeon Crawler Forever > Map and entrances.
local _, ns = ...

local RADIUS_PAD = 5
local ICON = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\minimap-icon" -- the logo's gem staff, round (tools/make_minimap_icon.py)
local button

local function place()
    if not button then return end
    local m = _G.Minimap
    local a = math.rad((DungeonMapDB and DungeonMapDB.minimapAngle) or 225)
    button:ClearAllPoints()
    if m then
        local r = (m:GetWidth() or 140) / 2 + RADIUS_PAD
        button:SetPoint("CENTER", m, "CENTER", math.cos(a) * r, math.sin(a) * r)
    else
        button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -180, -30)
    end
end

-- shown or hidden by the option; a protected frame cannot be changed in combat, so that waits (RefreshOpeners runs again when combat ends)
function ns.UpdateMinimapButton()
    if not button then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local want = DungeonMapDB and DungeonMapDB.showMinimapButton ~= false
    if button:IsShown() ~= want then button:SetShown(want) end
end

local function dragging(self)
    local m = _G.Minimap
    if not m then return end
    local scale = m:GetEffectiveScale()
    local cx, cy = m:GetCenter()
    local x, y = GetCursorPosition()
    DungeonMapDB.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
    place()
end

function ns.SetupMinimapButton()
    if button or not (ns.NewOpener and CreateFrame) then return end
    button = ns.NewOpener({
        name = "DungeonMapMinimapButton",
        run = function(justOpened) if justOpened then ns.ShowJournal() else ns.ToggleJournal() end end,
        rightClick = function() if ns.OpenOptions then ns.OpenOptions() end end,
    }, UIParent, false)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", 0, 0)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    -- during a drag the click target is cleared, so the release after the drag does not open the journal; it comes back a moment after
    button:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:SetAttribute("clickbutton", nil)
        self:SetScript("OnUpdate", dragging)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if C_Timer and C_Timer.After then C_Timer.After(0.2, function() if ns.RefreshOpenerTarget then ns.RefreshOpenerTarget() end end) end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Dungeon Crawler Forever")
        GameTooltip:AddLine("Left click: dungeon journal", 1, 1, 1)
        GameTooltip:AddLine("Right click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    place()
    button:Hide()
    ns.UpdateMinimapButton()
end
