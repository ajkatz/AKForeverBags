-- ForeverBags work meter. Run from the repo root:  lua tests/bench.lua
-- Counts, per player action, what the addon does: how often its layout pass runs, how many questions it
-- asks Blizzard's frames (reads), how many things it changes on them (writes), how much garbage it makes
-- and how long it takes here (plain Lua on this machine - a relative number, not the game's).
package.path = "./tests/?.lua;" .. package.path
local Mock = require("wowmock")

local ns = Mock.install({ bagSlots = 44, reagentSlots = 4 }) -- the character this was built on
local applies = 0
local realApply = ns.Reagents.Apply
ns.Reagents.Apply = function(...) applies = applies + 1; return realApply(...) end

local function measure(label, action, repeats)
    repeats = repeats or 1
    collectgarbage(); collectgarbage("stop")
    local reads0, writes0, applies0, kb0, t0 = Mock.reads, #Mock.touched, applies, collectgarbage("count"), os.clock()
    for _ = 1, repeats do action() end
    local seconds, kb = os.clock() - t0, collectgarbage("count") - kb0
    collectgarbage("restart")
    Mock.realPrint(string.format("  %-44s layout passes %5.1f   reads %6.1f   writes %5.1f   garbage %6.2f KB   %7.3f ms",
        label, (applies - applies0) / repeats, (Mock.reads - reads0) / repeats, (#Mock.touched - writes0) / repeats, kb / repeats, seconds * 1000 / repeats))
end

Mock.realPrint("ForeverBags work per action (44 normal slots, 4 reagent slots)")
measure("open all bags (B)", function() Mock.openAllBags(); Mock.closeAllBags() end)
Mock.openAllBags()
measure("click an item in the bag window", function() Mock.clickInBagWindow(3); Mock.advance(0.02) end, 200)
measure("click a reagent slot", function() Mock.clickReagentSlot(1); Mock.advance(0.02) end, 200)
measure("60 s with the bags open, nothing happening", function() Mock.advance(60) end)
Mock.closeAllBags()
measure("60 s with the bags closed", function() Mock.advance(60) end)
measure("open + close, 200 times", function() Mock.openAllBags(); Mock.closeAllBags() end, 200)
if #Mock.errors > 0 then Mock.realPrint("ERRORS: " .. table.concat(Mock.errors, "\n")) os.exit(1) end
