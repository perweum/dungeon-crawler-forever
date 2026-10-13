-- Developer reference layer (edit mode, "Landmarks" button): known bosses, rares, vendors, quest givers, doors, lifts and chests plotted on the floor,
-- so abstract maps (Gnomeregan, Blackrock Spire) are easier to read while recording stairs and arrows. Data: Data/Reference.lua (CMaNGOS spawns).
local _, ns = ...

local COLORS = {
    boss = { 1, 0.2, 0.2 }, rare = { 0.75, 0.8, 1 }, vendor = { 1, 0.85, 0.1 }, quest = { 1, 0.65, 0.1 }, trainer = { 0.4, 0.9, 0.4 },
    npc = { 0.7, 0.7, 0.7 }, door = { 0.3, 0.7, 1 }, lift = { 0.9, 0.4, 1 }, chest = { 0.9, 0.7, 0.3 },
}
local LABELS = { boss = "Boss", rare = "Rare", vendor = "Vendor", quest = "Quest giver", trainer = "Trainer", npc = "NPC", door = "Door / gate", lift = "Lift / transport", chest = "Chest" }

local dots = {}

local function create(parent)
    local f = CreateFrame("Button", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f:SetScript("OnEnter", function(self)
        local d = self.d
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(d.n or "?")
        GameTooltip:AddLine((LABELS[d.t] or d.t) .. (d.l and (", level " .. d.l) or ""), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

-- Draw (or hide) the landmarks of one floor on the art frame.
function ns.RenderReference(art, instanceID, floorID, show)
    local list = show and ns.Reference and ns.Reference[instanceID] and ns.Reference[instanceID][floorID]
    local n = 0
    if list then
        local w, h = art:GetWidth(), art:GetHeight()
        for _, d in ipairs(list) do
            n = n + 1
            local f = dots[n] or create(art)
            dots[n] = f
            f.d = d
            local c = COLORS[d.t] or COLORS.npc
            f.tex:SetColorTexture(c[1], c[2], c[3], 0.9)
            local s = (d.t == "boss" or d.t == "lift" or d.t == "door") and 11 or 8
            f:SetSize(s, s)
            f:ClearAllPoints()
            f:SetPoint("CENTER", art, "TOPLEFT", d.x * w, -d.y * h)
            f:Show()
        end
    end
    for i = n + 1, #dots do dots[i]:Hide() end
    return n
end
