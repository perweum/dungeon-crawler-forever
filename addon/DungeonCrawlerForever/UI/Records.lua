-- The Highscore tab (sidebar, beside Bosses and Quests; key "records"): a leaderboard for the dungeon's official route. One row per player (their best
-- run), fastest first; click a row for the run: time at every boss, who was in the group, deaths and wipes. Your own best is always shown: if you are
-- below the cut-off (TOP_N) it sits under a gap with its true rank. Below that, your latest runs. Today the board holds your own runs only; runs of other
-- players join it with the sharing step (D-063, D-066) through ns.BoardEntries, which is the one place that knows where entries come from.
local _, ns = ...
local ui = {}
ns.RecordsUI = ui

local TOP_N = 10          -- rows of the board before your own pinned row
local ROW_H, ROW_GAP = 38, 3
local GOLD, GREY, WHITE, GREEN, RED = "|cffffd100", "|cff9a9a9a", "|cffffffff", "|cff66ff66", "|cffff6666"
local MEDAL = { { 1, 0.82, 0 }, { 0.82, 0.84, 0.9 }, { 0.8, 0.5, 0.22 } } -- gold, silver, bronze
local TROPHY = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\tab_highscore"

local function stamp(t) return (date and date("%d %b %H:%M", t)) or tostring(t) end

-- "|cffRRGGBBName|r" in the class colour (plain when the class is unknown)
local function classText(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), name) end
    return WHITE .. name .. "|r"
end

-- "26-36" for the in-bracket board, "36++" for over-levelled characters
function ns.BracketShort(instanceID, wing, bracket)
    local d = ns.Dungeons[instanceID] and ns.LevelData(instanceID, wing)
    if not (d and d.recMax) then return bracket == "over" and "over-levelled" or "in range" end
    if bracket == "over" then return d.recMax .. "++" end
    return ns.LevelLabel(d)
end

function ns.MyRunName()
    local ok, name, extra = pcall(UnitName, "player")
    if not (ok and type(name) == "string") or (issecretvalue and issecretvalue(name)) then return "You" end
    if type(extra) == "string" and extra ~= "" and not (issecretvalue and issecretvalue(extra)) then name = name .. " " .. extra end
    return name
end

-- Demo mode (/dm demo, screenshots): fake players around your best time, in memory only. They are never in DungeonMapDB, so nothing shares them.
local DEMO_NAMES = { { "Thalindra Moonwhisper", "DRUID" }, { "Gorrak Ironhide", "WARRIOR" }, { "Sylvaris Dawnbringer", "PALADIN" }, { "Vexa Shadowmend", "PRIEST" },
    { "Brann Stonebeard", "HUNTER" }, { "Zul'jin Hexweaver", "SHAMAN" }, { "Mirelle Frostbloom", "MAGE" }, { "Kaldor Gravetouch", "WARLOCK" },
    { "Nyx Quickblade", "ROGUE" }, { "Aldric Brightforge", "PALADIN" }, { "Ysera Greenleaf", "DRUID" }, { "Rokhan Skullsplitter", "WARRIOR" },
    { "Lunara Silverbow", "HUNTER" }, { "Dromm Deepdelver", "SHAMAN" }, { "Eldrin Starfall", "MAGE" }, { "Morwen Nightveil", "PRIEST" } }
local DEMO_FACTORS = {
    low = { 0.62, 0.66, 0.69, 0.72, 0.75, 0.78, 0.81, 0.84, 0.88, 0.91, 0.94, 0.97, 1.12, 1.3 },
    mid = { 0.9, 0.94, 0.98, 1.06, 1.1, 1.15, 1.2, 1.27, 1.35, 1.45, 1.6, 1.8 },
    top = { 1.04, 1.08, 1.13, 1.2, 1.28, 1.37, 1.5, 1.65, 1.8, 2.0 },
}
-- made-up damage and healing for the demo runs (screenshots): healers heal, the rest deal damage
local HEALER = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
local function demoStats(members, total, i)
    local stats = {}
    for k, m in ipairs(members) do
        local f = 0.6 + ((i * 7 + k * 13) % 10) / 14
        local heals = HEALER[m.class] and k % 2 == 0
        stats[ns.NormName(m.name)] = { dmg = math.floor(total * (heals and 40 or 120) * f), heal = math.floor(total * (heals and 220 or (k == 1 and 8 or 1)) * f) }
    end
    return stats
end

function ns.DemoRuns(instanceID, wing, route, bracket)
    local out = {}
    local mine
    for _, r in ipairs(ns.RunsFor(instanceID, wing, ns.RouteKey(route))) do
        if r.ranked and not r.from and r.bracket == bracket and (not mine or r.total < mine) then mine = r.total end
    end
    local base = mine or (route.count * 140)
    local d = ns.LevelData(instanceID, wing)
    local keys = {}
    for _, name in ipairs(route.bosses) do keys[#keys + 1] = { ns.NormName(name), name } end
    local factors = DEMO_FACTORS[(ns.demo and ns.demo.mode) or "mid"] or DEMO_FACTORS.mid
    local now = time()
    for i, f in ipairs(factors) do
        local total = math.max(60, math.floor(base * f))
        local owner = DEMO_NAMES[(i - 1) % #DEMO_NAMES + 1]
        local members = { { name = owner[1], class = owner[2] } }
        local size = (i % 3 == 0) and 1 or 5
        for k = 1, size - 1 do local m = DEMO_NAMES[(i + k * 3) % #DEMO_NAMES + 1]; members[#members + 1] = { name = m[1], class = m[2] } end
        local kills, names = {}, {}
        for n, kn in ipairs(keys) do
            kills[kn[1]] = (n == #keys) and total or math.floor(total * ((n / #keys) ^ 0.92) + (i * n) % 7)
            names[kn[1]] = kn[2]
        end
        out[#out + 1] = { id = "demo" .. i, inst = instanceID, wing = wing or 0, route = route.id, rv = route.version, rname = route.name, started = now - i * 5400 - total,
            finished = now - i * 5400, total = total, kills = kills, names = names, pulls = {}, deaths = (i * 2) % 4, wipes = (i % 5 == 0) and 1 or 0, size = size,
            level = (bracket == "over") and ((d and d.recMax or 55) + 4) or (d and d.recMax or 55), bracket = bracket, members = members, ranked = true, by = owner[1],
            from = owner[1], verified = (i % 2 == 1) and size > 1 or nil, hop = 1, stats = demoStats(members, total, i) }
    end
    return out
end

-- The board of one route and bracket: { { run, rank, by, own, total } ... } fastest first, one entry per player (their best run), plus `mine`, the entry
-- of your own best run (any rank), and `count`, the number of entries. Runs of other players will be added here (DungeonMapDB.board, from sharing).
function ns.BoardEntries(instanceID, wing, route, bracket)
    local best = {}
    local function consider(r)
        if r.ranked and r.bracket == bracket and r.route .. "." .. r.rv == ns.RouteKey(route) then
            local by = r.by or "?"
            if not best[by] or r.total < best[by].total or (r.total == best[by].total and r.finished < best[by].finished) then best[by] = r end
        end
    end
    for _, r in ipairs(ns.RunsFor(instanceID, wing, ns.RouteKey(route))) do consider(r) end
    for _, r in ipairs(DungeonMapDB.board or {}) do
        if r.inst == instanceID and (r.wing or 0) == (wing or 0) then consider(r) end
    end
    if ns.demo then for _, r in ipairs(ns.DemoRuns(instanceID, wing, route, bracket)) do consider(r) end end
    local list = {}
    for by, r in pairs(best) do list[#list + 1] = { run = r, by = by, own = not r.from, total = r.total } end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total < b.total end
        if a.run.finished ~= b.run.finished then return a.run.finished < b.run.finished end
        return a.by < b.by
    end)
    local mine
    for i, e in ipairs(list) do
        e.rank = i
        if e.own and not mine then mine = e end
    end
    return list, mine
end

-- the number on the tab: runs recorded in this dungeon
function ns.RecordsCount(instanceID, wing)
    local n = 0
    for _, r in ipairs(DungeonMapDB and DungeonMapDB.runs or {}) do
        if r.inst == instanceID and (r.wing or 0) == (wing or 0) then n = n + 1 end
    end
    return n
end

-- who was in a run, for a row: the first two names, then "+3"
local function groupLine(r)
    local out = {}
    for i, m in ipairs(r.members or {}) do
        if i > 2 then out[#out + 1] = GREY .. format("+%d", #r.members - 2) .. "|r" break end
        out[#out + 1] = classText(m.name, m.class)
    end
    if #out == 0 then return GREY .. (r.by or "?") .. "|r" end
    return table.concat(out, ", ")
end

-- The group's damage and healing per second on a row: "3.9k dps  1.2k hps" (nothing when the run has no numbers)
local DMG_C, HEAL_C = "|cffe8873f", "|cff63c46d"
local function statsLine(r)
    local t = ns.RunStatsTotals(r)
    if not t then return "" end
    return format("  %s%s dps|r  %s%s hps|r", DMG_C, ns.ShortNumber(t.dps), HEAL_C, ns.ShortNumber(t.hps))
end

-- The run's detail, opened under its row: two columns of lines (names left, times right) with a gold heading per section and bullets.
-- Returns the left and the right lines (same count, so the rows line up).
function ns.RunDetailLines(r)
    local L, R = {}, {}
    local function add(l, rt) L[#L + 1] = l; R[#R + 1] = rt or "" end
    local BUL = GREY .. "\226\128\162|r " -- a bullet
    add(GOLD .. "Run|r")
    add("  " .. BUL .. stamp(r.finished))
    add("  " .. BUL .. ns.BracketLabel(r.inst, r.wing, r.bracket) .. (r.level and (", level " .. r.level) or ""))
    add("")
    add(GOLD .. "Group|r " .. GREY .. "(" .. #(r.members or {}) .. ")|r")
    for _, m in ipairs(r.members or {}) do add("  " .. BUL .. classText(m.name, m.class)) end
    if #(r.members or {}) == 0 then add("  " .. BUL .. GREY .. (r.by or "?") .. "|r") end
    add("")
    add(GOLD .. "Bosses|r", GREY .. "time  (segment)|r")
    local list = {}
    for key, cum in pairs(r.kills or {}) do list[#list + 1] = { name = (r.names and r.names[key]) or key, cum = cum } end
    table.sort(list, function(a, b) if a.cum ~= b.cum then return a.cum < b.cum end return a.name < b.name end)
    local prev = 0
    for _, e in ipairs(list) do
        add("  " .. BUL .. e.name, format("%s%s|r  %s(+%s)|r", WHITE, ns.FormatTime(e.cum), GREY, ns.FormatTime(e.cum - prev)))
        prev = e.cum
    end
    add("")
    add(GOLD .. "Result|r")
    add("  " .. BUL .. format("%d death(s)", r.deaths or 0))
    add("  " .. BUL .. format("%d wipe(s)", r.wipes or 0))
    if r.verified then add("  " .. BUL .. GREEN .. "Confirmed by someone in the group|r") end
    for _, p in ipairs(r.pulls or {}) do
        if not p.ok then add("      " .. RED .. "wipe on " .. tostring(p.boss or "?") .. "|r", RED .. ns.FormatTime(p.at or 0) .. "|r") end
    end
    if r.from then add("  " .. BUL .. "From " .. r.from) end
    return L, R
end

-- The detail in three parts when the run has stats: the lines above the group, and the lines from "Bosses" on (the group is drawn as bars between them).
function ns.RunDetailSplit(r)
    local L, Rr = ns.RunDetailLines(r)
    local gi, bi
    for i, l in ipairs(L) do
        if not gi and l:find("Group", 1, true) and l:find(GOLD, 1, true) then gi = i end
        if not bi and l:find("Bosses", 1, true) and l:find(GOLD, 1, true) then bi = i end
    end
    if not (gi and bi and bi > gi) then return nil end
    local topL, topR, botL, botR = {}, {}, {}, {}
    for i = 1, gi - 1 do topL[#topL + 1] = L[i]; topR[#topR + 1] = Rr[i] end
    for i = bi, #L do botL[#botL + 1] = L[i]; botR[#botR + 1] = Rr[i] end
    return topL, topR, botL, botR
end

function ns.RunDetailText(r)
    local L = ns.RunDetailLines(r)
    return table.concat(L, "\n")
end

-- The rows to show, in order: { kind = "label", text } / { kind = "row", entry, rankText, tag, deltaTo }.
function ns.RecordsItems(instanceID, wing, route, bracket, expandedIds)
    local items = {}
    local list, mine = ns.BoardEntries(instanceID, wing, route, bracket)
    local first = list[1]
    local function add(e, tag)
        items[#items + 1] = { kind = "row", entry = e, run = e.run, rank = e.rank, tag = tag, behind = first and e.total - first.total or 0 }
    end
    if #list == 0 then return items, list, mine end
    for i = 1, math.min(TOP_N, #list) do add(list[i], list[i].own and "YOU" or nil) end
    if mine and mine.rank > TOP_N then
        items[#items + 1] = { kind = "label", text = GREY .. "· · ·|r" }
        add(mine, "YOUR BEST")
    end
    local runs = ns.RunsFor(instanceID, wing, ns.RouteKey(route))
    local shown = 0
    local others = {}
    local onBoard = {}
    for _, it in ipairs(items) do if it.run then onBoard[it.run.id] = true end end
    for i = #runs, 1, -1 do
        local r = runs[i]
        if r.bracket == bracket and not r.from and not onBoard[r.id] then others[#others + 1] = r end
    end
    if #others > 0 then
        items[#items + 1] = { kind = "label", text = GOLD .. "Your latest runs|r" }
        for _, r in ipairs(others) do
            if shown >= 5 then break end
            shown = shown + 1
            items[#items + 1] = { kind = "row", run = r, run_only = true, rank = nil, behind = mine and (r.total - mine.total) or 0, unranked = not r.ranked }
        end
    end
    return items, list, mine
end

local function build(panel)
    local box = ns.CreateBox(panel)
    box.title:SetText("Highscore")
    box.bracketBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.bracketBtn:SetFrameLevel(box:GetFrameLevel() + 5)
    -- a small menu of our own under the button (the game's drop-down frames taint; D-060)
    box.menu = CreateFrame("Frame", nil, box)
    box.menu:SetFrameStrata("DIALOG")
    box.menu:SetSize(150, 52)
    box.menu.bg = box.menu:CreateTexture(nil, "BACKGROUND")
    box.menu.bg:SetAllPoints()
    box.menu.bg:SetColorTexture(0.05, 0.04, 0.03, 0.97)
    box.menu.items = {}
    for i, br in ipairs({ "in", "over" }) do
        local b = CreateFrame("Button", nil, box.menu, "UIPanelButtonTemplate")
        b:SetSize(144, 22)
        b:SetPoint("TOP", box.menu, "TOP", 0, -3 - (i - 1) * 24)
        b.which = br
        b:SetScript("OnClick", function(self)
            ns.GetState().recBracket = self.which
            box.menu:Hide()
            ns.RefreshMap()
        end)
        box.menu.items[i] = b
    end
    box.menu:Hide()
    box.bracketBtn:SetScript("OnClick", function() box.menu:SetShown(not box.menu:IsShown()) end)
    box.bracketBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Level bracket")
        GameTooltip:AddLine("Characters in the dungeon's level range (or below it) race each other; over-levelled characters have a board of their own. Click to switch.", 0.9, 0.9, 0.9, true)
        local st = ns.GetState()
        if st.recRouteInfo then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(st.recRouteInfo, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    box.bracketBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.routeBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.routeBtn:SetFrameLevel(box:GetFrameLevel() + 5)
    box.routeBtn:SetScript("OnClick", function()
        local st = ns.GetState()
        st.recRoute = (st.recRoute or 1) + 1
        ns.RefreshMap()
    end)
    box.routeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Route")
        GameTooltip:AddLine("This dungeon has more than one official route. Click to switch board.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    box.routeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.head = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.head:SetJustifyH("LEFT")
    box.head:SetSpacing(3)
    box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    box.scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    box.content = CreateFrame("Frame", nil, box.scroll)
    box.content:SetSize(10, 10)
    box.scroll:SetScrollChild(box.content)
    box.syncBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.syncBtn:SetFrameLevel(box:GetFrameLevel() + 5)
    box.syncBtn:SetSize(150, 22)
    box.syncBtn:SetText("Sync with guild")
    box.syncBtn:SetScript("OnClick", function() ns.CommsSyncGuild(true) end)
    box.syncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sync runs with your guild")
        GameTooltip:AddLine("Asks guild members who have the addon for their best runs. They arrive over the next minute and join the board. Also done once at login.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    box.syncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.ioBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.ioBtn:SetFrameLevel(box:GetFrameLevel() + 5)
    box.ioBtn:SetSize(130, 22)
    box.ioBtn:SetText("Copy / paste runs")
    box.ioBtn:SetScript("OnClick", function() if ns.ShowRunsIO then ns.ShowRunsIO() end end)
    box.ioBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy / paste runs")
        GameTooltip:AddLine("Copy your runs as text, or paste runs copied on another machine (or from a friend) to add them here. Also /dm runs.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    box.ioBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box.rows, box.labels = {}, {}
    panel.recordsBox = box
end

local function getRow(box, i)
    local r = box.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, box.content)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "BORDER")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.08)
    r.hl:Hide()
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(3)
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.rank:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.rank:SetWidth(30)
    r.rank:SetHeight(20)
    r.rank:SetJustifyH("CENTER")
    r.trophy = r:CreateTexture(nil, "OVERLAY")
    r.trophy:SetSize(22, 22)
    r.trophy:SetPoint("CENTER", r.rank, "CENTER", 0, 0)
    r.trophy:SetTexture(TROPHY)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 52, -5)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sub:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 52, 5)
    r.sub:SetJustifyH("LEFT")
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.time:SetPoint("TOPRIGHT", -10, -4)
    r.delta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.delta:SetPoint("BOTTOMRIGHT", -10, 5)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.tag:SetPoint("TOPRIGHT", r.time, "TOPLEFT", -8, -2)
    -- the opened run lives in a frame that clips what is below its current height, so it can slide open and shut
    r.clip = CreateFrame("Frame", nil, box.content)
    if r.clip.SetClipsChildren then r.clip:SetClipsChildren(true) end
    r.clip:Hide()
    r.detailBg = r.clip:CreateTexture(nil, "BACKGROUND")
    r.detailBg:SetColorTexture(1, 1, 1, 0.05)
    r.detailBg:Hide()
    r.detail = r.clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.detail:SetJustifyH("LEFT")
    r.detail:SetSpacing(5)
    r.detailR = r.clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.detailR:SetJustifyH("RIGHT")
    r.detailR:SetSpacing(5)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click for the run")
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if not self.runId then return end
        local st = ns.GetState()
        st.recOpen = st.recOpen or {}
        st.recOpen[self.runId] = not st.recOpen[self.runId] or nil
        ns.RefreshMap()
    end)
    box.rows[i] = r
    return r
end

local function getLabel(box, i)
    local l = box.labels[i]
    if not l then
        l = box.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetJustifyH("LEFT")
        box.labels[i] = l
    end
    return l
end

-- The group of an opened run like a damage meter (D-080): one section for damage and one for healing, a bar per player (the class colour, the biggest
-- fills the width, the others are scaled to it) with the name inside the bar and the total and the per second value at its right end. Damage is
-- compared with damage and healing with healing; a player who did none of a kind is not in that section.
local BAR_H, BAR_GAP, HEAD_H = 15, 2, 17
local KINDS = { { key = "dmg", label = "Damage", color = DMG_C, rgb = { 0.88, 0.5, 0.2 } }, { key = "heal", label = "Healing", color = HEAL_C, rgb = { 0.35, 0.78, 0.43 } } }
local function groupFrame(box, r)
    if r.group then return r.group end
    local g = CreateFrame("Frame", nil, r.clip)
    g.head = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.head:SetPoint("TOPLEFT", 0, 0)
    g.legend = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") -- a note at the right of the group heading
    g.legend:SetPoint("TOPRIGHT", 0, 0)
    g.sections = {}
    r.group = g
    return g
end
local function sectionOf(g, k)
    local sec = g.sections[k]
    if sec then return sec end
    sec = { rows = {} }
    sec.head = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sec.head:SetJustifyH("LEFT")
    sec.none = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    g.sections[k] = sec
    return sec
end
local function barRow(g, sec, i, rgb)
    local b = sec.rows[i]
    if not b then
        b = {}
        b.back = g:CreateTexture(nil, "BACKGROUND")
        b.back:SetColorTexture(1, 1, 1, 0.07)
        b.fill = g:CreateTexture(nil, "ARTWORK")
        b.name = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.val = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.val:SetJustifyH("RIGHT")
        sec.rows[i] = b
    end
    return b
end
function ui.HideGroupBars(r)
    if r.group then r.group:Hide() end
end
-- Lays the opened run out inside its clip frame (coordinates from the clip's top) and returns its full height.
function ui.LayoutDetailWithBars(box, r, run, w, topL, topR, botL, botR)
    local textW = math.max(60, w - 32 - 110)
    r.detail:ClearAllPoints()
    r.detail:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 16, -10)
    r.detail:SetWidth(textW)
    r.detail:SetText(table.concat(topL, "\n"))
    r.detailR:ClearAllPoints()
    r.detailR:SetPoint("TOPRIGHT", r.clip, "TOPLEFT", w - 16, -10)
    r.detailR:SetWidth(110)
    r.detailR:SetText(table.concat(topR, "\n"))
    local gy = 10 + (r.detail:GetStringHeight() or 40) + 2
    local g = groupFrame(box, r)
    local W = w - 32
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 16, -gy)
    g:SetWidth(W)
    local members = run.members or {}
    local t = math.max(1, run.total or 1)
    g.head:SetText(GOLD .. "Group|r " .. GREY .. "(" .. #members .. ")|r")
    g.legend:SetText(run.statsPartial and (GREY .. "the meter was reset during the run|r") or "")
    local y2 = HEAD_H + 2
    for _, kind in ipairs(KINDS) do
        local sec = sectionOf(g, kind.key)
        local list, sum = {}, 0
        for _, m in ipairs(members) do
            local s = run.stats and run.stats[ns.NormName(m.name)]
            local v = s and s[kind.key] or 0
            if v > 0 then list[#list + 1] = { m = m, v = v }; sum = sum + v end
        end
        table.sort(list, function(a, b) return a.v > b.v end)
        sec.head:ClearAllPoints()
        sec.head:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y2)
        sec.head:SetText(kind.color .. kind.label .. "|r  " .. GREY .. (sum > 0 and format("group %s  -  %s/s", ns.ShortNumber(sum), ns.ShortNumber(sum / t)) or "none") .. "|r")
        sec.head:Show()
        y2 = y2 + HEAD_H
        local top = list[1] and list[1].v or 1
        for i, e in ipairs(list) do
            local b = barRow(g, sec, i)
            local c = e.m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.m.class]
            local rr, gg, bb = c and c.r or 0.55, c and c.g or 0.55, c and c.b or 0.55
            b.back:ClearAllPoints()
            b.back:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y2)
            b.back:SetSize(W, BAR_H)
            b.back:Show()
            b.fill:ClearAllPoints()
            b.fill:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y2)
            b.fill:SetColorTexture(rr * 0.8, gg * 0.8, bb * 0.8, 0.9)
            b.fill:SetSize(math.max(2, math.floor(W * (e.v / top) + 0.5)), BAR_H)
            b.fill:Show()
            b.name:ClearAllPoints()
            b.name:SetPoint("LEFT", g, "TOPLEFT", 5, -(y2 + BAR_H / 2))
            b.name:SetWidth(math.max(40, W - 120))
            b.name:SetText(WHITE .. e.m.name .. "|r")
            b.name:Show()
            b.val:ClearAllPoints()
            b.val:SetPoint("RIGHT", g, "TOPLEFT", W - 5, -(y2 + BAR_H / 2))
            b.val:SetText(format("%s  %s/s", ns.ShortNumber(e.v), ns.ShortNumber(e.v / t)))
            b.val:Show()
            y2 = y2 + BAR_H + BAR_GAP
        end
        for i = #list + 1, #sec.rows do
            local b = sec.rows[i]
            b.back:Hide(); b.fill:Hide(); b.name:Hide(); b.val:Hide()
        end
        sec.none:Hide()
        y2 = y2 + 14 -- air between the damage bars and the healing section
    end
    local gh = y2
    g:SetHeight(gh)
    g:Show()
    if not r.detail2 then
        r.detail2 = r.clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.detail2:SetJustifyH("LEFT")
        r.detail2:SetSpacing(5)
        r.detail2R = r.clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.detail2R:SetJustifyH("RIGHT")
        r.detail2R:SetSpacing(5)
    end
    local by = gy + gh + 2
    r.detail2:ClearAllPoints()
    r.detail2:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 16, -by)
    r.detail2:SetWidth(textW)
    r.detail2:SetText(table.concat(botL, "\n"))
    r.detail2R:ClearAllPoints()
    r.detail2R:SetPoint("TOPRIGHT", r.clip, "TOPLEFT", w - 16, -by)
    r.detail2R:SetWidth(110)
    r.detail2R:SetText(table.concat(botR, "\n"))
    local h = by + (r.detail2:GetStringHeight() or 60) + 10
    r.detailBg:ClearAllPoints()
    r.detailBg:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 0, 0)
    r.detailBg:SetSize(w, h)
    r.detailBg:Show(); r.detail:Show(); r.detailR:Show(); r.detail2:Show(); r.detail2R:Show()
    return h
end

-- A run without numbers: the plain detail text. Returns its full height.
function ui.LayoutDetailPlain(box, r, run, w)
    ui.HideGroupBars(r)
    local L, R = ns.RunDetailLines(run)
    r.detail:ClearAllPoints()
    r.detail:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 16, -10)
    r.detail:SetWidth(math.max(60, w - 32 - 110))
    r.detail:SetText(table.concat(L, "\n"))
    r.detailR:ClearAllPoints()
    r.detailR:SetPoint("TOPRIGHT", r.clip, "TOPLEFT", w - 16, -10)
    r.detailR:SetWidth(110)
    r.detailR:SetText(table.concat(R, "\n"))
    local h = (r.detail:GetStringHeight() or 100) + 20
    r.detailBg:ClearAllPoints()
    r.detailBg:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 0, 0)
    r.detailBg:SetSize(w, h)
    r.detailBg:Show(); r.detail:Show(); r.detailR:Show()
    if r.detail2 then r.detail2:Hide(); r.detail2R:Hide() end
    return h
end

-- Opening and closing slide: a run's progress (0 closed .. 1 open) moves toward its target in DUR seconds while the Highscore tab is open.
local DUR = 0.22
local lastArgs
function ui.StartAnim()
    ui.driver = ui.driver or CreateFrame("Frame")
    ui.driver:SetScript("OnUpdate", function(_, dt)
        local st = ns.GetState()
        local changed, pending = false, false
        for id, p in pairs(ui.prog or {}) do
            local target = (st.recOpen and st.recOpen[id]) and 1 or 0
            if p ~= target then
                if target > p then p = math.min(1, p + dt / DUR) else p = math.max(0, p - dt / DUR) end
                ui.prog[id] = p
                changed = true
                if p ~= target then pending = true end
            end
        end
        if changed and lastArgs then pcall(ui.Update, unpack(lastArgs)) end
        if not pending then ui.driver:SetScript("OnUpdate", nil) end
    end)
end

function ui.Update(panel, instanceID, wing, show, wide, S, top)
    lastArgs = { panel, instanceID, wing, show, wide, S, top }
    if not panel.recordsBox then build(panel) end
    local box = panel.recordsBox
    box:SetShown(show)
    if not show then return end
    local st = ns.GetState()
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 42)
    box:SetCut(wide and 11 or 7)
    box.title:SetFontObject(wide and "GameFontNormalLarge" or "GameFontNormal")

    local routes = ns.OfficialRoutes(instanceID, wing)
    local route = routes[((st.recRoute or 1) - 1) % math.max(1, #routes) + 1]
    local lvl = tonumber((select(2, pcall(UnitLevel, "player"))))
    local bracket = st.recBracket or ns.RunBracket(instanceID, wing, lvl)
    st.recBracketShown = bracket
    local w = math.max(80, (panel:GetWidth() or 400) - 28 - 40)

    -- header: bracket and route buttons, then who leads and where you stand
    local titleH = wide and 40 or 28
    box.bracketBtn:ClearAllPoints()
    box.bracketBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -(wide and 8 or 4))
    box.bracketBtn:SetSize(150, 22)
    box.bracketBtn:SetText("Bracket: " .. ns.BracketShort(instanceID, wing, bracket))
    box.menu:ClearAllPoints()
    box.menu:SetPoint("TOPRIGHT", box.bracketBtn, "BOTTOMRIGHT", 0, 0)
    for _, b in ipairs(box.menu.items) do
        b:SetText(ns.BracketShort(instanceID, wing, b.which))
        b:SetEnabled(b.which ~= bracket)
    end
    box.menu:Hide()
    box.routeBtn:ClearAllPoints()
    box.routeBtn:SetPoint("RIGHT", box.bracketBtn, "LEFT", -6, 0)
    box.routeBtn:SetSize(130, 22)
    box.routeBtn:SetShown(#routes > 1)
    if route then box.routeBtn:SetText(route.name) end

    local items, list, mine = {}, {}, nil
    local head
    st.recRouteInfo = route and format("%s: %s", route.name, table.concat(route.bosses, ", ")) or nil
    if not route then
        head = GREY .. "No official route for this dungeon yet, so runs are not recorded."
    else
        items, list, mine = ns.RecordsItems(instanceID, wing, route, bracket)
        if #list == 0 then
            head = GREY .. "No time yet. The clock starts with the first fight and stops when the last of " .. table.concat(route.bosses, ", ") .. " is down."
        elseif mine then
            head = format("%sYour best|r %s%s|r   %s#%d of %d|r", GREY, WHITE, ns.FormatTime(mine.total), GOLD, mine.rank, #list)
        else
            head = format("%sFastest|r %s%s|r", GREY, WHITE, ns.FormatTime(list[1].total))
        end
    end
    box.head:ClearAllPoints()
    box.head:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -(titleH + 2))
    box.head:SetWidth(w)
    box.head:SetText(head)
    local headH = (box.head:GetStringHeight() or 30) + 8
    box.scroll:ClearAllPoints()
    box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -(titleH + 2 + headH))
    box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 34)
    box.syncBtn:ClearAllPoints()
    box.syncBtn:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 8)
    box.syncBtn:SetShown(IsInGuild and IsInGuild() and true or false)
    box.ioBtn:ClearAllPoints()
    if box.syncBtn:IsShown() then box.ioBtn:SetPoint("LEFT", box.syncBtn, "RIGHT", 6, 0) else box.ioBtn:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 8) end

    -- rows
    local y, nr, nl = 0, 0, 0
    local animating = false
    for _, it in ipairs(items) do
        if it.kind == "label" then
            nl = nl + 1
            local l = getLabel(box, nl)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", box.content, "TOPLEFT", 6, -(y + 6))
            l:SetText(it.text)
            l:Show()
            y = y + 24
        else
            nr = nr + 1
            local r = getRow(box, nr)
            local run = it.run
            r.runId = run.id
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", box.content, "TOPLEFT", 0, -y)
            r:SetWidth(w)
            local mineRow = not run.from
            local medal = it.rank and MEDAL[it.rank]
            -- rank: a trophy for #1, a coloured number for the next two, white after; "-" for a run that is not on the board
            r.trophy:SetShown(it.rank == 1)
            r.rank:SetText(it.rank == 1 and "" or (it.rank and tostring(it.rank) or GREY .. "-"))
            if medal then
                r.rank:SetTextColor(medal[1], medal[2], medal[3])
                r.trophy:SetVertexColor(medal[1], medal[2], medal[3], 1)
                r.edge:SetColorTexture(medal[1], medal[2], medal[3], 1)
                r.edge:Show()
            else
                r.rank:SetTextColor(1, 1, 1)
                r.edge:SetColorTexture(1, 0.82, 0, 1)
                r.edge:SetShown(mineRow and it.tag ~= nil)
            end
            r.bg:SetColorTexture(it.tag and 1 or 0.1, it.tag and 0.82 or 0.1, it.tag and 0 or 0.1, it.tag and 0.14 or 0.45)
            r.name:SetWidth(math.max(60, w - 52 - 10 - 90 - 10))
            r.name:SetText(groupLine(run))
            r.sub:SetText(GREY .. stamp(run.finished) .. (it.unranked and ("  not ranked: " .. tostring(run.why)) or "") .. "|r" .. (run.verified and (GREEN .. "  verified|r") or "") .. statsLine(run))
            r.time:SetText(WHITE .. ns.FormatTime(run.total) .. "|r")
            r.tag:SetText(it.tag and (GOLD .. it.tag .. "|r") or "")
            if it.behind and it.behind > 0 then r.delta:SetText(RED .. "+" .. ns.FormatTime(it.behind) .. "|r")
            elseif it.rank == 1 then r.delta:SetText(GREEN .. "fastest|r")
            else r.delta:SetText("") end
            r:Show()
            y = y + ROW_H + ROW_GAP
            local open = (st.recOpen and st.recOpen[run.id]) and true or false
            ui.prog = ui.prog or {}
            local p = ui.prog[run.id]
            if p == nil then p = open and 1 or 0 end -- first seen open (after a reload): no slide
            ui.prog[run.id] = p
            if p ~= (open and 1 or 0) then animating = true end
            if p > 0 then
                local topL, topR, botL, botR
                if run.stats then topL, topR, botL, botR = ns.RunDetailSplit(run) end
                local H = topL and ui.LayoutDetailWithBars(box, r, run, w, topL, topR, botL, botR) or ui.LayoutDetailPlain(box, r, run, w)
                local e = p * p * (3 - 2 * p) -- smoothstep
                local hh = math.max(1, math.floor(H * e + 0.5))
                r.clip:ClearAllPoints()
                r.clip:SetPoint("TOPLEFT", box.content, "TOPLEFT", 0, -y)
                r.clip:SetSize(w, hh)
                r.clip:SetAlpha(math.min(1, p * 1.6))
                r.clip:Show()
                y = y + hh + math.floor(8 * e + 0.5)
            else
                r.clip:Hide()
                ui.HideGroupBars(r)
            end
        end
    end
    if animating then ui.StartAnim() end
    for i = nr + 1, #box.rows do
        local hr = box.rows[i]
        hr:Hide(); hr.clip:Hide(); hr.detail:Hide(); hr.detailR:Hide(); hr.detailBg:Hide()
        if hr.detail2 then hr.detail2:Hide(); hr.detail2R:Hide() end
        ui.HideGroupBars(hr)
    end
    for i = nl + 1, #box.labels do box.labels[i]:Hide() end
    box.content:SetSize(w, math.max(10, y + 8))
end
