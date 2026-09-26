-- The bag bar (backpack button, bag slots, key ring), docked under the bag window.
--
-- WHY. On Forever a bag is swapped by dropping the new one on a BAG SLOT BUTTON, and those only exist on
-- Blizzard's bag bar - BagsBar, an Edit Mode system at the bottom right, next to the micro menu. The
-- combined bag window has no bag slots of its own: its header is search box + sort button (Blizzard's
-- GamepadBagBar only fits in there because gamepad mode removes those two). Whoever puts Blizzard's
-- bottom fixtures away - AKForeverActionBars parks its action bars and micro menu - is left with the bar
-- floating on its own, or, hidden, with no way to swap a bag. So the bar is DOCKED: made a child of the
-- combined bag window, hanging under its right end, with a little arrow of ours beside it that folds it
-- away and brings it back. It then shows, hides and scales with your bags by itself, and every button on
-- it is still Blizzard's own (drag & drop, tooltips, key ring). Worked out and proven in the game in
-- AKForeverActionBars 0.5.5 - 0.5.6; moved here in 0.3.0, because it is about bags.
--
-- HOW, within this addon's rules (Core.lua): on Blizzard's frame only widget methods - SetParent, and the
-- RAW SetPointBase / ClearAllPointsBase, because the bar is an Edit Mode system whose SetPoint and
-- ClearAllPoints are Lua overrides doing Edit Mode bookkeeping (run from addon code they write tainted
-- values into Edit Mode); nothing is written on it; and no timer - the arrangement is re-applied from the
-- same post-hook that places the reagent slots (UpdateContainerFrameAnchors: every path in Blizzard's bag
-- code that shows, hides, sizes or lays out a bag window ends there), from the two full-screen panel
-- hooks (Blizzard moves the bag windows AND the bag bar onto a full-screen panel while one is open, and
-- back), on Edit Mode layouts, when the combined-bags setting changes, and at login. Checked in Blizzard's
-- source first (2026-09-19/20): the bar's code never asks for its parent, the bag windows anchor to the
-- screen and not to the bar (no circular anchor), Blizzard keeps 85 px free under the first bag window
-- (CONTAINER_OFFSET_Y) and the bar is 45 high, so it fits. The bar is not a protected frame on this
-- client; should it ever be, a fight waits.
--
--   bagBar      "window" (default)  docked onto the combined bag window; with separate bag windows (the
--                                   combined view off) it shows in Blizzard's place while a bag is open
--               "show"              Blizzard's place, always
--               "hide"              out of sight (nowhere to swap a bag, then)
--   bagBarShown the fold: true (default) shown, false folded away behind the arrow
--
-- Never docked while Blizzard's own main action bar is on the screen: the bar is part of THAT arrangement
-- - the main bar's right end cap is anchored to it (EndCapRight -> BagsBar in the Edit Mode presets) and
-- would wander off to the bag window with it. Then it stays in Blizzard's place, whatever the option.
local _, ns = ...

local BagBar = {}
ns.BagBar = BagBar

-- Hanging under the window's right end, the way tabs hang under Blizzard's panels; the arrow sits in the
-- corner and the bar to its left. Inside the window there is no room (search box + sort button).
local DOCK = { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = -4, y = -2 }
local TOGGLE_SIZE = 18

BagBar.state = "untouched"
BagBar.hooks = {}

local hiddenParent = CreateFrame("Frame", "AKForeverBagsHidden", UIParent)
hiddenParent:Hide()

local home = {}     -- the last parent / anchor seen on the bar that were NOT ours: "Blizzard's place",
                    -- also after Edit Mode moved it. Kept on OUR side, never on the frame.
local pending = false
local toggle        -- our arrow, a child of the bag window

local function setState(state)
    if state ~= BagBar.state then
        BagBar.state = state
        ns:Log("bagbar", state)
    end
end

local function bar()
    local frame = _G.BagsBar
    if type(frame) == "table" and frame.SetParent and frame.GetParent and frame.GetPoint then
        return frame
    end
    return nil
end

local function bagWindow()
    local window = _G.ContainerFrameCombinedBags
    if type(window) == "table" and window.SetParent then
        return window
    end
    return nil
end

-- The window to dock onto: the combined bag window, while the game is set to use it.
local function combinedWindow()
    local setting = ns.Readable((C_CVar and C_CVar.GetCVar) or GetCVar, "combinedBags")
    if setting and setting[1] == "1" then
        return bagWindow()
    end
    return nil
end

local function anyBagOpen()
    local open = ns.Readable(IsAnyBagOpen)
    return open ~= nil and open[1] == true
end

local function editModeOpen()
    local manager = _G.EditModeManagerFrame
    if type(manager) == "table" and manager.IsEditModeActive then
        local active = ns.Readable(manager.IsEditModeActive, manager)
        return active ~= nil and active[1] and true or false
    end
    return false
end

-- Blizzard's own main action bar on the screen (parked by an action bar addon: not visible)
local function stockMainBarShown()
    local main = _G.MainActionBar or _G.MainMenuBar
    if type(main) ~= "table" or type(main.IsVisible) ~= "function" then
        return false
    end
    local visible = ns.Readable(main.IsVisible, main)
    return visible ~= nil and visible[1] == true
end

-- in a fight a protected (or unreadable) frame is not ours to move
local function mustWait(frame)
    if not InCombatLockdown() then
        return false
    end
    local protected = ns.Readable(frame.IsProtected, frame)
    return not (protected and protected[1] == false)
end

------------------------------------------------------------------------
-- The arrow: OUR button, a child of the bag window so that it comes and goes with it; nothing is written
-- onto Blizzard's frame. Click: fold the bar away / bring it back (option bagBarShown, remembered).
------------------------------------------------------------------------
local function updateToggle(window)
    if not window then
        if toggle then
            toggle:Hide()
        end
        return
    end
    if not toggle then
        toggle = CreateFrame("Button", "AKForeverBagsBagBarToggle", window)
        toggle:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
        toggle.arrow = toggle:CreateTexture(nil, "ARTWORK")
        toggle.arrow:SetAllPoints(toggle)
        toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        toggle:SetScript("OnClick", function()
            ns:SetOption("bagBarShown", not ns:GetOption("bagBarShown"))
        end)
        toggle:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(ns:GetOption("bagBarShown") and "Hide the bag slots" or "Show the bag slots")
            GameTooltip:AddLine("Drop a bag on a slot to swap it. (AKForeverBags)", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        toggle:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    if toggle:GetParent() ~= window then
        toggle:SetParent(window)
    end
    toggle:ClearAllPoints()
    toggle:SetPoint(DOCK.point, window, DOCK.relativePoint, DOCK.x, DOCK.y)
    toggle.arrow:SetTexture(ns:GetOption("bagBarShown") and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
    toggle:Show()
end

------------------------------------------------------------------------
-- Placing the bar
------------------------------------------------------------------------
function BagBar:Apply()
    local frame = bar()
    if not frame then
        setState("no bag bar on this client")
        return
    end
    if mustWait(frame) then
        pending = true -- after the fight
        return
    end
    if editModeOpen() then
        return -- in Edit Mode the bar is the player's to drag
    end
    pending = false
    local parent, anchor = ns.Readable(frame.GetParent, frame), ns.Readable(frame.GetPoint, frame, 1)
    if not (parent and anchor) then
        setState("unreadable - left alone") -- cannot see what we would be doing: hands off
        return
    end
    local window = bagWindow()
    local parentIsOurs = parent[1] == hiddenParent or (window ~= nil and parent[1] == window)
    local anchorIsOurs = window ~= nil and anchor[2] == window
    if not parentIsOurs then
        home.parent = parent[1] or UIParent
    end
    if not anchorIsOurs and anchor[1] then
        home.anchor = anchor
    end

    local function setParent(target)
        if parent[1] ~= target then
            frame:SetParent(target)
            parent[1] = target
        end
    end
    local function setAnchor(point, relativeTo, relativePoint, x, y)
        if anchor[1] == point and anchor[2] == relativeTo and anchor[3] == relativePoint
            and math.abs((anchor[4] or 0) - x) < 0.01 and math.abs((anchor[5] or 0) - y) < 0.01 then
            return
        end
        -- an Edit Mode system: its SetPoint / ClearAllPoints are Lua overrides that write Edit Mode state
        local clear, set = frame.ClearAllPointsBase or frame.ClearAllPoints, frame.SetPointBase or frame.SetPoint
        clear(frame)
        set(frame, point, relativeTo, relativePoint, x, y)
        anchor = { point, relativeTo, relativePoint, x, y }
    end
    -- Back to Blizzard's place = the last parent and anchor that were not ours. When they are not ours right
    -- now (Blizzard moved the bar onto a full-screen panel, Edit Mode re-anchored it), that IS the current
    -- one and nothing happens: only our own doing is ever undone.
    local function goHome()
        setParent(home.parent or UIParent)
        local place = home.anchor
        if place then
            setAnchor(place[1], place[2], place[3], place[4] or 0, place[5] or 0)
        end
    end

    local mode = ns:GetOption("bagBar")
    local stock = stockMainBarShown()
    local dock = mode == "window" and not stock and combinedWindow() or nil
    local docking = false
    if mode == "hide" then
        setParent(hiddenParent)
        setState("hidden")
    elseif mode == "show" then
        goHome()
        setState("Blizzard's place")
    elseif stock then
        goHome()
        setState("Blizzard's place (its action bars are on the screen)")
    elseif dock then
        docking = true
        if ns:GetOption("bagBarShown") then
            setParent(dock)
            setAnchor(DOCK.point, dock, DOCK.relativePoint, DOCK.x - TOGGLE_SIZE - 2, DOCK.y) -- left of the arrow
            setState("docked on the bag window")
        else
            setParent(hiddenParent)
            setState("docked on the bag window - folded away")
        end
    elseif anyBagOpen() then
        goHome()
        setState("Blizzard's place (a bag is open)")
    else
        setParent(hiddenParent)
        setState("hidden (no bag open)")
    end
    updateToggle(docking and dock or nil)
end

function BagBar:Describe()
    return {
        state = self.state, mode = ns:GetOption("bagBar"), shown = ns:GetOption("bagBarShown"),
        hooks = self.hooks, arrow = toggle ~= nil and toggle:IsShown() or false,
    }
end

------------------------------------------------------------------------
-- Wiring: no timer - only when something happened
------------------------------------------------------------------------
local function apply()
    ns.SafeCall(BagBar.Apply, BagBar)
end

ns:Listen("LOGIN", function()
    if type(hooksecurefunc) == "function" then
        for _, name in ipairs({ "UpdateContainerFrameAnchors", "ContainerFrame_SetFullScreenFrame", "ContainerFrame_ClearFullScreenFrame" }) do
            if type(_G[name]) == "function" then
                hooksecurefunc(name, apply)
                BagBar.hooks[name] = true
            end
        end
    end
    apply()
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED" }) do
    ns:On(event, apply)
end

ns:On("CVAR_UPDATE", function(_, name)
    if name == "combinedBags" or name == nil then
        apply()
    end
end)

ns:Listen("COMBAT_END", function()
    if pending then
        apply()
    end
end)

ns:Listen("OPTION_CHANGED", function(_, key)
    if key == "bagBar" or key == "bagBarShown" then
        apply()
    end
end)

------------------------------------------------------------------------
-- Command
------------------------------------------------------------------------
ns:RegisterCommand("bagbar", "the bag buttons (backpack, bag slots, key ring): 'window' (default) docks them under your bag window - that is where a bag is swapped; 'show': Blizzard's place; 'hide': never; 'fold' / 'unfold': what the little arrow on the bag window does", function(rest)
    local mode = string.lower(rest or "")
    if mode == "window" or mode == "show" or mode == "hide" then
        ns:SetOption("bagBar", mode)
    elseif mode == "fold" or mode == "unfold" then
        ns:SetOption("bagBarShown", mode == "unfold")
    elseif mode ~= "" then
        ns:Print("usage: /fbags bagbar window | show | hide | fold | unfold")
        return
    end
    ns:Print("bag buttons:", ns:GetOption("bagBar"), "-", BagBar.state .. ".")
    if InCombatLockdown() and mode ~= "" then
        ns:Print("in combat - applied when the fight ends.")
    end
end)
