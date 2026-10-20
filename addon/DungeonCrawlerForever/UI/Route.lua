-- Route (developer tool for now): a hand-drawn path through the dungeon. In edit mode choose "Route", click the map to add points and click a boss
-- pin to add a stop at that boss. While you play, the legs between the stops are coloured by progress: done (green), the way to the next boss
-- (bold) and what is left (normal); every leg has its own colour. Data: DungeonMapDB.routes[instanceID][wing or 0] = { {f = floorUiMapID, x, y, boss = name|nil}, ... }
local _, ns = ...

-- Lines are drawn in layers by progress, so the way to the next boss is always on top of legs that double back over it: done / skipped lowest,
-- then the legs ahead, then the active leg. One pool per layer (a line keeps the layer it was created in).
local LAYER = { done = 1, skipped = 1, gapped = 1, later = 2, active = 3 }
local lines, badges, dots, steps = { {}, {}, {} }, {}, {}, {}
local handles = {} -- while drawing: a dot on every plain point of the route (click one to add the next points after it)
local cursorRing, cutRing
-- Every leg of the route (the way to one boss) has its own colour; the progress shows in how strong it is: the way to the next boss is bold,
-- legs you have done are faint, legs ahead are normal, a skipped leg is grey.
local LEG_COLORS = { { 0.35, 0.65, 1 }, { 1, 0.6, 0.25 }, { 0.45, 0.85, 0.45 }, { 1, 0.5, 0.8 }, { 0.95, 0.88, 0.35 }, { 0.55, 0.2, 0.9 }, { 0.4, 0.95, 0.9 }, { 1, 0.45, 0.4 } }
local GREY = { 0.55, 0.55, 0.55 }
local DARK = { 0.28, 0.28, 0.28 } -- the part behind a cut: dark grey, clearly different from the coloured legs
local STYLE = { done = { 0.35, 2 }, active = { 1, 4 }, later = { 0.8, 2.5 }, skipped = { 0.45, 2 }, gapped = { 0.7, 3 } } -- alpha, thickness
local function legColor(leg) return LEG_COLORS[(leg - 1) % #LEG_COLORS + 1] end

local function key(wing) return wing or 0 end
-- the colour of leg n (the way to the n-th stop), for the number badges in the sidebar's Route tab
function ns.RouteLegColor(n)
    local c = legColor(n)
    return c[1], c[2], c[3]
end

-- Points on floors the addon does not show any more (a dungeon whose map was replaced) are dropped from the route, here and in the saved data.
local function prune(list, instanceID)
    if not list then return end
    local shown = ns.ShownFloorSet(instanceID)
    for i = #list, 1, -1 do
        if not shown[list[i].f] then table.remove(list, i) end
    end
end

-- A stop (a point with a boss) is a REFERENCE to that boss, not a copy of a position: its position always comes from the boss's pin, so moving a
-- boss in edit mode moves the stop, the leg, the number badge and the hit area with it. To take a boss out of the route, delete the point
-- (Delete point in the route tools). Steps at markers work the same way the other direction: removing a marker removes its steps (ns.RouteDropMarker).
local function followBosses(list, instanceID, wing)
    local has
    for _, p in ipairs(list) do if p.boss then has = true break end end
    if not has or not (ns.GetBosses and instanceID) then return end
    local byName = {}
    for _, b in ipairs(ns.GetBosses(instanceID, nil, wing) or {}) do
        if b.x and b.floor then byName[b.name] = b end
    end
    for _, p in ipairs(list) do
        local b = p.boss and byName[p.boss]
        if b then p.f, p.x, p.y = tonumber(b.floor), b.x, b.y end
    end
end

-- The route of a dungeon: the one recorded in game (developer, /dm edit) when there is one, otherwise the route that ships with the addon (Data/Routes.lua).
function ns.GetRoute(instanceID, wing)
    local r = DungeonMapDB and DungeonMapDB.routes and DungeonMapDB.routes[instanceID]
    local list = r and r[key(wing)] or nil
    prune(list, instanceID)
    if list and (#list > 0 or ns.RouteTool()) then
        followBosses(list, instanceID, wing)
        return list
    end
    local shipped = ns.RouteData and ns.RouteData[instanceID] and ns.RouteData[instanceID][key(wing)]
    if shipped then
        prune(shipped, instanceID)
        followBosses(shipped, instanceID, wing)
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

-- Editing ----------------------------------------------------------------------------------------------------------------------
-- ns.routeAt: the SELECTED point while drawing (nil = none). New points are added after it and each one moves the selection on; with nothing
-- selected they go at the end. A point can be moved (drag), deleted, or the route can be CUT after it: the rest of the route (from the next point
-- on) is then the "gap" part, drawn grey and not connected (its first point carries gap = true) until a point of it is clicked to join the new
-- section to it.
-- Every change keeps a snapshot, so Undo takes back whatever was done last: a point, a move, a cut, a join, a delete, Start over.
local history, historyKey = {}, nil

local function mark(instanceID, wing)
    local k = instanceID .. "/" .. key(wing)
    if historyKey ~= k then history, historyKey = {}, k end
end

local function snapshot(instanceID, wing)
    mark(instanceID, wing)
    local r = routeFor(instanceID, wing, true)
    return { pts = copyRoute(r), at = ns.routeAt }
end

local function push(instanceID, wing, snap)
    mark(instanceID, wing)
    history[#history + 1] = snap
    if #history > 80 then table.remove(history, 1) end
end

-- for changes made over several frames (dragging a point): take the snapshot first, commit it when the change is done
ns.RouteSnapshot = snapshot
ns.RouteCommit = push

function ns.RouteUndo(instanceID, wing)
    mark(instanceID, wing)
    local snap = table.remove(history)
    if not snap then return false end
    local r = routeFor(instanceID, wing, true)
    for i = #r, 1, -1 do r[i] = nil end
    for i, p in ipairs(snap.pts) do r[i] = p end
    ns.routeAt = snap.at
    return true
end

function ns.RouteCanUndo(instanceID, wing)
    mark(instanceID, wing)
    return #history > 0
end

-- Several additions that Undo takes back together (a linked door adds both its ends)
local batching = false
function ns.RouteBatch(instanceID, wing, fn)
    push(instanceID, wing, snapshot(instanceID, wing))
    batching = true
    local ok, err = pcall(fn)
    batching = false
    if not ok then error(err, 0) end
end

function ns.RouteAdd(instanceID, wing, point)
    local r = routeFor(instanceID, wing, true)
    prune(r, instanceID)
    if not batching then push(instanceID, wing, snapshot(instanceID, wing)) end
    local at = ns.routeAt
    if at and at >= 1 and at <= #r then
        table.insert(r, at + 1, point)
        ns.routeAt = at + 1
        return at + 1
    end
    ns.routeAt = nil
    r[#r + 1] = point
    return #r
end

-- A point inside a leg (Ctrl-click on a line): goes in after point `after`; the selection stays on the same point.
function ns.RouteInsert(instanceID, wing, after, point)
    local r = routeFor(instanceID, wing, true)
    push(instanceID, wing, snapshot(instanceID, wing))
    table.insert(r, after + 1, point)
    if ns.routeAt and ns.routeAt > after then ns.routeAt = ns.routeAt + 1 end
end

-- Take a point out (a linked door / stair loses both ends). The gap flag moves on to the next point when it sat on the removed one.
function ns.RouteDeletePoint(instanceID, wing, index)
    local r = routeFor(instanceID, wing, true)
    if not r[index] then return false end
    push(instanceID, wing, snapshot(instanceID, wing))
    local from, to = index, index
    if r[index].pair and index > 1 then from = index - 1 elseif r[index + 1] and r[index + 1].pair then to = index + 1 end
    local gap = false
    for k = from, to do if r[k].gap then gap = true end end
    for k = to, from, -1 do table.remove(r, k) end
    if gap and r[from] then r[from].gap = true end
    ns.routeAt = from > 1 and from - 1 or nil
    return true
end

-- A marker was removed: the route steps that stand on it go too (a linked door loses both ends).
function ns.RouteDropMarker(instanceID, floorID, kind, x, y)
    local byInst = DungeonMapDB.routes and DungeonMapDB.routes[instanceID]
    if not byInst then return end
    for _, list in pairs(byInst) do
        for i = #list, 1, -1 do
            local p = list[i]
            if p and p.kind == kind and p.f == floorID and math.abs(p.x - x) < 0.006 and math.abs(p.y - y) < 0.006 then
                local from, to = i, i
                if p.pair and i > 1 then from = i - 1 elseif list[i + 1] and list[i + 1].pair then to = i + 1 end
                local gap = false
                for k = from, to do if list[k].gap then gap = true end end
                for k = to, from, -1 do table.remove(list, k) end
                if gap and list[from] then list[from].gap = true end
            end
        end
    end
end

-- The first point of the grey part, or nil when the route is whole.
function ns.RouteGap(instanceID, wing)
    local r = routeFor(instanceID, wing)
    if r then for i, p in ipairs(r) do if p.gap then return i end end end
end

-- Cut the route after point k: the part behind it turns grey and is no longer connected to it. New points then go in after k.
function ns.RouteCut(instanceID, wing, k)
    local r = routeFor(instanceID, wing, true)
    if not (r[k] and r[k + 1]) or ns.RouteGap(instanceID, wing) then return false end
    push(instanceID, wing, snapshot(instanceID, wing))
    r[k + 1].gap = true
    ns.routeAt = k
    return true
end

-- Join the new section to the grey part at point m (m >= the first grey point): the grey points before m are dropped, so m follows the new
-- section. Returns the names of the stops that were dropped with them.
function ns.RouteConnect(instanceID, wing, m)
    local r = routeFor(instanceID, wing, true)
    local g = ns.RouteGap(instanceID, wing)
    if not (g and m >= g and r[m]) then return nil end
    push(instanceID, wing, snapshot(instanceID, wing))
    local dropped = {}
    for k = m - 1, g, -1 do
        if r[k].boss then table.insert(dropped, 1, r[k].boss) end
        table.remove(r, k)
    end
    r[g].gap = nil -- the point that was m
    ns.routeAt = nil
    return dropped
end

-- Leave a gap open (Save, closing the map): the end of the new section simply joins the first grey point.
function ns.RouteCloseGap(instanceID, wing)
    local g = ns.RouteGap(instanceID, wing)
    if not g then return false end
    local r = routeFor(instanceID, wing)
    r[g].gap = nil
    return true
end

-- Selection one point back / forward along the route (to reach stops and steps that the mouse cannot pick).
function ns.RouteSelectStep(instanceID, wing, delta)
    local r = routeFor(instanceID, wing)
    if not r or #r == 0 then return end
    local at = ns.routeAt
    if not at then at = delta < 0 and #r + 1 or 0 end
    ns.routeAt = math.max(1, math.min(#r, at + delta))
end

-- A player's own route: the saved route of this dungeon, used instead of the one that ships with the addon.
function ns.RouteIsCustom(instanceID, wing)
    local r = routeFor(instanceID, wing)
    return r ~= nil
end

-- Back to the route that ships with the addon (or no route, when the dungeon has none).
function ns.RouteReset(instanceID, wing)
    ns.routeAt = nil
    mark(instanceID, wing)
    history = {}
    local byInst = DungeonMapDB.routes and DungeonMapDB.routes[instanceID]
    if byInst then byInst[key(wing)] = nil end
end

-- Is the route tool active? Developers use it from edit mode; players start it from the "Draw your own route" link under the map.
function ns.RouteTool()
    return ns.routeDraw == true or (ns.editing and ns.editKind == "__route") or false
end

function ns.RouteClear(instanceID, wing)
    local r = routeFor(instanceID, wing, true) -- clearing a dungeon that only has the built-in route gives the player an empty route of their own
    push(instanceID, wing, snapshot(instanceID, wing))
    ns.routeAt = nil
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
    if ns.RouteTool() or ns.routeTab then return true end -- (drawing, or the sidebar's Route tab is open: it is the route's own page)
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
local function handle(n, host) -- a round dot (the mouse is read on the map itself, see ns.RouteHitPoint)
    local h = handles[n]
    if not h then
        h = host:CreateTexture(nil, "ARTWORK", nil, 6)
        local m = host:CreateMaskTexture()
        m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(h)
        h:AddMaskTexture(m)
        handles[n] = h
    end
    return h
end

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
        local gapAt -- the first point of the grey part while a cut is open (drawing only)
        for i, p in ipairs(route) do if p.gap then gapAt = i break end end
        local function statusAt(i, leg) -- the status of the leg a point belongs to; the grey part is "gapped" whatever its progress
            if gapAt and i >= gapAt then return "gapped" end
            return nil
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
            local c = status == "gapped" and DARK or (status == "skipped" and GREY or legColor(leg))
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
                while j < #route and pos[j + 1] and not route[j + 1].pair and not route[j + 1].gap do j = j + 1 end
                if j > i then
                    local pts, legAt, idxAt = {}, {}, {}
                    for k = i, j do pts[#pts + 1] = pos[k]; legAt[#pts] = legOf[k]; idxAt[#pts] = k end
                    local path = smooth(pts)
                    for q = 1, #path - 1 do
                        local leg = legAt[path[q][3] + 1] -- the leg of the point the segment leads to
                        local status = statusAt(idxAt[path[q][3] + 1], leg) or legStatus(leg)
                        local r, g, bl, al, th = colorOf(leg, status)
                        addLine(path[q], path[q + 1], r, g, bl, al, th, status)
                    end
                end
                if route[j + 1] and route[j + 1].pair and pos[j + 1] then
                    -- the jump through a linked door / stair: a dotted line, in the colour of its leg
                    local a, b = pos[j], pos[j + 1]
                    local leg = legOf[j + 1]
                    local r, g, bl, al = colorOf(leg, statusAt(j + 1, leg) or legStatus(leg))
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
                local r, g, bl = colorOf(leg, statusAt(k, leg) or legStatus(leg))
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
        -- drawing: a dot on every point (stops and steps are drawn bigger already), a gold ring on the selected one
        local nh = 0
        if ns.RouteTool() then
            for k, p in ipairs(route) do
                if pos[k] and not p.boss and not p.kind then
                    nh = nh + 1
                    local h = handle(nh, host)
                    local r, g, bl = colorOf(legOf[k], statusAt(k, legOf[k]) or legStatus(legOf[k]))
                    h:SetColorTexture(r, g, bl, 1)
                    h:SetSize(ns.routeAt == k and 13 or 9, ns.routeAt == k and 13 or 9)
                    h:ClearAllPoints()
                    h:SetPoint("CENTER", host, "TOPLEFT", pos[k][1], pos[k][2])
                    h:Show()
                end
            end
        end
        for q = nh + 1, #handles do handles[q]:Hide() end
        -- a red ring where the route was cut (the last point before the grey part)
        if ns.RouteTool() and gapAt and gapAt > 1 and pos[gapAt - 1] then
            if not cutRing then
                cutRing = host:CreateTexture(nil, "ARTWORK", nil, 4)
                cutRing:SetSize(32, 32)
                local m = host:CreateMaskTexture()
                m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(cutRing)
                cutRing:AddMaskTexture(m)
                cutRing:SetColorTexture(1, 0.3, 0.2, 1)
            end
            cutRing:ClearAllPoints()
            cutRing:SetPoint("CENTER", host, "TOPLEFT", pos[gapAt - 1][1], pos[gapAt - 1][2])
            cutRing:Show()
        elseif cutRing then
            cutRing:Hide()
        end
        if ns.RouteTool() and ns.routeAt and pos[ns.routeAt] then
            if not cursorRing then
                cursorRing = host:CreateTexture(nil, "ARTWORK", nil, 5)
                cursorRing:SetSize(24, 24)
                local m = host:CreateMaskTexture()
                m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(cursorRing)
                cursorRing:AddMaskTexture(m)
                cursorRing:SetColorTexture(1, 0.82, 0, 1)
            end
            cursorRing:ClearAllPoints()
            cursorRing:SetPoint("CENTER", host, "TOPLEFT", pos[ns.routeAt][1], pos[ns.routeAt][2])
            cursorRing:Show()
        elseif cursorRing then
            cursorRing:Hide()
        end
        -- numbers on the stops, in the colour of the leg that leads to them
        for n, st in ipairs(prog.stops) do
            local p = pos[st.index]
            if p then
                nb = nb + 1
                local bd = badge(nb, host)
                local r, g, bl = colorOf(n, statusAt(st.index, n) or legStatus(n))
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
        for q = 1, #handles do handles[q]:Hide() end
        if cursorRing then cursorRing:Hide() end
        if cutRing then cutRing:Hide() end
        for q = 1, #dots do dots[q]:Hide() end
        for q = 1, #steps do steps[q]:Hide() end
    end
    for q = nb + 1, #badges do badges[q].fs:Hide(); badges[q].bg:Hide(); badges[q].ring:Hide() end
end
