-- All-floors overview and the floor strip. Both draw floors small, using the same art as the big view:
--   * Overview: every floor of the dungeon on one screen (grid), boss pins and markers scaled down; click a floor to open it.
--   * Strip: a narrow column of floor thumbnails on the left edge of the single-floor view; click to switch floor.
-- Painted maps (retail, legacy, community) have a parchment border and a title banner baked in; the small copies crop them off.
local _, ns = ...

-- fraction of the full art that is kept in small copies: left, right, top, bottom
local CROP = { 0.045, 0.955, 0.125, 0.94 }
local FULL = { 0, 1, 0, 1 }

local function cropFor(floor)
    if floor.yards then return FULL end -- stitched maps have no parchment
    return CROP
end

-- Draw `floor` into `frame` (size w x h, clipping its children). Returns a function mapping the floor's normalised (x, y)
-- to pixels from the frame's top-left corner, and the pixel size of one "unit" for pins.
function ns.DrawFloor(frame, floor, w, h)
    frame.tiles = frame.tiles or {}
    frame:SetClipsChildren(true)
    local used = 0
    local function tex()
        used = used + 1
        local t = frame.tiles[used]
        if not t then
            t = frame:CreateTexture(nil, "ARTWORK")
            frame.tiles[used] = t
        end
        t:ClearAllPoints()
        t:Show()
        return t
    end
    local place
    if floor.yards then
        local s = math.min(w / floor.w, h / floor.h)
        local ox, oy = (w - floor.w * s) / 2, (h - floor.h * s) / 2
        for _, t in ipairs(floor.tiles) do
            local size = (t[4] or 128) * s
            local x = tex()
            x:SetSize(size + 0.6, size + 0.6)
            x:SetPoint("TOPLEFT", frame, "TOPLEFT", ox + t[2] * s, -(oy + t[3] * s))
            x:SetTexture(t[1])
        end
        place = function(nx, ny) return ox + nx * floor.w * s, oy + ny * floor.h * s end
    else
        local c = cropFor(floor)
        local cw, ch = c[2] - c[1], c[4] - c[3]
        local fullW, fullH = w / cw, h / ch
        local ox, oy = -c[1] * fullW, -c[3] * fullH
        local tw, th = floor.tile / floor.w * fullW, floor.tile / floor.h * fullH
        for r, row in ipairs(floor.tiles) do
            for col, fileID in ipairs(row) do
                if fileID ~= "" and fileID ~= 0 then
                    local x = tex()
                    x:SetSize(tw + 0.5, th + 0.5)
                    x:SetPoint("TOPLEFT", frame, "TOPLEFT", ox + (col - 1) * tw, -(oy + (r - 1) * th))
                    x:SetTexture(fileID)
                end
            end
        end
        place = function(nx, ny) return ox + nx * fullW, oy + ny * fullH end
    end
    for i = used + 1, #frame.tiles do frame.tiles[i]:Hide() end
    return place
end

-- Best grid for n floors inside availW x availH (maximises the scale of the floors' aspect ratio).
local function bestGrid(n, availW, availH, aspect)
    local best
    for cols = 1, n do
        local rows = math.ceil(n / cols)
        local cellW, cellH = availW / cols, availH / rows
        local scale = math.min(cellW, cellH * aspect)
        if not best or scale > best.scale then best = { cols = cols, rows = rows, scale = scale, cellW = cellW, cellH = cellH } end
    end
    return best
end

local overview
local function getOverview(view)
    if overview then return overview end
    overview = CreateFrame("Frame", nil, view)
    overview:SetAllPoints(view)
    overview:SetFrameLevel(view:GetFrameLevel() + 20)
    overview.bg = overview:CreateTexture(nil, "BACKGROUND")
    overview.bg:SetAllPoints()
    overview.bg:SetColorTexture(0.06, 0.05, 0.03, 1)
    overview.cells = {}
    overview.linkLayer = CreateFrame("Frame", nil, overview) -- the link lines and their letters, above every floor
    overview.linkLayer:SetAllPoints(overview)
    overview.linkLayer:SetFrameLevel(overview:GetFrameLevel() + 400)
    overview.linkLayer:EnableMouse(false)
    overview.linkLines, overview.linkLabels = {}, {}
    overview:EnableMouse(true)
    overview:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ns.SetOverview(false) end end)
    overview:Hide()
    return overview
end

local function getCell(i)
    local c = overview.cells[i]
    if c then return c end
    c = CreateFrame("Button", nil, overview)
    c.art = CreateFrame("Frame", nil, c)
    c.art:SetPoint("TOPLEFT")
    c.frameTex = c:CreateTexture(nil, "OVERLAY")
    c.frameTex:SetAllPoints()
    c.frameTex:SetColorTexture(1, 0.82, 0, 0)
    c.border = CreateFrame("Frame", nil, c, "BackdropTemplate")
    c.border:SetAllPoints()
    c.border:SetFrameLevel(c:GetFrameLevel() + 30)
    c.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    c.border:SetBackdropBorderColor(0.4, 0.33, 0.15, 1)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.label:SetPoint("TOPLEFT", 6, -5)
    c.labelBg = c:CreateTexture(nil, "OVERLAY", nil, 6)
    c.labelBg:SetColorTexture(0, 0, 0, 0.55)
    c.labelBg:SetPoint("TOPLEFT", c.label, "TOPLEFT", -4, 3)
    c.labelBg:SetPoint("BOTTOMRIGHT", c.label, "BOTTOMRIGHT", 4, -3)
    c.pins = {}
    c.marks = {}
    c:SetScript("OnEnter", function(self) self.border:SetBackdropBorderColor(1, 0.82, 0, 1) end)
    c:SetScript("OnLeave", function(self) self.border:SetBackdropBorderColor(0.4, 0.33, 0.15, 1) end)
    c:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.SetOverview(false) return end
        ns.OpenFloor(self.floorIndex)
    end)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overview.cells[i] = c
    return c
end

-- Render the overview. `ctx` = { view, panelW, floors, bosses, instanceID, wing, pinFactory, markerFactory, markers, order }
function ns.RenderOverview(ctx)
    local ov = getOverview(ctx.view)
    local n = #ctx.floors
    local margin, gap = 12, 10
    local availW = ctx.view:GetWidth() - ctx.panelW - 24 - margin * 2
    local availH = ctx.view:GetHeight() - margin * 2
    local f1 = ctx.floors[1]
    local aspect = f1.yards and (f1.w / f1.h) or ((CROP[2] - CROP[1]) * f1.w / ((CROP[4] - CROP[3]) * f1.h))
    local g = bestGrid(n, availW + gap, availH + gap, aspect)
    local cw = math.min(g.cellW - gap, (g.cellH - gap) * aspect)
    local ch = cw / aspect
    local totalW, totalH = g.cols * (cw + gap) - gap, g.rows * (ch + gap) - gap
    local x0 = margin + (availW - totalW) / 2
    local y0 = margin + (availH - totalH) / 2
    local pinSize = math.max(14, math.min(30, cw * 0.075))
    for i, floor in ipairs(ctx.floors) do
        local c = getCell(i)
        local col, row = (i - 1) % g.cols, math.floor((i - 1) / g.cols)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", ov, "TOPLEFT", x0 + col * (cw + gap), -(y0 + row * (ch + gap)))
        c:SetSize(cw, ch)
        c.art:SetSize(cw, ch)
        c.floorIndex = i
        local place = ns.DrawFloor(c.art, floor, cw, ch)
        c.place, c.ox, c.oy, c.uiMapID = place, x0 + col * (cw + gap), y0 + row * (ch + gap), floor.uiMapID
        c.label:SetText(format("%d. %s", i, floor.name or ("Floor " .. i)))
        -- bosses on this floor
        local used = 0
        for idx, b in ipairs(ctx.bosses) do
            if b.x and tonumber(b.floor) == floor.uiMapID then
                used = used + 1
                local p = c.pins[used] or ctx.pinFactory(c)
                c.pins[used] = p
                p:SetFrameLevel(c:GetFrameLevel() + 40)
                ctx.sizePin(p, pinSize)
                ctx.fillPin(p, b, idx)
                local px, py = place(b.x, b.y)
                p:ClearAllPoints()
                p:SetPoint("CENTER", c, "TOPLEFT", px, -py)
                p:Show()
            end
        end
        for k = used + 1, #c.pins do c.pins[k]:Hide() end
        -- markers on this floor
        local m = 0
        for _, mk in ipairs(ctx.markers(floor.uiMapID)) do
            m = m + 1
            local f = c.marks[m] or ctx.markerFactory(c)
            c.marks[m] = f
            f:SetFrameLevel(c:GetFrameLevel() + 38)
            ctx.fillMarker(f, mk, math.max(12, pinSize * 0.75))
            if f.letter then f.letter:SetText("") end -- the overview draws its own coloured letters at the line ends
            local px, py = place(mk.x, mk.y)
            f:ClearAllPoints()
            f:SetPoint("CENTER", c, "TOPLEFT", px, -py)
            f:Show()
        end
        for k = m + 1, #c.marks do c.marks[k]:Hide() end
        c:Show()
    end
    for i = n + 1, #ov.cells do ov.cells[i]:Hide() end
    -- links: a coloured line between the two ends, and the same letter at both ends
    local COLORS = { { 0.45, 0.8, 1 }, { 1, 0.6, 0.3 }, { 0.5, 1, 0.5 }, { 1, 0.5, 0.8 }, { 0.9, 0.9, 0.3 }, { 0.7, 0.55, 1 }, { 0.4, 1, 0.9 }, { 1, 0.45, 0.4 } }
    local byFloor = {}
    for i = 1, n do byFloor[ctx.floors[i].uiMapID] = ov.cells[i] end
    local letters = ctx.instanceID and ns.LinkLetters(ctx.instanceID) or {}
    local used = 0
    for li, e in ipairs(letters) do
        local l = e.link
        local ca, cb = byFloor[l.fa], byFloor[l.fb]
        if ca and cb and ca.place and cb.place then
            used = used + 1
            local ax, ay = ca.place(l.xa, l.ya)
            local bx, by = cb.place(l.xb, l.yb)
            ax, ay, bx, by = ca.ox + ax, ca.oy + ay, cb.ox + bx, cb.oy + by
            local col = COLORS[(li - 1) % #COLORS + 1]
            local line = ov.linkLines[used]
            if not line then
                line = ov.linkLayer:CreateLine(nil, "OVERLAY")
                line:SetThickness(2.5)
                ov.linkLines[used] = line
            end
            line:SetColorTexture(col[1], col[2], col[3], 0.85)
            line:SetStartPoint("TOPLEFT", ov, ax, -ay)
            line:SetEndPoint("TOPLEFT", ov, bx, -by)
            line:Show()
            for end_ = 1, 2 do
                local k = (used - 1) * 2 + end_
                local fs = ov.linkLabels[k]
                if not fs then
                    fs = ov.linkLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    local f, sz = fs:GetFont()
                    if f then fs:SetFont(f, sz, "OUTLINE") end
                    ov.linkLabels[k] = fs
                end
                fs:SetText(e.letter)
                fs:SetTextColor(col[1], col[2], col[3])
                fs:ClearAllPoints()
                fs:SetPoint("BOTTOMLEFT", ov, "TOPLEFT", (end_ == 1 and ax or bx) + 6, -((end_ == 1 and ay or by)) + 2)
                fs:Show()
            end
        end
    end
    for k = used + 1, #ov.linkLines do ov.linkLines[k]:Hide() end
    for k = used * 2 + 1, #ov.linkLabels do ov.linkLabels[k]:Hide() end
    ov:Show()
end

function ns.HideOverview()
    if overview then overview:Hide() end
end

-- Floor strip -----------------------------------------------------------------------------------

local strip
function ns.RenderStrip(ctx)
    if not strip then
        strip = CreateFrame("Frame", nil, ctx.view)
        strip:SetFrameLevel(ctx.view:GetFrameLevel() + 60)
        strip.thumbs = {}
    end
    -- an overview map (one map of the whole dungeon, its own proportions) is not a thumbnail: it is one click away in the floor picker
    local items = {}
    for i, fl in ipairs(ctx.floors) do
        if not fl.overview then items[#items + 1] = { floor = fl, index = i } end
    end
    local n = #items
    if n < 2 or ctx.hidden then strip:Hide() return end
    local tw = 92
    local f1 = items[1].floor
    local aspect = f1.yards and (f1.w / f1.h) or ((CROP[2] - CROP[1]) * f1.w / ((CROP[4] - CROP[3]) * f1.h))
    local th = tw / aspect
    local gap = 6
    local avail = ctx.view:GetHeight() - 24 - 40 -- keep clear of the zoom buttons at the bottom
    if n * (th + gap) - gap > avail then -- too many floors for the height: shrink
        th = (avail + gap) / n - gap
        tw = th * aspect
    end
    strip:SetSize(tw + 4, n * (th + gap))
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", 8, -12)
    for i, item in ipairs(items) do
        local floor = item.floor
        local b = strip.thumbs[i]
        if not b then
            b = CreateFrame("Button", nil, strip)
            b.art = CreateFrame("Frame", nil, b)
            b.art:SetPoint("TOPLEFT")
            b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
            b.border:SetAllPoints()
            b.border:SetFrameLevel(b:GetFrameLevel() + 10)
            b.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
            b.num = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.num:SetPoint("TOPLEFT", 3, -2)
            b.dots = {}
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.title or "")
                GameTooltip:AddLine("Click to open this floor", 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", GameTooltip_Hide)
            b:SetScript("OnClick", function(self) ns.OpenFloor(self.floorIndex) end)
            strip.thumbs[i] = b
        end
        b.floorIndex = item.index
        b.title = format("%d. %s", item.index, floor.name or ("Floor " .. item.index))
        b:SetSize(tw, th)
        b.art:SetSize(tw, th)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", strip, "TOPLEFT", 2, -((i - 1) * (th + gap)))
        local place = ns.DrawFloor(b.art, floor, tw, th)
        b.num:SetText(item.index)
        local current = (item.index == ctx.floorIndex)
        if current then b.border:SetBackdropBorderColor(1, 0.82, 0, 1) else b.border:SetBackdropBorderColor(0.3, 0.25, 0.12, 1) end
        b.art:SetAlpha(current and 1 or 0.8)
        -- boss dots
        local d = 0
        for _, bo in ipairs(ctx.bosses) do
            if bo.x and tonumber(bo.floor) == floor.uiMapID then
                d = d + 1
                local dot = b.dots[d]
                if not dot then
                    dot = b:CreateTexture(nil, "OVERLAY", nil, 5)
                    dot:SetSize(6, 6)
                    b.dots[d] = dot
                end
                dot:SetColorTexture(1, 0.82, 0.1, 1)
                local px, py = place(bo.x, bo.y)
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", b, "TOPLEFT", px, -py)
                dot:Show()
            end
        end
        for k = d + 1, #b.dots do b.dots[k]:Hide() end
        b:Show()
    end
    for i = n + 1, #strip.thumbs do strip.thumbs[i]:Hide() end
    strip:Show()
end

function ns.HideStrip()
    if strip then strip:Hide() end
end
