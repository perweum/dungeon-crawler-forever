-- The run complete window (shown when an official route is finished, out of combat) and the sharing question (D-066): asked once, with the first finished
-- ranked run, and again any time with /dm sharing. Our own window, nothing is written into the game's popup tables (D-060: that tainted Escape).
-- Sharing itself is not wired yet (the message protocol is the next step): SENDING_LIVE says so in the window until it is, and the choice is saved
-- as DungeonMapDB.shareScope ("everyone" or "guild") for when it is.
local _, ns = ...

local SENDING_LIVE = true
local WIDTH, PAD, TITLE_H = 460, 18, 26
local GOLD, GREY, WHITE, GREEN = "|cffffd100", "|cff9a9a9a", "|cffffffff", "|cff66ff66"
local BANNER = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\welcome-banner" -- the same banner as the welcome window (1024x512, the top 338 rows)
local BANNER_V = 0.6602
local BANNER_H = math.floor((WIDTH - 16) * 661 / 2000 + 0.5)
local f

local function bigFont(parent)
    local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", "GameFontNormalHuge")
    if ok and fs then return fs end
    return parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
end

local function scopeText(scope)
    if scope == "none" then return "off (your runs stay on this computer)" end
    return scope == "guild" and "guild and friends only" or "everyone with the addon you meet"
end

local function openHighscore(run)
    if not run then return end
    f:Hide()
    ns.ShowInstance(run.inst, nil, false, (run.wing and run.wing ~= 0) and run.wing or nil)
    local st = ns.GetState()
    st.tab = "records"
    st.recBracket = run.bracket
    if ns.RefreshMap then ns.RefreshMap() end
end

local function build()
    f = ns.NewWindow("DungeonMapRunDone")
    f:SetWidth(WIDTH)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetTitle then f:SetTitle("Dungeon Crawler Forever") end

    -- the logo across the top wherever the window asks to share, so it is clear which addon is asking
    f.banner = f:CreateTexture(nil, "ARTWORK")
    f.banner:SetSize(WIDTH - 16, BANNER_H)
    f.banner:SetPoint("TOP", 0, -TITLE_H)
    f.banner:SetTexture(BANNER)
    f.banner:SetTexCoord(0, 1, 0, BANNER_V)

    f.route = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.route:SetPoint("TOP", 0, -TITLE_H - 10)
    f.route:SetWidth(WIDTH - 2 * PAD)
    f.time = bigFont(f)
    f.time:SetPoint("TOP", f.route, "BOTTOM", 0, -6)
    f.rank = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.rank:SetPoint("TOP", f.time, "BOTTOM", 0, -6)
    f.rank:SetWidth(WIDTH - 2 * PAD)
    f.bosses = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.bosses:SetPoint("TOPLEFT", f.rank, "BOTTOMLEFT", 40, -12)
    f.bosses:SetWidth(WIDTH - 2 * PAD - 80)
    f.bosses:SetJustifyH("LEFT")
    f.bosses:SetSpacing(3)

    f.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.intro:SetPoint("TOPLEFT", f.route, "BOTTOMLEFT", 0, -12)
    f.intro:SetWidth(WIDTH - 2 * PAD)
    f.intro:SetJustifyH("LEFT")
    f.intro:SetSpacing(4)

    f.askTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.askTitle:SetJustifyH("LEFT")
    f.askTitle:SetWidth(WIDTH - 2 * PAD)
    f.askBody = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.askBody:SetJustifyH("LEFT")
    f.askBody:SetWidth(WIDTH - 2 * PAD)
    f.askBody:SetSpacing(3)
    f.askNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.askNote:SetJustifyH("LEFT")
    f.askNote:SetWidth(WIDTH - 2 * PAD)

    local function choice(scope, label, point, x)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(136, 26)
        b:SetText(label)
        b.scope = scope
        b:SetScript("OnClick", function(self)
            DungeonMapDB.shareAsked = true
            DungeonMapDB.shareScope = self.scope
            ns.Print("Sharing: " .. scopeText(self.scope) .. (SENDING_LIVE and "." or " (saved; this version does not send yet)."))
            if ns.CommsShareBacklog then ns.CommsShareBacklog() end -- runs recorded while private are shared now
            if f.mode == "sharing" or f.mode == "intro" then f:Hide() else ns.LayoutRunDone() end
        end)
        f[point] = b
    end
    choice("everyone", "Everyone", "everyoneBtn")
    choice("guild", "Guild and friends", "guildBtn")
    choice("none", "Don't share mine", "noneBtn")

    f.highscore = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.highscore:SetSize(150, 26)
    f.highscore:SetText("See the highscore")
    f.highscore:SetScript("OnClick", function() openHighscore(f.run) end)
    f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.close:SetSize(90, 26)
    f.close:SetText("Close")
    f.close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
end

-- Size and place everything for the current mode ("run" with or without the question, or "sharing" alone).
function ns.LayoutRunDone()
    if not f then return end
    local run, ctx = f.run, f.ctx
    local asking = f.mode == "sharing" or f.mode == "intro" or not DungeonMapDB.shareAsked
    local isRun = f.mode == "run"
    local banner = not isRun or asking
    f.banner:SetShown(banner)
    local y = TITLE_H + 10 + (banner and (BANNER_H + 6) or 0)
    f.route:ClearAllPoints()
    f.route:SetPoint("TOP", f, "TOP", 0, -y)
    f.route:SetShown(f.mode ~= "sharing")
    f.time:SetShown(isRun)
    f.rank:SetShown(isRun)
    f.bosses:SetShown(isRun)
    f.highscore:SetShown(isRun)
    f.intro:SetShown(f.mode == "intro")
    local bodyTop
    if f.mode == "intro" then
        f.route:SetText("Highscores")
        f.intro:SetText("Every dungeon run is timed now: the clock starts with the first fight and stops when the last boss of the dungeon's official route is down. Your times and your rank are under the |cffffd100Highscore|r tab of the dungeon map, and the |cffffd100+/-|r in the timer window (|cffffd100/dm timer|r) shows how you are doing against your best while you play.")
        y = y + (f.route:GetStringHeight() or 18) + 12 + (f.intro:GetStringHeight() or 70)
        bodyTop = y + 16
    elseif isRun and run then
        local d = ns.Dungeons[run.inst]
        f.route:SetText((d and ns.DungeonTitle(run.inst, run.wing ~= 0 and run.wing or nil) or "Dungeon") .. GREY .. "  -  |r" .. (run.rname or "Route"))
        f.time:SetText((run.ranked and (ctx and ctx.newBest) and GREEN or WHITE) .. ns.FormatTime(run.total) .. "|r")
        local line
        if not run.ranked then
            line = GREY .. "Not ranked: " .. tostring(run.why) .. "|r"
        elseif ctx and ctx.newBest and ctx.prevTotal then
            line = format("%sNew personal best!|r  %sThe old one was %s|r", GREEN, GREY, ns.FormatTime(ctx.prevTotal))
        elseif ctx and ctx.newBest then
            line = GOLD .. "Your first time on this route|r"
        elseif ctx and ctx.prevTotal then
            line = format("%sYour best is %s (+%s)|r", GREY, ns.FormatTime(ctx.prevTotal), ns.FormatTime(run.total - ctx.prevTotal))
        end
        if run.ranked and ctx and ctx.rank then
            local br = ns.BracketLabel(run.inst, run.wing, run.bracket)
            line = format("%s#%d of %d|r %sin %s|r", GOLD, ctx.rank, ctx.count or ctx.rank, GREY, br) .. (line and ("\n" .. line) or "")
        end
        f.rank:SetText(line or "")
        local list = {}
        for key, cum in pairs(run.kills or {}) do list[#list + 1] = { name = (run.names and run.names[key]) or key, key = key, cum = cum } end
        table.sort(list, function(a, b) if a.cum ~= b.cum then return a.cum < b.cum end return a.name < b.name end)
        local out, prev = {}, 0
        for _, e in ipairs(list) do
            local ref = ctx and ctx.refKills and ctx.refKills[e.key]
            local dt = ""
            if ref and ns.SplitDelta then
                local color, txt = ns.SplitDelta(e.cum, ref)
                dt = "   " .. color .. txt .. "|r"
            end
            out[#out + 1] = format("%s   %s%s|r  %s(+%s)|r%s", e.name, WHITE, ns.FormatTime(e.cum), GREY, ns.FormatTime(e.cum - prev), dt)
            prev = e.cum
        end
        f.bosses:SetText(table.concat(out, "\n"))
        y = y + (f.route:GetStringHeight() or 18) + 6 + (f.time:GetStringHeight() or 30) + 6 + (f.rank:GetStringHeight() or 14) + 12 + (f.bosses:GetStringHeight() or 60)
        bodyTop = y + 16
    else
        bodyTop = y + 4
    end
    y = bodyTop
    f.askTitle:SetShown(asking); f.askBody:SetShown(asking); f.askNote:SetShown(asking)
    f.everyoneBtn:SetShown(asking); f.guildBtn:SetShown(asking); f.noneBtn:SetShown(asking)
    if asking then
        f.askTitle:ClearAllPoints(); f.askTitle:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
        f.askTitle:SetText(GOLD .. "Share your highscores|r")
        f.askBody:ClearAllPoints(); f.askBody:SetPoint("TOPLEFT", f.askTitle, "BOTTOMLEFT", 0, -6)
        f.askBody:SetText("Finished runs are shared automatically, so the boards fill up and people can see who is fastest. Your character name, class, level, time and group go to the people you group with, to your guild and friends, and to everyone else with the addon you meet, wherever the game lets an addon send. You see one line in chat when it happens. Choose Guild and friends to keep it to them, or Don't share my own to keep your own runs on this computer (you still see runs that others share, and pass those on to your guild and friends so the best times reach everyone).")
        local h = f.askBody:GetStringHeight() or 70
        f.everyoneBtn:ClearAllPoints(); f.everyoneBtn:SetPoint("TOPLEFT", f.askBody, "BOTTOMLEFT", 0, -12)
        f.guildBtn:ClearAllPoints(); f.guildBtn:SetPoint("LEFT", f.everyoneBtn, "RIGHT", 8, 0)
        f.noneBtn:ClearAllPoints(); f.noneBtn:SetPoint("LEFT", f.guildBtn, "RIGHT", 8, 0)
        local scope = DungeonMapDB.shareScope
        f.everyoneBtn:SetEnabled(not (DungeonMapDB.shareAsked and scope == "everyone"))
        f.guildBtn:SetEnabled(not (DungeonMapDB.shareAsked and scope == "guild"))
        f.noneBtn:SetEnabled(not (DungeonMapDB.shareAsked and scope == "none"))
        f.askNote:ClearAllPoints(); f.askNote:SetPoint("TOPLEFT", f.everyoneBtn, "BOTTOMLEFT", 0, -8)
        f.askNote:SetText("Nothing is sent to anyone before you choose. Change it any time with /dm sharing or in the options.")
        y = y + (f.askTitle:GetStringHeight() or 14) + 6 + h + 12 + 26 + 8 + (f.askNote:GetStringHeight() or 24)
    end
    f.close:SetText(f.mode == "intro" and "Later" or "Close")
    f.close:ClearAllPoints(); f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD - 2), 14)
    f.highscore:ClearAllPoints(); f.highscore:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f:SetHeight(y + 20 + 26 + 14)
end

local function show(mode, run, ctx)
    if not f then build() end
    f.mode, f.run, f.ctx = mode, run, ctx
    ns.LayoutRunDone()
    f:Show()
end

-- A few seconds after every login until the sharing question is answered: what the highscore is, and the question. Not in a dungeon, not in combat, not
-- on top of the welcome window. Closing it with "Later" asks again with the first finished ranked run and at the next login (until then your own runs
-- are not shared; the runs of others are still passed on, D-074).
function ns.MaybeIntro()
    if not (ns.isForever and DungeonMapDB) or DungeonMapDB.shareAsked then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if IsInInstance and IsInInstance() then return end
    if _G.DungeonMapWelcomeFrame and _G.DungeonMapWelcomeFrame:IsShown() then return end
    DungeonMapDB.introShown = true
    show("intro")
end

-- /dm demo summary: the run summary for a screenshot, from your latest ranked run (or a made-up one), as a new personal best in 2nd place
function ns.ShowRunDoneDemo()
    local rec
    for _, r in ipairs(DungeonMapDB.runs or {}) do if r.ranked then rec = r end end
    local ctx
    if rec then
        local ref = {}
        for k, t in pairs(rec.kills or {}) do ref[k] = math.floor(t * 1.08) end
        ctx = { prevTotal = math.floor(rec.total * 1.08), refKills = ref, rank = 2, count = 14, newBest = true }
    else
        ns.Print("No ranked run recorded yet to build the demo summary from. Finish one, or use /dm demo for the leaderboard.")
        return
    end
    show("run", rec, ctx)
end

-- /dm sharing reset: the intro again (for testing)
function ns.ShowIntro()
    if DungeonMapDB and ns.isForever then show("intro") end
end

-- /dm sharing: the question on its own, with the current choice marked
function ns.ShowSharing()
    if not (DungeonMapDB and ns.isForever) then return end
    show("sharing")
end

-- How much a finished run is worth a window: a first time or a personal best counts most, then a top three place; nothing for the rest.
local function worth(rec, ctx)
    if not rec.ranked then return 0 end
    local w = 0
    if ctx and ctx.newBest then w = 100 end
    if ctx and ctx.rank and ctx.rank <= 3 then w = w + (4 - ctx.rank) * 10 end
    return w
end

-- A finished route (Runs.lua calls this). By default the window only comes when the run is worth it (first time, personal best, top three) or when the
-- sharing question is still open; other runs get the chat line only. One kill can finish several routes (a short route inside a full clear): they are
-- collected for a moment and only the best result is shown. Never in combat: it waits (the last boss's adds may still be up).
local pending
function ns.OnRunRecorded(rec, ctx)
    if not DungeonMapDB then return end
    local mode = DungeonMapDB.runSummaryMode or "notable"
    local wantQuestion = rec.ranked and not DungeonMapDB.shareAsked
    if mode == "never" and not wantQuestion then return end
    if mode == "notable" and not wantQuestion and worth(rec, ctx) == 0 then return end
    local score = worth(rec, ctx) + (ctx and ctx.rank and 0 or 0)
    if pending then
        if score > pending.score or (score == pending.score and rec.total >= pending.rec.total) then pending.rec, pending.ctx, pending.score = rec, ctx, score end
        return
    end
    pending = { rec = rec, ctx = ctx, score = score }
    local tries = 0
    local function try()
        tries = tries + 1
        if InCombatLockdown and InCombatLockdown() and tries < 90 then
            C_Timer.After(2, try)
            return
        end
        local p = pending
        pending = nil
        if p then show("run", p.rec, p.ctx) end
    end
    C_Timer.After(1.5, try)
end
