-- Records tab of the sidebar (shown where the dungeon has an official route): your best time in a level bracket, a switch between the two
-- brackets, and your runs on that board (ranked first, by time; unranked ones greyed with the reason). Hover a run for its splits; the wide
-- view has a detail pane. Data: Records.lua. Local only for now: sharing with party and guild is milestone 2 of LEADERBOARD.md.
local _, ns = ...

local ui = {}
ns.RecordsUI = ui

local ROW_H, GAP = 36, 3
local rows = {}

local function createRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.05)
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.78, 0.3, 0.16)
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(3)
    r.bar:SetColorTexture(0.86, 0.68, 0.22, 1)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.rank:SetPoint("LEFT", 6, 0)
    r.rank:SetWidth(24)
    r.rank:SetJustifyH("CENTER")
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.time:SetJustifyH("LEFT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.tag:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
        ns.GetState().recSel = self.rec and self.rec.id or nil
        ns.RefreshMap()
    end)
    r:SetScript("OnEnter", function(self)
        if ui.wide or not self.rec then return end -- the wide view has the detail pane
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local lines = ns.RecordsDetailLines(ui.instanceID, self.rec)
        GameTooltip:SetText(lines[1])
        for i = 2, #lines do GameTooltip:AddLine(lines[i], 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function bracketButton(box, which)
    local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    b:SetFrameLevel(box:GetFrameLevel() + 3)
    b:SetScript("OnClick", function()
        ns.GetState().recBracket = which
        ns.RefreshMap()
    end)
    return b
end

local function build(panel)
    local box = ns.CreateBox(panel)
    box.title:SetText("Records")
    box.bestLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.bestTime = box:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    box.bestSub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.bestSub:SetJustifyH("LEFT")
    box.bIn = bracketButton(box, "in")
    box.bOver = bracketButton(box, "over")
    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.hint:SetJustifyH("LEFT")
    box.hint:SetWordWrap(true)
    box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    box.content = CreateFrame("Frame", nil, box.scroll)
    box.content:SetSize(10, 10)
    box.scroll:SetScrollChild(box.content)
    box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    box.empty:SetJustifyH("LEFT")
    box.empty:SetWordWrap(true)
    box:Hide()
    panel.recBox = box

    local d = ns.CreateBox(panel)
    d.title:SetText("Run")
    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.body:SetPoint("TOPLEFT", 14, -40)
    d.body:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    d.body:SetWordWrap(true)
    d:Hide()
    panel.recDetail = d
    panel.recBuilt = true
end

local function dateText(t)
    return date("%b %d", t or 0)
end

-- Show or hide the Records tab (show = it is the active tab). S = sidebar scale, wide = wide view, top = y where the boxes start.
function ui.Update(panel, instanceID, wing, show, wide, S, top)
    if not panel.recBuilt then
        if not show then return end
        build(panel)
    end
    local box, det = panel.recBox, panel.recDetail
    ui.wide, ui.instanceID = wide, instanceID
    box:SetShown(show)
    det:SetShown(show and wide)
    if not show then return end
    local st = ns.GetState()
    if st.recInstance ~= instanceID then
        st.recInstance, st.recSel, st.recBracket = instanceID, nil, nil
        box.scroll:SetVerticalScroll(0)
    end
    local bracket = st.recBracket or ns.RecordsBracket(instanceID, ns.RecordsPlayerLevel())

    box:ClearAllPoints()
    det:ClearAllPoints()
    local pw = panel:GetWidth()
    local cut = wide and 11 or 7
    box:SetCut(cut)
    det:SetCut(cut)
    box.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")
    det.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")
    local boxW
    if wide then
        boxW = math.floor((pw - 28 - 8) * 0.5)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        box:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 42)
        box:SetWidth(boxW)
        det:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
        det:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
    else
        boxW = pw - 28
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
    end
    local innerW = boxW - 28

    -- best time in this bracket
    local label = ns.RecordsBracketLabel(instanceID, bracket)
    local list, older = ns.RecordsList(instanceID, wing, bracket)
    local best = list[1] and list[1].ranked and list[1] or nil
    local y = wide and 40 or 30
    box.bestLabel:ClearAllPoints()
    box.bestLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
    box.bestLabel:SetText("Your best · " .. label)
    y = y + 16
    box.bestTime:ClearAllPoints()
    box.bestTime:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
    box.bestTime:SetText(best and ns.FormatTime(best.total) or "|cff9a9a9a--:--|r")
    box.bestSub:ClearAllPoints()
    box.bestSub:SetPoint("BOTTOMLEFT", box.bestTime, "BOTTOMRIGHT", 10, 2)
    box.bestSub:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    if best then
        box.bestSub:SetText(format("|cff9a9a9a%s · %s|r", dateText(best.date), best.size == 1 and "solo" or (best.size .. " players")))
    else
        box.bestSub:SetText("")
    end
    y = y + 30

    -- the two boards (level brackets)
    local bw = math.floor((innerW - 4) / 2)
    for i, b in ipairs({ box.bIn, box.bOver }) do
        local which = i == 1 and "in" or "over"
        b:SetSize(bw, 20 * S)
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", box, "TOPLEFT", 14 + (i - 1) * (bw + 4), -y)
        b:SetText(ns.RecordsBracketLabel(instanceID, which))
        b:SetEnabled(which ~= bracket)
        b:Show()
    end
    y = y + 20 * S + 6

    local bosses = ns.RecordsRoute(instanceID, wing) or {}
    box.hint:ClearAllPoints()
    box.hint:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -y)
    box.hint:SetWidth(innerW)
    box.hint:SetText(format("Kill all %d bosses on the route, in any order. The clock starts at the first fight.%s", #bosses,
        older > 0 and format(" %d run%s on an older route not shown.", older, older == 1 and "" or "s") or ""))
    y = y + math.max(14, box.hint:GetStringHeight() or 14) + 6

    box.scroll:ClearAllPoints()
    box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -y)
    box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)
    box.content:SetWidth(math.max(40, boxW - 34))
    box.empty:ClearAllPoints()
    box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -(y + 6))
    box.empty:SetWidth(innerW)
    box.empty:SetText(format("No runs in %s yet. Clear the dungeon to set a time; it is kept here even with the timer window off.", label))
    box.empty:SetShown(#list == 0)

    local selected
    for _, r in ipairs(list) do if r.id == st.recSel then selected = r end end
    selected = selected or list[1]

    local cy, rank = 0, 0
    for i, rec in ipairs(list) do
        local r = rows[i] or createRow(box.content)
        rows[i] = r
        r:SetParent(box.content)
        r.rec = rec
        local h = ROW_H * S
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", box.content, "TOPLEFT", 0, -cy)
        r:SetPoint("TOPRIGHT", box.content, "TOPRIGHT", 0, -cy)
        local isSel = rec == selected
        r.hl:SetShown(isSel)
        r.bar:SetShown(isSel)
        if rec.ranked then rank = rank + 1 end
        r.rank:SetText(rec.ranked and tostring(rank) or "|cff9a9a9a-|r")
        r.time:ClearAllPoints()
        r.time:SetPoint("TOPLEFT", r, "TOPLEFT", 34, -4 * S)
        r.time:SetFontObject(S > 1 and "GameFontHighlightLarge" or "GameFontHighlight")
        r.time:SetText(rec.ranked and ns.FormatTime(rec.total) or ("|cff9a9a9a" .. ns.FormatTime(rec.total) .. "|r"))
        r.tag:ClearAllPoints()
        r.tag:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -5 * S)
        local wipes = 0
        for _, p in ipairs(rec.pulls or {}) do if p[3] == 0 then wipes = wipes + 1 end end
        r.tag:SetText(rec.ranked and format("|cff9a9a9a%d deaths · %d wipes|r", rec.deaths or 0, wipes) or "|cffff9a5aunranked|r")
        r.sub:ClearAllPoints()
        r.sub:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 34, 4 * S)
        r.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        local bits = { dateText(rec.date) }
        if rec.level then bits[#bits + 1] = "level " .. rec.level end
        bits[#bits + 1] = rec.size == 1 and "solo" or (rec.size .. " players")
        if rec.mock then bits[#bits + 1] = "test data" end
        r.sub:SetText("|cff9a9a9a" .. table.concat(bits, " · ") .. "|r")
        r:Show()
        cy = cy + h + GAP
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    box.content:SetHeight(math.max(cy, 10))

    if wide then
        det.body:SetFontObject("GameFontHighlightLarge")
        det.body:SetText(selected and table.concat(ns.RecordsDetailLines(instanceID, selected), "\n") or "Pick a run on the left to see its splits.")
    end
end
