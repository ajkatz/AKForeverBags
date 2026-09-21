-- The reagent bag's slots, in the combined bag window's own grid.
--
-- Blizzard's combined view only takes the backpack and bags 1-4 (ContainerFrame_IsGenericHeldBag); the
-- reagent bag - bag 5 - always gets a window of its own, ContainerFrame6, opened next to it by "Open All
-- Bags". Here that window is pushed off the screen and its ITEM BUTTONS are re-anchored so that they
-- continue the combined window's grid: Blizzard fills it from the bottom right (AnchorUtil.GridLayout,
-- 10 wide, every button anchored to the money row), which leaves the top row's left end empty - the
-- reagent slots take those cells, then rows of their own on top, and the window grows by those rows.
-- Behind every reagent slot sits a slot background of OURS in another colour.
--
-- The buttons stay Blizzard's: children of its reagent window, filled, updated, searched, sorted and
-- clicked by its own (secure) code. We only say where they stand - and nothing runs unless something
-- happened: every path in Blizzard's ContainerFrame.lua that sizes a bag window or lays out its buttons
-- ends in the global UpdateContainerFrameAnchors(); one post-hook there re-applies the arrangement in the
-- same frame. No timers, no polling.
--
-- NEVER done (see Core.lua): calling OpenBag / ToggleAllBags / frame:Update, re-parenting a button (its
-- code asks self:GetParent() for bag window methods), showing or hiding a bag window, writing any field,
-- covering one of Blizzard's buttons. The reagent window has to be OPEN for its buttons to exist and the
-- backpack key alone only opens the combined window - so that key gets an override binding to Blizzard's
-- own "Open All Bags": the key press runs ToggleAllBags() securely, not us.
local _, ns = ...

local Reagents = {}
ns.Reagents = Reagents

local REAGENT_BAG = 5                     -- ContainerFrame_IsReagentBag(id): id == 5
local REAGENT_WINDOW = "ContainerFrame6"  -- the only one made from ContainerFrameReagentBagTemplate
local COLUMNS, SLOT, SPACING = 10, 37, 5  -- the combined window's grid: GetColumns(), template size, ITEM_SPACING_X/Y
local PITCH = SLOT + SPACING
local RIM = 2                             -- our slot background reaches this far around the button
-- The reagent slots' colour. art: multiplied into Blizzard's grey slot art; wash: laid over it; rim: around it.
local COLOR = { art = { 0.55, 1.00, 0.72 }, wash = { 0.10, 0.85, 0.45, 0.16 }, rim = { 0.22, 0.80, 0.52, 0.70 } }
local SLOT_ART = { file = "Interface\\ContainerFrame\\UI-Bag-Components", 0.64453125, 0.7890625, 0.42578125, 0.498046875 }

Reagents.state = "not applied yet"
Reagents.moved = 0   -- reagent slots standing in the bag window right now
Reagents.raises = 0  -- how often the reagent window was brought back in front (for /fbags diag)
Reagents.keys = ""   -- the backpack keys pointed at Open All Bags right now
Reagents.work = { layoutPasses = 0, layoutMs = 0, slowestLayoutMs = 0, raisesOnClicks = 0 } -- the gauge of /fbags diag

local baseHeight, appliedHeight -- the combined window's height as Blizzard set it / as we set it
local sizeHooked, anchorsHooked = false, false
local pending, keysPending = false, false
local backdrop                  -- our frame behind the reagent slots, with one background per slot

local function setState(state)
    if state ~= Reagents.state then
        Reagents.state = state
        ns:Log("reagents", state)
    end
end

local function usingCombinedBags()
    local setting = ns.Readable((C_CVar and C_CVar.GetCVar) or GetCVar, "combinedBags")
    return setting ~= nil and setting[1] == "1"
end

local function isFrame(object)
    return type(object) == "table" and type(object.SetPoint) == "function" and type(object.GetPoint) == "function"
end

-- true / false, or nil when the client would not say
local function shown(frame)
    local answer = ns.Readable(frame.IsShown, frame)
    if answer == nil then
        return nil
    end
    return answer[1] == true
end

local function blockedByCombat(...)
    if not InCombatLockdown() then
        return false
    end
    for i = 1, select("#", ...) do
        local frame = (select(i, ...))
        local protected = ns.Readable(frame.IsProtected, frame)
        if not protected or protected[1] ~= false then
            return true -- protected (or unreadable): not ours to move in a fight
        end
    end
    return false
end

local function anchor(frame, point, relativeTo, relativePoint, x, y)
    local now = ns.Readable(frame.GetPoint, frame, 1)
    if now and now[1] == point and now[2] == relativeTo and now[3] == relativePoint
        and math.abs((now[4] or 0) - x) < 0.01 and math.abs((now[5] or 0) - y) < 0.01 then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    return true
end

------------------------------------------------------------------------
-- In front of the bag window. Blizzard's bag windows live in TWO "toplevel" frames: the combined window,
-- and ContainerFrameContainer, the full-screen parent of every separate bag window (the reagent window
-- among them). A toplevel frame flattens its render layers: all it holds is drawn as ONE unit, and which
-- of two units is in front is decided by which was raised last - not by the strata or level of anything
-- inside them. A mouse button going down anywhere in the combined window's unit raises it over the reagent
-- slots standing in its grid: their items vanish, the mouse no longer reaches them, and every getter still
-- says "shown". (README: "In front of the bag window" has the story and the proof.)
-- The way back is the call Blizzard's own code makes when a bag window opens (ContainerFrame_GenerateFrame:
-- frame:Raise()). Widget methods on unprotected frames: none of Blizzard's Lua runs, no field is written.
------------------------------------------------------------------------
local function unitOf(window)
    local frame = window
    for _ = 1, 8 do
        local parent = ns.Readable(frame.GetParent, frame)
        if not parent or not isFrame(parent[1]) then
            return nil
        end
        frame = parent[1]
        local toplevel = ns.Readable(frame.IsToplevel, frame)
        if toplevel and toplevel[1] == true then
            return frame
        end
    end
    return nil
end

local function bringForward(reagent) -- (from Apply only: the reagent window is ours to touch right now)
    local unit = unitOf(reagent)
    if unit and not blockedByCombat(unit) then
        unit:Raise()
    end
    reagent:Raise()
    Reagents.raises = Reagents.raises + 1
end

-- The frames that have the mouse, as a list - or nil when the client would not say.
local function mouseFoci()
    local foci = GetMouseFoci and ns.Readable(GetMouseFoci) or (GetMouseFocus and ns.Readable(GetMouseFocus))
    if not foci then
        return nil
    end
    local list = foci[1]
    if type(list) == "table" and type(list.GetParent) ~= "function" then
        return list -- GetMouseFoci: a list of frames
    end
    return { list } -- GetMouseFocus: one frame (or none)
end

-- Is this frame the combined bag window, or something in it? A frame that would not say counts as yes:
-- better one raise too many than slots out of sight.
local function insideWindow(frame, combined)
    for _ = 1, 12 do
        if ns.IsSecret(frame) then
            return true
        elseif frame == combined then
            return true
        elseif type(frame) ~= "table" or type(frame.GetParent) ~= "function" then
            return false
        end
        local parent = ns.Readable(frame.GetParent, frame)
        if not parent then
            return true
        end
        frame = parent[1]
    end
    return false
end

-- Blizzard's list of the reagent window's item buttons, highest slot first (the order in which Blizzard
-- fills a grid from the bottom right, so that slot 1 ends up top left) - or nil when anything is unreadable.
local function collectButtons(reagent)
    local items = reagent.Items -- (read only)
    if type(items) ~= "table" then
        return nil
    end
    local list = {}
    for _, button in ipairs(items) do
        if not isFrame(button) or type(button.GetID) ~= "function" then
            return nil
        end
        local slot = ns.Readable(button.GetID, button)
        if not slot or type(slot[1]) ~= "number" then
            return nil
        end
        list[#list + 1] = { button = button, slot = slot[1] }
    end
    table.sort(list, function(a, b) return a.slot > b.slot end)
    return list
end

------------------------------------------------------------------------
-- The combined window's grid, as Blizzard has laid it out - read from the buttons themselves.
-- Every button must be anchored BOTTOMRIGHT -> one and the same frame's TOPRIGHT (the money row), a whole
-- number of cells from the first one. Anything else (gamepad mode lays out from the top left, a future
-- build may do something new, an unreadable anchor): nil = hands off.
------------------------------------------------------------------------
local function readGrid(combined)
    local items = combined.Items -- (read only)
    if type(items) ~= "table" then
        return nil
    end
    local anchors = {}
    for _, button in ipairs(items) do
        if not isFrame(button) then
            return nil
        end
        local at = ns.Readable(button.GetPoint, button, 1)
        if not at then
            return nil
        end
        if at[1] ~= nil then
            if at[1] ~= "BOTTOMRIGHT" or at[3] ~= "TOPRIGHT" or not isFrame(at[2])
                or type(at[4]) ~= "number" or type(at[5]) ~= "number" then
                return nil
            end
            anchors[#anchors + 1] = at
        end
    end
    if #anchors == 0 then
        return nil
    end
    local origin, x0, y0 = anchors[1][2], -math.huge, math.huge
    for _, at in ipairs(anchors) do
        if at[2] ~= origin then
            return nil
        end
        x0, y0 = math.max(x0, at[4]), math.min(y0, at[5])
    end
    local last = 0 -- the highest cell number Blizzard uses; cells count from 1 at the bottom right, leftwards, then up
    for _, at in ipairs(anchors) do
        local column, row = (x0 - at[4]) / PITCH, (at[5] - y0) / PITCH
        local wholeColumn, wholeRow = math.floor(column + 0.5), math.floor(row + 0.5)
        if math.abs(column - wholeColumn) > 0.02 or math.abs(row - wholeRow) > 0.02 or wholeColumn >= COLUMNS then
            return nil
        end
        last = math.max(last, wholeRow * COLUMNS + wholeColumn + 1)
    end
    return { origin = origin, x0 = x0, y0 = y0, last = last, rows = math.floor((last - 1) / COLUMNS) + 1 }
end

local function cellOffset(grid, cell)
    local column, row = (cell - 1) % COLUMNS, math.floor((cell - 1) / COLUMNS)
    return grid.x0 - column * PITCH, grid.y0 + row * PITCH
end

------------------------------------------------------------------------
-- Slot backgrounds: OUR textures on OUR frame (a child of the combined window: comes, goes and scales with
-- it), one behind every reagent slot. Nothing is created on Blizzard's buttons.
------------------------------------------------------------------------
local function ensureBackdrop(combined)
    if not backdrop then
        backdrop = CreateFrame("Frame", "ForeverBagsReagentSlots", combined)
        backdrop.slots = {}
    end
    if backdrop:GetParent() ~= combined then
        backdrop:SetParent(combined)
    end
    backdrop:SetAllPoints(combined)
    return backdrop
end

local function slotBackground(frame, index)
    local slot = frame.slots[index]
    if not slot then
        slot = {}
        slot.rim = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        slot.rim:SetColorTexture(COLOR.rim[1], COLOR.rim[2], COLOR.rim[3], COLOR.rim[4])
        slot.rim:SetSize(SLOT + 2 * RIM, SLOT + 2 * RIM)
        slot.art = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        slot.art:SetTexture(SLOT_ART.file)
        slot.art:SetTexCoord(SLOT_ART[1], SLOT_ART[2], SLOT_ART[3], SLOT_ART[4])
        slot.art:SetVertexColor(COLOR.art[1], COLOR.art[2], COLOR.art[3])
        slot.art:SetSize(SLOT, SLOT)
        slot.wash = frame:CreateTexture(nil, "BORDER")
        slot.wash:SetColorTexture(COLOR.wash[1], COLOR.wash[2], COLOR.wash[3], COLOR.wash[4])
        slot.wash:SetSize(SLOT, SLOT)
        frame.slots[index] = slot
    end
    return slot
end

local function showBackgrounds(combined, grid, count)
    local frame = ensureBackdrop(combined)
    for index = 1, math.max(count, #frame.slots) do
        local slot = index <= count and slotBackground(frame, index) or frame.slots[index]
        if index <= count then
            local x, y = cellOffset(grid, grid.last + index)
            for _, texture in pairs(slot) do
                texture:ClearAllPoints()
                texture:Show()
            end
            slot.rim:SetPoint("BOTTOMRIGHT", grid.origin, "TOPRIGHT", x + RIM, y - RIM)
            slot.art:SetPoint("BOTTOMRIGHT", grid.origin, "TOPRIGHT", x, y)
            slot.wash:SetPoint("BOTTOMRIGHT", grid.origin, "TOPRIGHT", x, y)
        else
            for _, texture in pairs(slot) do
                texture:Hide()
            end
        end
    end
    frame:Show()
end

------------------------------------------------------------------------
-- The combined window's height: Blizzard's (remembered by a post-hook on its UpdateFrameSize) + ours
------------------------------------------------------------------------
local function setGrowth(combined, growth)
    local height = ns.Readable(combined.GetHeight, combined)
    if not height or type(height[1]) ~= "number" then
        return false
    end
    local current = height[1]
    local oursNow = appliedHeight ~= nil and math.abs(current - appliedHeight) < 0.5
    if not oursNow and not (sizeHooked and baseHeight) then
        baseHeight = current -- no hook to tell us: a height we did not set is Blizzard's
    end
    if not baseHeight then
        return false
    end
    local target = baseHeight + growth
    if math.abs(current - target) > 0.5 then
        combined:SetHeight(target)
    end
    appliedHeight = growth > 0 and target or nil
    return true
end

-- Buttons that still stand where WE put them (anchored to anything but their own window) go back into the
-- reagent window, in the grid Blizzard lays them out in: 4 columns from the bottom right, (-7, 9), highest
-- slot first (ContainerFrameMixin:GetInitialItemAnchor / GetAnchorLayout). Buttons Blizzard has laid out
-- itself since are not touched.
local function sendButtonsHome(reagent, buttons)
    for index, entry in ipairs(buttons) do
        local now = ns.Readable(entry.button.GetPoint, entry.button, 1)
        if now and now[1] ~= nil and now[2] ~= reagent then
            local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
            anchor(entry.button, "BOTTOMRIGHT", reagent, "BOTTOMRIGHT", -7 - column * PITCH, 9 + row * PITCH)
        end
    end
end

-- Everything of ours undone, as far as it is ours to undo. (Where Blizzard's reagent WINDOW stands is
-- Blizzard's business: its next UpdateContainerFrameAnchors puts it back on the screen.)
local function unmerge(combined, reagent, why)
    if backdrop then
        backdrop:Hide()
    end
    if reagent and shown(reagent) == true then
        local buttons = collectButtons(reagent)
        if buttons then
            sendButtonsHome(reagent, buttons)
        end
    end
    if combined and appliedHeight and shown(combined) == true then
        setGrowth(combined, 0) -- (a closed window is sized by Blizzard when it opens)
    end
    Reagents.moved = 0
    setState(why)
end

------------------------------------------------------------------------
-- Apply: idempotent. Runs after Blizzard laid out a bag window, on a mouse button in the bag window, on
-- an option change and at the end of a fight - never on a timer.
------------------------------------------------------------------------
function Reagents:Apply()
    local combined, reagent = _G.ContainerFrameCombinedBags, _G[REAGENT_WINDOW]
    if not (isFrame(combined) and isFrame(reagent)) then
        setState("this client has no combined bag window / reagent window")
        return
    end
    if not anchorsHooked then
        setState("this client's bag code is not the one we know - left alone") -- nothing would tell us when to re-apply
        return
    end
    if blockedByCombat(combined, reagent) then
        pending = true
        setState("waiting for the end of the fight")
        return
    end
    pending = false

    if not ns:GetOption("merge") then
        return unmerge(combined, reagent, "switched off")
    end
    local combinedShown, reagentShown = shown(combined), shown(reagent)
    local bag = ns.Readable(reagent.GetID, reagent)
    if combinedShown == nil or reagentShown == nil or bag == nil then
        return unmerge(combined, reagent, "unreadable - left alone")
    end
    if not combinedShown then
        return unmerge(combined, reagent, "bags closed")
    end
    if not usingCombinedBags() then
        return unmerge(combined, reagent, "separate bag windows: nothing to merge into")
    end
    if not (reagentShown and bag[1] == REAGENT_BAG) then
        return unmerge(combined, reagent, "the reagent bag is not open")
    end
    local buttons = collectButtons(reagent)
    if not buttons or #buttons == 0 then
        return unmerge(combined, reagent, buttons and "the reagent bag has no slots" or "unreadable - left alone")
    end
    if blockedByCombat(buttons[1].button) then
        pending = true
        setState("waiting for the end of the fight")
        return
    end
    local grid = readGrid(combined)
    if not grid then
        return unmerge(combined, reagent, "the bag window's grid is not one we know - left alone")
    end

    -- Blizzard's reagent window: off the screen, still open (its buttons only exist while it is)
    anchor(reagent, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT", -300, 0)

    if not ns:GetOption("reagentsShown") then
        -- put away: the buttons stay inside the parked window, the bag window is Blizzard's size
        if backdrop then
            backdrop:Hide()
        end
        sendButtonsHome(reagent, buttons)
        setGrowth(combined, 0)
        Reagents.moved = 0
        setState("merged, reagent slots put away (/fbags show)")
        return
    end

    local rows = math.floor((grid.last + #buttons - 1) / COLUMNS) + 1
    if not setGrowth(combined, (rows - grid.rows) * PITCH) then
        return unmerge(combined, reagent, "unreadable - left alone")
    end
    for index, entry in ipairs(buttons) do
        local x, y = cellOffset(grid, grid.last + index)
        anchor(entry.button, "BOTTOMRIGHT", grid.origin, "TOPRIGHT", x, y)
    end
    showBackgrounds(combined, grid, #buttons)
    -- Whatever brought us here - Blizzard laid out (and raised) a bag window, a mouse button went down in
    -- the bag window, the merge was just switched on - may have left that window in front.
    bringForward(reagent)
    Reagents.moved = #buttons
    setState("merged: " .. #buttons .. " reagent slots after Blizzard's " .. grid.last
        .. (rows > grid.rows and (", " .. (rows - grid.rows) .. " more row" .. (rows - grid.rows > 1 and "s" or "")) or ", no extra row"))
end

------------------------------------------------------------------------
-- The backpack key -> Blizzard's "Open All Bags"
------------------------------------------------------------------------
local keyOwner = CreateFrame("Frame", "ForeverBagsKeyOwner")

local function wantedKeys()
    if not (ns:GetOption("merge") and ns:GetOption("backpackKeyOpensAll") and usingCombinedBags()) then
        return ""
    end
    local slots = ns.Readable(C_Container and C_Container.GetContainerNumSlots, REAGENT_BAG)
    if not slots or type(slots[1]) ~= "number" or slots[1] <= 0 then
        return "" -- no reagent bag (or the client would not say): the key stays what it is
    end
    local keys = { GetBindingKey("TOGGLEBACKPACK") }
    table.sort(keys)
    return table.concat(keys, " ")
end

function Reagents:ApplyKeys()
    local wanted = wantedKeys()
    if wanted == self.keys then
        return -- (also what stops UPDATE_BINDINGS, which our own change fires, from looping)
    end
    if InCombatLockdown() then
        keysPending = true -- changing bindings is protected in a fight
        return
    end
    keysPending = false
    self.keys = wanted -- BEFORE the calls: each of them fires UPDATE_BINDINGS, which comes straight back here
    ClearOverrideBindings(keyOwner)
    for key in string.gmatch(wanted, "%S+") do
        SetOverrideBinding(keyOwner, false, key, "OPENALLBAGS")
    end
    ns:Log("keys", wanted ~= "" and ("backpack key(s) " .. wanted .. " -> Open All Bags") or "backpack key left alone")
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------
local function apply()
    local started = debugprofilestop and debugprofilestop()
    ns.SafeCall(Reagents.Apply, Reagents)
    local work = Reagents.work
    work.layoutPasses = work.layoutPasses + 1
    if started then
        local ms = debugprofilestop() - started
        work.layoutMs = work.layoutMs + ms
        work.slowestLayoutMs = math.max(work.slowestLayoutMs, ms)
    end
end

-- A mouse button in the bag window changes ONE thing: which of the two windows is in front. So that is all
-- that is put right - no grid is read, nothing is re-anchored (a full layout pass per click cost ~240 reads).
local function raiseOnly()
    local reagent = _G[REAGENT_WINDOW]
    if Reagents.moved == 0 or not isFrame(reagent) then
        return
    end
    if blockedByCombat(reagent) then
        pending = true -- the end of the fight runs a layout pass, which ends with the raise
        return
    end
    bringForward(reagent)
    Reagents.work.raisesOnClicks = Reagents.work.raisesOnClicks + 1
end

ns:Listen("LOGIN", function()
    if type(hooksecurefunc) == "function" then
        if type(_G.UpdateContainerFrameAnchors) == "function" then
            hooksecurefunc("UpdateContainerFrameAnchors", apply)
            anchorsHooked = true
        end
        local combined = _G.ContainerFrameCombinedBags
        if isFrame(combined) and type(combined.UpdateFrameSize) == "function" then
            hooksecurefunc(combined, "UpdateFrameSize", function(window)
                local height = ns.Readable(window.GetHeight, window)
                baseHeight = height and type(height[1]) == "number" and height[1] or nil -- Blizzard's own height, just set
            end)
            sizeHooked = true
        end
    end
    Reagents.hooks = { anchors = anchorsHooked, size = sizeHooked }
    ns.SafeCall(Reagents.ApplyKeys, Reagents)
    apply()
end)

-- A mouse button on the bag window (or on anything in it): the client raises that window's unit over the
-- reagent slots. Back in front at once - and once more a frame later, should the client raise AFTER it
-- has told us (a held button is a drag: the slots must be there to be dropped on).
for _, event in ipairs({ "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP" }) do
    ns:On(event, function()
        if Reagents.moved == 0 then
            return
        end
        local combined = _G.ContainerFrameCombinedBags
        local foci = mouseFoci()
        local inside = foci == nil -- the client would not say what is under the mouse
        for _, frame in ipairs(foci or {}) do
            inside = inside or insideWindow(frame, combined)
        end
        if not inside then
            return
        end
        raiseOnly()
        C_Timer.After(0, function()
            ns.SafeCall(raiseOnly)
        end)
    end)
end

ns:Listen("COMBAT_END", function()
    if pending then
        apply()
    end
    if keysPending then
        ns.SafeCall(Reagents.ApplyKeys, Reagents)
    end
end)

ns:Listen("OPTION_CHANGED", function()
    apply()
    ns.SafeCall(Reagents.ApplyKeys, Reagents)
end)

for _, event in ipairs({ "UPDATE_BINDINGS", "BAG_UPDATE_DELAYED", "CVAR_UPDATE" }) do
    ns:On(event, function()
        ns.SafeCall(Reagents.ApplyKeys, Reagents)
    end)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
local function report()
    ns:Print("reagent bag:", Reagents.state .. ".",
        Reagents.keys ~= "" and ("Backpack key " .. Reagents.keys .. " opens all bags.") or "")
end

ns:RegisterCommand("on", "reagent bag slots in the combined bag window's grid, in their own colour (default)", function()
    ns:SetOption("merge", true)
    report()
end)

ns:RegisterCommand("off", "leave the reagent bag as Blizzard's separate window", function()
    ns:SetOption("merge", false)
    ns:Print("off. Close and open your bags once to get Blizzard's reagent window back in its place.")
end)

ns:RegisterCommand("show", "show the reagent slots in the bag window (default)", function()
    ns:SetOption("reagentsShown", true)
    report()
end)

ns:RegisterCommand("hide", "put the reagent slots away (the bag window looks stock)", function()
    ns:SetOption("reagentsShown", false)
    report()
end)

ns:RegisterCommand("key", "'on' (default): the backpack key opens the reagent bag too (it runs Blizzard's Open All Bags); 'off': leave the key alone", function(rest)
    local mode = string.lower(rest or "")
    if mode == "on" or mode == "off" then
        ns:SetOption("backpackKeyOpensAll", mode == "on")
        if InCombatLockdown() then
            ns:Print("in combat - applied when the fight ends.")
        end
    end
    ns:Print("backpack key:", Reagents.keys ~= "" and (Reagents.keys .. " opens all bags.") or "left alone.")
end)

ns:RegisterCommand("status", "what is being done with the reagent slots right now", report)
