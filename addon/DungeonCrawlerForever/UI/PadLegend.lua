-- Controller key legend drawn like the game's own input legend: the real button glyphs (atlases) next to a gold label, on a dark plate.
-- Nothing of Blizzard's is created or touched: our own frame, our own textures.
-- The glyphs are the game's own: the atlas comes from Blizzard's input icon sets (InputIconTextureSetUtility, read only: the same lookup the game's
-- footers use, so the set follows the connected controller: Xbox letters, PlayStation shapes, Switch). When that lookup is missing the real atlas
-- names below are used; when this client lacks an atlas the key is drawn as a gold [A] badge.
-- (Names from Blizzard_SharedXML/Shared/InputIcons/InputIconTexture.lua, branch forever, read 2026-11-17. The earlier gamepad-xb-32x-* names
-- were guesses and mostly do not exist: A / B / X / Y showed up as [A] / [B] text.)
local ADDON, ns = ...

-- our key token -> the game's constant for it (the value is what the game's icon sets are keyed by)
local KEY = {
    A = "GAMEPAD_FACE_BOTTOM", B = "GAMEPAD_FACE_RIGHT", X = "GAMEPAD_FACE_LEFT", Y = "GAMEPAD_FACE_TOP",
    LB = "GAMEPAD_SHOULDER_LEFT", RB = "GAMEPAD_SHOULDER_RIGHT", LT = "GAMEPAD_TRIGGER_LEFT", RT = "GAMEPAD_TRIGGER_RIGHT",
    LSTICK = "GAMEPAD_STICK_LEFT", RSTICK = "GAMEPAD_STICK_RIGHT", RSTICK_UD = "GAMEPAD_STICK_RIGHT_VERTICAL",
    DPAD = "GAMEPAD_DPAD", DPAD_UP = "GAMEPAD_DPAD_TOP", DPAD_DOWN = "GAMEPAD_DPAD_BOTTOM", DPAD_LEFT = "GAMEPAD_DPAD_LEFT", DPAD_RIGHT = "GAMEPAD_DPAD_RIGHT",
}
-- same tokens, the Normal state of the game's Letters (Xbox) and Shapes (PlayStation) sets
local ATLAS = {
    xbox = {
        A = "gamepad-xbox1-buttona-normal", B = "gamepad-xbox1-buttonb-normal", X = "gamepad-xbox1-buttonx-normal", Y = "gamepad-xbox1-buttony-normal",
        LB = "gamepad-xbox1-trigger-lb-normal", RB = "gamepad-xbox1-trigger-rb-normal", LT = "gamepad-xbox1-trigger-lt-normal", RT = "gamepad-xbox1-trigger-rt-normal",
        LSTICK = "gamepad-xbox1-stick-l-normal", RSTICK = "gamepad-xbox1-stick-r-normal", RSTICK_UD = "gamepad-xbox1-stick-updown-normal",
        DPAD = "gamepad-xbox1-dpadall-normal", DPAD_UP = "gamepad-xbox1-dpadup-normal", DPAD_DOWN = "gamepad-xbox1-dpaddown-normal",
        DPAD_LEFT = "gamepad-xbox1-dpadleft-normal", DPAD_RIGHT = "gamepad-xbox1-dpadright-normal",
    },
    playstation = {
        A = "gamepad-ps-buttoncrox-normal", B = "gamepad-ps-buttoncircle-normal", X = "gamepad-ps-buttonsquare-normal", Y = "gamepad-ps-buttontriangle-normal",
        LB = "gamepad-ps-triggerl1-normal", RB = "gamepad-ps-triggerr1-normal", LT = "gamepad-ps-triggerl2-normal", RT = "gamepad-ps-triggerr2-normal",
        LSTICK = "gamepad-ps-stickl-normal", RSTICK = "gamepad-ps-stickr-normal", RSTICK_UD = "gamepad-ps-stickr-updown-normal",
        DPAD = "gamepad-ps-dpadall-normal", DPAD_UP = "gamepad-ps-dpadup-normal", DPAD_DOWN = "gamepad-ps-dpaddown-normal",
        DPAD_LEFT = "gamepad-ps-dpadleft-normal", DPAD_RIGHT = "gamepad-ps-dpadright-normal",
    },
}
local FALLBACK_TEXT = {
    xbox = { A = "A", B = "B", X = "X", Y = "Y", LB = "LB", RB = "RB", LT = "LT", RT = "RT", LSTICK = "LS", RSTICK = "RS", RSTICK_UD = "RS", DPAD = "D-pad", DPAD_UP = "Up", DPAD_DOWN = "Down", DPAD_LEFT = "Left", DPAD_RIGHT = "Right" },
    playstation = { A = "Cross", B = "Circle", X = "Square", Y = "Triangle", LB = "L1", RB = "R1", LT = "L2", RT = "R2", LSTICK = "L3", RSTICK = "R3", RSTICK_UD = "R3", DPAD = "D-pad", DPAD_UP = "Up", DPAD_DOWN = "Down", DPAD_LEFT = "Left", DPAD_RIGHT = "Right" },
}
local GLYPH = 28

-- "xbox" or "playstation": the saved choice (DungeonMapDB.padStyle), else what the connected controller calls itself, else xbox
function ns.PadStyle()
    local s = DungeonMapDB and DungeonMapDB.padStyle
    if s == "xbox" or s == "playstation" then return s end
    if C_GamePad and C_GamePad.GetDeviceMappedState then
        local ok, state = pcall(C_GamePad.GetDeviceMappedState)
        local name = ok and type(state) == "table" and type(state.name) == "string" and state.name:lower() or ""
        if name:find("dual") or name:find("playstation") or name:find("ps5") or name:find("ps4") then return "playstation" end
    end
    return "xbox"
end

local function atlasExists(name)
    return type(name) == "string" and (not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(name) ~= nil)
end

-- atlas name for a key token, or nil when this client has none (the legend then writes [A]). Looked up each time (cheap, and only when the legend
-- changes): the game's active icon set can change while we are open.
function ns.PadGlyph(token, style)
    local util = _G.InputIconTextureSetUtility
    local constant = KEY[token] and _G[KEY[token]]
    if constant and type(util) == "table" and util.GetNormalActiveInputIconButtonTexture then
        local ok, name = pcall(util.GetNormalActiveInputIconButtonTexture, constant)
        if ok and atlasExists(name) then return name end
    end
    local name = ATLAS[style or ns.PadStyle()] and ATLAS[style or ns.PadStyle()][token]
    if atlasExists(name) then return name end
    return nil
end

-- the game's newer prompt art is a 76x75 canvas with padding: drawn 5 px bigger on each side, the way the game's own footers do
local function padded(atlas)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    return type(info) == "table" and info.width == 76 and info.height == 75
end

local Legend = {}

-- rows: { { {keys = {"LSTICK"}, text = "Crosshair"}, ... }, ... }
function Legend:SetRows(rows)
    local style = ns.PadStyle()
    local sig = style .. (ns.PadGlyph("A", style) or "-") -- (the glyph of A tells which icon set the game uses now)
    for _, row in ipairs(rows) do
        for _, e in ipairs(row) do sig = sig .. "|" .. table.concat(e.keys, "+") .. ":" .. e.text end
        sig = sig .. "/"
    end
    if sig == self.sig then return end
    self.sig = sig
    local usedTex, usedStr = 0, 0
    for _, t in ipairs(self.texs) do t:Hide() end
    for _, s in ipairs(self.strs) do s:Hide() end
    local function tex()
        usedTex = usedTex + 1
        local t = self.texs[usedTex]
        if not t then t = self:CreateTexture(nil, "ARTWORK"); self.texs[usedTex] = t end
        t:ClearAllPoints(); t:SetRotation(0); t:Show()
        return t
    end
    local function str(font)
        usedStr = usedStr + 1
        local s = self.strs[usedStr]
        if not s then s = self:CreateFontString(nil, "OVERLAY", font); self.strs[usedStr] = s end
        s:SetFontObject(font); s:ClearAllPoints(); s:Show()
        return s
    end
    local layout, widest = {}, 0
    for r, row in ipairs(rows) do
        local items, w = {}, 0
        for i, e in ipairs(row) do
            local parts, pw = {}, 0
            for k, token in ipairs(e.keys) do
                local atlas = ns.PadGlyph(token, style)
                local part
                if atlas then
                    local t = tex()
                    t:SetAtlas(atlas)
                    local big = padded(atlas)
                    t:SetSize(big and GLYPH + 10 or GLYPH, big and GLYPH + 10 or GLYPH)
                    part = { obj = t, w = GLYPH, pad = big and 5 or 0 }
                else
                    local s = str("GameFontHighlightSmall")
                    s:SetText("[" .. ((FALLBACK_TEXT[style] or FALLBACK_TEXT.xbox)[token] or token) .. "]")
                    s:SetTextColor(1, 0.82, 0)
                    part = { obj = s, w = s:GetStringWidth() or 18 }
                end
                parts[#parts + 1] = part
                pw = pw + part.w + (k > 1 and 4 or 0)
            end
            local label = str("GameFontNormal")
            label:SetText(e.text)
            local lw = label:GetStringWidth() or 40
            items[#items + 1] = { parts = parts, label = label, lw = lw }
            w = w + pw + 6 + lw + (i > 1 and 22 or 0)
        end
        layout[r] = { items = items, w = w }
        if w > widest then widest = w end
    end
    local rowH = GLYPH + 8
    self:SetSize(widest + 36, #rows * rowH + 10)
    for r, row in ipairs(layout) do
        local x = (widest - row.w) / 2 + 18
        local y = -(5 + (r - 1) * rowH + rowH / 2)
        for i, it in ipairs(row.items) do
            if i > 1 then x = x + 22 end
            for k, part in ipairs(it.parts) do
                if k > 1 then x = x + 4 end
                part.obj:SetPoint("LEFT", self, "TOPLEFT", x - (part.pad or 0), y)
                x = x + part.w
            end
            it.label:SetPoint("LEFT", self, "TOPLEFT", x + 6, y)
            x = x + 6 + it.lw
        end
    end
end

-- parent: the frame it lives in; the caller anchors it
function ns.NewPadLegend(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.92)
    f:SetBackdropBorderColor(0.45, 0.4, 0.3, 1)
    f:EnableMouse(false)
    f.texs, f.strs = {}, {}
    for k, v in pairs(Legend) do f[k] = v end
    return f
end
