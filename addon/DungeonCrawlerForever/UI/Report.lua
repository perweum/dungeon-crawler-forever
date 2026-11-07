-- "Share my recordings": a short text of what the player has recorded in game (boss positions and portraits that the shipped data does not have yet),
-- in a small window with the text already selected: Ctrl+C, then paste it into an issue on GitHub. Addons cannot send anything out of the game, so copy and
-- paste is the way back. One short line per boss:
--   DCF 0.1.19 build 70862
--   P|2970|829591|Deathless Marrow|0.4123|0.2345      (position: instance, floor map id, boss, x, y)
--   D|2970|Zin'aka|12345                              (portrait: instance, boss, creature display id)
-- Read by tools/import_report.py. Not behind /dm dev: reporting is for every player (recording itself still starts with /dm dev, then /dm edit).
local _, ns = ...

local ISSUES_URL = "https://github.com/perweum/dungeon-crawler-forever/issues/new?labels=boss-position&title=Boss+positions"

local function shipped(instanceID, name)
    local d = ns.Dungeons and ns.Dungeons[instanceID]
    for _, b in ipairs(d and d.bosses or {}) do
        if b.name == name then return b end
    end
end

local function header()
    local ver = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("DungeonCrawlerForever", "Version") or "?"
    local ok, _, build = pcall(GetBuildInfo)
    return format("DCF %s build %s", tostring(ver), ok and tostring(build) or "?")
end

-- The report: lines (without the header), and how many positions / portraits are in it. Only what the shipped data lacks or has elsewhere.
function ns.BuildReport()
    local pos, disp = {}, {}
    for inst, bosses in pairs(DungeonMapDB.manual or {}) do
        for name, m in pairs(bosses) do
            local b = shipped(inst, name)
            if b and type(m.x) == "number" and type(m.y) == "number" and m.floor then
                local same = b.x and b.floor == m.floor and math.abs(b.x - m.x) < 0.003 and math.abs(b.y - m.y) < 0.003
                if not same then pos[#pos + 1] = format("P|%d|%d|%s|%.4f|%.4f", inst, m.floor, name, m.x, m.y) end
            end
        end
    end
    for inst, bosses in pairs(DungeonMapDB.portraits or {}) do
        for name, id in pairs(bosses) do
            local b = shipped(inst, name)
            if b and not b.display and not b.portrait then disp[#disp + 1] = format("D|%d|%s|%d", inst, name, id) end
        end
    end
    table.sort(pos)
    table.sort(disp)
    local lines = {}
    for _, l in ipairs(pos) do lines[#lines + 1] = l end
    for _, l in ipairs(disp) do lines[#lines + 1] = l end
    return lines, #pos, #disp
end

local function plural(n, word) return format("%d %s%s", n, word, n == 1 and "" or "s") end

function ns.ShowReport()
    local lines, np, nd = ns.BuildReport()
    local f = DungeonMapReportFrame
    if not f then
        f = ns.NewWindow("DungeonMapReportFrame")
        f:SetSize(500, 270)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetTitle then f:SetTitle("Share my recordings") end
        f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.info:SetPoint("TOPLEFT", 16, -34)
        f.info:SetPoint("TOPRIGHT", -16, -34)
        f.info:SetJustifyH("LEFT")
        f.info:SetWordWrap(true)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -90)
        sf:SetPoint("BOTTOMRIGHT", -34, 44)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(440)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        f.link = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.link:SetSize(150, 24)
        f.link:SetPoint("BOTTOMLEFT", 16, 12)
        f.link:SetText("Copy the GitHub link")
        f.link:SetScript("OnClick", function() ns.ShowLink(ISSUES_URL) end)
        f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.close:SetSize(90, 24)
        f.close:SetPoint("BOTTOMRIGHT", -16, 12)
        f.close:SetText("Close")
        f.close:SetScript("OnClick", function() f:Hide() end)
    end
    if #lines == 0 then
        f.info:SetText("Nothing to share yet. To record a boss position: type /dm dev once, then /dm edit, pick the boss in the list and click its spot on the map. Then come back here.")
        f.edit:SetText("")
    else
        f.info:SetText(format("%s ready. Press Ctrl+C to copy the text below, then paste it into a new issue on GitHub (the button copies the link). Thank you!",
            (np > 0 and nd > 0) and (plural(np, "position") .. " and " .. plural(nd, "portrait")) or (np > 0 and plural(np, "position") or plural(nd, "portrait"))))
        f.edit:SetText(header() .. "\n" .. table.concat(lines, "\n"))
    end
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end
