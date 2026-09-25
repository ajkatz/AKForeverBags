-- AKForeverBags scenario tests. Run from the repo root:  lua tests/run.lua
-- Every scenario loads a fresh copy of the addon into the mock client and fails if the addon raised ANY
-- Lua error, did something forbidden in combat, or did one of the things that spread taint into
-- Blizzard's bag code (see tests/wowmock.lua).
package.path = "./tests/?.lua;" .. package.path
local Mock = require("wowmock")

local failures, passed = {}, 0

local function check(condition, message)
    if not condition then
        error(message or "check failed", 2)
    end
end

local function equal(actual, expected, what)
    if actual ~= expected then
        error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function scenario(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok and #Mock.errors > 0 then
        ok, err = false, "addon raised errors:\n      " .. table.concat(Mock.errors, "\n      ")
    end
    if ok and #Mock.forbiddenCalls > 0 then
        ok, err = false, "forbidden in combat: " .. table.concat(Mock.forbiddenCalls, ", ")
    end
    if ok and #Mock.taintViolations > 0 then
        ok, err = false, "taint risk: " .. table.concat(Mock.taintViolations, ", ")
    end
    if ok then
        passed = passed + 1
        Mock.realPrint("  ok    " .. name)
    else
        failures[#failures + 1] = name
        Mock.realPrint("  FAIL  " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
    end
end

local function start(options)
    return Mock.install(options)
end

local function printed(text)
    for _, line in ipairs(Mock.printed) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

-- Blizzard's grid: cells count from 1 at the bottom right, leftwards, then up; 42 px apart; every button is
-- anchored BOTTOMRIGHT -> the money row's TOPRIGHT at (-column * 42, 4 + row * 42).
local function cellOf(button)
    local point, relativeTo, relativePoint, x, y = button:GetPoint(1)
    if point ~= "BOTTOMRIGHT" or relativeTo ~= ContainerFrameCombinedBags.MoneyFrame or relativePoint ~= "TOPRIGHT" then
        return nil
    end
    local column, row = -x / 42, (y - 4) / 42
    if column ~= math.floor(column) or row ~= math.floor(row) or column < 0 or column > 9 or row < 0 then
        return nil
    end
    return row * 10 + column + 1, column, row
end

local function reagentButtons()
    local bySlot = {}
    for _, button in ipairs(ContainerFrame6.Items) do
        bySlot[button:GetID()] = button
    end
    return bySlot
end

local function anchorOf(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    return { point = point, to = relativeTo, toPoint = relativePoint, x = x, y = y }
end

Mock.realPrint("AKForeverBags tests")

scenario("Open All Bags: the reagent slots continue the bag window's own grid - Blizzard's buttons, only re-anchored, none of the normal slots moved", function()
    local ns = start() -- 56 normal slots: Blizzard fills cells 1-56, so its top row (51-60) has four cells free on the left
    Mock.openAllBags()
    local combined, reagent = ContainerFrameCombinedBags, ContainerFrame6
    equal(ns.Reagents.state, "merged: 12 reagent slots after Blizzard's 56, 1 more row")
    equal(combined:GetHeight(), Mock.combinedHeight() + 42, "the window grew by exactly the one row that was needed")

    local taken = {}
    for index, button in ipairs(combined.Items) do
        equal(cellOf(button), index, "normal slot " .. index .. " stands where Blizzard put it")
        taken[index] = "a normal slot"
    end
    local buttons = reagentButtons()
    for slot = 1, 12 do
        local button = buttons[slot]
        local cell = cellOf(button)
        check(cell, "reagent slot " .. slot .. " is on the bag window's grid, anchored like Blizzard's own buttons")
        equal(cell, 56 + (12 - slot + 1), "Blizzard's order goes on: highest slot first, so slot 1 ends up top left")
        check(not taken[cell], "reagent slot " .. slot .. " shares cell " .. cell .. " with " .. tostring(taken[cell]))
        taken[cell] = "reagent slot " .. slot
        equal(button:GetParent(), reagent, "still a child of Blizzard's reagent window")
        equal(button:GetFrameStrata(), "MEDIUM", "its strata is left alone: between two toplevel windows it decides nothing")
    end
    equal(Mock.reagentSlotsSeen(), 12, "and the player can see them: in front of the bag window")
    for cell = 1, 68 do
        check(taken[cell], "no hole in the grid at cell " .. cell)
    end
    local _, column1, row1 = cellOf(buttons[1])
    local _, column12, row12 = cellOf(buttons[12])
    equal(row12, 5); equal(column12, 6, "reagent slot 12 sits right next to Blizzard's last normal slot (top row, column 5)")
    equal(row1, 6); equal(column1, 7, "reagent slot 1: the new top row")

    local parked = anchorOf(reagent)
    equal(parked.to, UIParent); equal(parked.toPoint, "BOTTOMLEFT"); check(parked.x < 0, "Blizzard's reagent window: off the screen, still open")
    equal(reagent:IsShown(), true)

    Mock.advance(5) -- (nothing is scheduled: nothing happens)
    equal(combined:GetHeight(), Mock.combinedHeight() + 42)
end)

scenario("the colour is on the SLOTS: one tinted slot background behind every reagent slot, ours, none on Blizzard's buttons", function()
    start()
    Mock.openAllBags()
    local frame = AKForeverBagsReagentSlots
    equal(frame:GetParent(), ContainerFrameCombinedBags, "our frame is a child of the bag window: comes, goes and scales with it")
    equal(frame:IsShown(), true)
    equal(#frame.slots, 12)
    local buttons = reagentButtons()
    for index, slot in ipairs(frame.slots) do
        local button = buttons[12 - index + 1]
        local at, art = anchorOf(button), anchorOf(slot.art)
        equal(art.to, at.to); equal(art.x, at.x); equal(art.y, at.y, "the slot art stands exactly behind its button")
        check(slot.art.__texture:find("UI-Bag-Components", 1, true), "Blizzard's own slot art ...")
        check(slot.art.__vertexColor[2] > slot.art.__vertexColor[1], "... in another colour")
        equal(slot.art:IsShown(), true); equal(slot.rim:IsShown(), true)
        local rim = anchorOf(slot.rim)
        equal(rim.x, at.x + 2); equal(rim.y, at.y - 2); equal(slot.rim:GetWidth(), 41, "a thin rim that still shows around an item")
    end
    -- (that nothing was created on or written to Blizzard's buttons is what the taint check of every scenario says)

    Mock.state.reagentSlots = 8 -- a smaller reagent bag next time: the spare backgrounds go away
    Mock.closeAllBags(); Mock.openAllBags()
    equal(frame.slots[8].art:IsShown(), true); equal(frame.slots[9].art:IsShown(), false)
end)

scenario("the window's own height is never lost: full top row, a bag swapped while open, the backpack alone, no room needed at all", function()
    local ns = start({ bagSlots = 60 }) -- Blizzard's top row is full: the reagent slots start a row of their own
    Mock.openAllBags()
    local combined = ContainerFrameCombinedBags
    equal(ns.Reagents.state, "merged: 12 reagent slots after Blizzard's 60, 2 more rows")
    equal(combined:GetHeight(), Mock.combinedHeight() + 84)
    equal(cellOf(reagentButtons()[12]), 61, "the first cell of the new row: bottom right of it")

    local before = Mock.combinedHeight()
    Mock.resizeBags(70) -- one more row of normal slots: Blizzard sizes and lays out the window again
    equal(Mock.combinedHeight(), before + 42)
    equal(combined:GetHeight(), Mock.combinedHeight() + 84, "ours on top of the NEW height - not the old one, not twice")
    equal(cellOf(reagentButtons()[12]), 71, "and the reagent slots moved on behind the new normal slots")

    Mock.closeAllBags()
    equal(ns.Reagents.state, "bags closed")
    Mock.openBackpack() -- the backpack button: the combined window alone
    equal(combined:GetHeight(), Mock.combinedHeight(), "no reagent window open: Blizzard's height")
    equal(ns.Reagents.state, "the reagent bag is not open")
    check(not AKForeverBagsReagentSlots:IsShown())

    ns = start({ bagSlots = 52, reagentSlots = 8 }) -- eight free cells in Blizzard's top row: they fit in
    Mock.openAllBags()
    equal(ns.Reagents.state, "merged: 8 reagent slots after Blizzard's 52, no extra row")
    equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight(), "not a pixel taller")

    -- the height is always worked out from the window: nothing of Blizzard's is hooked or run for it
    ns = start({ noSizeMethod = true })
    equal(ns.Reagents.hooks.size, false)
    for _ = 1, 3 do
        Mock.openAllBags()
        equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight() + 42, "never added twice")
        Mock.advance(3)
        equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight() + 42)
        Mock.closeAllBags()
    end
end)

scenario("/fbags hide puts the reagent slots away (the bag window looks stock) - remembered next session; show brings them back", function()
    local ns = start()
    Mock.openAllBags()
    local combined, reagent = ContainerFrameCombinedBags, ContainerFrame6
    SlashCmdList.AKFOREVERBAGS("hide")
    equal(ns:GetOption("reagentsShown"), false)
    equal(ns.Reagents.state, "merged, reagent slots put away (/fbags show)")
    equal(combined:GetHeight(), Mock.combinedHeight())
    check(not AKForeverBagsReagentSlots:IsShown(), "no coloured slot backgrounds left behind")
    for slot, button in pairs(reagentButtons()) do
        equal(anchorOf(button).to, reagent, "slot " .. slot .. " is back inside the (parked) reagent window")
        equal(button:GetFrameStrata(), "MEDIUM")
    end
    equal(anchorOf(reagent).to, UIParent, "which stays off the screen")

    SlashCmdList.AKFOREVERBAGS("show")
    equal(ns.Reagents.state, "merged: 12 reagent slots after Blizzard's 56, 1 more row")
    equal(cellOf(reagentButtons()[1]), 68)

    local db = { chars = { ["Purrdee - TestRealm"] = { options = { reagentsShown = false } } } }
    ns = start({ db = db, bridge = { table = db } })
    equal(ns.savedStateSource, "bridge addon")
    Mock.openAllBags()
    equal(ns.Reagents.state, "merged, reagent slots put away (/fbags show)", "remembered over a logout")
    equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight())
end)

scenario("the backpack key opens the reagent bag too - through Blizzard's own Open All Bags command, never through us", function()
    local ns, state = start()
    equal(Mock.commandFor("B"), "OPENALLBAGS", "an override binding: the key press runs Blizzard's ToggleAllBags()")
    equal(Mock.commandFor("SHIFT-B"), "OPENALLBAGS")
    Mock.pressKey("B")
    equal(ns.Reagents.moved, 12)
    Mock.pressKey("B")
    equal(ContainerFrameCombinedBags:IsShown(), false); equal(ContainerFrame6:IsShown(), false)

    SlashCmdList.AKFOREVERBAGS("key off")
    equal(Mock.commandFor("B"), "TOGGLEBACKPACK", "left alone")
    Mock.setCombat(true)
    SlashCmdList.AKFOREVERBAGS("key on")
    equal(Mock.commandFor("B"), "TOGGLEBACKPACK", "changing bindings is protected in a fight")
    check(printed("applied when the fight ends"))
    Mock.setCombat(false)
    equal(Mock.commandFor("B"), "OPENALLBAGS")

    state.bindings = { N = "TOGGLEBACKPACK" } -- the player rebinds the backpack
    Mock.fire("UPDATE_BINDINGS")
    equal(Mock.commandFor("N"), "OPENALLBAGS"); equal(Mock.commandFor("B"), nil)
    SlashCmdList.AKFOREVERBAGS("off")
    equal(Mock.commandFor("N"), "TOGGLEBACKPACK", "merge off: the key is the player's again")

    start({ separateBags = true })
    equal(Mock.commandFor("B"), "TOGGLEBACKPACK", "separate bag windows: nothing to merge, key untouched")
    start({ reagentSlots = 0 })
    equal(Mock.commandFor("B"), "TOGGLEBACKPACK", "no reagent bag: key untouched")
end)

scenario("the backpack button closes only the combined window: no reagent slots are left floating on the screen", function()
    local ns = start()
    Mock.openAllBags()
    Mock.closeBackpackOnly()
    equal(ns.Reagents.state, "bags closed")
    for slot, button in pairs(reagentButtons()) do
        equal(anchorOf(button).to, ContainerFrame6, "slot " .. slot .. " went back into the reagent window")
        equal(button:GetFrameStrata(), "MEDIUM")
    end
    equal(anchorOf(ContainerFrame6).to, ContainerFrameContainer, "which stands where Blizzard just put it - on the screen")
end)

scenario("/fbags off undoes everything that is ours; on brings it back", function()
    local ns = start()
    Mock.openAllBags()
    SlashCmdList.AKFOREVERBAGS("off")
    equal(ns.Reagents.state, "switched off")
    equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight())
    check(not AKForeverBagsReagentSlots:IsShown())
    equal(anchorOf(reagentButtons()[1]).to, ContainerFrame6)
    equal(Mock.commandFor("B"), "TOGGLEBACKPACK")
    check(printed("Close and open your bags once"))
    Mock.closeAllBags(); Mock.openAllBags()
    equal(anchorOf(ContainerFrame6).to, ContainerFrameCombinedBags, "stock: Blizzard's reagent window next to the combined one")
    equal(anchorOf(reagentButtons()[1]).to, ContainerFrame6, "and its buttons where Blizzard laid them out")

    SlashCmdList.AKFOREVERBAGS("on")
    equal(ns.Reagents.moved, 12)
    SlashCmdList.AKFOREVERBAGS("status")
    check(printed("merged: 12 reagent slots"))
    SlashCmdList.AKFOREVERBAGS("")
    check(printed("/fbags hide"))
end)

scenario("a secret answer from one of Blizzard's frames, or a grid we do not know (gamepad layout), means hands off", function()
    local ns, state = start()
    state.secretGetters.IsShown = true
    Mock.touched = {}
    Mock.openAllBags()
    equal(ns.Reagents.state, "unreadable - left alone")
    equal(#Mock.touched, 0, "nothing of Blizzard's was touched: " .. table.concat(Mock.touched, ", "))
    equal(anchorOf(reagentButtons()[1]).to, ContainerFrame6)

    ns, state = start()
    state.secretGetters.GetID = true -- which bag is in that window? which slot is that button?
    Mock.touched = {}
    Mock.openAllBags()
    equal(ns.Reagents.state, "unreadable - left alone")
    equal(#Mock.touched, 0, table.concat(Mock.touched, ", "))

    ns, state = start()
    state.secretGetters.GetPoint = true -- where do Blizzard's own buttons stand?
    Mock.touched = {}
    Mock.openAllBags()
    equal(ns.Reagents.state, "the bag window's grid is not one we know - left alone")
    equal(#Mock.touched, 0, table.concat(Mock.touched, ", "))

    ns = start({ gamepadLayout = true })
    Mock.touched = {}
    Mock.openAllBags()
    equal(ns.Reagents.state, "the bag window's grid is not one we know - left alone")
    equal(#Mock.touched, 0, table.concat(Mock.touched, ", "))
    equal(anchorOf(ContainerFrame6).to, ContainerFrameCombinedBags, "Blizzard's reagent window stays where Blizzard put it")

    ns, state = start()
    state.secretGetters.GetHeight = true
    Mock.openAllBags()
    equal(ns.Reagents.state, "unreadable - left alone")
    equal(anchorOf(reagentButtons()[1]).to, ContainerFrame6, "no window height, no extra row - and no buttons moved into nothing")
end)

scenario("combat: bag frames are arranged in a fight because they are not protected; if they ever are, it waits", function()
    local ns = start()
    Mock.setCombat(true)
    Mock.openAllBags()
    equal(ns.Reagents.moved, 12)
    Mock.setCombat(false)

    ns = start({ protectedBags = true })
    Mock.setCombat(true)
    Mock.touched = {}
    Mock.openAllBags()
    equal(ns.Reagents.state, "waiting for the end of the fight")
    equal(#Mock.touched, 0, table.concat(Mock.touched, ", "))
    Mock.setCombat(false)
    equal(ns.Reagents.moved, 12)
end)

scenario("nothing to merge: separate bag windows, no reagent bag, a client without these windows - no error, nothing touched", function()
    local ns = start({ separateBags = true })
    Mock.advance(5)
    equal(ns.Reagents.state, "bags closed")

    ns = start({ reagentSlots = 0 })
    Mock.touched = {}
    Mock.openAllBags()
    equal(ns.Reagents.state, "the reagent bag is not open")
    equal(#Mock.touched, 0, table.concat(Mock.touched, ", "))

    ns = start({ reagentSlots = 37 }) -- a big one: 4 cells of Blizzard's top row + 33 -> 4 more rows
    Mock.openAllBags()
    equal(ns.Reagents.state, "merged: 37 reagent slots after Blizzard's 56, 4 more rows")
    equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight() + 4 * 42)

    ns = start({ noBagWindows = true })
    Mock.advance(5)
    equal(ns.Reagents.state, "this client has no combined bag window / reagent window")
end)

scenario("the bag bar's reagent bag button stays Blizzard's: nothing of ours covers it (the bag can be picked up, swapped, unequipped); a click hides the reagent slots, the next brings them back", function()
    local ns = start()
    Mock.openAllBags()
    for _, frame in ipairs(Mock.frames) do
        check(frame.__allPoints ~= CharacterReagentBag0Slot, "a frame of the addon lies over Blizzard's reagent bag button: " .. tostring(frame.__name))
    end
    equal(Mock.clickReagentBagButton(), "Blizzard's button toggled the reagent bag")
    equal(ns.Reagents.state, "the reagent bag is not open")
    equal(ns.Reagents.moved, 0); check(not AKForeverBagsReagentSlots:IsShown(), "no green slots left behind")
    equal(ContainerFrameCombinedBags:GetHeight(), Mock.combinedHeight(), "and the bag window is Blizzard's size again")
    equal(Mock.clickReagentBagButton(), "Blizzard's button toggled the reagent bag")
    equal(ns.Reagents.moved, 12, "a second click brings them back")
    equal(Mock.reagentSlotsSeen(), 12, "in front of the bag window")

    ns = start({ stockBagBar = true }) -- Blizzard's bag bar in its own place (no AKForeverActionBars docking): the same
    Mock.openAllBags()
    equal(Mock.clickReagentBagButton(), "Blizzard's button toggled the reagent bag")
    equal(ns.Reagents.moved, 0)
end)

-- THE bug of 2026-09-20. Two toplevel windows = two drawing units; the one raised last is in front, whatever
-- the strata or level of the frames in them; a mouse button going down on anything in a unit raises it.
for _, order in ipairs({
    { eventBeforeRaise = false, name = "the client raises, then tells us" },
    { eventBeforeRaise = true, name = "the client tells us, then raises" },
}) do
    scenario("the key ring bug: a mouse button on anything in the bag window must not leave that window in front of the reagent slots (" .. order.name .. ")", function()
        local ns = start({ eventBeforeRaise = order.eventBeforeRaise })
        Mock.openAllBags()
        equal(Mock.reagentSlotsSeen(), 12, "right after Open All Bags: Blizzard's own frame:Raise() has the reagent window's unit in front")
        local before = ns.Reagents.raises

        Mock.clickKeyRing() -- showKeyring = 0: no window opens, not one line of Blizzard's Lua changes anything - only the press
        Mock.advance(0.01)
        equal(Mock.reagentSlotsSeen(), 12, "the key ring (docked into the bag window by AKForeverActionBars: part of its unit)")
        check(ns.Reagents.raises > before, "by raising the reagent window the way Blizzard's code does when it opens")
        equal(ns.Reagents.state, "merged: 12 reagent slots after Blizzard's 56, 1 more row")

        Mock.clickInBagWindow(3)
        Mock.advance(0.01)
        equal(Mock.reagentSlotsSeen(), 12, "a click on a normal item")

        Mock.holdInBagWindow(7) -- a drag starts: the button stays down, no release to help
        Mock.advance(0.01)
        equal(Mock.reagentSlotsSeen(), 12, "a held button: the reagent slots are there to be dropped on")
        Mock.releaseMouse()
        Mock.advance(0.01)

        local raises = ns.Reagents.raises
        Mock.clickReagentSlot(1) -- the press raises the reagent window's own unit: nothing for us to do
        Mock.advance(0.01)
        equal(Mock.reagentSlotsSeen(), 12)
        equal(ns.Reagents.raises, raises, "a press on a reagent slot itself needs no help")

        Mock.advance(10)
        equal(ns.Reagents.raises, raises, "and nothing is raised while nothing happens (a window the player put over the bags stays there)")
    end)
end

scenario("the bags opened the other way round (reagent bag first, then the backpack): the reagent slots still end up in front", function()
    local ns = start()
    equal(Mock.clickReagentBagButton(), "Blizzard's button toggled the reagent bag", "bags closed: no guard, the button is Blizzard's")
    equal(ns.Reagents.state, "bags closed")
    Mock.openBackpack() -- shown and raised AFTER the reagent window: the combined window's unit is in front ...
    equal(ns.Reagents.moved, 12)
    equal(Mock.reagentSlotsSeen(), 12, "... until the merge brings the reagent window forward")
    Mock.resizeBags(52) -- a bag swapped while open: Blizzard generates the combined window again - Show, Raise, layout
    equal(Mock.reagentSlotsSeen(), 12, "whenever Blizzard has laid out (and raised) a bag window, too")
end)

scenario("a stock bag bar is not part of the bag window: a click on its key ring raises nothing, and nothing is done", function()
    local ns = start({ stockBagBar = true })
    Mock.openAllBags()
    local raises = ns.Reagents.raises
    Mock.clickKeyRing()
    Mock.advance(0.01)
    equal(ns.Reagents.raises, raises)
    equal(Mock.reagentSlotsSeen(), 12)
end)

scenario("always smooth: no timer, no ticker, no polling - the addon only runs when something happened", function()
    local ns = start()
    equal(#Mock.timers, 0, "nothing scheduled after login")
    Mock.openAllBags()
    equal(ns.Reagents.moved, 12)
    equal(#Mock.timers, 0, "nothing scheduled while the bags are open")
    Mock.clickInBagWindow(2)
    Mock.advance(0.01)
    equal(#Mock.timers, 0, "a click's one deferred raise is gone a frame later")
    Mock.closeAllBags()
    Mock.advance(30)
    equal(#Mock.timers, 0)

    -- the bag window raised by a way we did not see (no press, no layout): the next press anywhere in it heals
    Mock.openAllBags()
    Mock.raiseBagWindowBehindOurBack()
    equal(Mock.reagentSlotsSeen(), 0)
    Mock.clickInBagWindow(1)
    Mock.advance(0.01)
    equal(Mock.reagentSlotsSeen(), 12)
end)

scenario("combat: should the bag windows ever be protected, nothing is raised in a fight - the end of the fight does it", function()
    local ns = start({ protectedBags = true })
    Mock.openAllBags()
    equal(Mock.reagentSlotsSeen(), 12)
    Mock.setCombat(true)
    local raises = ns.Reagents.raises
    Mock.clickKeyRing()
    Mock.advance(1)
    equal(ns.Reagents.raises, raises, "hands off (the scenario fails on any call on a protected frame in combat)")
    equal(Mock.reagentSlotsSeen(), 0)
    Mock.setCombat(false)
    equal(Mock.reagentSlotsSeen(), 12, "wanted all along: done when the fight ends")

    ns = start({ protectedContainer = true }) -- only the windows' full-screen parent: it is left alone in a fight ...
    Mock.openAllBags()
    Mock.setCombat(true)
    Mock.clickKeyRing()
    Mock.advance(0.01)
    equal(Mock.reagentSlotsSeen(), 12, "... and the reagent window itself is raised, as Blizzard's code does")
    Mock.setCombat(false)
end)

scenario("/fbags show while the bag window is in front (clicked while the slots were put away): they come up in front of it", function()
    local ns = start()
    Mock.openAllBags()
    SlashCmdList.AKFOREVERBAGS("hide")
    local raises = ns.Reagents.raises
    Mock.clickInBagWindow(2)
    Mock.advance(0.01)
    equal(ns.Reagents.raises, raises, "nothing of ours in the bag window: nothing is raised")
    SlashCmdList.AKFOREVERBAGS("show")
    equal(ns.Reagents.moved, 12)
    equal(Mock.reagentSlotsSeen(), 12)
end)


scenario("the performance promise, as budgets: idle costs nothing, a click only raises, a layout pass only runs when Blizzard laid out", function()
    local ns = start()
    local passes = 0
    local realApply = ns.Reagents.Apply
    ns.Reagents.Apply = function(...) passes = passes + 1; return realApply(...) end
    local function cost(action)
        local reads, writes, before = Mock.reads, #Mock.touched, passes
        action()
        local touched = {}
        for i = writes + 1, #Mock.touched do touched[#touched + 1] = Mock.touched[i] end
        return { reads = Mock.reads - reads, writes = touched, passes = passes - before }
    end

    local open = cost(Mock.openAllBags)
    equal(ns.Reagents.moved, 12)
    check(open.passes <= 2, "opening the bags: " .. open.passes .. " layout passes (one per window Blizzard laid out)")
    check(open.reads <= 120, "opening the bags: " .. open.reads .. " reads of Blizzard's frames (budget 120)")

    for _, click in ipairs({ { "an item", function() Mock.clickInBagWindow(3) end }, { "the key ring", Mock.clickKeyRing },
        { "a held button (drag)", function() Mock.holdInBagWindow(5); Mock.advance(0.02); Mock.releaseMouse() end } }) do
        local spent = cost(function() click[2](); Mock.advance(0.02) end)
        equal(spent.passes, 0, "a click on " .. click[1] .. " runs no layout pass")
        check(spent.reads <= 16, "a click on " .. click[1] .. ": " .. spent.reads .. " reads (budget 16)")
        for _, what in ipairs(spent.writes) do
            check(what:find("^Raise "), "a click on " .. click[1] .. " only raises - it did: " .. what)
        end
        equal(Mock.reagentSlotsSeen(), 12, "and the slots are in front after a click on " .. click[1])
    end

    local idle = cost(function() Mock.advance(120) end)
    equal(idle.reads, 0, "two minutes with the bags open: not one read"); equal(#idle.writes, 0); equal(idle.passes, 0); equal(#Mock.timers, 0)
    Mock.closeAllBags()
    idle = cost(function() Mock.advance(120) end)
    equal(idle.reads, 0, "two minutes with the bags closed: not one read"); equal(#idle.writes, 0); equal(idle.passes, 0)

    -- a press whose deferred raise finds the bags closed again: nothing is touched
    Mock.openAllBags()
    Mock.holdInBagWindow(1)
    Mock.closeAllBags()
    local late = cost(function() Mock.advance(0.02) end)
    equal(#late.writes, 0, "the bags were closed within the same frame: " .. table.concat(late.writes, ", "))

    -- the gauge of /fbags diag counts what was done
    equal(ns.Reagents.work.layoutPasses, passes + 1, "(+1: the pass at login, before the counter of this scenario)")
    check(ns.Reagents.work.raisesOnClicks >= 6)
    SlashCmdList.AKFOREVERBAGS("diag")
    equal(AKForeverBagsDB.diag.work.layoutPasses, ns.Reagents.work.layoutPasses)
    check(type(AKForeverBagsDB.diag.performance) == "table", "and the report asks the client what the addon costs")
end)

scenario("diagnostics and logout run; the report is SavedVariables-safe and holds no frame", function()
    local ns = start()
    Mock.openAllBags()
    SlashCmdList.AKFOREVERBAGS("diag")
    Mock.fire("PLAYER_LOGOUT")
    local report = AKForeverBagsDB.diag
    local function assertPlain(value, path)
        local kind = type(value)
        if kind == "table" then
            check(getmetatable(value) == nil, path .. ": a frame (or other object) got into the report")
            for k, v in pairs(value) do
                check(type(k) == "string" or type(k) == "number", path .. ": bad key type " .. type(k))
                assertPlain(v, path .. "." .. tostring(k))
            end
        else
            check(kind == "string" or kind == "number" or kind == "boolean", path .. ": " .. kind)
        end
    end
    assertPlain(report, "diag")
    equal(report.reagents.moved, 12); equal(report.reagents.keys, "B"); check(report.reagents.raises >= 1)
    equal(report.reagents.hooks.anchors, true); equal(report.reagents.hooks.size, false, "never hooked: see Reagents.lua")
    equal(report.bagSlots["5"], 12)
    equal(report.windows.ContainerFrame6.itemButtons, 12)
    equal(report.windows.ContainerFrame6.samples[1].anchor.relativeTo, "ContainerFrameCombinedBagsMoneyFrame")
    equal(report.windows.ContainerFrameCombinedBags.itemButtons, 56)
    equal(report.windows.ContainerFrame6.anchor.relativeTo, "UIParent")
    equal(#report.errors, 0); equal(#report.blockedActions, 0)
    equal(report.addonVersion, "0.1.0-test", "the version the packager stamped into the TOC")

    ns = start({ version = "@project-version@" }) -- a working copy: the TOC still holds the packager's token
    equal(ns.version, "dev")
    ns = start({ version = "v0.2.0" }) -- a release: the packager stamps the tag's name
    equal(ns.version, "0.2.0", "printed as v0.2.0, not vv0.2.0")
end)

Mock.realPrint(string.format("\n%d passed, %d failed", passed, #failures))
if #failures > 0 then
    os.exit(1)
end
