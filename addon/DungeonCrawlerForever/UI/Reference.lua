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

-- Test layer (/dm questtest): a blue "!" where a quest giver stands inside a dungeon, from the same CMaNGOS spawns, for the quests whose `where` is
-- inside (a "!") and for the NPCs that take a quest in inside (a "?"). Only to check the generated positions in the game before they become real quest markers; nothing is saved.
local qdots = {}

-- The quests an NPC (by name) hands out inside this dungeon (pick) and takes in inside it (hand: a turn-in with no outdoor zone), as names.
local function givenBy(instanceID, name)
    local pick, hand = {}, {}
    for _, q in ipairs(ns.QuestData and ns.QuestData[instanceID] or {}) do
        if q.where == "inside" and q.giver == name then pick[#pick + 1] = q.name end
        if q.turnin == name and not q.turninZone then hand[#hand + 1] = q.name end
    end
    return pick, hand
end

function ns.RenderQuestTest(art, instanceID, floorID, show)
    local list = show and ns.Reference and ns.Reference[instanceID] and ns.Reference[instanceID][floorID]
    local n = 0
    if list then
        local w, h = art:GetWidth(), art:GetHeight()
        for _, d in ipairs(list) do
            local pick, hand
            if d.t ~= "door" and d.t ~= "chest" and d.t ~= "lift" then pick, hand = givenBy(instanceID, d.n) end
            if pick and (#pick > 0 or #hand > 0) then
                n = n + 1
                local f = qdots[n]
                if not f then
                    f = CreateFrame("Button", nil, art)
                    f:SetFrameLevel(art:GetFrameLevel() + 6)
                    f:SetSize(22, 22)
                    f.tex = f:CreateTexture(nil, "OVERLAY")
                    f.tex:SetAllPoints()
                    f:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.d.n or "?")
                        for _, qn in ipairs(self.pick) do GameTooltip:AddLine("Pick up: " .. qn, 1, 0.82, 0) end
                        for _, qn in ipairs(self.hand) do GameTooltip:AddLine("Hand in: " .. qn, 0.5, 0.9, 0.5) end
                        GameTooltip:AddLine("test marker: CMaNGOS spawn position", 0.6, 0.6, 0.6)
                        GameTooltip:Show()
                    end)
                    f:SetScript("OnLeave", GameTooltip_Hide)
                    qdots[n] = f
                end
                f.d, f.pick, f.hand = d, pick, hand
                if #pick > 0 then ns.SetQuestMarker(f.tex) else f.tex:SetAtlas("QuestTurnin"); f.tex:SetDesaturated(false); f.tex:SetVertexColor(1, 1, 1) end -- "!" to pick up, "?" only to hand in
                f:ClearAllPoints()
                f:SetPoint("CENTER", art, "TOPLEFT", d.x * w, -d.y * h)
                f:Show()
            end
        end
    end
    for i = n + 1, #qdots do qdots[i]:Hide() end
    return n
end

-- /dm questtest: switch the test layer on or off, and say which givers of this dungeon have a spawn and which do not
function ns.ToggleQuestTest()
    ns.questTest = not ns.questTest
    local id = ns.GetState and ns.GetState().instanceID
    if ns.questTest and id then
        local want, found = {}, {}
        for _, q in ipairs(ns.QuestData and ns.QuestData[id] or {}) do
            if q.where == "inside" and q.giver then want[q.giver] = true end
            if q.turnin and not q.turninZone then want[q.turnin] = true end
        end
        for _, floor in pairs(ns.Reference and ns.Reference[id] or {}) do
            for _, d in ipairs(floor) do if d.t ~= "door" and d.t ~= "chest" and d.t ~= "lift" and want[d.n] then found[d.n] = (found[d.n] or 0) + 1 end end
        end
        local with, without = {}, {}
        for name in pairs(want) do if found[name] then with[#with + 1] = format("%s (%d)", name, found[name]) else without[#without + 1] = name end end
        table.sort(with); table.sort(without)
        ns.Print("Quest marker test ON. Givers placed: " .. (#with > 0 and table.concat(with, ", ") or "none") .. ". No spawn found: " .. (#without > 0 and table.concat(without, ", ") or "none") .. ".")
    else
        ns.Print("Quest marker test " .. (ns.questTest and "ON (open a dungeon map)." or "off."))
    end
    if ns.RefreshMap then ns.RefreshMap() end
end
