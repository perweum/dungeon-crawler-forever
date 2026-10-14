-- Route (developer tool for now): a hand-drawn path through the dungeon. In edit mode choose "Route", click the map to add points and click a boss
-- pin to add a stop at that boss. While you play, the legs between the stops are coloured by progress: done (green), the way to the next boss
-- (bold) and what is left (normal); every leg has its own colour. Data: DungeonMapDB.routes[instanceID][wing or 0] = { {f = floorUiMapID, x, y, boss = name|nil}, ... }
local _, ns = ...

-- Lines are drawn in layers by progress, so the way to the next boss is always on top of legs that double back over it: done / skipped lowest,
-- then the legs ahead, then the active leg. One pool per layer (a line keeps the layer it was created in).
local LAYER = { done = 1, skipped = 1, later = 2, active = 3 }
local lines, badges, dots, steps = { {}, {}, {} }, {}, {}, {}
-- Every leg of the route (the way to one boss) has its own colour; the progress shows in how strong it is: the way to the next boss is bold,
-- legs you have done are faint, legs ahead are normal, a skipped leg is grey.
local LEG_COLORS = { { 0.35, 0.65, 1 }, { 1, 0.6, 0.25 }, { 0.45, 0.85, 0.45 }, { 1, 0.5, 0.8 }, { 0.95, 0.88, 0.35 }, { 0.7, 0.55, 1 }, { 0.4, 0.95, 0.9 }, { 1, 0.45, 0.4 } }
local GREY = { 0.55, 0.55, 0.55 }
local STYLE = { done = { 0.35, 2 }, active = { 1, 4 }, later = { 0.8, 2.5 }, skipped = { 0.45, 2 } } -- alpha, thickness
local function legColor(leg) return LEG_COLORS[(leg - 1) % #LEG_COLORS + 1] end

local function key(wing) return wing or 0 end

-- Points on floors the addon does not show any more (a dungeon whose map was replaced) are dropped from the route, here and in the saved data.
local function prune(list, instanceID)
    if not list then return end
    local shown = ns.ShownFloorSet(instanceID)
    for i = #list, 1, -1 do
        if not shown[list[i].f] then table.remove(list, i) end
    end
end

-- The route of a dungeon: the one recorded in game (developer, /dm edit) when there is one, otherwise the route that ships with the addon (Data/Routes.lua).
function ns.GetRoute(instanceID, wing)
    local r = DungeonMapDB and DungeonMapDB.routes and DungeonMapDB.routes[instanceID]
    local list = r and r[key(wing)] or nil
    prune(list, instanceID)
    if list and #list > 0 then return list end
    local shipped = ns.RouteData and ns.RouteData[instanceID] and ns.RouteData[instanceID][key(wing)]
    if shipped then
        prune(shipped, instanceID)
        return shipped
    end
    return list
end

local function copyRoute(list)
    local out = {}
    for i, p in ipairs(list) do
        local c = {}
        for k, v in pairs(p) do c[k] = v end
        out[i] = c
    end
    return out
end

local function routeFor(instanceID, wing, create)
    DungeonMapDB.routes = DungeonMapDB.routes or {}
    local byInst = DungeonMapDB.routes[instanceID]
    if not byInst then
        if not create then return nil end
        byInst = {}
        DungeonMapDB.routes[instanceID] = byInst
    end
    local r = byInst[key(wing)]
    if not r and create then
        -- editing a dungeon that has a shipped route starts from a copy of it
        local shipped = ns.RouteData and ns.RouteData[instanceID] and ns.RouteData[instanceID][key(wing)]
        r = shipped and copyRoute(shipped) or {}
        byInst[key(wing)] = r
    end
    return r
end

function ns.RouteAdd(instanceID, wing, point)
    local r = routeFor(instanceID, wing, true)
    prune(r, instanceID)
    r[#r + 1] = point
    return #r
end

function ns.RouteUndo(instanceID, wing)
    local r = routeFor(instanceID, wing)
    if r and #r > 0 then
        local last = table.remove(r)
        if last.pair and #r > 0 then table.remove(r) end -- the two ends of a linked door / stair go together
        return true
    end
end

function ns.RouteClear(instanceID, wing)
    local r = routeFor(instanceID, wing)
    if r then for i = #r, 1, -1 do r[i] = nil end end
end

-- Is the route drawn at all? Developer tool: only with /dm dev, and not when the player hid it (/dm route).
ns.routesShipped = true -- routes ship with the addon: every player can show or hide them
function ns.RouteAvailable()
    return DungeonMapDB and (DungeonMapDB.dev or ns.routesShipped) and true or false
end
-- Shown or not: the check box on the map decides for this session; without a choice the option "Show routes by default" applies (off by default).
function ns.RouteVisible()
    if not ns.RouteAvailable() then return false end
    if ns.routeShow ~= nil then return ns.routeShow end
    return DungeonMapDB.routesDefault == true
end

-- Where the route stands: the stops (points with a boss) in order, which ones are defeated, the next one.
-- A stop is SKIPPED when a later stop was defeated first: the route moves on without it. Defeating it afterwards makes it a normal kill again.
-- Returns { stops = { {index, boss, killed, skipped} }, nextStop = n or nil, total = n, skipped = n }
function ns.RouteProgress(instanceID, wing, bosses)
    local route = ns.GetRoute(instanceID, wing) or {}
    local byName = {}
    for _, b in ipairs(bosses or {}) do byName[ns.NormName(b.name)] = b end
    local stops, nextStop, furthest, skipped = {}, nil, 0, 0
    for i, p in ipairs(route) do
        if p.boss then
            local b = byName[ns.NormName(p.boss)]
            local killed = b and ns.IsKilled(b, instanceID) or false
            stops[#stops + 1] = { index = i, boss = p.boss, killed = killed }
            if killed then furthest = #stops end
        end
    end
    for n, st in ipairs(stops) do
        if not st.killed then
            if n < furthest then
                st.skipped = true
                skipped = skipped + 1
            elseif not nextStop then
                nextStop = n
            end
        end
    end
    return { stops = stops, nextStop = nextStop, total = #stops, skipped = skipped }
end

-- What a step at a marker means, for the tooltip
local STEP_TEXT = { up = "Take the stairs up", down = "Take the stairs down", left = "Go left", right = "Go right", entrance = "Entrance", exit = "Exit",
                    portal = "Enter the portal" }
function ns.RouteStepText(p)
    local text
    if p.kind == "trigger" then
        text = "Activate" .. ((p.tag and p.tag ~= "") and (": " .. p.tag) or "") .. (p.mboss and (" (starts " .. p.mboss .. ")") or "")
    else
        text = STEP_TEXT[p.kind] or "Step"
        if p.tag and p.tag ~= "" then text = text .. " " .. p.tag end
    end
    return text
end

local function stepFrame(n, host)
    local f = steps[n]
    if not f then
        f = CreateFrame("Button", nil, host)
        f:SetSize(16, 16)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.label:SetPoint("LEFT", f, "RIGHT", 1, 0)
        local lf, ls = f.label:GetFont()
        if lf then f.label:SetFont(lf, ls, "OUTLINE") end
        f:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Route: " .. (self.text or "step"))
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        steps[n] = f
    end
    return f
end

local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function badge(n, host) -- a round number badge: a ring in the leg colour, a dark disc, the number in the middle
    local b = badges[n]
    if not b then
        b = {}
        b.ring = host:CreateTexture(nil, "ARTWORK", nil, 6)
        b.ring:SetSize(26, 26)
        b.bg = host:CreateTexture(nil, "ARTWORK", nil, 7)
        b.bg:SetSize(22, 22)
        b.bg:SetPoint("CENTER", b.ring)
        b.bg:SetColorTexture(0.06, 0.05, 0.03, 0.9)
        for _, t in ipairs({ b.ring, b.bg }) do
            local m = host:CreateMaskTexture()
            m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            t:AddMaskTexture(m)
        end
        b.fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        b.fs:SetPoint("CENTER", b.ring, "CENTER", 0, 0)
        badges[n] = b
    end
    return b
end

-- Smooth path through the points (Catmull-Rom spline): the curve passes exactly through every point (stops stay where they are) and rounds the
-- corners. Returns a list of {x, y, seg} samples for the run of points `pts`; seg is the segment (point seg to seg + 1) the sample lies on.
local function smooth(pts)
    local out = {}
    local n = #pts
    if n < 3 then
        for i = 1, n do out[#out + 1] = { pts[i][1], pts[i][2], math.min(i, n - 1) } end
        return out
    end
    for i = 1, n - 1 do
        local p0, p1, p2, p3 = pts[math.max(1, i - 1)], pts[i], pts[i + 1], pts[math.min(n, i + 2)]
        local d = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
        local m = math.max(2, math.min(10, math.floor(d / 14)))
        for k = 0, m - 1 do
            local t = k / m
            local t2, t3 = t * t, t * t * t
            out[#out + 1] = {
                0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
                0.5 * ((2 * p1[2]) + (-p0[2] + p2[2]) * t + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2 + (-p0[2] + 3 * p1[2] - 3 * p2[2] + p3[2]) * t3),
                i,
            }
        end
        if i == n - 1 then out[#out + 1] = { p2[1], p2[2], i } end
    end
    return out
end

-- Draw the route of the shown map. host = the clipped frame of the art, art = the art frame (its size scales the points), toDisplay maps a
-- floor point to the shown map (nil when it is not on it).
ns.RouteSmooth = smooth -- for the smoke test

function ns.RenderRoute(host, art, instanceID, wing, floor, toDisplay, bosses, show)
    local route = show and ns.RouteVisible() and floor and ns.GetRoute(instanceID, wing) or nil
    local nl, nb, nd, ns_ = { 0, 0, 0 }, 0, 0, 0
    if route and #route > 0 then
        local W, H = art:GetWidth(), art:GetHeight()
        local prog = ns.RouteProgress(instanceID, wing, bosses)
        -- which leg (the way to which stop) each point belongs to
        local legOf, stopNo = {}, 1
        for i, p in ipairs(route) do
            legOf[i] = stopNo
            if p.boss then stopNo = stopNo + 1 end
        end
        local pos = {}
        for i, p in ipairs(route) do
            local dx, dy = toDisplay(floor, p.f, p.x, p.y)
            if dx then pos[i] = { dx * W, -dy * H } end
        end
        local function legStatus(leg)
            local stop = prog.stops[leg]
            if stop and stop.killed then return "done" end
            if stop and stop.skipped then return "skipped" end
            if prog.nextStop == leg then return "active" end
            if not stop and prog.total > 0 and not prog.nextStop then return "done" end -- after the last boss
            return "later"
        end
        local function colorOf(leg, status)
            local c = status == "skipped" and GREY or legColor(leg)
            return c[1], c[2], c[3], STYLE[status][1], STYLE[status][2]
        end
        local function addLine(a, b, r, g, bl, al, th, status)
            local layer = LAYER[status]
            nl[layer] = nl[layer] + 1
            local ln = lines[layer][nl[layer]]
            if not ln then
                ln = host:CreateLine(nil, "ARTWORK", nil, 2 + layer) -- sublevels 3 / 4 / 5: below the badges (6, 7)
                lines[layer][nl[layer]] = ln
            end
            ln:SetThickness(th)
            ln:SetColorTexture(r, g, bl, al)
            ln:SetStartPoint("TOPLEFT", host, a[1], a[2])
            ln:SetEndPoint("TOPLEFT", host, b[1], b[2])
            ln:Show()
        end
        -- the route is cut into runs of connected points (a linked door / stair or a point on another floor ends a run); each run is smoothed
        -- and every piece of it takes the colour and strength of its leg
        local i = 1
        while i <= #route do
            if not pos[i] then
                i = i + 1
            else
                local j = i
                while j < #route and pos[j + 1] and not route[j + 1].pair do j = j + 1 end
                if j > i then
                    local pts, legAt = {}, {}
                    for k = i, j do pts[#pts + 1] = pos[k]; legAt[#pts] = legOf[k] end
                    local path = smooth(pts)
                    for q = 1, #path - 1 do
                        local leg = legAt[path[q][3] + 1] -- the leg of the point the segment leads to
                        local status = legStatus(leg)
                        local r, g, bl, al, th = colorOf(leg, status)
                        addLine(path[q], path[q + 1], r, g, bl, al, th, status)
                    end
                end
                if route[j + 1] and route[j + 1].pair and pos[j + 1] then
                    -- the jump through a linked door / stair: a dotted line, in the colour of its leg
                    local a, b = pos[j], pos[j + 1]
                    local leg = legOf[j + 1]
                    local r, g, bl, al = colorOf(leg, legStatus(leg))
                    local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
                    local count = math.min(60, math.floor(len / 10))
                    for k = 1, count do
                        nd = nd + 1
                        local d = dots[nd]
                        if not d then
                            d = host:CreateTexture(nil, "ARTWORK", nil, 5)
                            d:SetSize(4, 4)
                            dots[nd] = d
                        end
                        local f = k / (count + 1)
                        d:SetColorTexture(r, g, bl, al)
                        d:ClearAllPoints()
                        d:SetPoint("CENTER", host, "TOPLEFT", a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)
                        d:Show()
                    end
                end
                i = j + 1
            end
        end
        for q = nd + 1, #dots do dots[q]:Hide() end
        -- icons of the steps at markers (stairs, doors, triggers ...)
        for k, p in ipairs(route) do
            if p.kind and pos[k] then
                ns_ = ns_ + 1
                local f = stepFrame(ns_, host)
                local kd = ns.MARKER_KINDS[p.kind]
                if kd then
                    f.icon:SetTexCoord(0, 1, 0, 1)
                    if kd.texture then f.icon:SetTexture(kd.texture) else f.icon:SetAtlas(kd.atlas) end
                end
                local leg = legOf[k]
                local r, g, bl = colorOf(leg, legStatus(leg))
                f.icon:SetVertexColor(r, g, bl, 1)
                f.text = ns.RouteStepText(p)
                local tag = p.tag
                f.label:SetText((tag and #tag <= 3) and tag or "")
                f.label:SetTextColor(r, g, bl)
                f:ClearAllPoints()
                f:SetPoint("CENTER", host, "TOPLEFT", pos[k][1], pos[k][2])
                f:Show()
            end
        end
        for q = ns_ + 1, #steps do steps[q]:Hide() end
        -- numbers on the stops, in the colour of the leg that leads to them
        for n, st in ipairs(prog.stops) do
            local p = pos[st.index]
            if p then
                nb = nb + 1
                local bd = badge(nb, host)
                local r, g, bl = colorOf(n, legStatus(n))
                bd.fs:SetText(tostring(n))
                bd.fs:SetTextColor(r, g, bl)
                local rim = ((DungeonMapDB.pinSize or 34) + 12) / 2 -- the badge sits beside the boss pin, clear of its ring
                bd.ring:SetVertexColor(r, g, bl, 1)
                bd.ring:SetColorTexture(r, g, bl, 1)
                bd.ring:ClearAllPoints()
                bd.ring:SetPoint("CENTER", host, "TOPLEFT", p[1] + rim + 14, p[2])
                bd.ring:Show()
                bd.bg:Show()
                bd.fs:Show()
            end
        end
    end
    for layer = 1, 3 do
        for q = nl[layer] + 1, #lines[layer] do lines[layer][q]:Hide() end
    end
    if not (route and #route > 0) then
        for q = 1, #dots do dots[q]:Hide() end
        for q = 1, #steps do steps[q]:Hide() end
    end
    for q = nb + 1, #badges do badges[q].fs:Hide(); badges[q].bg:Hide(); badges[q].ring:Hide() end
end
