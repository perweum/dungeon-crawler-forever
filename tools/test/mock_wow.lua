-- Minimal WoW UI mock so addon code can be executed outside the game (smoke tests; catches nil calls/typos, not API semantics).
local M = {}
local calls = {}
M.errors = {}

M.colorErrors = {}
local numeric = { GetWidth = 800, GetHeight = 600, GetLeft = 100, GetRight = 900, GetTop = 700, GetBottom = 100, GetScale = 1,
  GetEffectiveScale = 1, GetFrameLevel = 10, GetStringWidth = 80, GetTextWidth = 80, GetStringHeight = 12, GetAlpha = 1, GetEffectiveAlpha = 1,
  GetNumPoints = 1, GetCanvasScale = 1, GetVerticalScrollRange = 100 }
local returnsSelf = {}

local FrameMT = {}
M.frames = {}
local function newFrame(name, parent)
  local f = { __name = name, __parent = parent, __shown = true, __scripts = {}, __text = "" }
  table.insert(M.frames, f)
  return setmetatable(f, FrameMT)
end
FrameMT.__index = function(t, k)
  if numeric[k] then return function() return numeric[k] end end
  if k == "IsShown" or k == "IsVisible" then return function(self) return self.__shown end end
  if k == "Show" then return function(self) self.__shown = true end end
  if k == "Hide" then return function(self) self.__shown = false end end
  if k == "SetShown" then return function(self, v) self.__shown = v and true or false end end
  if k == "SetTextColor" then return function(self, r, g, b) if type(r) ~= "number" then error("bad argument #1 to 'SetTextColor'") end end end
  if k == "SetSize" then return function(self, w, h) if type(w) ~= "number" or type(h) ~= "number" then error("bad argument to 'SetSize' (" .. tostring(w) .. ", " .. tostring(h) .. ")", 2) end end end
  if k == "SetWidth" or k == "SetHeight" then return function(self, v) if type(v) ~= "number" then error("bad argument to '" .. k .. "' (" .. tostring(v) .. ")", 2) end end end
  if k == "SetText" then return function(self, v) self.__text = tostring(v) end end
  if k == "GetText" then return function(self) return self.__text end end
  if k == "SetScript" then return function(self, ev, fn) self.__scripts[ev] = fn end end
  if k == "GetScript" then return function(self, ev) return self.__scripts[ev] end end
  if k == "HookScript" then return function() end end
  if k == "GetParent" then return function(self) return self.__parent end end
  if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
  if k == "GetAtlas" or k == "GetTexture" then return function() return nil end end
  if k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" then return function(self) return newFrame(k, self) end end
  if type(k) == "string" and k:match("^[A-Z]") then return function(self) return self end end
  return nil
end

function M.install(G)
  G.CreateFrame = function(_, name, parent, template)
    local f = newFrame(name, parent)
    if name then G[name] = f end
    f.Inset = newFrame("Inset", f); f.TitleText = newFrame("TitleText", f); f.SetTitle = function(self, t) self.__title = t end
    return f
  end
  G.UIParent = newFrame("UIParent")
  G.WorldMapFrame = newFrame("WorldMapFrame")
  G.WorldMapFrame.ScrollContainer = newFrame("ScrollContainer", G.WorldMapFrame)
  G.WorldMapFrame.NavBar = newFrame("NavBar", G.WorldMapFrame)
  G.WorldMapFrame.NavBar.navList = {}
  G.WorldMapFrame.mapID = 947
  G.WorldMapFrame.GetMapID = function(self) return self.mapID end
  G.WorldMapFrame.SetMapID = function(self, id) self.mapID = id end
  G.WorldMapFrame.GetCanvas = function(self) return self.ScrollContainer end
  G.SetPortraitTextureFromCreatureDisplayID = function() end
  G.UnitExists = function() return true end
  G.Item = { CreateFromItemID = function(_, id) local o = { id = id }
    function o:ContinueOnItemLoad(fn) fn() end
    function o:GetItemIcon() return 134400 end
    function o:GetItemName() return 'Item' .. self.id end
    function o:GetItemQualityColor() return { r = 0, g = 0.44, b = 0.87, hex = '', color = {} } end
    function o:GetItemLink() return '|Hitem:' .. self.id .. '|h[x]|h' end
    return o end }
  G.Spell = { CreateFromSpellID = function(_, id) local o = { id = id }
    function o:ContinueOnSpellLoad(fn) fn() end
    function o:GetSpellName() return 'Spell' .. self.id end
    function o:GetSpellDescription() return 'Deals damage to a random target.' end
    return o end }
  G.C_Spell = { GetSpellInfo = function(id) return { name = 'Spell' .. id, iconID = 134400, castTime = 1500 } end }
  G.IsModifiedClick = function() return false end
  G.GetBuildInfo = function() return '1.60.1', '70291', 'Oct  7 2026', 16001 end
  G.GetQuestDifficultyColor = function(l) return { r = 0.25, g = 0.75, b = 0.25 } end
  G.time = os.time
  G.GetTime = function() return os.clock() end
  G.SecondsToTime = function(n) return n .. 's' end
  G.INSTANCE_RESET_SUCCESS = '%s has been reset.'
  G.Settings = { VarType = { Boolean = 'boolean', Number = 'number' },
    RegisterVerticalLayoutCategory = function(n) return { GetID = function() return 1 end, name = n } end,
    RegisterAddOnSetting = function(cat, var, key, tbl, vt, label, default) if tbl[key] == nil then tbl[key] = default end return { SetValueChangedCallback = function() end } end,
    CreateCheckbox = function() end, CreateSliderOptions = function() return { SetLabelFormatter = function() end } end, CreateSlider = function() end,
    RegisterAddOnCategory = function() end, OpenToCategory = function() end }
  G.IsShiftKeyDown = function() return false end
  G.unpack = table.unpack or unpack
  G.GameTooltip = newFrame("GameTooltip")
  G.GameTooltip_Hide = function() end
  G.ToggleWorldMap = function() G.WorldMapFrame.__shown = true end
  G.NavBar_AddButton = function(nav, data)
    local b = newFrame("navbtn", nav); b.data = data; b.SetText = function(self, t) self.__text = t end; b.__text = data.name
    table.insert(nav.navList, b)
  end
  G.hooksecurefunc = function() end
  G.C_Timer = { After = function(_, fn) fn() end }
  G.C_Map = { GetMapInfo = function(id) return { name = "Map" .. id, parentMapID = 947, mapID = id, mapType = (id == 1414 or id == 1415) and 2 or 3 } end }
  G.C_Texture = {}
  G.IsInInstance = function() return false end
  G.GetInstanceInfo = function() return "x", "party", 1, "", 5, 0, false, 36 end
  G.GetNumSavedInstances = function() return 0 end
  G.GetCursorPosition = function() return 400, 300 end
  G.IsMouseButtonDown = function() return false end
  G.InCombatLockdown = function() return false end
  G.format = string.format; G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  G.tinsert = table.insert; G.UISpecialFrames = {}
  G.SlashCmdList = {}
  G.pcall = pcall
  G.date = os.date
end
return M
