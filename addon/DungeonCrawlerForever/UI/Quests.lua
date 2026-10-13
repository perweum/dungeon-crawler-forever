-- Quests view of the sidebar: a "Bosses | Quests" switch, the quest list (chains are one collapsible row, completed quests are folded)
-- and, in the wide view, a detail pane. Data and rules: Quests.lua. Text only: no quest markers on our maps (D-058).
local _, ns = ...

local ui = {}
ns.QuestsUI = ui

local ROW_H, GAP = 44, 3
local TOOLTIP_SCALE = 1.35 -- quest tooltips are drawn larger than the game's default tooltip
local rows = {}

local function levelHex(level)
    if level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if type(c) == "table" and c.r then return format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5)) end
    end
    return "|cffffffff"
end

local SUB_COLOR = { ready = { 0.7, 0.7, 0.7 }, locked = { 1, 0.62, 0.38 }, active = { 1, 0.82, 0 }, done = { 0.4, 0.85, 0.4 } }

local function key(e) return e.kind == "chain" and ("c:" .. e.name) or ("q:" .. e.q.id) end

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
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT", 8, 0)
    r.expand = r:CreateTexture(nil, "OVERLAY")
    r.expand:SetPoint("RIGHT", -8, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r:SetScript("OnClick", function(self) ui.Click(self) end)
    r:SetScript("OnEnter", function(self)
        if ui.wide or not self.entry then return end -- the wide view has the detail pane
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetScale(TOOLTIP_SCALE) -- the default tooltip text is small; put back on leave
        local lines = ns.QuestDetailLines(self.entry)
        GameTooltip:SetText(ui.entryTitle(self.entry))
        for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function()
        GameTooltip:SetScale(1)
        GameTooltip:Hide()
    end)
    return r
end

function ui.entryTitle(e)
    if e.kind == "chain" then return ns.QuestTitle(e.steps[1].q) end -- a chain is named after the quest that starts it
    return ns.QuestTitle(e.q)
end

function ui.Click(row)
    local st = ns.GetState()
    st.questExpanded = st.questExpanded or {}
    if row.head then
        st.questExpanded.__done = not st.questExpanded.__done
    elseif row.entry then
        st.questSel = key(row.entry)
        if row.entry.kind == "chain" then st.questExpanded[key(row.entry)] = not st.questExpanded[key(row.entry)] end
    end
    ns.RefreshMap()
end

-- the sidebar's "Bosses | Quests (n)" switch, below the floor row; returns the height it takes
function ui.LayoutTabs(panel, y, S, pw, has, nOpen, active)
    if not panel.tabBosses then
        local function tab(label, which)
            local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            b:SetFrameLevel(panel:GetFrameLevel() + 5)
            b:SetScript("OnClick", function()
                ns.GetState().tab = which
                ns.RefreshMap()
            end)
            return b
        end
        panel.tabBosses, panel.tabQuests = tab("Bosses", "bosses"), tab("Quests", "quests")
    end
    local a, b = panel.tabBosses, panel.tabQuests
    a:SetShown(has)
    b:SetShown(has)
    if not has then return 0 end
    local w = math.floor((pw - 28 - 2) / 2)
    for i, btn in ipairs({ a, b }) do
        btn:SetSize(w, 22 * S)
        btn:SetNormalFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
        btn:SetHighlightFontObject(S > 1 and "GameFontHighlightLarge" or "GameFontHighlight")
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (i - 1) * (w + 2), -y)
    end
    a:SetText("Bosses")
    b:SetText(format("Quests (%d)", nOpen or 0))
    a:SetEnabled(active == "quests")
    b:SetEnabled(active ~= "quests")
    return 28 * S
end

local function build(panel)
    local box = ns.CreateBox(panel)
    box.title:SetText("Quests")
    box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    box.scroll:SetPoint("TOPLEFT", 6, -26)
    box.scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    box.content = CreateFrame("Frame", nil, box.scroll)
    box.content:SetSize(10, 10)
    box.scroll:SetScrollChild(box.content)
    box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    box.empty:SetPoint("TOPLEFT", 14, -34)
    box.empty:SetText("No quests are known for this dungeon.")
    box:Hide()
    panel.questBox, panel.questScroll, panel.questContent = box, box.scroll, box.content

    local d = ns.CreateBox(panel)
    d.title:SetText("Details")
    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", 14, -34)
    d.name:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.name:SetJustifyH("LEFT")
    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.body:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -10)
    d.body:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    d.body:SetWordWrap(true)
    d:Hide()
    panel.questDetail = d
    panel.questBuilt = true
end

-- Show or hide the quest list (show = the Quests tab is active). S = sidebar scale, wide = wide view, top = y where the boxes start.
function ui.Update(panel, instanceID, show, wide, S, top)
    if not panel.questBuilt then build(panel) end
    local box, det = panel.questBox, panel.questDetail
    ui.wide = wide
    box:SetShown(show)
    det:SetShown(show and wide)
    if not show then return end
    local st = ns.GetState()
    st.questExpanded = st.questExpanded or {}

    box:ClearAllPoints()
    det:ClearAllPoints()
    local pw = panel:GetWidth()
    local cut = wide and 11 or 7
    box:SetCut(cut)
    det:SetCut(cut)
    local titleH = wide and 38 or 26
    box.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")
    det.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")
    local contentW
    if wide then
        local avail = pw - 28 - 8
        local lw = math.floor(avail * 0.5)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        box:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 42)
        box:SetWidth(lw)
        det:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
        det:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
        contentW = lw - 34
    else
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
        contentW = pw - 28 - 34
    end
    panel.questScroll:ClearAllPoints()
    panel.questScroll:SetPoint("TOPLEFT", 6, -titleH)
    panel.questScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    panel.questContent:SetWidth(math.max(40, contentW))

    local list, counts = ns.GetQuestEntries(instanceID)
    list = list or {}
    -- display items: open quests, then a folded "Completed" header and the completed ones
    local items = {}
    local function addEntry(e)
        items[#items + 1] = { entry = e }
        if e.kind == "chain" and st.questExpanded[key(e)] then
            for _, s in ipairs(e.steps) do items[#items + 1] = { entry = s, step = true } end
        end
    end
    local doneList = {}
    for _, e in ipairs(list) do
        if e.status == "done" then doneList[#doneList + 1] = e else addEntry(e) end
    end
    if #doneList > 0 then
        items[#items + 1] = { head = true, count = #doneList }
        if st.questExpanded.__done then for _, e in ipairs(doneList) do addEntry(e) end end
    end
    box.title:SetText(format("Quests (%d open)", counts and counts.open or 0))
    box.empty:SetShown(#list == 0)

    local selected
    for _, it in ipairs(items) do
        if it.entry and key(it.entry) == st.questSel then selected = it.entry end
    end
    if not selected then
        for _, it in ipairs(items) do if it.entry and not it.step then selected = it.entry break end end
    end

    local y = 0
    for i, it in ipairs(items) do
        local r = rows[i] or createRow(panel.questContent)
        rows[i] = r
        r:SetParent(panel.questContent)
        r.entry, r.head = it.entry, it.head
        local h = (it.head and 30 or ROW_H) * S
        r:SetHeight(h)
        r:ClearAllPoints()
        local indent = it.step and 22 or 0
        r:SetPoint("TOPLEFT", panel.questContent, "TOPLEFT", indent, -y)
        r:SetPoint("TOPRIGHT", panel.questContent, "TOPRIGHT", 0, -y)
        r.bar:SetWidth(3 * S)
        local isel = (it.entry and selected and key(it.entry) == key(selected)) and true or false
        r.hl:SetShown(isel)
        r.bar:SetShown(isel)
        r.icon:SetSize(24 * S, 24 * S)
        r.expand:SetSize(18 * S, 18 * S)
        r.text:SetFontObject(S > 1 and "GameFontHighlightLarge" or "GameFontHighlight")
        r.sub:SetFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        r.text:ClearAllPoints()
        r.sub:ClearAllPoints()
        if it.head then
            local open = st.questExpanded.__done
            r.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            r.icon:SetDesaturated(false)
            r.icon:SetAlpha(1)
            r.expand:Hide()
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.text:SetText(format("Completed (%d)", it.count))
            r.text:SetTextColor(0.4, 0.85, 0.4)
            r.sub:SetText("")
        else
            local e = it.entry
            local sub, kind = ns.QuestSubText(e)
            local done = e.status == "done"
            if done then
                r.icon:SetAtlas("common-icon-checkmark")
            elseif e.status == "active" then
                r.icon:SetAtlas("QuestTurnin")
            else
                r.icon:SetAtlas("QuestNormal")
            end
            r.icon:SetDesaturated(e.status == "locked")
            r.icon:SetAlpha(e.status == "locked" and 0.6 or 1)
            local isChain = e.kind == "chain"
            r.expand:SetShown(isChain)
            if isChain then
                r.expand:SetTexture(st.questExpanded[key(e)] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            end
            r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 4 * S)
            r.text:SetPoint("RIGHT", r, "RIGHT", isChain and -(30 * S) or -8, 0)
            r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -4 * S)
            r.sub:SetPoint("RIGHT", r, "RIGHT", isChain and -(30 * S) or -8, 0)
            local lvl = isChain and e.steps[1].q.level or e.q.level
            local title = ui.entryTitle(e)
            local prefix = lvl and (levelHex(lvl) .. "[" .. lvl .. "]|r ") or ""
            if e.attune then prefix = "|cffffd100Key|r " .. prefix end
            r.text:SetText(prefix .. title)
            local grey = done or e.status == "locked"
            r.text:SetTextColor(grey and 0.62 or 1, grey and 0.62 or 1, grey and 0.62 or 1)
            local c = SUB_COLOR[kind] or SUB_COLOR.ready
            r.sub:SetText(sub)
            r.sub:SetTextColor(c[1], c[2], c[3])
        end
        r:Show()
        y = y + h + GAP
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    panel.questContent:SetHeight(math.max(y, 10))

    if wide then
        if selected then
            det.name:SetText(ui.entryTitle(selected))
            det.body:SetText(table.concat(ns.QuestDetailLines(selected), "\n"))
        else
            det.name:SetText("")
            det.body:SetText("")
        end
        det.name:SetFontObject("GameFontNormalHuge")
        det.body:SetFontObject("GameFontHighlightLarge")
    end
end
