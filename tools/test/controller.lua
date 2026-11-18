-- Isolated input/geometry fixture: real controller code, without the permissive UI mock.
local ns = {}
local frames = {}
local function frame(kind,parent,x,y,w,h)
    local f = {kind=kind,parent=parent,x=x or 0,y=y or 0,w=w or 20,h=h or 20,shown=true,children={},scripts={}}
    frames[#frames+1]=f
    if parent then parent.children[#parent.children+1]=f end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:IsShown() return self.shown end
    function f:Show() local old=self.shown; self.shown=true; if not old and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function f:Hide() local old=self.shown; self.shown=false; if old and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function f:IsObjectType(t) return self.kind==t end
    function f:IsEnabled() return not self.disabled end
    function f:IsProtected() return self.protected or false end
    function f:GetChildren() return table.unpack(self.children) end
    function f:GetParent() return self.parent end
    function f:GetRect() return self.x,self.y,self.w,self.h end
    function f:GetEffectiveScale() return 1 end
    function f:GetFrameLevel() return 1 end
    function f:GetScript(k) return self.scripts[k] end
    function f:SetText(text) self.text=text end
    function f:SetScript(k,fn) self.scripts[k]=fn end
    function f:HookScript(k,fn) self.scripts[k]=fn end
    function f:IsMoving() return false end
    function f:SetPropagateKeyboardInput(v) self.propagate=v end
    function f:EnableGamePadButton(v) self.enabledPad=v end
    function f:GetVerticalScroll() return self.scroll or 0 end
    function f:GetVerticalScrollRange() return 500 end
    function f:SetVerticalScroll(v) self.scroll=v end
    function f:CreateFontString() return frame('FontString',self) end
    function f:CreateTexture() return frame('Texture',self) end
    for _,name in ipairs({'LockHighlight','UnlockHighlight','SetFrameStrata','ClearAllPoints','SetPoint','SetBackdrop','SetBackdropBorderColor','EnableMouse','RegisterEvent','EnableKeyboard','SetSize','SetWidth','SetColorTexture','SetAtlas','SetTexCoord','SetVertexColor'}) do f[name]=function() end end
    return f
end
UIParent=frame('Frame')
WorldMapFrame=frame('Frame',UIParent)
local canvasFocus=true
WorldMapFrame.IsCanvasGamepadFocus=function() return canvasFocus end
local questPanel=frame('Frame',WorldMapFrame) -- the quest log panel (shown on the small map)
WorldMapFrame.QuestLog=questPanel
WorldMapFrame.IsQuestDetailsFocused=function() return false end
GamepadMode={FrameControlsManager={isUIFocused=true,focusedFrame=WorldMapFrame}}
CreateFrame=function(kind,_,parent) return frame(kind,parent) end
local inCombat,pad=false,true
InCombatLockdown=function() return inCombat end
InputUtil={IsGamepadUIEnabled=function() return pad end}
local view=frame('Frame',WorldMapFrame)
local scroll=frame('ScrollFrame',view,0,50,100,200)
local clicks={}
local function button(parent,x,y,name)
    local f=frame('Button',parent,x,y)
    f:SetScript('OnClick',function() clicks[#clicks+1]=name end)
    return f
end
local first=button(scroll,10,200,'boss')
local second=button(scroll,10,160,'loot')
local offscreen=button(scroll,10,10,'quest')
local right=button(view,200,200,'floor')
local disabled=button(view,10,180,'disabled'); disabled.disabled=true
local protected=button(view,10,190,'protected'); protected.protected=true
local journal=frame('Frame',WorldMapFrame); journal:Hide()
local chooser=frame('Frame',UIParent); chooser:Hide()
button(chooser,10,10,'chooser')
local pin=button(WorldMapFrame,10,10,'entrance')
ns.journalButton=button(WorldMapFrame,100,10,'journal')
ns.ControllerEntranceRoots=function() return {pin},chooser end
ns.ControllerViewRoots=function() return {view} end
ns.ControllerSidebarRoot=function() return scroll end
ns.ControllerMapRoot=function() return view end
ns.ControllerMapRect=function() return 0,0,500,500 end
local zoomCalls=0
local pans={}
ns.ControllerPan=function(dx,dy) pans[#pans+1]={dx,dy} end
ns.ControllerZoom=function(factor,x,y) zoomCalls=zoomCalls+1; assert(factor>0 and x and y) end
ns.ControllerSetSection=function() end
ns.ShowJournal=function() view:Hide(); journal:Show() end
ns.ControllerJournalRoot=function() return journal end
ns.ViewShown=function() return view:IsVisible() end
ns.JournalShown=function() return journal:IsVisible() end
ns.GoUp=function() view:Hide() end
ns.HideJournal=function() journal:Hide() end
ns.HideEntranceChooser=function() chooser:Hide() end
local toggles=0
ns.ControllerToggleSide=function() toggles=toggles+1 end
assert(loadfile('addon/DungeonCrawlerForever/UI/Controller.lua'))('DungeonCrawlerForever',ns)
ns.SetupController()
local input,watch
for _,f in ipairs(frames) do
    if f.scripts.OnGamePadButtonUp then input=f end
    if f.scripts.OnUpdate then watch=f end
end
assert(input and watch)
local function press(key)
    input.scripts.OnGamePadButtonDown(input,key)
    local consumed=not input.propagate
    input.scripts.OnGamePadButtonUp(input,key)
    return consumed
end
watch.scripts.OnUpdate(watch,0.1)
assert(press('PADDRIGHT')); assert(press('PAD1')); assert(clicks[#clicks]=='boss')
assert(press('PADDDOWN')); press('PAD1'); assert(clicks[#clicks]=='loot','disabled/protected controls skipped')
press('PADDDOWN'); press('PAD1'); assert(clicks[#clicks]=='quest'); assert(scroll.scroll>0,'offscreen row scrolled into view')
press('PADDLEFT'); SoftCursor=frame('Frame',nil,200,200,2,2); press('PAD1'); assert(clicks[#clicks]=='floor','map mode selects with crosshair')
press('PADDRIGHT'); SoftCursor.x=10; SoftCursor.y=10; watch.scripts.OnUpdate(watch,0.1); press('PAD1'); assert(clicks[#clicks]=='boss','sidebar focus unaffected by moving cursor')
SoftCursor:Hide()
press('PAD3'); assert(toggles==1)
assert(press('PAD2')); assert(not view:IsShown());
for _,key in ipairs({'PADDUP','PADDDOWN','PADDLEFT','PADDRIGHT','PAD3','PAD4'}) do assert(not press(key),'native world-map control: '..key) end
watch.scripts.OnUpdate(watch,0.1); assert(not input:IsShown() and not input.enabledPad,'no listener on ordinary map')
 assert(not press('PAD2'),'world map Cancel belongs to Blizzard')
chooser:Show(); press('PADDDOWN'); press('PAD1'); assert(clicks[#clicks]=='chooser'); press('PAD2'); assert(not chooser:IsShown())
SoftCursor=frame('Frame',nil,10,10,2,2)
watch.scripts.OnUpdate(watch,0.1); press('PAD1'); assert(clicks[#clicks]=='entrance','soft cursor selects pin')
-- A stationary soft cursor must not steal A or directions from quests/details.
canvasFocus=false
watch.scripts.OnUpdate(watch,0.1); assert(not input:IsShown() and not input.enabledPad)
local before=#clicks
for _,key in ipairs({'PAD1','PAD2','PAD3','PAD4','PADDUP','PADDDOWN','PADDLEFT','PADDRIGHT'}) do assert(not ns.ControllerHandle(key)) end
assert(#clicks==before)
view:Show(); assert(not ns.ControllerHandle('PADDDOWN'),'quest focus wins even with our overlay visible'); view:Hide()
canvasFocus=true
GamepadMode.FrameControlsManager.isUIFocused=false
assert(not ns.ControllerHandle('PAD1'),'gameplay owns input when UI unfocused')
GamepadMode.FrameControlsManager.isUIFocused=true
GamepadMode.FrameControlsManager.focusedFrame=UIParent
assert(not ns.ControllerHandle('PAD1'),'another window owns input')
GamepadMode.FrameControlsManager.focusedFrame=WorldMapFrame
SoftCursor.x=500; watch.scripts.OnUpdate(watch,0.1)
assert(not input:IsShown() and not input.enabledPad,'leaving pin disables listener')
assert(not ns.ControllerHandle('PAD1'),'no stale pin activation')
SoftCursor.x=10
-- Active (disabled) tabs retain focus; Down continues from that anchor.
view:Show(); press('PADDRIGHT')
first.controllerFocusAnchor=true
first:SetScript('OnClick',function() first.disabled=true; clicks[#clicks+1]='tab' end)
press('PAD1'); watch.scripts.OnUpdate(watch,0.1); press('PADDDOWN'); press('PAD1')
assert(clicks[#clicks]=='loot','focus continues from activated tab')
first.disabled=false
-- Dropdown is modal; Back restores the opener and its sidebar section.
local dropdown=frame('Frame',view); dropdown:Hide()
button(dropdown,50,180,'menu1'); button(dropdown,50,140,'menu2')
ns.ControllerModal=function() return dropdown end
first:SetScript('OnClick',function() dropdown:Show() end)
press('PADDUP'); press('PAD1'); watch.scripts.OnUpdate(watch,0.1)
press('PADDDOWN'); press('PAD1'); assert(clicks[#clicks]=='menu2')
press('PADDLEFT'); press('PAD1'); assert(clicks[#clicks]=='menu2','background cannot receive menu navigation')
press('PAD2'); assert(not dropdown:IsShown() and view:IsShown(),'Back closes menu only')
press('PAD1'); assert(dropdown:IsShown(),'focus returned to opener')
press('PAD2'); view:Hide()
WorldMapFrame:Hide(); assert(not ns.ControllerHandle('PAD2')); assert(not ns.ControllerHandle('PAD1'))
WorldMapFrame:Show(); inCombat=true; watch.scripts.OnEvent(watch); assert(not input:IsShown()); assert(not ns.ControllerHandle('PAD1'))
inCombat=false; pad=false; watch.scripts.OnUpdate(watch,0.1); assert(not input:IsShown()); assert(not ns.ControllerHandle('PAD1'))
pad=true; watch.scripts.OnUpdate(watch,0.1); assert(input:IsShown() and input.propagate)
local welcome=frame('Frame',UIParent)
UISpecialFrames={'existing'}
ns.ControllerDismiss(welcome); welcome.scripts.OnKeyDown(welcome,'ESCAPE')
assert(not welcome:IsShown() and #UISpecialFrames==1)
welcome:Show(); assert(welcome.propagate); welcome.scripts.OnGamePadButtonDown(welcome,'PAD2'); assert(not welcome:IsShown())
print('ok   controller: navigation, scroll, cursor, modal chooser, Cancel, combat, mouse mode, welcome')

-- A rejected controller key must retain the previous journal binding.
format=string.format
ns.Print=function() end
local bindings={OLD='DUNGEONMAP_JOURNAL'}
GetBindingAction=function(k) return bindings[k] end
GetBindingKey=function(action) for k,v in pairs(bindings) do if v==action then return k end end end
SetBinding=function(k,action) if k=='INVALID' then return false end; bindings[k]=action; return true end
SaveBindings=function() end
assert(loadfile('addon/DungeonCrawlerForever/UI/Options.lua'))('DungeonCrawlerForever',ns)
assert(not ns.BindKey('INVALID','DUNGEONMAP_JOURNAL')); assert(bindings.OLD=='DUNGEONMAP_JOURNAL')
assert(ns.BindKey('PAD4','DUNGEONMAP_JOURNAL')); assert(not bindings.OLD and bindings.PAD4=='DUNGEONMAP_JOURNAL')
inCombat=true; assert(not ns.BindKey('PAD3','DUNGEONMAP_JOURNAL')); assert(bindings.PAD4)
inCombat=false
IsAltKeyDown=function() return false end
IsControlKeyDown=function() return false end
IsShiftKeyDown=function() return false end
ns.NewWindow=function(name)
    local f=frame('Frame',UIParent)
    _G[name]=f
    function f:SetSize() end
    function f:SetTitle() end
    return f
end
local oldCreate=CreateFrame
CreateFrame=function(...)
    local f=oldCreate(...)
    function f:SetSize() end
    function f:SetJustifyH() end
    return f
end
-- Font strings also need the text alignment method used in the real dialog.
local oldNew=ns.NewWindow
ns.NewWindow=function(name)
    local f=oldNew(name)
    function f:CreateFontString()
        local t=frame('FontString',self)
        function t:SetJustifyH() end
        return t
    end
    return f
end
ns.CaptureJournalKey()
assert(DungeonMapKeyCapture.enabledPad and not DungeonMapKeyCapture.propagate)
DungeonMapKeyCapture.scripts.OnGamePadButtonDown(DungeonMapKeyCapture,'PAD3')
assert(not DungeonMapKeyCapture:IsShown() and bindings.PAD3=='DUNGEONMAP_JOURNAL')
ns.CaptureJournalKey(); inCombat=true
DungeonMapKeyCapture.scripts.OnEvent(DungeonMapKeyCapture,'PLAYER_REGEN_DISABLED')
assert(not DungeonMapKeyCapture:IsShown())
print('ok   controller binding: failure preserves old binding, success replaces, combat rejects, capture accepts PAD3')

-- Fullscreen is requested on opening only; combat and already-maximized are no-ops.
inCombat=false
local maximized=false
local maximizes=0
WorldMapFrame.IsMaximized=function() return maximized end
WorldMapFrame.BorderFrame={MaximizeMinimizeFrame={Maximize=function() maximizes=maximizes+1; maximized=true end}}
local dbWas=DungeonMapDB; DungeonMapDB={}
DungeonMapDB.openFullscreen=false; ns.OpenDungeonFullscreen(); assert(maximizes==0, 'option off: the map keeps its size')
DungeonMapDB.openFullscreen=true
local padWas=pad; pad=true; ns.OpenDungeonFullscreen(); assert(maximizes==0, 'no maximize with a controller (taint)'); pad=false
ns.OpenDungeonFullscreen(); ns.OpenDungeonFullscreen(); assert(maximizes==1)
maximized=false; inCombat=true; ns.OpenDungeonFullscreen(); assert(maximizes==1)
inCombat=false; ns.OpenDungeonFullscreen(); assert(maximizes==2)
pad=padWas
DungeonMapDB=dbWas
print('ok   fullscreen opening is opt-in and respects combat and current size')

-- The game's size toggle: D-pad Down while small, D-pad Up while full, are the game's (not swallowed) in the dungeon map section.
do
  local wasMax=WorldMapFrame.IsMaximized
  context=nil
  view:Show(); SoftCursor:Show()
  WorldMapFrame.IsMaximized=function() return false end
  watch.scripts.OnUpdate(watch,0.1); press('PADDLEFT')
  assert(not press('PADDDOWN'),'small map: D-pad Down is the game full-map toggle')
  assert(press('PADDUP'),'small map: D-pad Up is still ours (swallowed)')
  WorldMapFrame.IsMaximized=function() return true end
  assert(not press('PADDUP'),'full map: D-pad Up is the game small-map toggle')
  WorldMapFrame.IsMaximized=wasMax
  print('ok   dungeon map keeps the game size toggle (Down full, Up small)')
end
-- Zoom uses the mapped Camera stick, dead zone, and current controller context.
C_GamePad={GetDeviceMappedState=function() return {stickCount=2,sticks={{y=0.9},{y=-0.7}}} end,
StickIndexToConfigName=function(i) return i==0 and "Movement" or "Camera" end}
assert(ns.ControllerZoomTilt()==-0.7)
C_GamePad.GetDeviceMappedState=function() return {stickCount=1,sticks={{y=0.1}}} end
C_GamePad.StickIndexToConfigName=function() return "Camera" end
assert(ns.ControllerZoomTilt()==0)
C_GamePad.GetDeviceMappedState=function() return {stickCount=1,sticks={{y=0.8}}} end
view.w=500; view.h=500; view:Show(); SoftCursor:Show(); SoftCursor.x=200; SoftCursor.y=200
watch.scripts.OnUpdate(watch,0.1); watch.scripts.OnUpdate(watch,0.1); assert(zoomCalls>0,'right stick zooms dungeon map')
-- pushing the cursor into the map edge scrolls it (the left stick only moves the cursor); the middle does not
assert(#pans==0,'cursor in the middle does not pan')
SoftCursor.x=5; SoftCursor.y=250; watch.scripts.OnUpdate(watch,0.05); assert(#pans>0 and pans[#pans][1]<0 and pans[#pans][2]==0,'left edge pans left')
SoftCursor.x=250; SoftCursor.y=495; watch.scripts.OnUpdate(watch,0.05); assert(pans[#pans][2]<0,'top edge pans up')
SoftCursor.x=200; SoftCursor.y=200
local beforeZoom=zoomCalls
press('PADDRIGHT'); watch.scripts.OnUpdate(watch,0.1); assert(zoomCalls==beforeZoom,'sidebar does not zoom')
press('PADDLEFT'); canvasFocus=false; watch.scripts.OnUpdate(watch,0.1); assert(zoomCalls==beforeZoom,'native quest focus does not zoom dungeon')
-- Journal / dungeon map on the FULL map (no quest panel): Blizzard's focus sits on the quest log after opening, yet the pad is ours at once
-- (no A + D-pad Left first). With the quest panel showing, or quest details open, the quest log keeps it.
do
  canvasFocus=false
  local card=button(journal,50,50,'card')
  view:Hide(); journal:Hide(); questPanel:Hide(); journal:Show()
  watch.scripts.OnUpdate(watch,0.1)
  assert(input:IsShown() and input.enabledPad,'full map + journal: listener on although Blizzard focus is the quest log')
  assert(press('PADDDOWN'),'full map + journal: D-pad is consumed')
  local n=#clicks
  press('PAD1'); assert(clicks[#clicks]=='card','full map + journal: A opens the focused card')
  journal:Hide(); view:Show(); watch.scripts.OnUpdate(watch,0.1)
  assert(press('PADDRIGHT'),'full map + dungeon view: sidebar switch works straight away')
  questPanel:Show(); watch.scripts.OnUpdate(watch,0.1)
  assert(not ns.ControllerHandle('PADDDOWN'),'quest panel showing: quest focus wins')
  questPanel:Hide(); WorldMapFrame.IsQuestDetailsFocused=function() return true end
  assert(not ns.ControllerHandle('PADDDOWN'),'quest details focused: quest focus wins')
  WorldMapFrame.IsQuestDetailsFocused=function() return false end
  view:Hide(); journal:Hide()
  assert(not ns.ControllerHandle('PADDDOWN'),'plain map without our screen: Blizzard owns the pad')
  canvasFocus=true; questPanel:Show()
end
print('ok   controller regressions: active tab, modal focus and return, mapped right-stick zoom')
