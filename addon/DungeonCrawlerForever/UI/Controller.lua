-- Controller navigation is limited to our own controls. No secure buttons, global
-- bindings, Blizzard frame hooks, or writes to Blizzard's navigation tables.
local _, ns = ...
local driver, focus, directional, context, cursorOn
local elapsed = 0
local section = "map"
local modalReturn, activeModal
local directions = { PADDUP = {0, 1}, PADDDOWN = {0, -1}, PADDLEFT = {-1, 0}, PADDRIGHT = {1, 0} }
local function combat() return InCombatLockdown and InCombatLockdown() end
function ns.ControllerEnabled()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end
local function visible(f) return f and f:IsVisible() end
local function signal(f, event)
    local fn = f and f:GetScript(event)
    if fn then fn(f) end
end
local function setFocus(f)
    if f == focus then return end
    if focus then
        if focus.UnlockHighlight then focus:UnlockHighlight() end
        signal(focus, "OnLeave")
    end
    focus = f
    if driver then driver.ring:Hide() end
    if f then
        if f.LockHighlight then f:LockHighlight() end
        signal(f, "OnEnter")
        if driver then
            driver.ring:ClearAllPoints()
            driver.ring:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
            driver.ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
            driver.ring:Show()
        end
    end
end
local function rect(f)
    local l, b, w, h = f:GetRect()
    if not l or not b or not w or not h or w <= 0 or h <= 0 then return end
    local s = f:GetEffectiveScale()
    return l*s, b*s, w*s, h*s
end
local function center(f)
    local l,b,w,h = rect(f)
    if l then return l+w/2, b+h/2 end
end
local function inside(f,x,y)
    local l,b,w,h = rect(f)
    return l and x >= l and x <= l+w and y >= b and y <= b+h
end
local function clipped(f,x,y)
    local p = f:GetParent()
    while p and p ~= WorldMapFrame and p ~= UIParent do
        if p:IsObjectType("ScrollFrame") and not inside(p,x,y) then return true end
        p = p:GetParent()
    end
    return false
end
local function reveal(f)
    local p = f:GetParent()
    while p and p ~= WorldMapFrame and p ~= UIParent do
        if p:IsObjectType("ScrollFrame") then
            local _, b, _, h = rect(p)
            local _, fb, _, fh = rect(f)
            if b and fb then
                local delta = fb < b and (b-fb) or (fb+fh > b+h and (b+h-fb-fh) or 0)
                local v = p:GetVerticalScroll() + delta/p:GetEffectiveScale()
                p:SetVerticalScroll(math.max(0, math.min(p:GetVerticalScrollRange(), v)))
            end
        end
        p = p:GetParent()
    end
end
local function collect(root, list, seen, skip)
    if root == skip or not visible(root) or seen[root] then return end
    seen[root] = true
    -- Never invoke protected actions from an insecure gamepad callback.
    if root:IsObjectType("Button") and (root:IsEnabled() or root.controllerFocusAnchor) and not root:IsProtected() and not root.controllerSkip and root:GetScript("OnClick") then
        list[#list+1] = root
    end
    for _, child in ipairs({root:GetChildren()}) do collect(child,list,seen,skip) end
end
local function targets()
    local list, seen = {}, {}
    local modal = ns.ControllerModal and ns.ControllerModal()
    if visible(modal) then collect(modal,list,seen); return list, modal end
    local pins, chooser = ns.ControllerEntranceRoots()
    if visible(chooser) then collect(chooser,list,seen); return list, chooser end
    if ns.ViewShown() then
        local sidebar = ns.ControllerSidebarRoot()
        if section == "sidebar" then collect(sidebar,list,seen)
        else
            for _, root in pairs(ns.ControllerViewRoots()) do collect(root,list,seen,sidebar) end
        end
        return list, "dungeon"
    end
    local journal = ns.ControllerJournalRoot()
    if visible(journal) then
        collect(journal,list,seen)
        for _, root in pairs(ns.ControllerViewRoots()) do collect(root,list,seen) end
        return list, journal
    end
    collect(ns.journalButton,list,seen)
    for _, pin in ipairs(pins) do collect(pin,list,seen) end
    for _, pin in ipairs(ns.ControllerOpenMapPins and ns.ControllerOpenMapPins() or {}) do
        if visible(pin) and not pin:IsProtected() then list[#list+1] = pin end
    end
    return list, "world"
end
-- Does the pad belong to the map canvas (and so to us)? Read only; Blizzard's focus is never changed.
-- Blizzard puts the focus on the QUEST LOG when the map opens (WorldMapMixin:FocusGamepad), so with our journal or dungeon map covering the canvas the
-- player had to press A and then D-pad Left (Blizzard's own "focus map") before anything worked. The quest log is not on screen on the full map: its
-- focus then has nothing to navigate, and our own screen covering the whole canvas takes the pad. With the quest panel showing (small map) or quest
-- details open, the quest log keeps the pad as before.
local function ownScreenShown()
    return (ns.ViewShown and ns.ViewShown()) or (ns.JournalShown and ns.JournalShown()) or false
end
local function canvasPad()
    local w = WorldMapFrame
    if not (w and w.IsCanvasGamepadFocus) then return false end
    if w:IsCanvasGamepadFocus() then return true end
    if not ownScreenShown() then return false end
    local panel = w.QuestLog
    if type(panel) == "table" and panel.IsShown and panel:IsShown() then return false end
    if w.IsQuestDetailsFocused and w:IsQuestDetailsFocused() then return false end
    return true
end
-- What Blizzard's focus looked like the last time our screen was up but the pad was not ours (DungeonMapDB.padDiag), to read after a repro.
local lastPadState
local function padState()
    local w, m = WorldMapFrame, GamepadMode and GamepadMode.FrameControlsManager
    local panel = w and w.QuestLog
    local fw = m and m.focusedFrame
    return format("focus=%s canvas=%s uiFocused=%s focusedFrame=%s maxed=%s questPanel=%s details=%s", tostring(w and w.currentFocus),
        tostring(w and w.IsCanvasGamepadFocus and w:IsCanvasGamepadFocus()), tostring(m and m.isUIFocused),
        tostring(fw and (fw.GetName and fw:GetName() or "?")), tostring(w and w.IsMaximized and w:IsMaximized()),
        tostring(type(panel) == "table" and panel.IsShown and panel:IsShown()), tostring(w and w.IsQuestDetailsFocused and w:IsQuestDetailsFocused()))
end
local nextPadNote = 0
local function notePadState()
    if not DungeonMapDB then return end
    local now = GetTime()
    if now < nextPadNote then return end -- (at most once a second)
    nextPadNote = now + 1
    local state = padState()
    if state ~= lastPadState then
        lastPadState = state
        DungeonMapDB.padDiag = date("%H:%M:%S") .. " " .. state
    end
end
local function available()
    -- SoftCursor can remain visible when the quest list/details own the pad.
    -- Read Blizzard's focus; never change its focus groups or binding stack.
    if not canvasPad() then return false end
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if manager and (not manager.isUIFocused or manager.focusedFrame ~= WorldMapFrame) then return false end
    return visible(WorldMapFrame) and ns.ControllerEnabled() and not combat()
        and not visible(DungeonMapKeyCapture) and not visible(DungeonMapWelcomeFrame)
        and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) and not ns.editing
end
local function refreshTargets()
    local list, nextContext = targets()
    local modal = ns.ControllerModal and ns.ControllerModal()
    if visible(modal) and modal ~= activeModal then
        modalReturn = {focus=focus,section=section,context=context,directional=directional}
        activeModal = modal
        setFocus(list[1]); directional = true; context = nextContext
    elseif activeModal and not visible(activeModal) then
        local saved = modalReturn
        activeModal,modalReturn = nil,nil
        if saved then section=saved.section; context=saved.context; directional=saved.directional; setFocus(saved.focus) end
        list,nextContext = targets()
    end
    local present = false
    for _, f in ipairs(list) do if f == focus then present = true break end end
    if context ~= nextContext then section = "map"; setFocus(nil); directional = false
    elseif not present then setFocus(nil); directional = false end
    context = nextContext
    return list
end
local function move(list, dx, dy)
    if not focus then
        table.sort(list,function(a,b)
            local ax,ay = center(a); local bx,by = center(b)
            if not ax then return false end
            if not bx then return true end
            if math.abs(ay-by) > 6 then return ay > by end
            return ax < bx
        end)
        setFocus(list[1])
    else
        local x,y = center(focus)
        if not x then return end
        local best, score
        for _, f in ipairs(list) do
            local fx,fy = center(f)
            if fx and f ~= focus then
                local along = (fx-x)*dx+(fy-y)*dy
                local across = math.abs((fx-x)*dy-(fy-y)*dx)
                local value = along + across*3
                if along > 2 and (not score or value < score) then best,score = f,value end
            end
        end
        if best then setFocus(best) end
    end
    directional = true
    if focus then reveal(focus) end
end
local function hover(list)
    if not visible(SoftCursor) then
        if not directional then setFocus(nil) end
        return
    end
    if activeModal then return end
    if directional and not SoftCursor:IsMoving() then return end
    directional = false
    local x,y = center(SoftCursor)
    if not x then return end
    local best, level
    for _, f in ipairs(list) do
        if inside(f,x,y) and not clipped(f,x,y) and (not level or f:GetFrameLevel() >= level) then
            best,level = f,f:GetFrameLevel()
        end
    end
    setFocus(best)
end
local function handle(key)
    if not available() then return false end
    local list = refreshTargets()
    if activeModal and key == (GAMEPAD_FACE_RIGHT or "PAD2") then
        activeModal:Hide(); refreshTargets(); return true
    end
    -- The world map's D-pad changes sections/fullscreen; X zooms and B goes back.
    -- Only A directly over one of our controls is ours on that screen.
    if context == "world" then
        directional = false
        hover(list)
        if key ~= (GAMEPAD_FACE_BOTTOM or "PAD1") or not focus then return false end
    end
    if context == "dungeon" then
        if key == "PADDLEFT" or key == "PADDRIGHT" then
            section = key == "PADDLEFT" and "map" or "sidebar"
            ns.ControllerSetSection(section)
            setFocus(nil); directional = section == "sidebar"
            list = refreshTargets()
            if section == "sidebar" then move(list,0,-1) end
            return true
        end
        -- The game's own size toggle (Blizzard_WorldMap bindings): D-pad Down = full map while small, D-pad Up = small map while full. Left to
        -- Blizzard's binding (a call from us would taint the map).
        if section == "map" then
            local maxed = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
            if (key == "PADDDOWN" and not maxed) or (key == "PADDUP" and maxed) then return false end
        end
        if section == "map" and directions[key] then return true end
        if section == "sidebar" and (key == "PADDUP" or key == "PADDDOWN") then
            -- Reading order within the panel, including its tabs and offscreen rows.
            table.sort(list,function(a,b)
                local ax,ay = center(a); local bx,by = center(b)
                if not ax then return false end
                if not bx then return true end
                if ay ~= by then return ay > by end
                return ax < bx
            end)
            local index = 0
            for i,f in ipairs(list) do if f == focus then index = i break end end
            local nextIndex = math.max(1, math.min(#list, index + (key == "PADDUP" and -1 or 1)))
            setFocus(list[nextIndex]); directional = true
            if focus then reveal(focus) end
            return true
        end
    end
    local dir = directions[key]
    if dir and #list > 0 then move(list,dir[1],dir[2]); return true end
    if key == (GAMEPAD_FACE_BOTTOM or "PAD1") then
        if not directional and not (context == "dungeon" and section == "sidebar") then hover(list) end
        if focus then
            local f = focus
            -- The ordinary OnClick path also performs the existing tooltip/link logic.
            if f.IsEnabled and not f:IsEnabled() then return true end
            if f.dcfWrapped then ns.OpenMapTakeOver(f)
            else f:GetScript("OnClick")(f,"LeftButton") end
            return true
        end
        if context == "dungeon" then return true end -- empty map clicks must not zoom the native map underneath
    elseif key == (GAMEPAD_FACE_RIGHT or "PAD2") then
        local _,chooser = ns.ControllerEntranceRoots()
        if visible(chooser) then ns.HideEntranceChooser()
        elseif ns.ViewShown() then ns.GoUp()
        elseif ns.JournalShown() then ns.HideJournal()
        else return false end -- Blizzard owns closing the world map and global Cancel.
        setFocus(nil); directional = false
        return true
    elseif key == (GAMEPAD_FACE_LEFT or "PAD3") and ns.ViewShown() then
        ns.ControllerToggleSide(); section = "map"; setFocus(nil); directional = false; return true
    end
    return false
end
ns.ControllerHandle = handle

function ns.SetupController()
    if driver or not WorldMapFrame then return end
    -- The watcher inherits map visibility; input is a separate child, disabled while idle.
    local watch = CreateFrame("Frame",nil,WorldMapFrame)
    driver = CreateFrame("Frame",nil,watch)
    driver:SetFrameStrata("FULLSCREEN_DIALOG")
    driver:SetPropagateKeyboardInput(true)
    driver:SetScript("OnShow",function(self)
        if not combat() then self:SetPropagateKeyboardInput(true) end
    end)
    driver:EnableGamePadButton(false)
    driver.ring = CreateFrame("Frame",nil,driver,"BackdropTemplate")
    driver.ring:SetBackdrop({edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    driver.ring:SetBackdropBorderColor(1,0.82,0,1)
    driver.ring:EnableMouse(false)
    driver.ring:Hide()
    -- our key legend: same look as the game's (glyph + gold label on a dark plate), see UI/PadLegend.lua
    driver.footer = ns.NewPadLegend and ns.NewPadLegend(driver) or CreateFrame("Frame",nil,driver)
    driver.footer:SetPoint("BOTTOM",WorldMapFrame,"BOTTOM",0,34)
    driver.footer:EnableMouse(false)
    driver.cursor = CreateFrame("Frame",nil,driver)
    driver.cursor:SetSize(30,30)
    driver.cursor:EnableMouse(false)
    driver.cursor.lines = {}
    for _,horizontal in ipairs({true,false}) do
        local line = driver.cursor:CreateTexture(nil,"OVERLAY")
        line:SetColorTexture(1,0.82,0,0.95)
        line:SetPoint("CENTER")
        line:SetSize(horizontal and 30 or 2,horizontal and 2 or 30)
        driver.cursor.lines[#driver.cursor.lines+1] = line
    end
    driver.cursor.shadow = driver.cursor:CreateTexture(nil,"OVERLAY")
    driver.cursor.shadow:SetPoint("CENTER",1,0)
    driver.cursor.shadow:SetSize(30,30)
    driver.cursor.shadow:SetAtlas("gamepad-reticletargeting-indicator-x1")
    driver.cursor.shadow:SetTexCoord(0.08,0.95,0.08,0.95)
    driver.cursor.shadow:SetVertexColor(0,0,0)
    driver.cursor.diamond = driver.cursor:CreateTexture(nil,"OVERLAY")
    driver.cursor.diamond:SetPoint("CENTER")
    driver.cursor.diamond:SetSize(30,30)
    driver.cursor.diamond:SetAtlas("gamepad-reticletargeting-indicator-x1")
    driver.cursor.diamond:SetTexCoord(0.08,0.95,0.08,0.95)
    driver.cursor:Hide()
    driver:SetScript("OnGamePadButtonDown",function(self,key)
        if combat() then self:Hide(); return end
        self:SetPropagateKeyboardInput(not handle(key))
    end)
    driver:SetScript("OnGamePadButtonUp",function(self)
        if not combat() then self:SetPropagateKeyboardInput(true) end
    end)
    driver:SetScript("OnHide",function() setFocus(nil); directional = false; context = nil; section = "map"; activeModal,modalReturn = nil,nil; driver.cursor:Hide() end)
    watch:RegisterEvent("PLAYER_REGEN_DISABLED")
    watch:SetScript("OnEvent",function() driver:Hide() end)
    -- Every frame while the map section is active (the throttled update below only decides whether it is): the game's own cursor moves every
    -- frame, so a crosshair that follows it at 20 Hz felt laggy.
    local PAN_BAND, PAN_SPEED = 0.14, 900 -- share of the map area that pans, view units per second at the very edge
    local function drawCursor(dt)
        if not cursorOn or section ~= "map" or context ~= "dungeon" then return end
        local x,y = center(SoftCursor)
        local area = ns.ControllerMapRoot()
        local sidebar = ns.ControllerSidebarRoot()
        if not (x and area and inside(area,x,y) and not (visible(sidebar) and inside(sidebar,x,y))) then driver.cursor:Hide(); return end
        local scale = UIParent:GetEffectiveScale()
        driver.cursor:ClearAllPoints()
        driver.cursor:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale,y/scale)
        local l,b,w,h = ns.ControllerMapRect()
        local horizontal,vertical = driver.cursor.lines[1],driver.cursor.lines[2]
        horizontal:ClearAllPoints(); vertical:ClearAllPoints()
        horizontal:SetPoint("LEFT",UIParent,"BOTTOMLEFT",l/scale,y/scale)
        horizontal:SetSize(w/scale,1)
        vertical:SetPoint("BOTTOM",UIParent,"BOTTOMLEFT",x/scale,b/scale)
        vertical:SetSize(1,h/scale)
        driver.cursor:Show()
        dt = math.min(dt,0.1)
        local tilt = ns.ControllerZoomTilt()
        if tilt ~= 0 then ns.ControllerZoom(math.exp(tilt * dt * 1.8),x,y) end
        -- zoomed in, the left stick only moves the cursor: pushing it into the edge band scrolls the map (the way the game's own map does)
        if ns.ControllerPan then
            local band = math.min(w,h) * PAN_BAND
            local ex = x < l + band and -(l + band - x) / band or (x > l + w - band and (x - (l + w - band)) / band or 0)
            local ey = y < b + band and (b + band - y) / band or (y > b + h - band and -(y - (b + h - band)) / band or 0)
            if ex ~= 0 or ey ~= 0 then
                ex,ey = math.max(-1,math.min(1,ex)),math.max(-1,math.min(1,ey))
                ns.ControllerPan(ex * PAN_SPEED * dt, ey * PAN_SPEED * dt)
            end
        end
    end
    watch:SetScript("OnUpdate",function(_,dt)
        drawCursor(dt)
        elapsed = elapsed + dt
        if elapsed < 0.05 then return end
        local step = math.min(elapsed, 0.1)
        elapsed = 0
        if not available() then
            cursorOn = false; driver.cursor:Hide(); driver:EnableGamePadButton(false); driver:Hide()
            if ns.ControllerEnabled() and visible(WorldMapFrame) and ownScreenShown() then notePadState() end
            return
        end
        local list = refreshTargets()
        if context ~= "dungeon" or section == "map" then hover(list) end
        local ownView = context ~= "world"
        if not ownView and not focus then driver:EnableGamePadButton(false); driver:Hide(); return end
        driver:Show()
        driver:EnableGamePadButton(true)
        -- (the crosshair, zoom and edge panning run every frame: see drawCursor)
        cursorOn = context == "dungeon" and section == "map" and not activeModal and visible(SoftCursor)
        if not cursorOn then driver.cursor:Hide() end
        -- Blizzard's own control guide sits along the bottom edge of the map: our hint goes just above it (only anchored to it, nothing of
        -- Blizzard's is moved), or at the old place when it is not shown.
        local footer = WorldMapFrame.worldMapFooter
        local legend = type(footer) == "table" and footer.inputLegend or nil
        local above = type(legend) == "table" and legend.IsShown and legend:IsShown() and legend or nil
        if driver.footerAbove ~= above then
            driver.footerAbove = above
            driver.footer:ClearAllPoints()
            if above then driver.footer:SetPoint("BOTTOM",above,"TOP",0,8)
            else driver.footer:SetPoint("BOTTOM",WorldMapFrame,"BOTTOM",0,34) end
        end
        if driver.footer.SetRows then
            local rows
            if context == "dungeon" then
                local maxed = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
                rows = { section == "map"
                    and { {keys={"LSTICK"},text="Crosshair"}, {keys={"RSTICK_UD"},text="Zoom"}, {keys={"DPAD_LEFT","DPAD_RIGHT"},text="Map / Sidebar"},
                          maxed and {keys={"DPAD_UP"},text="Small map"} or {keys={"DPAD_DOWN"},text="Full map"} }
                    or { {keys={"DPAD_UP","DPAD_DOWN"},text="Choose"}, {keys={"DPAD_LEFT","DPAD_RIGHT"},text="Map / Sidebar"} },
                    { {keys={"A"},text="Select"}, {keys={"B"},text="Back"}, {keys={"X"},text="Sidebar"} } }
            elseif ownView then
                rows = { { {keys={"DPAD"},text="Choose"}, {keys={"A"},text="Select"}, {keys={"B"},text="Back"} } }
            else
                rows = { { {keys={"A"},text="Open dungeon / Journal"} } }
            end
            driver.footer:SetRows(rows)
        end
    end)
end

-- Local Escape/Cancel handling; no insertion into UISpecialFrames.
function ns.ControllerDismiss(f)
    f:EnableKeyboard(true)
    if f.EnableGamePadButton then f:EnableGamePadButton(true) end
    f:SetPropagateKeyboardInput(true)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent",function(self) self:Hide() end)
    f:HookScript("OnShow",function(self)
        if not combat() then self:SetPropagateKeyboardInput(true) end
    end)
    local function key(self,k)
        if combat() then self:Hide(); return end
        local close = k == "ESCAPE" or k == (GAMEPAD_FACE_RIGHT or "PAD2")
        self:SetPropagateKeyboardInput(not close)
        if close then self:Hide() end
    end
    f:SetScript("OnKeyDown",key)
    f:SetScript("OnGamePadButtonDown",key)
end

-- Only when the option is on (default off: the map opens at the size the player has). Once per opening, never on refresh: a later minimize is retained.
function ns.OpenDungeonFullscreen()
    if not (DungeonMapDB and DungeonMapDB.openFullscreen) then return end
    -- With a controller the maximize runs the map's footer/binding refresh in our (tainted) execution: the taint marks showed the whole gamepad binding
    -- set and the map canvas fields turning tainted in one ShowInstance, and the radial/chat then got "blocked". Left to the player (the map's own button).
    if ns.ControllerEnabled() then return end
    if combat() or not WorldMapFrame or not WorldMapFrame.IsMaximized or WorldMapFrame:IsMaximized() then return end
    local border = WorldMapFrame.BorderFrame
    local sizes = type(border) == "table" and border.MaximizeMinimizeFrame
    if type(sizes) == "table" and type(sizes.Maximize) == "function" then
        (ns.Secure or pcall)(sizes.Maximize, sizes) -- same size control used by the map's maximize button
    end
end

-- Read mapped Camera stick, not a device-specific numeric axis; no native bindings changed.
function ns.ControllerZoomTilt()
    if not (C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.StickIndexToConfigName) then return 0 end
    local ok,state = pcall(C_GamePad.GetDeviceMappedState)
    if not ok or type(state) ~= "table" or type(state.sticks) ~= "table" or type(state.stickCount) ~= "number" then return 0 end
    for i=1,state.stickCount do
        if C_GamePad.StickIndexToConfigName(i-1) == "Camera" then
            local stick=state.sticks[i]
            local y=type(stick)=="table" and stick.y
            if issecretvalue and issecretvalue(y) then return 0 end
            if type(y)~="number" or y~=y or math.abs(y)<0.18 then return 0 end
            return math.max(-1,math.min(1,y))
        end
    end
    return 0
end
