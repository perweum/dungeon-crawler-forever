-- /dm icons [words]: a browser for the game's own icons (atlases). Type words (all must be in the name), see every match drawn; hover for the name,
-- click one to put its name in the box at the bottom (select it and copy with Ctrl+C). For picking art for the addon: nothing here is used by the addon itself.
local _, ns = ...

local COLS, CELL, MAX_SHOWN = 14, 40, 560
local win, cells, names, shown = nil, {}, nil, {}

-- Every atlas name the client knows (C_Texture.GetAtlasElements on retail clients); nil when this client has no such list
local function allNames()
    if names then return names end
    local f = C_Texture and C_Texture.GetAtlasElements
    if not f then return nil end
    local ok, list = pcall(f)
    if not (ok and type(list) == "table") then return nil end
    names = {}
    for _, n in ipairs(list) do if type(n) == "string" then names[#names + 1] = n end end
    table.sort(names)
    return names
end

local function match(filter)
    local out, all = {}, allNames()
    local words = {}
    for w in (filter or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return out, 0 end
    if not all then -- no list on this client: the typed words are taken as atlas names (comma or space separated)
        for _, w in ipairs(words) do if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(w) then out[#out + 1] = w end end
        return out, #out
    end
    local total = 0
    for _, n in ipairs(all) do
        local low, ok = n:lower(), true
        for _, w in ipairs(words) do if not low:find(w, 1, true) then ok = false break end end
        if ok then
            total = total + 1
            if #out < MAX_SHOWN then out[#out + 1] = n end
        end
    end
    return out, total
end

local function cell(i)
    local c = cells[i]
    if c then return c end
    c = CreateFrame("Button", nil, win.content)
    c:SetSize(CELL, CELL)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(1, 1, 1, 0.06)
    c.tex = c:CreateTexture(nil, "ARTWORK")
    c.tex:SetPoint("CENTER")
    c:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.atlas or "")
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(self.atlas)
        if info and info.width then GameTooltip:AddLine(format("%d x %d", info.width, info.height), 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function(self)
        win.pick:SetText(self.atlas or "")
        win.pick:HighlightText()
        win.pick:SetFocus()
        ns.Print("icon: " .. tostring(self.atlas))
    end)
    cells[i] = c
    return c
end

local function refresh()
    local list, total = match(win.filter:GetText())
    local rows = math.ceil(#list / COLS)
    for i, n in ipairs(list) do
        local c = cell(i)
        c.atlas = n
        local ok = pcall(c.tex.SetAtlas, c.tex, n)
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(n)
        local w, h = (info and info.width) or CELL, (info and info.height) or CELL
        local k = math.min(1, (CELL - 4) / math.max(w, h, 1))
        c.tex:SetSize(math.max(4, w * k), math.max(4, h * k)) -- small icons keep their size, big ones shrink to the cell
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", win.content, "TOPLEFT", ((i - 1) % COLS) * (CELL + 2), -math.floor((i - 1) / COLS) * (CELL + 2))
        c:Show()
        if not ok then c.tex:SetColorTexture(1, 0, 0, 0.4) end
    end
    for i = #list + 1, #cells do cells[i]:Hide() end
    win.content:SetHeight(math.max(10, rows * (CELL + 2)))
    local hasList = allNames() ~= nil
    if (win.filter:GetText() or "") == "" then
        win.count:SetText(hasList and format("%d icons known. Type words to search (for example: quest, map, arrow, route, pin).", #allNames()) or "This client has no atlas list: type exact atlas names to test them.")
    else
        win.count:SetText(format("%d match%s%s", total, total == 1 and "" or "es", total > #list and format(" (showing the first %d: add a word to narrow it)", #list) or ""))
    end
end

function ns.ShowIcons(filter)
    if not win then
        local f = ns.NewWindow("DungeonMapIcons")
        f:SetSize(CELL * COLS + COLS * 2 + 60, 560)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetTitle then f:SetTitle("Icons in the game") end
        f.filter = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.filter:SetSize(300, 22)
        f.filter:SetPoint("TOPLEFT", 22, -34)
        f.filter:SetAutoFocus(false)
        f.filter:SetMaxLetters(60)
        f.filter:SetScript("OnTextChanged", function(self, user) if user and win then refresh() end end)
        f.filter:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.count:SetPoint("LEFT", f.filter, "RIGHT", 12, 0)
        f.count:SetWidth(CELL * COLS - 330)
        f.count:SetJustifyH("LEFT")
        f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 18, -64)
        f.scroll:SetPoint("BOTTOMRIGHT", -34, 44)
        f.content = CreateFrame("Frame", nil, f.scroll)
        f.content:SetSize(CELL * COLS + COLS * 2, 10)
        f.scroll:SetScrollChild(f.content)
        f.pick = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.pick:SetSize(CELL * COLS - 40, 22)
        f.pick:SetPoint("BOTTOMLEFT", 22, 14)
        f.pick:SetAutoFocus(false)
        f.pick:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        win = f
    end
    win:Show()
    if filter and filter ~= "" then win.filter:SetText(filter) end
    refresh()
end
