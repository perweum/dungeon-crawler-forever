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
    r.bg:SetAtlas("heavybronze-frame-background") -- the sidebar's own brown grainy texture (was a grey tint)
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
    r.glyph = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- "..." for a quest you are on (the game's in-progress mark)
    r.glyph:SetPoint("CENTER", r.icon, "CENTER", 0, 3)
    r.glyph:SetText("...")
    r.glyph:SetTextColor(1, 0.82, 0)
    r.glyph:Hide()
    r.expand = r:CreateTexture(nil, "OVERLAY")
    r.expand:SetPoint("RIGHT", -8, 0)
    -- the journey's stepper: a line down the left (solid on the current stop, dotted after it) and a circle on every stop
    r.railLine = r:CreateTexture(nil, "BORDER")
    r.railLine:SetColorTexture(1, 0.82, 0, 0.9)
    r.railLine:Hide()
    r.railDots = {}
    r.upLine = r:CreateTexture(nil, "BORDER") -- the piece of the line above a stop's circle, so it joins the line of the stop before
    r.upLine:SetColorTexture(1, 0.82, 0, 0.9)
    r.upLine:Hide()
    r.upDots = {}
    r.node = r:CreateTexture(nil, "OVERLAY")
    r.node:SetTexture("Interface\\Buttons\\UI-RadioButton")
    r.node:Hide()
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r:SetScript("OnClick", function(self) ui.Click(self) end)
    r.share = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.share:SetText("Share")
    r.share:SetScript("OnClick", function(self)
        if self.questID then ns.ShareQuest(self.questID) end
    end)
    r.share:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Share with your party")
        GameTooltip:AddLine("Offers this quest to everyone in your group, like Share Quest in the quest log.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    r.share:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.share:Hide()
    r.track = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.track:SetScript("OnClick", function(self)
        local q = self.trackQuest
        if not q then return end
        local on = not ns.IsQuestTracked(q.id)
        ns.SetQuestTracked(q, self.instance, on)
        if on then ns.Print(format("Marked on the world map: %s (%s)", ns.QuestTitle(q), q.giverZone or "?")) end
        ns.RefreshMap()
    end)
    r.track:SetScript("OnEnter", function(self)
        local q = self.trackQuest
        if not q then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if ns.IsQuestTracked(q.id) then
            GameTooltip:SetText("Stop tracking")
            GameTooltip:AddLine("Removes the blue quest marker from the world map.", 0.9, 0.9, 0.9, true)
        else
            GameTooltip:SetText("Track")
            GameTooltip:AddLine("Puts a blue quest marker on the world map where this quest starts" .. (q.giverZone and (" (" .. q.giverZone .. ")") or "") .. ". It goes away once you have the quest.", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    r.track:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.track:Hide()
    r:SetScript("OnEnter", function(self)
        if ui.wide or ui.sideDetail or not self.entry then return end -- the pane has the details
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

local DOTS = 9
-- Draw the stepper's line on a row: mode "solid" | "dotted" | nil; x = the line's distance from the row's left edge (may be negative: the row is indented)
local function setRail(r, mode, x, S, grow, from)
    r.railLine:Hide()
    r.upLine:Hide()
    for _, d in ipairs(r.railDots) do d:Hide() end
    for _, d in ipairs(r.upDots) do d:Hide() end
    if not mode then return end
    from = from or 0
    local h = r:GetHeight() + (grow or 0) - from
    if mode == "solid" then
        r.railLine:ClearAllPoints()
        r.railLine:SetPoint("TOP", r, "TOPLEFT", x, -from)
        r.railLine:SetSize(2, h)
        r.railLine:Show()
        return
    end
    local step = 6 -- a dot every 6 pixels, always the same: whole pixels only, so the dots look alike
    local n = math.floor(h / step)
    for i = 1, n do
        local d = r.railDots[i]
        if not d then
            d = r:CreateTexture(nil, "BORDER")
            d:SetColorTexture(0.62, 0.62, 0.62, 0.85)
            r.railDots[i] = d
        end
        d:SetSize(2, 2)
        d:ClearAllPoints()
        d:SetPoint("TOP", r, "TOPLEFT", math.floor(x + 0.5), -(math.floor(from + 0.5) + (i - 1) * step + 1))
        d:Show()
    end
end

-- from the top of a stop's row down to its circle: the same line as the one that ended the stop before
local function setRailUp(r, mode, x, len)
    if not mode or len < 2 then return end
    if mode == "solid" then
        r.upLine:ClearAllPoints()
        r.upLine:SetPoint("TOP", r, "TOPLEFT", x, 0)
        r.upLine:SetSize(2, len)
        r.upLine:Show()
        return
    end
    local step, n = 6, math.max(1, math.floor(len / 6))
    for i = 1, n do
        local d = r.upDots[i]
        if not d then
            d = r:CreateTexture(nil, "BORDER")
            d:SetColorTexture(0.62, 0.62, 0.62, 0.85)
            r.upDots[i] = d
        end
        d:SetSize(2, 2)
        d:ClearAllPoints()
        d:SetPoint("TOP", r, "TOPLEFT", math.floor(x + 0.5), -((i - 1) * step))
        d:Show()
    end
end

-- The quest behind the highlighted row of the Quests tab (state.questSel), or nil: a chain gives its current step.
function ui.SelectedQuest(instanceID, sel)
    if type(sel) ~= "string" then return end
    local id = tonumber(sel:match("^q:(%d+)$"))
    if id then return ns.QuestById(instanceID, id) end -- (a chain header is not a quest: pick a step)
end

function ui.entryTitle(e)
    if e.kind == "chain" then return ns.QuestTitle(e.steps[1].q) end -- a chain is named after the quest that starts it
    return ns.QuestTitle(e.q)
end

function ui.Click(row)
    local st = ns.GetState()
    st.questExpanded = st.questExpanded or {}
    if row.head == "stop" then
        st.stopOpen = st.stopOpen or {}
        st.stopOpen[row.stopKey] = not row.stopIsOpen
    elseif row.head == "pre" then
        st.questExpanded.__preClosed = not st.questExpanded.__preClosed
    elseif row.head then
        st.questExpanded.__done = not st.questExpanded.__done
    elseif row.entry and ns.editing and ns.MARKER_KINDS[ns.editKind] and ns.MARKER_KINDS[ns.editKind].quest then
        -- edit mode with a quest marker chosen: the click picks the quest for the marker. A chain header only opens (its steps are picked one by one:
        -- picking "the chain" used to give its first step, so a marker for a later step like No Orc Left Behind went to the wrong quest)
        local e = row.entry
        if e.kind == "chain" then
            st.questExpanded[key(e)] = not st.questExpanded[key(e)]
        else
            st.questSel = key(e) -- the highlight follows the pick: the kind buttons read the highlighted quest, so an old highlight used to win over it
            ns.EditSelectQuest(e.q)
            return
        end
    elseif row.entry then
        if not ui.wide and st.questSel == key(row.entry) and row.entry.kind ~= "chain" then
            st.questSel = nil -- the narrow view: clicking the open quest again closes its details
        else
            st.questSel = key(row.entry)
        end
        if row.entry.kind == "chain" then st.questExpanded[key(row.entry)] = not st.questExpanded[key(row.entry)] end
    end
    ns.RefreshMap()
end

-- the sidebar's tab switch ("Bosses | Quests (n) | Route"), below the floor row; tabs = { { key, label }, ... }, active = the key shown; returns the height it takes
-- Our own monochrome pictures for the tab titles (tools/make_tab_icons.py: white shapes, tinted here so they stay one colour)
local ART = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\"
local TAB_ICON = { bosses = ART .. "tab_bosses", quests = ART .. "tab_quests", records = ART .. "tab_highscore" }
local TAB_H = 32 -- tab height (was 22): easier to see and to hit

function ui.LayoutTabs(panel, y, S, pw, tabs, active)
    panel.tabBtns = panel.tabBtns or {}
    for i, def in ipairs(tabs) do
        local b = panel.tabBtns[i]
        if not b then
            b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            b:SetFrameLevel(panel:GetFrameLevel() + 5)
            b:SetScript("OnClick", function(self)
                ns.GetState().tab = self.which
                ns.RefreshMap()
            end)
            panel.tabBtns[i] = b
        end
        b.controllerFocusAnchor = true
        b.which = def.key
        if not b.icon then
            b.icon = b:CreateTexture(nil, "OVERLAY")
        end
    end
    for i = #tabs + 1, #panel.tabBtns do panel.tabBtns[i]:Hide() end
    if #tabs < 2 then for _, b in ipairs(panel.tabBtns) do if b.icon then b.icon:Hide() end end end
    local n = #tabs
    if n < 2 then
        for i = 1, #tabs do panel.tabBtns[i]:Hide() end
        return 0
    end
    local w = math.floor((pw - 28 - (n - 1) * 2) / n)
    for i, def in ipairs(tabs) do
        local btn = panel.tabBtns[i]
        btn:Show()
        btn:SetSize(w, TAB_H * S)
        btn:SetNormalFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
        btn:SetHighlightFontObject(S > 1 and "GameFontHighlightLarge" or "GameFontHighlight")
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + (i - 1) * (w + 2), -y)
        btn:SetText(def.label)
        btn:SetEnabled(def.key ~= active)
        local tex = TAB_ICON[def.key]
        if tex then
            btn.icon:SetTexture(tex)
            -- icon and label are laid out as one group, centred in the tab, with a gap between them
            local iw, gap = 16 * S, 8 * S
            local fs = btn:GetFontString()
            local tw = fs and fs.GetStringWidth and fs:GetStringWidth() or 60
            local start = math.max(4 * S, (w - (iw + gap + tw)) / 2)
            btn.icon:SetSize(iw, iw)
            btn.icon:ClearAllPoints()
            btn.icon:SetPoint("LEFT", btn, "LEFT", start, 0)
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", btn.icon, "RIGHT", gap, 0)
            end
            if def.key == active then btn.icon:SetVertexColor(1, 1, 1, 1) else btn.icon:SetVertexColor(1, 0.82, 0, 1) end
            btn.icon:Show()
        else
            btn.icon:Hide()
        end
    end
    return (TAB_H + 6) * S
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
    -- the two ways to order the quests: a fixed pair of buttons under the title (the one that is on is pressed in)
    box.viewBtns = {}
    for i, def in ipairs({ { key = "journey", label = "Journey" }, { key = "list", label = "List" } }) do
        local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        b:SetFrameLevel(box:GetFrameLevel() + 5)
        b.which = def.key
        b:SetText(def.label)
        -- a small monochrome icon right next to the label (like the Bosses, Quests and Highscore tabs), the pair centred in the button. The list icon is
        -- drawn from plain bars; the journey icon is a game atlas (a drawn trip stands in on a client without it). Colours: see below (gold, white when on).
        b.icon = {}
        local ibox = CreateFrame("Frame", nil, b)
        ibox:SetSize(16, 16)
        local fs = b.GetFontString and b:GetFontString()
        local boxW = 16
        local function bar(x, y, w, h) -- x from the ibox's left edge, y from its middle
            local t = ibox:CreateTexture(nil, "OVERLAY")
            t:SetPoint("LEFT", ibox, "LEFT", x, y)
            t:SetSize(w, h)
            t:SetColorTexture(1, 1, 1, 1)
            b.icon[#b.icon + 1] = t
        end
        if def.key == "list" then
            for k = -1, 1 do bar(0, k * 4, 3, 2); bar(5, k * 4, 9, 2) end
            boxW = 14
        else
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Bonus-Objective-Star")
            if info then
                local t = ibox:CreateTexture(nil, "OVERLAY")
                t:SetPoint("CENTER", ibox, "CENTER", 0, 0)
                t:SetSize(16, 16)
                t:SetAtlas("Bonus-Objective-Star")
                t:SetDesaturated(true)
                t.isRing = true -- tinted with SetVertexColor
                b.icon[#b.icon + 1] = t
            else
                local function ring(x, y)
                    local t = ibox:CreateTexture(nil, "OVERLAY")
                    t:SetPoint("LEFT", ibox, "LEFT", x, y)
                    t:SetSize(9, 9)
                    t:SetTexture("Interface\\Buttons\\UI-RadioButton")
                    t:SetTexCoord(0, 0.25, 0, 1)
                    t.isRing = true
                    b.icon[#b.icon + 1] = t
                end
                ring(0, 5)
                bar(9, 5, 12, 1)
                bar(20, 0, 1, 11)
                for k = 0, 3 do bar(16 - k * 3, -5, 2, 1) end
                ring(0, -5)
                boxW = 21
            end
        end
        ibox:SetWidth(boxW)
        if fs and fs.ClearAllPoints then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", b, "CENTER", (boxW + 6) / 2, 0) -- text a little right of centre, the icon just left of it
            ibox:SetPoint("RIGHT", fs, "LEFT", -6, 0)
        else
            ibox:SetPoint("LEFT", b, "LEFT", 12, 0)
        end
        b:SetScript("OnClick", function(self)
            DungeonMapDB.questView = self.which
            ns.RefreshMap()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.which == "journey" then
                GameTooltip:SetText("Journey")
                GameTooltip:AddLine("The quests in the order to do them: where to pick them up, the dungeon, where to hand them in. The step you are on is open.", 0.9, 0.9, 0.9, true)
            else
                GameTooltip:SetText("List")
                GameTooltip:AddLine("Every quest in one list: dungeon quests, pre-quests and the completed ones.", 0.9, 0.9, 0.9, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        box.viewBtns[i] = b
    end
    -- the journey's short explanation, in gold above the first step
    box.intro = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.intro:SetJustifyH("LEFT")
    box.intro:SetWordWrap(true)
    box.intro:SetText("Your quests in the order to do them: pick up, enter the dungeon, hand in. Do the open step, then the next.")
    box.introLine = box:CreateTexture(nil, "BORDER")
    box.introLine:SetColorTexture(0.78, 0.6, 0.32, 0.6)
    box.introLine:SetHeight(1)
    box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    box.empty:SetPoint("TOPLEFT", 14, -34)
    box.empty:SetText("No quests are known for this dungeon.")
    box.shareAll = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.shareAll:SetFrameLevel(box:GetFrameLevel() + 5)
    box.shareAll:SetScript("OnClick", function(self)
        if self.ids then ns.ShareQuests(self.ids) end
    end)
    box.shareAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Share all with your party")
        GameTooltip:AddLine("Offers every quest of this dungeon that is in your quest log and can be shared, one after another.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    box.shareAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.shareAll:Hide()
    box.trackAll = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.trackAll:SetFrameLevel(box:GetFrameLevel() + 5)
    box.trackAll:SetScript("OnClick", function(self)
        if self.journey then -- this button turns the tracker window on or off (both views)
            ns.TrackerToggle(self.instance)
            ns.RefreshMap()
            return
        end
        for _, q in ipairs(self.quests or {}) do ns.SetQuestTracked(q, self.instance, not self.allTracked) end
        if not self.allTracked then ns.Print(format("Marked %d quests on the world map.", #(self.quests or {}))) end
        ns.RefreshMap()
    end)
    box.trackAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.journey then
            GameTooltip:SetText(self.allTracked and "Stop tracking quests" or "Track quests")
            GameTooltip:AddLine("A small window that says what to do next for this dungeon's quests. It stays open until you close it.", 0.9, 0.9, 0.9, true)
        elseif self.allTracked then
            GameTooltip:SetText("Stop tracking all")
            GameTooltip:AddLine("Removes the blue quest markers of this dungeon from the world map.", 0.9, 0.9, 0.9, true)
        else
            GameTooltip:SetText("Track all")
            GameTooltip:AddLine("Puts a blue quest marker on the world map where each quest of this dungeon that you do not have yet starts.", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    box.trackAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.trackAll:Hide()
    box.allQuests = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.allQuests:SetFrameLevel(box:GetFrameLevel() + 5)
    box.allQuests:SetText("All quests")
    box.allQuests:SetScript("OnClick", function() ns.ShowGameQuestLog() end)
    box.allQuests:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("All quests")
        GameTooltip:AddLine("Leaves the dungeon map for the game's own quest log (every quest you are on). Press the world map key to come back.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    box.allQuests:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    -- the reward display (after the game's own quest reward frame): objective, "choose one of these", "you will receive", experience, reputation, money
    local rw = CreateFrame("Frame", nil, d)
    rw:SetPoint("TOPLEFT", d.body, "BOTTOMLEFT", 0, -12)
    rw:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    rw:SetHeight(10)
    rw.heads, rw.texts, rw.items = {}, {}, {}
    d.rew = rw
    if d.SetClipsChildren then d:SetClipsChildren(true) end
    d:Hide()
    panel.questDetail = d
    panel.questBuilt = true
end

local ITEM_ROW = 36
local function newRewardItem(rw)
    local b = CreateFrame("Button", nil, rw)
    b:SetHeight(ITEM_ROW)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.045)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.iconBack = b:CreateTexture(nil, "BORDER")
    b.iconBack:SetSize(34, 34)
    b.iconBack:SetPoint("LEFT", 2, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("CENTER", b.iconBack)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("LEFT", b.iconBack, "RIGHT", 8, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if type(self.item) == "number" then GameTooltip:SetItemByID(self.item) else GameTooltip:SetText(tostring(self.item or "")) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end -- shift: link in chat
    end)
    return b
end

local function setRewardItem(b, it)
    local what, n = it[1], it[2] or 1
    b.item, b.link = what, nil
    b.count:SetText(n > 1 and tostring(n) or "")
    b.iconBack:SetColorTexture(0.86, 0.68, 0.22, 1)
    b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    if type(what) ~= "number" then -- a name without an id: shown as text only
        b.name:SetText(what)
        b.name:SetTextColor(0.85, 0.85, 0.85)
        return
    end
    b.name:SetText("Item " .. what)
    b.name:SetTextColor(0.6, 0.6, 0.6)
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(what)
        item:ContinueOnItemLoad(function()
            if b.item ~= what then return end -- the button was reused for another item meanwhile
            b.icon:SetTexture(item:GetItemIcon())
            b.name:SetText(item:GetItemName())
            local c1, c2, c3 = item:GetItemQualityColor()
            local r, g, bl
            if type(c1) == "table" then
                r, g, bl = c1.r, c1.g, c1.b
                if not r and c1.color and c1.color.GetRGB then r, g, bl = c1.color:GetRGB() end
            else
                r, g, bl = c1, c2, c3
            end
            if type(r) == "number" then
                b.name:SetTextColor(r, g, bl)
                b.iconBack:SetColorTexture(r, g, bl, 1)
            end
            b.link = item:GetItemLink()
        end)
    end
end

-- Fill the reward display under the details text of the pane for quest q (nil = nothing). S = sidebar scale.
function ui.FillRewards(det, q, S)
    local rw = det.rew
    for _, h in ipairs(rw.heads) do h:Hide() end
    for _, t in ipairs(rw.texts) do t:Hide() end
    for _, b in ipairs(rw.items) do b:Hide() end
    local d = q and ns.GetQuestDetails(q.id)
    if not d then rw:SetHeight(1) return end
    local w = math.max(120, (det:GetWidth() or 0) - 28)
    if w <= 120 then w = 200 end
    local y, hi, ti, ii = 0, 0, 0, 0
    local function text(str, gold)
        ti = ti + 1
        local t = rw.texts[ti]
        if not t then t = rw:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetJustifyH("LEFT"); t:SetWordWrap(true); rw.texts[ti] = t end
        t:SetFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        t:SetWidth(w)
        t:SetText(str)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", rw, "TOPLEFT", 0, -y)
        t:Show()
        y = y + (t:GetStringHeight() or 14) + 6
    end
    local function head(str)
        hi = hi + 1
        local h = rw.heads[hi]
        if not h then h = rw:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetJustifyH("LEFT"); rw.heads[hi] = h end
        h:SetFontObject(S > 1 and "GameFontNormalLarge" or "GameFontNormal")
        h:SetText(str)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", rw, "TOPLEFT", 0, -y)
        h:Show()
        y = y + (h:GetStringHeight() or 16) + 6
    end
    local function items(list)
        for _, it in ipairs(list) do
            ii = ii + 1
            local b = rw.items[ii] or newRewardItem(rw)
            rw.items[ii] = b
            setRewardItem(b, it)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", rw, "TOPLEFT", 0, -y)
            b:SetPoint("TOPRIGHT", rw, "TOPRIGHT", 0, -y)
            b:Show()
            y = y + ITEM_ROW + 3
        end
        y = y + 4
    end
    if d.obj then head("Objectives"); text(d.obj) end
    if d.choose then head(#d.choose > 1 and "You will be able to choose one of these rewards:" or "You will receive:"); items(d.choose) end
    if d.get then head((d.choose and "You will also receive:") or "You will receive:"); items(d.get) end
    if d.xp or d.money or d.rep then
        head("Rewards")
        if d.xp then text("|cffffd100Experience:|r " .. ns.Thousands(d.xp)) end
        for _, r in ipairs(d.rep or {}) do text(format("|cffffd100Reputation:|r +%d with %s", r[2], r[1])) end
        if d.money then text("|cffffd100Money:|r " .. ns.MoneyText(d.money)) end
    end
    rw:SetHeight(math.max(y, 1))
end

-- the entry of the list (or a step of a chain) that a selection key names
function ui.FindEntry(list, selKey)
    for _, e in ipairs(list or {}) do
        if key(e) == selKey then return e end
        if e.kind == "chain" then
            for _, s in ipairs(e.steps) do if key(s) == selKey then return s end end
        end
    end
end

-- Show or hide the quest list (show = the Quests tab is active). S = sidebar scale, wide = wide view, top = y where the boxes start.
function ui.Update(panel, instanceID, show, wide, S, top)
    if not panel.questBuilt then build(panel) end
    local box, det = panel.questBox, panel.questDetail
    ui.wide = wide
    box:SetShown(show)
    -- the detail pane: beside the list in the wide view; under the list (a quest you clicked) in the narrow one
    local st0 = ns.GetState()
    local sideDetail = show and not wide and st0.questSel and ui.FindEntry(ns.GetQuestEntries(instanceID), st0.questSel) ~= nil or false
    ui.sideDetail = sideDetail
    det:SetShown(show and (wide or sideDetail) and true or false)
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
    elseif sideDetail then
        local avail = (panel:GetHeight() or 600) - top - 42
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -top)
        box:SetHeight(math.max(160, math.floor(avail * 0.5)))
        det:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
        det:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
        contentW = pw - 28 - 34
    else
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
        box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
        contentW = pw - 28 - 34
    end
    local barH = (S > 1 and 30 or 24) + 6
    local boxW = wide and math.floor((pw - 28 - 8) * 0.5) or (pw - 28)
    for i, b in ipairs(box.viewBtns) do
        local active = (DungeonMapDB.questView ~= "list") == (b.which == "journey")
        for _, t in ipairs(b.icon) do
            local r, g, bl = 1, 0.82, 0 -- like the label: gold on the red button, white on the greyed one (the view that is on)
            if active then r, g, bl = 1, 1, 1 end
            if t.isRing then t:SetVertexColor(r, g, bl, 1) else t:SetColorTexture(r, g, bl, 1) end
        end
        b:SetNormalFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
        b:SetHighlightFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        b:SetSize(math.floor((boxW - 16 - 2) / 2), barH - 6)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", box, "TOPLEFT", 8 + (i - 1) * (math.floor((boxW - 16 - 2) / 2) + 2), -(titleH + 2))
        b:SetEnabled(not active)
        b:Show()
    end
    local list, counts = ns.GetQuestEntries(instanceID)
    local showIntro = DungeonMapDB.questView ~= "list" and #list > 0
    local introH = 0
    box.intro:SetShown(showIntro)
    box.introLine:SetShown(showIntro)
    if showIntro then
        box.intro:SetFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
        box.intro:ClearAllPoints()
        box.intro:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -(titleH + barH + 2))
        box.intro:SetWidth(math.max(60, boxW - 28))
        introH = (box.intro:GetStringHeight() or 24) + 12
        box.introLine:ClearAllPoints()
        box.introLine:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -(titleH + barH + introH - 5))
        box.introLine:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -(titleH + barH + introH - 5))
    end
    barH = barH + introH
    panel.questScroll:ClearAllPoints()
    panel.questScroll:SetPoint("TOPLEFT", 6, -(titleH + barH))
    panel.questScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    panel.questContent:SetWidth(math.max(40, contentW))

    list = list or {}
    -- display items: open quests, then a folded "Completed" header and the completed ones
    local items = {}
    local function addEntry(e)
        items[#items + 1] = { entry = e }
        local picking = ns.editing and ns.MARKER_KINDS[ns.editKind] and ns.MARKER_KINDS[ns.editKind].quest -- choosing a quest for a marker: chains are open
        if e.kind == "chain" and (picking or st.questExpanded[key(e)]) then
            for _, s in ipairs(e.steps) do items[#items + 1] = { entry = s, step = true } end
        end
    end
    -- three blocks: the dungeon quests, then the pre-quests (needed before them, folded away with the header), then the completed ones
    local doneList, preList = {}, {}
    local journey = DungeonMapDB and DungeonMapDB.questView ~= "list" -- the journey is the default
    for _, e in ipairs(list) do
        if e.status == "done" then doneList[#doneList + 1] = e
        elseif journey then -- the journey lists the open quests step by step below
        elseif e.isPre then preList[#preList + 1] = e
        else addEntry(e) end
    end
    if journey then
        local dname = ns.Dungeons[instanceID] and ns.Dungeons[instanceID].name or "the dungeon"
        local stops, last = {}, nil
        for _, sp in ipairs(ns.GetQuestJourney(instanceID) or {}) do
            if sp.place ~= last then
                stops[#stops + 1] = { place = sp.place, steps = {} }
                last = sp.place
            end
            local stp = stops[#stops]
            stp.steps[#stp.steps + 1] = sp
        end
        st.stopOpen = st.stopOpen or {}
        for n, stp in ipairs(stops) do
            local key = instanceID .. ":" .. n
            local open = st.stopOpen[key]
            if open == nil then open = n == 1 end -- the step you are on is open, the rest is closed until you open it
            local rail = n < #stops and (n == 1 and "solid" or "dotted") or nil
            local railUp = n > 1 and (n - 1 == 1 and "solid" or "dotted") or nil
            items[#items + 1] = { head = "stop", n = n, count = #stp.steps, railUp = railUp, stopKey = key, open = open, rail = rail, current = n == 1,
                text = format("%d. %s", n, stp.place == ns.JOURNEY_DUNGEON and ("Inside " .. dname) or stp.place), dungeon = stp.place == ns.JOURNEY_DUNGEON }
            if open then
                for _, sp in ipairs(stp.steps) do items[#items + 1] = { entry = sp.e, action = sp.kind, rail = rail, journeyRow = true } end
            end
        end
    end
    if #preList > 0 then
        items[#items + 1] = { head = "pre", count = #preList }
        if not st.questExpanded.__preClosed then for _, e in ipairs(preList) do addEntry(e) end end
    end
    if #doneList > 0 then
        items[#items + 1] = { head = "done", count = #doneList }
        if st.questExpanded.__done then for _, e in ipairs(doneList) do addEntry(e) end end
    end
    box.title:SetText(format("Quests (%d open)", counts and counts.open or 0) .. ((counts and (counts.pre or 0) > 0) and format(" + %d pre", counts.pre) or ""))
    -- "Share all" in the header, only in a group and when at least two quests can be shared (one has its own row button)
    local shareIDs = {}
    for _, e in ipairs(list) do
        local id = e.status ~= "done" and ns.CanShareQuest(e)
        if id then shareIDs[#shareIDs + 1] = id end
    end
    local sa = box.shareAll
    sa.ids = shareIDs
    sa:SetShown(#shareIDs > 1)
    if sa:IsShown() then
        sa:SetNormalFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
        sa:SetHighlightFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        sa:SetText(format("Share all (%d)", #shareIDs))
        sa:SetSize(S > 1 and 110 or 90, titleH - 8) -- fits in the header above the list
        sa:ClearAllPoints()
        sa:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -4)
    end
    -- "Track all" / "Untrack all" next to it, when at least two quests you do not have yet can be marked
    local trackQs, allTracked = {}, true
    for _, e in ipairs(list) do
        local q = e.status ~= "done" and ns.TrackTarget(e)
        if q then
            trackQs[#trackQs + 1] = q
            if not ns.IsQuestTracked(q.id) then allTracked = false end
        end
    end
    local ta = box.trackAll
    ta.quests, ta.allTracked, ta.instance = trackQs, allTracked, instanceID
    ta.journey = true -- in the List view as well as the Journey view
    allTracked = ns.TrackerInstance and ns.TrackerInstance() == instanceID or false
    ta.allTracked = allTracked
    ta:SetShown(#list > 0 and #(ns.TrackerSteps and ns.TrackerSteps(instanceID) or {}) > 0 or allTracked)
    if ta:IsShown() then
        ta:SetNormalFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
        ta:SetHighlightFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        ta:SetText(allTracked and "Stop tracking" or "Track quests")
        ta:SetSize((S > 1 and 96 or 76) + 28, titleH - 8)
        ta:ClearAllPoints()
        if sa:IsShown() then ta:SetPoint("RIGHT", sa, "LEFT", -4, 0) else ta:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -4) end
    end
    box.empty:SetShown(#list == 0)
    local aq = box.allQuests
    aq:SetNormalFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
    aq:SetHighlightFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
    aq:SetSize(S > 1 and 92 or 76, titleH - 8)
    aq:ClearAllPoints()
    local lastBtn = ta:IsShown() and ta or (sa:IsShown() and sa or nil)
    if lastBtn then aq:SetPoint("RIGHT", lastBtn, "LEFT", -4, 0) else aq:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -4) end
    aq:Show()

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
        local indent = it.step and 22 or (it.journeyRow and 30 * S or 0)
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
        if it.head == "stop" then
            r.glyph:Hide()
            r.share:Hide()
            r.share.questID = nil
            r.track:Hide()
            r.track.trackQuest = nil
            r.stopKey, r.stopIsOpen = it.stopKey, it.open
            -- the circle on the line: filled on the stop you are on, hollow on the others
            r.icon:Hide()
            r.node:SetSize(22 * S, 22 * S)
            r.node:ClearAllPoints()
            r.node:SetPoint("LEFT", r, "LEFT", 3 * S, 0)
            r.node:SetTexCoord(it.current and 0.25 or 0, it.current and 0.5 or 0.25, 0, 1)
            if it.current then r.node:SetVertexColor(1, 0.82, 0) else r.node:SetVertexColor(0.75, 0.75, 0.75) end
            r.node:Show()
            r.expand:SetSize(18 * S, 18 * S)
            r.expand:SetTexture(it.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            r.expand:Show()
            r.text:SetPoint("LEFT", r.node, "RIGHT", 8, 0)
            r.text:SetPoint("RIGHT", r.expand, "LEFT", -6, 0)
            r.text:SetText(format("%s  |cff9a9a9a(%d)|r", it.text, it.count))
            if it.current then r.text:SetTextColor(1, 0.82, 0) elseif it.dungeon then r.text:SetTextColor(1, 0.5, 0.25) else r.text:SetTextColor(0.8, 0.8, 0.8) end
            r.sub:SetText("")
            -- a closed stop leaves room for the line down to the next circle (otherwise the circles of closed stops touch and the line is not visible)
            it.extra = (not it.open and it.rail) and 7 * S or 0
            setRail(r, it.rail, 14 * S, S, GAP + it.extra, (r:GetHeight() + 22 * S) / 2) -- the line starts below the circle
            setRailUp(r, it.railUp, 14 * S, (r:GetHeight() - 22 * S) / 2 + 2) -- and the line of the stop before runs down to it
        elseif it.head then
            r.node:Hide()
            setRail(r, nil)
            local isPreHead = it.head == "pre"
            local open = isPreHead and not st.questExpanded.__preClosed or (not isPreHead and st.questExpanded.__done)
            r.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            r.icon:SetDesaturated(false)
            r.icon:SetAlpha(1)
            r.icon:Show()
            r.glyph:Hide()
            r.expand:Hide()
            r.share:Hide()
            r.share.questID = nil
            r.track:Hide()
            r.track.trackQuest = nil
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            if isPreHead then
                r.text:SetText(format("Pre-quests (%d) - needed before the dungeon quests", it.count))
                r.text:SetTextColor(0.4, 0.75, 1)
            else
                r.text:SetText(format("Completed (%d)", it.count))
                r.text:SetTextColor(0.4, 0.85, 0.4)
            end
            r.sub:SetText("")
        else
            local e = it.entry
            r.node:Hide()
            r.expand:Hide()
            setRail(r, it.rail, (14 - 30) * S, S, GAP)
            local sub, kind = ns.QuestSubText(e)
            local done = e.status == "done"
            local act = it.action
            if act then -- a journey step: what to do here
                local q = e.q
                local levelLocked = e.status == "locked" and e.reason and e.reason:find("^Requires level")
                if levelLocked then
                    sub, kind = e.reason, "locked"
                elseif act == "pickup" then
                    sub, kind = ns.QuestWhere(q), "ready"
                elseif act == "handin" then
                    local t = q.turnin and (q.turnin .. (q.turninZone and (", " .. q.turninZone) or "")) or (q.giver and ("back to " .. q.giver) or "the quest giver")
                    local prog = e.status == "active" and ns.QuestActiveText(q.id)
                    if prog and prog ~= "Ready to turn in" then sub, kind = prog .. " - then hand in: " .. t, "active"
                    else sub, kind = "Hand in: " .. t, e.status == "active" and "active" or "ready" end
                else
                    if e.status == "active" then sub, kind = ns.QuestActiveText(q.id), "active"
                    elseif q.objective then sub, kind = q.objective, "ready"
                    elseif q.where == "inside" or q.where == "item" then sub, kind = ns.QuestWhere(q), "ready"
                    else sub, kind = "Complete it in the dungeon", "ready" end
                end
            end
            -- the game's marks: ! not started, ... on it, ? ready to hand in, check mark done
            local cur = e.kind == "chain" and e.current or e
            local ready = e.status == "active" and cur and cur.q and ns.QuestProgress(cur.q.id).ready
            r.icon:Show()
            r.glyph:Hide()
            if done then
                r.icon:SetAtlas("common-icon-checkmark")
            elseif ready then
                r.icon:SetAtlas("QuestTurnin")
            elseif e.status == "active" then
                r.icon:Hide()
                r.glyph:SetFontObject(S > 1 and "GameFontNormalHuge" or "GameFontNormalLarge")
                r.glyph:Show()
            else
                r.icon:SetAtlas("QuestNormal")
            end
            if act == "handin" and not done then
                r.glyph:Hide()
                r.icon:Show()
                r.icon:SetAtlas("QuestTurnin")
            end
            local dim = e.status == "locked" and (not act or kind == "locked")
            r.icon:SetDesaturated(dim)
            r.icon:SetVertexColor(1, 1, 1)
            r.icon:SetAlpha(dim and 0.6 or 1)
            local tq = ns.TrackTarget(e)
            if tq and ns.IsQuestTracked(tq.id) and ns.SetQuestMarker then -- tracked: the same blue marker as on the world map
                ns.SetQuestMarker(r.icon)
                r.icon:SetAlpha(1)
            end
            local isChain = e.kind == "chain"
            r.expand:SetShown(isChain)
            if isChain then
                r.expand:SetTexture(st.questExpanded[key(e)] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            end
            local right = isChain and -(30 * S) or -8
            local shareID = (not act or act ~= "pickup") and ns.CanShareQuest(e) or nil
            r.share.questID = shareID
            r.share:SetShown(shareID and true or false)
            if shareID then
                r.share:SetNormalFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
                r.share:SetHighlightFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
                r.share:SetSize(56 * S, 22 * S)
                r.share:ClearAllPoints()
                r.share:SetPoint("RIGHT", r, "RIGHT", right, 0)
                right = right - 60 * S
            end
            local trackQ = not journey and (not act or act == "pickup") and not shareID and ns.TrackTarget(e)
            r.track.trackQuest, r.track.instance = trackQ or nil, instanceID
            r.track:SetShown(trackQ and true or false)
            if trackQ then
                local on = ns.IsQuestTracked(trackQ.id)
                r.track:SetNormalFontObject(S > 1 and "GameFontNormal" or "GameFontNormalSmall")
                r.track:SetHighlightFontObject(S > 1 and "GameFontHighlight" or "GameFontHighlightSmall")
                r.track:SetText(on and "Untrack" or "Track")
                r.track:SetSize(62 * S, 22 * S)
                r.track:ClearAllPoints()
                r.track:SetPoint("RIGHT", r, "RIGHT", right, 0)
                right = right - 66 * S
            end
            r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 4 * S)
            r.text:SetPoint("RIGHT", r, "RIGHT", right, 0)
            r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -4 * S)
            r.sub:SetPoint("RIGHT", r, "RIGHT", right, 0)
            local lvl = isChain and e.steps[1].q.level or e.q.level
            local title = ui.entryTitle(e)
            local prefix = lvl and (levelHex(lvl) .. "[" .. lvl .. "]|r ") or ""
            if e.attune then prefix = "|cffffd100Key|r " .. prefix end
            if e.isPre then prefix = "|cff66ccffPre|r " .. prefix end
            r.text:SetText(prefix .. title)
            local grey = done or dim
            r.text:SetTextColor(grey and 0.62 or 1, grey and 0.62 or 1, grey and 0.62 or 1)
            local c = SUB_COLOR[kind] or SUB_COLOR.ready
            r.sub:SetText(sub)
            r.sub:SetTextColor(c[1], c[2], c[3])
        end
        r:Show()
        y = y + h + GAP + (it.extra or 0)
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    panel.questContent:SetHeight(math.max(y + 12, 10)) -- a little air under the last row (the last pixels were cut off)

    if wide or sideDetail then
        if selected then
            det.name:SetText(ui.entryTitle(selected))
            det.body:SetText(table.concat(ns.QuestDetailLines(selected, true), "\n"))
            -- a chain shows the reward of the step you are on (the last one when all are done)
            local rq = selected.q
            if selected.kind == "chain" then rq = (selected.current and selected.current.q) or selected.steps[#selected.steps].q end
            ui.FillRewards(det, rq, S)
        else
            det.name:SetText("")
            det.body:SetText("")
            ui.FillRewards(det, nil, S)
        end
        det.name:SetFontObject(wide and "GameFontNormalHuge" or "GameFontNormalLarge")
        det.body:SetFontObject(wide and "GameFontHighlightLarge" or "GameFontHighlight")
    end
end
