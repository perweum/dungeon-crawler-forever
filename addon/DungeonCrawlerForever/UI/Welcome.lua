-- First run: one small window that says what the addon does and how to get to it (map key, entrance pins, the Journal button, a key of your own).
-- Shown once (DungeonMapDB.welcomed), a few seconds after the first login with the addon; /dm welcome shows it again.
local _, ns = ...

local WIDTH, PAD = 480, 18
local BANNER = "Interface\\AddOns\\DungeonCrawlerForever\\Art\\welcome-banner" -- 1024x512, the banner fills the top 338 rows (tools/make_banner.py)
local BANNER_V = 0.6602
local BANNER_H = math.floor((WIDTH - 16) * 661 / 2000 + 0.5) -- shown at the banner's own proportions (2000 x 661)
local TITLE_H = 26 -- the window's title bar

local function build()
    local f = ns.NewWindow("DungeonMapWelcomeFrame")
    f:SetWidth(WIDTH)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG") -- (over the settings panel, when opened from there)
    if f.SetTitle then f:SetTitle("Welcome") end
    if UISpecialFrames then tinsert(UISpecialFrames, "DungeonMapWelcomeFrame") end -- Esc closes it

    -- the logo as the header, across the top of the window
    f.banner = f:CreateTexture(nil, "ARTWORK")
    f.banner:SetSize(WIDTH - 16, BANNER_H)
    f.banner:SetPoint("TOP", 0, -TITLE_H)
    f.banner:SetTexture(BANNER)
    f.banner:SetTexCoord(0, 1, 0, BANNER_V)

    local intro = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    intro:SetPoint("TOPLEFT", f.banner, "BOTTOMLEFT", PAD - 8, -14)
    intro:SetWidth(WIDTH - 2 * PAD)
    intro:SetJustifyH("LEFT")
    intro:SetText("A map for every dungeon and raid, with bosses, loot and routes.")
    f.intro = intro

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
    body:SetWidth(WIDTH - 2 * PAD) -- a fixed width, so the text's height can be measured to size the window
    body:SetJustifyH("LEFT")
    body:SetSpacing(4)
    f.body = body

    local function button(text, w, point, x, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 26)
        b:SetPoint(point, x, 16)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    button("Open the journal", 140, "BOTTOMLEFT", PAD - 2, function() f:Hide(); ns.ShowJournal() end)
    button("Set a key", 100, "BOTTOMLEFT", PAD + 144, function() ns.CaptureJournalKey() end)
    button("Got it", 90, "BOTTOMRIGHT", -(PAD - 2), function() f:Hide() end)
    return f
end

function ns.ShowWelcome()
    DungeonMapDB.welcomed = true
    local f = DungeonMapWelcomeFrame or build()
    local key = ns.JournalKeyText and ns.JournalKeyText()
    f.body:SetText(table.concat({
        "|cffffd100Open the world map|r and click a dungeon or raid entrance pin to see its map.",
        "|cffffd100Inside a dungeon|r the map key shows the dungeon map: where you are, bosses, loot.",
        "|cffffd100The Journal|r lists every dungeon and raid, with search. Open it with the Journal button on the map's top bar" ..
            (key and (" or the " .. key .. " key") or ", or give it a key of your own") .. ", or type /dm list.",
        "Everything is in Esc > Options > AddOns > Dungeon Crawler Forever. /dm shows the commands.",
    }, "\n\n"))
    -- the window is as tall as its text: title bar, banner, intro, body, a clear gap, then the buttons
    local textH = (f.intro:GetStringHeight() or 14) + 12 + (f.body:GetStringHeight() or 200)
    f:SetHeight(TITLE_H + BANNER_H + 14 + textH + 28 + 26 + 16 + 4)
    f:Show()
end

-- called a few seconds after logging in: once ever, never in combat
function ns.MaybeWelcome()
    if not (ns.isForever and DungeonMapDB) or DungeonMapDB.welcomed then return end
    if InCombatLockdown and InCombatLockdown() then return end
    ns.ShowWelcome()
end
