-- Strict stand-in for the WoW client, enough to run ForeverBags under a plain Lua interpreter.
-- Same design as the other addons' mocks. What it models of Blizzard's side:
--
--  * the bag windows of Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua as far as the addon relies
--    on them: the combined window with its item buttons in `Items`, laid out the way
--    AnchorUtil.GridLayout does it (from the bottom right, 10 wide, every button anchored to the money
--    row), ContainerFrame6 for the reagent bag (bag 5) with its pooled item buttons, laid out 4 wide,
--    and the global UpdateContainerFrameAnchors() that every sizing / layout path ends in;
--  * taint: a field written onto one of Blizzard's frames, one of Blizzard's bag functions run by addon
--    code, an item button re-parented, a bag window shown / hidden or scripted by addon code - each is
--    recorded, and the test runner fails the scenario;
--  * secret values: getters on Blizzard's frames can be made to answer with a secret;
--  * combat: protected frames and binding changes are off limits.
--
-- Not loaded by the game (not in the .toc).
local Mock = {}

local REAL_PRINT = print
local ADDON = "ForeverBags"

Mock.SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local methods = {}
local newWidget

local function violation(text)
    Mock.taintViolations[#Mock.taintViolations + 1] = text
end

local function guard(self, what)
    if self.__blizzard and not Mock.blizzardCode then
        if Mock.state.inCombat and self.__protected then
            Mock.forbiddenCalls[#Mock.forbiddenCalls + 1] = what .. "() on protected " .. tostring(self.__name) .. " in combat"
        end
        Mock.touched[#Mock.touched + 1] = what .. " " .. tostring(self.__name)
    end
end

-- a getter on one of Blizzard's frames may answer with a secret value
local function getter(name, read)
    methods[name] = function(self, ...)
        if self.__blizzard and not Mock.blizzardCode then
            Mock.reads = Mock.reads + 1 -- the addon asked one of Blizzard's frames something
            if Mock.state.secretGetters[name] then
                return Mock.SECRET
            end
        end
        return read(self, ...)
    end
end

function methods.SetSize(self, width, height) guard(self, "SetSize"); self.__width, self.__height = width, height end
function methods.SetWidth(self, width) guard(self, "SetWidth"); self.__width = width end
function methods.SetHeight(self, height) guard(self, "SetHeight"); self.__height = height end
getter("GetWidth", function(self) return self.__width or 0 end)
getter("GetHeight", function(self) return self.__height or 0 end)
function methods.SetPoint(self, point, relativeTo, relativePoint, x, y)
    guard(self, "SetPoint")
    if type(relativeTo) ~= "table" then
        relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint
    end
    self.__points[#self.__points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
function methods.ClearAllPoints(self) guard(self, "ClearAllPoints"); self.__points = {} end
function methods.SetAllPoints(self, target) self.__allPoints = target or self.__parent end
getter("GetPoint", function(self, index)
    local point = self.__points[index or 1]
    if point then
        return point[1], point[2], point[3], point[4], point[5]
    end
end)
getter("GetNumPoints", function(self) return #self.__points end)
-- Drawing units. A "toplevel" frame flattens its render layers: it and everything in it is drawn as ONE
-- unit, and of two units that overlap, the one raised last is in front - whatever the strata or level of
-- the frames inside them. A unit is raised when its toplevel frame is shown, when a mouse button goes down
-- on anything in it, and by :Raise() on anything in it (ContainerFrame_GenerateFrame does that with every
-- bag window it opens - which is why the reagent window's unit is in front right after "Open All Bags").
local function unitOf(frame)
    while frame do
        if frame.__toplevel then
            return frame
        end
        frame = frame.__parent
    end
    return nil
end
Mock.unitOf = unitOf

local function raiseUnit(frame)
    local unit = unitOf(frame)
    if unit then
        Mock.raiseCount = Mock.raiseCount + 1
        unit.__raisedAt = Mock.raiseCount
    end
end

function methods.Show(self)
    if self.__bagWindow and not Mock.blizzardCode then
        violation("addon code showed Blizzard's " .. self.__name .. " (its OnShow would run tainted)")
    end
    if self.__toplevel and not self.__shown then
        raiseUnit(self)
    end
    self.__shown = true
end
function methods.Raise(self) guard(self, "Raise"); raiseUnit(self) end
getter("IsToplevel", function(self) return self.__toplevel and true or false end)
function methods.Hide(self)
    if self.__bagWindow and not Mock.blizzardCode then
        violation("addon code hid Blizzard's " .. self.__name .. " (its OnHide would run tainted)")
    end
    self.__shown = false
end
getter("IsShown", function(self) return self.__shown end)
getter("IsVisible", function(self)
    local frame = self
    while frame do
        if not frame.__shown then
            return false
        end
        frame = frame.__parent
    end
    return true
end)
function methods.SetParent(self, parent)
    if self.__itemButton and not Mock.blizzardCode then
        violation("addon code re-parented Blizzard's item button (its code asks the parent for bag window methods)")
    end
    guard(self, "SetParent")
    self.__parent = parent
end
getter("GetParent", function(self) return self.__parent end)
getter("GetName", function(self) return self.__name end)
function methods.SetID(self, id) self.__id = id end
getter("GetID", function(self) return self.__id or 0 end)
function methods.SetFrameStrata(self, strata) guard(self, "SetFrameStrata"); self.__strata = strata end
getter("GetFrameStrata", function(self) return self.__strata or (self.__parent and self.__parent:GetFrameStrata()) or "MEDIUM" end)
function methods.SetFrameLevel(self, level) self.__level = level end
getter("GetFrameLevel", function(self) return self.__level or 1 end)
getter("GetScale", function(self) return self.__scale or 1 end)
function methods.SetScale(self, scale) self.__scale = scale end
getter("GetRect", function(self)
    local rect = self.__rect or { 0, 0, self.__width or 0, self.__height or 0 }
    return rect[1], rect[2], rect[3], rect[4]
end)
getter("GetEffectiveScale", function(self) return self.__effectiveScale or 1 end)
getter("GetLeft", function() return 0 end)
getter("GetBottom", function() return 0 end)
getter("IsProtected", function(self) return self.__protected and true or false, self.__protected and true or false end)
function methods.SetScript(self, name, fn)
    if self.__blizzard and not Mock.blizzardCode then
        violation("addon code set a script on Blizzard's " .. tostring(self.__name))
    end
    self.__scripts[name] = fn
end
function methods.HookScript(self, name)
    if self.__blizzard and not Mock.blizzardCode then
        violation("addon code hooked a script on Blizzard's " .. tostring(self.__name))
    end
    self.__hooked = name
end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.RegisterEvent(self, event)
    if Mock.unknownEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"")
    end
    self.__events[event] = true
end
function methods.UnregisterEvent(self, event) self.__events[event] = nil end
function methods.CreateTexture(self) return newWidget("Texture", nil, self) end
function methods.CreateFontString(self) return newWidget("FontString", nil, self) end
function methods.SetText(self, text) self.__text = text end
function methods.GetText(self) return self.__text end
function methods.SetTexture(self, texture) self.__texture = texture end
function methods.SetColorTexture(self, r, g, b, a) self.__color = { r, g, b, a } end
function methods.SetVertexColor(self, r, g, b) self.__vertexColor = { r, g, b } end
function methods.SetTexCoord(self, ...) self.__texCoord = { ... } end
function methods.SetOwner(self, owner) self.__owner = owner end
for _, name in ipairs({ "SetHighlightTexture", "AddLine", "EnableMouse", "SetJustifyH", "SetTextColor", "RegisterForClicks" }) do
    methods[name] = function() end
end

local widgetMeta = { __index = methods }

function newWidget(kind, name, parent)
    return setmetatable({
        __kind = kind, __name = name, __parent = parent, __scripts = {}, __events = {}, __points = {}, __shown = true,
    }, widgetMeta)
end

-- One of BLIZZARD's frames: a field written onto it by addon code is how taint spreads.
local function newBlizzardFrame(kind, name, parent)
    local frame = newWidget(kind, name, parent)
    frame.__blizzard = true
    return setmetatable(frame, {
        __index = methods,
        __newindex = function(self, key, value)
            if not Mock.blizzardCode and not (type(key) == "string" and key:sub(1, 2) == "__") then
                violation("wrote field '" .. tostring(key) .. "' on Blizzard's " .. tostring(name))
            end
            rawset(self, key, value)
        end,
    })
end

function Mock.runScript(widget, name, ...)
    local script = widget.__scripts[name]
    if script then
        script(widget, ...)
    end
end

-- Runs fn as Blizzard's own (secure) code.
function Mock.asBlizzard(fn, ...)
    local before = Mock.blizzardCode
    Mock.blizzardCode = true
    local ok, err = pcall(fn, ...)
    Mock.blizzardCode = before
    if not ok then
        error(err, 0)
    end
end

-- One of Blizzard's bag FUNCTIONS: run by addon code it writes tainted values into the bag frames.
local function blizzardFunction(name, fn)
    return function(...)
        if not Mock.blizzardCode then
            violation("addon code ran Blizzard's " .. name .. " (taints the bag code)")
        end
        return fn(...)
    end
end

------------------------------------------------------------------------
-- Time and events
------------------------------------------------------------------------
function Mock.advance(seconds)
    local target = Mock.now + seconds
    while true do
        local nextIndex, nextTimer
        for index, timer in ipairs(Mock.timers) do
            if timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then
                nextIndex, nextTimer = index, timer
            end
        end
        if not nextTimer then
            break
        end
        Mock.now = math.max(Mock.now, nextTimer.at)
        if nextTimer.every then
            nextTimer.at = nextTimer.at + nextTimer.every
        else
            table.remove(Mock.timers, nextIndex)
        end
        nextTimer.fn()
    end
    Mock.now = target
end

function Mock.fire(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

function Mock.setCombat(inCombat)
    Mock.state.inCombat = inCombat
    Mock.fire(inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

------------------------------------------------------------------------
-- Install
------------------------------------------------------------------------
local function readToc(root)
    local files = {}
    for line in io.lines(root .. "/" .. ADDON .. ".toc") do
        line = line:gsub("\r", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

function Mock.install(options)
    options = options or {}
    local G = _G
    for _, name in ipairs(Mock.globalNames or {}) do
        G[name] = nil
    end
    Mock.globalNames = {}
    local function global(name, value)
        G[name] = value
        Mock.globalNames[#Mock.globalNames + 1] = name
    end

    Mock.now, Mock.timers, Mock.frames, Mock.raiseCount, Mock.reads = 1000, {}, {}, 0, 0
    Mock.printed, Mock.errors, Mock.forbiddenCalls, Mock.taintViolations, Mock.touched = {}, {}, {}, {}, {}
    Mock.unknownEvents = options.unknownEvents or {}
    Mock.blizzardCode = false
    local state = {
        inCombat = false,
        cvars = { combinedBags = options.separateBags and "0" or "1" },
        bindings = options.bindings or { B = "TOGGLEBACKPACK", ["SHIFT-B"] = "OPENALLBAGS" },
        overrides = {},          -- [owner] = { [key] = command }
        secretGetters = {},      -- [getter name] = true: Blizzard's frames answer it with a secret
        reagentSlots = options.reagentSlots == nil and 12 or options.reagentSlots,
        bagSlots = options.bagSlots or 56,
        playerName = options.playerName or "Purrdee",
    }
    Mock.state = state

    global("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
    end)
    global("issecretvalue", function(value) return value == Mock.SECRET end)
    global("geterrorhandler", function()
        return function(err)
            Mock.errors[#Mock.errors + 1] = tostring(err) .. debug.traceback("", 2):sub(1, 1200)
        end
    end)
    global("GetTime", function() return Mock.now end)
    global("date", function() return "2026-09-20 12:00:00" end)
    global("InCombatLockdown", function() return state.inCombat end)
    global("GetBuildInfo", function() return "1.60.1", "69913", "Sep 17 2026", 16001 end)
    global("UnitName", function() return state.playerName end)
    global("UnitFullName", function() return state.playerName, "TestRealm" end)
    global("GetRealmName", function() return "Test Realm" end)
    global("SlashCmdList", {})
    global("C_AddOns", { GetAddOnMetadata = function() return options.version or "0.1.0-test" end })
    global("C_CVar", { GetCVar = function(name) return state.cvars[name] end })
    global("C_Container", { GetContainerNumSlots = function(bag)
        if bag == 5 then
            return state.reagentSlots
        end
        return bag == 0 and 16 or 10
    end })
    global("C_Timer", {
        After = function(delay, fn) Mock.timers[#Mock.timers + 1] = { at = Mock.now + delay, fn = fn } end,
        NewTicker = function(interval, fn)
            local ticker = { at = Mock.now + interval, fn = fn, every = interval }
            Mock.timers[#Mock.timers + 1] = ticker
            return ticker
        end,
    })

    global("CreateFrame", function(kind, name, parent)
        local frame = newWidget(kind, name, parent)
        Mock.frames[#Mock.frames + 1] = frame
        if name then
            global(name, frame)
        end
        return frame
    end)
    global("UIParent", newBlizzardFrame("Frame", "UIParent"))
    G.UIParent.__width, G.UIParent.__height = 1366, 768
    global("GameTooltip", newWidget("GameTooltip", "GameTooltip"))

    -- Bindings ------------------------------------------------------------
    global("GetBindingKey", function(command)
        local keys = {}
        for key, bound in pairs(state.bindings) do
            if bound == command then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        return (table.unpack or unpack)(keys)
    end)
    local function bindingGuard(what)
        if state.inCombat then
            Mock.forbiddenCalls[#Mock.forbiddenCalls + 1] = what .. "() in combat"
        end
    end
    global("SetOverrideBinding", function(owner, _, key, command)
        bindingGuard("SetOverrideBinding")
        state.overrides[owner] = state.overrides[owner] or {}
        state.overrides[owner][key] = command
        Mock.fire("UPDATE_BINDINGS") -- (the real client does: a careless handler loops)
    end)
    global("ClearOverrideBindings", function(owner)
        bindingGuard("ClearOverrideBindings")
        local had = state.overrides[owner] and next(state.overrides[owner]) ~= nil
        state.overrides[owner] = {}
        if had then
            Mock.fire("UPDATE_BINDINGS")
        end
    end)
    function Mock.commandFor(key)
        for _, map in pairs(state.overrides) do
            if map[key] then
                return map[key]
            end
        end
        return state.bindings[key]
    end

    -- Blizzard's bag windows ---------------------------------------------------
    if not options.noBagWindows then
        local container = newBlizzardFrame("Frame", "ContainerFrameContainer", G.UIParent)
        global("ContainerFrameContainer", container)
        local combined = newBlizzardFrame("Frame", "ContainerFrameCombinedBags", G.UIParent)
        local reagent = newBlizzardFrame("Frame", "ContainerFrame6", container)
        container.__toplevel, combined.__toplevel = true, true -- (ContainerFrame.xml: toplevel="true" on both)
        combined.__bagWindow, reagent.__bagWindow = true, true
        combined.__shown, reagent.__shown = false, false
        combined.__protected, reagent.__protected = options.protectedBags or false, options.protectedBags or false
        container.__protected = options.protectedContainer or false
        rawset(reagent, "canUseForReagentBag", true)
        rawset(reagent, "Items", {})
        rawset(combined, "Items", {})
        rawset(combined, "MoneyFrame", newBlizzardFrame("Frame", "ContainerFrameCombinedBagsMoneyFrame", combined))
        local combinedPool = {}
        rawset(combined, "UpdateItemSlots", blizzardFunction("UpdateItemSlots", function(self)
            local items = {}
            for index = 1, state.bagSlots do
                local button = combinedPool[index]
                if not button then
                    button = newBlizzardFrame("ItemButton", "ContainerFrameCombinedBagsItem" .. index, self)
                    button.__itemButton = true
                    combinedPool[index] = button
                end
                button:SetID(index)
                button:SetSize(37, 37)
                button:Show()
                items[index] = button
            end
            for index = state.bagSlots + 1, #combinedPool do
                combinedPool[index]:Hide()
                combinedPool[index]:ClearAllPoints()
            end
            self.Items = items
        end))
        -- AnchorUtil.GridLayout, BottomRightToTopLeft, stride 10, from the money row's TOPRIGHT + (0, 4).
        -- (gamepad mode lays out from the window's TOPLEFT instead.)
        rawset(combined, "UpdateItemLayout", blizzardFunction("UpdateItemLayout", function(self)
            for index, button in ipairs(self.Items) do
                local column, row = (index - 1) % 10, math.floor((index - 1) / 10)
                button:ClearAllPoints()
                if options.gamepadLayout then
                    button:SetPoint("TOPLEFT", self, "TOPLEFT", 10 + column * 42, -65 - row * 42)
                else
                    button:SetPoint("BOTTOMRIGHT", self.MoneyFrame, "TOPRIGHT", -column * 42, 4 + row * 42)
                end
            end
        end))
        global("ContainerFrameCombinedBags", combined)
        global("ContainerFrame6", reagent)

        local function rowsHeight(count, columns)
            local rows = math.ceil(count / columns)
            return rows * 37 + (rows - 1) * 5
        end
        -- ContainerFrameMixin:CalculateHeight for the combined window: items + 75 + (money row 13 + 12)
        local function combinedHeight()
            return rowsHeight(state.bagSlots, 10) + 75 + 13 + 12
        end
        Mock.combinedHeight = combinedHeight
        if not options.noSizeMethod then
            rawset(combined, "UpdateFrameSize", blizzardFunction("UpdateFrameSize", function(self)
                self:SetSize(430, combinedHeight())
            end))
        end
        rawset(reagent, "UpdateFrameSize", blizzardFunction("UpdateFrameSize", function(self)
            self:SetSize(178, rowsHeight(math.max(1, state.reagentSlots), 4) + 57)
        end))
        local pool = {}
        rawset(reagent, "UpdateItemSlots", blizzardFunction("UpdateItemSlots", function(self)
            for _, button in ipairs(self.Items) do -- the pool's reset: hidden, anchors cleared
                button:Hide()
                button:ClearAllPoints()
            end
            local items = {}
            for index = 1, state.reagentSlots do
                local button = pool[index]
                if not button then
                    button = newBlizzardFrame("ItemButton", "ContainerFrame6Item" .. index, self)
                    button.__itemButton = true
                    button.__protected = options.protectedBags or false
                    pool[index] = button
                end
                button:SetID(state.reagentSlots - index + 1) -- Blizzard acquires them highest slot first
                button:SetSize(37, 37)
                button:Show()
                items[index] = button
            end
            self.Items = items
        end))
        rawset(reagent, "UpdateItemLayout", blizzardFunction("UpdateItemLayout", function(self)
            local sorted = {}
            for _, button in ipairs(self.Items) do
                sorted[#sorted + 1] = button
            end
            table.sort(sorted, function(a, b) return a:GetID() > b:GetID() end)
            for index, button in ipairs(sorted) do
                local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
                button:ClearAllPoints()
                button:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -7 - column * 42, 9 + row * 42)
            end
        end))

        global("UpdateContainerFrameAnchors", blizzardFunction("UpdateContainerFrameAnchors", function()
            local previous
            for _, window in ipairs({ combined, reagent }) do
                if window.__shown then
                    window:ClearAllPoints()
                    if not previous then
                        window:SetPoint("BOTTOMRIGHT", window.__parent, "BOTTOMRIGHT", -10, 85)
                    else
                        window:SetPoint("BOTTOMRIGHT", previous, "BOTTOMLEFT", -11, 0) -- a new column next to the combined bag
                    end
                    previous = window
                end
            end
        end))

        local function generate(window, bag)
            window:SetID(bag)
            if window.UpdateItemSlots then
                window:UpdateItemSlots()
            end
            window:Show()
            window:Raise()
            if window.UpdateFrameSize then
                window:UpdateFrameSize() -- (looked up on the frame: a hooksecurefunc wrapper is what runs)
            else
                window:SetSize(430, combinedHeight())
            end
            if window.UpdateItemLayout then
                window:UpdateItemLayout()
            end
            G.UpdateContainerFrameAnchors()
        end
        local function close(window)
            if window.__shown then
                window:Hide()
                G.UpdateContainerFrameAnchors() -- ContainerFrame_OnHide
            end
        end
        function Mock.openBackpack() -- ToggleBackpack_Combined: the combined window only
            Mock.asBlizzard(function() generate(combined, 0) end)
        end
        function Mock.openAllBags() -- OpenAllBagsInternal: the combined window, then every other bag - the reagent bag
            Mock.asBlizzard(function()
                if state.cvars.combinedBags ~= "1" then
                    return
                end
                if not combined.__shown then
                    generate(combined, 0)
                end
                if state.reagentSlots > 0 and not reagent.__shown then
                    generate(reagent, 5)
                end
            end)
        end
        function Mock.closeAllBags()
            Mock.asBlizzard(function() close(combined); close(reagent) end)
        end
        function Mock.closeBackpackOnly() -- a click on the backpack button: ToggleBackpack_Combined hides only that window
            Mock.asBlizzard(function() close(combined) end)
        end
        function Mock.resizeBags(slots) -- a bag was swapped while the windows are open: Blizzard sizes and lays out again
            state.bagSlots = slots
            Mock.asBlizzard(function() generate(combined, 0) end)
        end
        -- The bag bar's reagent bag button: a click toggles that bag's window (ToggleBag(5)) - unless a frame
        -- of the addon's lies over it and takes the click.
        -- The bag bar. Stock: a thing of its own on UIParent. With ForeverActionBars' docking (the default
        -- here - it is how the author plays) it is a child of the combined bag window, and so part of ITS unit.
        local bagsBar = newBlizzardFrame("Frame", "BagsBar", options.stockBagBar and G.UIParent or combined)
        global("BagsBar", bagsBar)
        local slotButton = newBlizzardFrame("ItemButton", "CharacterReagentBag0Slot", bagsBar)
        global("CharacterReagentBag0Slot", slotButton)
        local keyRing = newBlizzardFrame("ItemButton", "KeyRingButton", bagsBar)
        global("KeyRingButton", keyRing)
        slotButton.__level, keyRing.__level = 3, 3 -- (measured in game)
        -- What has the mouse: the frame last pressed - or, while the mouse rests on a reagent slot
        -- (Mock.hoverReagentSlot), that slot if the player can see it, else the bag window in front of it.
        local inFrontOf
        global("GetMouseFoci", function()
            local hovered = Mock.hovered
            if hovered then
                local reachable = hovered.__shown and reagent.__shown and inFrontOf(hovered, combined)
                return { reachable and hovered or combined }
            end
            return { Mock.mouseFocus }
        end)
        global("GetCursorPosition", function()
            return Mock.cursor[1], Mock.cursor[2]
        end)
        Mock.cursor, Mock.hovered = { -100, -100 }, nil -- (off every frame's rect until the mouse rests on a slot)
        function Mock.hoverReagentSlot(slot) -- nil: the mouse leaves
            Mock.hovered = nil
            Mock.cursor = { -100, -100 }
            for _, button in ipairs(reagent.Items) do
                rawset(button, "__rect", nil)
                if slot and button:GetID() == slot then
                    -- a 37 px button at (1571, 278) of its own scale 0.7111 (as measured in game): the cursor is in screen pixels
                    rawset(button, "__rect", { 1571, 278, 37, 37 })
                    rawset(button, "__effectiveScale", 0.7111)
                    Mock.cursor = { (1571 + 18) * 0.7111, (278 + 18) * 0.7111 }
                    Mock.hovered = button
                end
            end
        end
        function Mock.raiseBagWindowBehindOurBack() -- Blizzard's code (or another addon) raises the combined window: no press, no layout
            Mock.asBlizzard(function() combined:Raise() end)
        end
        function Mock.foldBagBar(folded) -- the bag bar's expand toggle: the bag slot buttons go away
            Mock.asBlizzard(function()
                if folded then slotButton:Hide() else slotButton:Show() end
            end)
        end

        -- Where a frame is drawn: inside a unit it is the UNIT's strata and level that count (flattened).
        local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
        function inFrontOf(a, b)
            local unitA, unitB = unitOf(a), unitOf(b)
            -- in one and the same unit (or both in none): their own strata and level. Otherwise it is
            -- where the UNIT is drawn that counts.
            local drawnA, drawnB = a, b
            if unitA ~= unitB then
                drawnA, drawnB = unitA or a, unitB or b
            end
            local wasBlizzard = Mock.blizzardCode
            Mock.blizzardCode = true -- (the engine's own look at the frames: never a secret)
            local strataA, strataB = STRATA[drawnA:GetFrameStrata()], STRATA[drawnB:GetFrameStrata()]
            local levelA, levelB = drawnA:GetFrameLevel(), drawnB:GetFrameLevel()
            Mock.blizzardCode = wasBlizzard
            if strataA ~= strataB then
                return strataA > strataB
            elseif unitA and unitB and unitA ~= unitB then
                return (unitA.__raisedAt or 0) > (unitB.__raisedAt or 0)
            end
            return levelA > levelB
        end

        -- The reagent slots the player can SEE (and reach with the mouse): visible - and, standing inside the
        -- combined bag window, only while their own unit is in front of that window's.
        function Mock.reagentSlotsSeen()
            local seen = 0
            for _, button in ipairs(reagent.Items) do
                local visible = button.__shown and reagent.__shown
                local relativeTo = button.__points[1] and button.__points[1][2]
                local insideBagWindow = relativeTo ~= nil and unitOf(relativeTo) == combined
                if visible and (not insideBagWindow or (combined.__shown and inFrontOf(button, combined))) then
                    seen = seen + 1
                end
            end
            return seen
        end

        -- A mouse button goes down on `frame`: its unit is raised, GLOBAL_MOUSE_DOWN fires - in which order
        -- is the client's secret, so scenarios run both ways (options.eventBeforeRaise).
        local function press(frame)
            Mock.mouseFocus = frame
            if options.eventBeforeRaise then
                Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
                raiseUnit(frame)
            else
                raiseUnit(frame)
                Mock.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
            end
        end
        local function release()
            Mock.fire("GLOBAL_MOUSE_UP", "LeftButton")
        end
        function Mock.clickKeyRing() -- showKeyring = 0: ToggleBag(KEYRING_CONTAINER) returns at once - only the press happens
            press(keyRing); release()
        end
        function Mock.clickInBagWindow(index) -- a press on one of the combined window's own item buttons
            press(combined.Items[index or 1]); release()
        end
        function Mock.holdInBagWindow(index) -- the button stays down: an item is being dragged
            press(combined.Items[index or 1])
        end
        Mock.releaseMouse = release
        function Mock.clickReagentSlot(index)
            press(reagent.Items[index or 1]); release()
        end
        function Mock.clickReagentBagButton()
            for _, frame in ipairs(Mock.frames) do
                if frame.__allPoints == slotButton and frame:IsVisible() and frame.__scripts.OnClick and inFrontOf(frame, slotButton) then
                    press(frame); release()
                    frame.__scripts.OnClick(frame, "LeftButton")
                    return "the addon's guard took the click"
                end
            end
            press(slotButton); release()
            Mock.asBlizzard(function()
                if reagent.__shown then
                    close(reagent)
                else
                    generate(reagent, 5)
                end
            end)
            return "Blizzard's button toggled the reagent bag"
        end

        function Mock.pressKey(key)
            local command = Mock.commandFor(key)
            if command == "OPENALLBAGS" then
                if combined.__shown and (reagent.__shown or state.reagentSlots == 0) then
                    Mock.closeAllBags()
                else
                    Mock.closeAllBags()
                    Mock.openAllBags()
                end
            elseif command == "TOGGLEBACKPACK" then
                if combined.__shown then
                    Mock.closeBackpackOnly()
                else
                    Mock.openBackpack()
                end
            end
            return command
        end
    end

    -- The sanctioned way to run addon code after a Blizzard function: the hook runs as addon code, the
    -- function stays Blizzard's. (Writes its wrapper onto the frame without that counting as addon data.)
    global("hooksecurefunc", function(target, name, hook)
        local function wrap(original)
            return function(...)
                local results = { original(...) }
                local before = Mock.blizzardCode
                Mock.blizzardCode = false
                local ok, err = pcall(hook, ...)
                Mock.blizzardCode = before
                if not ok then
                    Mock.errors[#Mock.errors + 1] = "in a secure hook: " .. tostring(err)
                end
                return (table.unpack or unpack)(results)
            end
        end
        if type(target) == "string" then
            hook, name = name, target
            assert(type(G[name]) == "function", "hooksecurefunc: no global function " .. tostring(name))
            G[name] = wrap(G[name])
        else
            assert(type(target[name]) == "function", "hooksecurefunc: no method " .. tostring(name))
            rawset(target, name, wrap(target[name]))
        end
    end)

    -- Saved variables, as the bridge addon leaves them
    G.ForeverBagsDB, G.ForeverBags_SavedStateBridge = options.db, options.bridge
    Mock.globalNames[#Mock.globalNames + 1] = "ForeverBagsDB"
    Mock.globalNames[#Mock.globalNames + 1] = "ForeverBags_SavedStateBridge"

    local root = options.root or "."
    local ns = {}
    for _, file in ipairs(readToc(root)) do
        local chunk = assert(loadfile(root .. "/" .. file))
        chunk(ADDON, ns)
    end
    for _, name in ipairs({ "SLASH_FOREVERBAGS1", "SLASH_FOREVERBAGS2", "SLASH_FOREVERBAGS3" }) do
        Mock.globalNames[#Mock.globalNames + 1] = name
    end
    Mock.ns = ns
    if options.login ~= false then
        Mock.login()
    end
    return ns, state
end

function Mock.login()
    Mock.fire("ADDON_LOADED", ADDON)
    Mock.fire("PLAYER_LOGIN")
    Mock.fire("PLAYER_ENTERING_WORLD", true, false)
end

Mock.realPrint = REAL_PRINT

return Mock
