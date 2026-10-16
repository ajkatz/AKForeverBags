-- Sort: around the client's own sort, the reagent pouch filled first and the items you asked for pinned
-- to the very bottom of the bag.
--
-- WHY. Blizzard's combined bag window has a sort button (BagItemAutoSortButton) at its top right, next
-- to the search box. On client builds up to 70338 it drew nothing (its atlas was missing - measured
-- 2026-10-14) and this addon had a button of its own in the title bar; build 1.60.1.70425 brought the
-- artwork back and the user chose Blizzard's button over two (2026-10-15). So there is no button of ours
-- any more: '/fbags sort' runs the whole pass, and every sort the client runs on its own - Blizzard's
-- button, /sort - is FOLLOWED by the same pass minus the sort itself (a post-hook on C_Container.SortBags;
-- '/fbags sort auto off' switches that off).
--
-- THEN the pinning. "I like my totems at the very bottom of my bag." Blizzard's sort has its own idea of
-- order and no way to ask for one item last. So once its sort has settled (BAG_UPDATE_DELAYED), the items
-- on the pin list go to the bottom-right cells of the combined view - visually the bottom, in either
-- /fbags order - and everything else keeps its order and closes up (see "The pins" below), using
-- nothing but the client's own item-moving calls on plain bag and slot numbers. The bag window's grid
-- (Reagents.lua reads it from the buttons' anchors) says which bag slot each bottom cell is.
--
-- RULES, as everywhere in this addon: no Blizzard Lua is called, nothing is written on Blizzard's
-- frames; the one hook is a post-hook on C_Container.SortBags (the client's call runs first, untouched).
-- C_Container.SortBags / PickupContainerItem / GetContainerItemInfo carry no restriction in the API
-- docs; their only flag is about SECRET arguments, and bag and slot numbers of ours are not secret.
-- Nothing runs in combat, and nothing starts while the cursor holds something.
local _, ns = ...

local Sort = {}
ns.Sort = Sort

local REAGENT_BAG = 5
local BAGS = { 0, 1, 2, 3, 4 }             -- the bags the combined window shows
local MAX_MOVES = 160                      -- a bound, not a budget: two rounds over full bags stay well under it
local BURST = 8                            -- swaps issued per step; the rest of a round follows on the next lock event
local SETTLE_SECONDS = 1.5                 -- how long to wait for the client between steps before giving up

-- what a shaman carries that belongs at the bottom; anything else is a `/fbags pin`
local CLASS_PINS = {
    SHAMAN = { "Earth Totem", "Fire Totem", "Water Totem", "Air Totem" },
}

Sort.state = "idle"        -- idle | filling | sorting | pinning | done | stopped: <why>
Sort.stats = { runs = 0, moves = 0, stopped = 0, movesThisRun = 0, filled = 0, filledThisRun = 0, rounds = 0 }
Sort.hooked = false         -- the post-hook on C_Container.SortBags is in place
local following = false     -- a sort of the client's own is in flight: the pouch fill and the pins follow it
local ownSort = false       -- the SortBags call in flight is ours (the hook must not follow that one)
local plan                  -- the moves still to make, in order
local waitingSince          -- GetTime() when the current step started waiting for the client
local stepping = false      -- a move fires lock events; those must not start another step inside this one

local function now()
    return GetTime and GetTime() or 0
end

local function setState(state)
    Sort.state = state
    ns:Log("sort", state)
end

------------------------------------------------------------------------
-- The pin list
------------------------------------------------------------------------
function Sort:GetPins()
    local saved = ns:GetOption("pins")
    if type(saved) == "table" then
        return saved
    end
    local class = ns.playerClass
    if not class and type(UnitClass) == "function" then
        local answer = ns.Readable(UnitClass, "player")
        class = answer and answer[2]
    end
    return CLASS_PINS[class or ""] or {}
end

-- "Earth Totem", "earth totem", an item link |Hitem:5175:...|h[Earth Totem]|h, or an item id
local function normalisePin(text)
    text = tostring(text or "")
    local id = tonumber(text) or tonumber(string.match(text, "|Hitem:(%d+)"))
    if id then
        return id
    end
    local linked = string.match(text, "%[(.-)%]")
    local name = linked or text
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    return name ~= "" and name or nil
end

local function pinMatches(pin, info)
    if type(pin) == "number" then
        return info.itemID == pin
    end
    return type(info.itemName) == "string" and string.lower(info.itemName) == string.lower(pin)
end

------------------------------------------------------------------------
-- Reading the bags. Every answer may be refused or secret; an unreadable bag stops the run.
------------------------------------------------------------------------
local function itemAt(bag, slot)
    local api = C_Container
    if type(api) ~= "table" or type(api.GetContainerItemInfo) ~= "function" then
        return nil, "no C_Container.GetContainerItemInfo on this client"
    end
    local ok, info = pcall(api.GetContainerItemInfo, bag, slot)
    if not ok then
        return nil, "GetContainerItemInfo raised"
    end
    if info == nil then
        return false -- an empty slot
    end
    if ns.IsSecret(info) or type(info) ~= "table" or ns.AnySecret(info.itemID, info.itemName, info.isLocked) then
        return nil, "item info is secret"
    end
    return info
end

local function slotsIn(bag)
    local api = C_Container
    local answer = ns.Readable(api and api.GetContainerNumSlots, bag)
    local count = answer and answer[1]
    return type(count) == "number" and count or 0
end

-- The reagent pouch's family bit, or nil when there is no pouch (no slots) or the client will not say.
local function pouchFamily()
    local api = C_Container
    if type(api) ~= "table" or type(api.GetContainerNumFreeSlots) ~= "function" then
        return nil
    end
    local answer = ns.Readable(api.GetContainerNumFreeSlots, REAGENT_BAG)
    local free, family = answer and answer[1], answer and answer[2]
    if type(family) ~= "number" or family == 0 or slotsIn(REAGENT_BAG) == 0 then
        return nil
    end
    return family, type(free) == "number" and free or 0
end

-- does this item belong in a bag of that family? (the classic test, for every special bag)
local function belongsTo(family, itemID)
    local getFamily = C_Item and C_Item.GetItemFamily
    if type(getFamily) ~= "function" or type(bit) ~= "table" or type(bit.band) ~= "function" then
        return false
    end
    local answer = ns.Readable(getFamily, itemID)
    local itemFamily = answer and answer[1]
    return type(itemFamily) == "number" and bit.band(itemFamily, family) ~= 0
end

local function isPinnedItem(info)
    for _, pin in ipairs(Sort:GetPins()) do
        if pinMatches(pin, info) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- The pins: a STABLE move. Blizzard's sort leaves the bags in its order; the pinned items go to the
-- bottom cells, in pin order, and everything else keeps its order and closes up - a list deletion and
-- an insert at the end, not a swap that would drop the bottom item into the pin's old slot (the user,
-- 2026-10-15: "move the items below it into those positions like list deletion").
--
-- That is one permutation of the ordinary bags' cells. Moving items one hop at a time would cost a
-- server round trip per cell of distance - hundreds for totems sorted to the far end of full bags - so
-- the permutation is realised in TWO ROUNDS of swaps on disjoint slot pairs: every permutation is the
-- product of two involutions (checked by simulation over 20,000 random permutations). A round's swaps
-- are issued a burst per step, each pair's slots unlocked; once the round has landed the next one is
-- computed from what the bags then hold. A third round only happens when something else moved an item
-- in between.
------------------------------------------------------------------------
-- the ordinary bags' cells, lowest first (cell 1 = the window's bottom right), each with what it holds
-- (false = empty), or nil + why; the third result says whether anything is still locked
local function readCells()
    local reagents = ns.Reagents
    if not reagents or type(reagents.Cells) ~= "function" then
        return nil, "the bag window's grid is not known"
    end
    local cells, why = reagents:Cells()
    if not cells then
        return nil, why or "the bag window's grid is not known"
    end
    local locked = false
    for _, cell in ipairs(cells) do
        local info, infoWhy = itemAt(cell.bag, cell.slot)
        if info == nil and infoWhy then
            return nil, infoWhy
        end
        cell.item = info
        if info and info.isLocked then
            locked = true
        end
    end
    return cells, nil, locked
end

-- where everything must go: the pinned items to cells 1..n in pin order (several stacks of one pin in
-- the order they stand), everything else - items and empty slots alike - after them, in the order it has
local function targetOf(cells)
    local isPinned, target, next = {}, {}, 0
    for _, pin in ipairs(Sort:GetPins()) do
        for index, cell in ipairs(cells) do
            if cell.item and not isPinned[index] and pinMatches(pin, cell.item) then
                isPinned[index] = true
                next = next + 1
                target[index] = next
            end
        end
    end
    for index = 1, #cells do
        if not isPinned[index] then
            next = next + 1
            target[index] = next
        end
    end
    return target, next
end

-- The two rounds. A cycle c1 -> c2 -> ... -> cm (the item at c_i goes to c_(i+1)) is r2 after r1 with
-- r1 = (c2 cm)(c3 c(m-1))... (c1 stays) and r2 = (c1 c2)(c3 cm)(c4 c(m-1))... - each a set of disjoint
-- swaps, so each round can go out together.
local function rounds(target, count)
    local seen, first, second = {}, {}, {}
    for start = 1, count do
        if not seen[start] and target[start] ~= start then
            local cycle, p = {}, start
            repeat
                seen[p] = true
                cycle[#cycle + 1] = p
                p = target[p]
            until p == start
            local m = #cycle
            for i = 2, m do
                local j = m + 2 - i
                if i < j then
                    first[#first + 1] = { cycle[i], cycle[j] }
                end
            end
            second[#second + 1] = { cycle[1], cycle[2] }
            for j = 3, m do
                local k = m + 3 - j
                if j < k then
                    second[#second + 1] = { cycle[j], cycle[k] }
                end
            end
        end
    end
    return first, second
end

------------------------------------------------------------------------
-- The run
------------------------------------------------------------------------
local function cursorHoldsSomething()
    if type(GetCursorInfo) ~= "function" then
        return false
    end
    local answer = ns.Readable(GetCursorInfo)
    return answer ~= nil and answer[1] ~= nil
end

local function stop(why)
    plan, waitingSince = nil, nil
    Sort.stats.stopped = Sort.stats.stopped + 1
    setState("stopped: " .. why)
    ns:Print("sort stopped: " .. why)
end

-- FILLING: pouch-eligible items in the ordinary bags, into free pouch slots. Pins stay out (they are
-- wanted at the bottom of the ordinary bags). Locked items and slots are waited for, not touched.
local function makeFillPlan()
    local family = pouchFamily()
    if not family then
        return {} -- no pouch, or nothing the client will say about it: nothing to fill
    end
    local free = {}
    for slot = 1, slotsIn(REAGENT_BAG) do
        local info, why = itemAt(REAGENT_BAG, slot)
        if info == nil and why then
            return nil, why
        end
        if info == false then
            free[#free + 1] = slot
        end
    end
    if #free == 0 then
        return {}
    end
    local moves, waiting = {}, false
    for _, bag in ipairs(BAGS) do
        for slot = 1, slotsIn(bag) do
            local info, why = itemAt(bag, slot)
            if info == nil and why then
                return nil, why
            end
            if info and type(info.itemID) == "number" and belongsTo(family, info.itemID) and not isPinnedItem(info) then
                if info.isLocked then
                    waiting = true
                elseif #moves < #free then
                    moves[#moves + 1] = { from = { bag = bag, slot = slot }, to = { bag = REAGENT_BAG, slot = free[#moves + 1] },
                        name = info.itemName, fill = true }
                end
            end
        end
    end
    return moves, waiting
end

-- The pin plan: nil + why; {} and true while something is still landing; else the two rounds of swaps
-- { a = cell, b = cell } (both empty = everything is in place). Worked out ONCE from the order the sort
-- left: the second round must not be re-derived from the half-done state, where the shuffled order of the
-- other items would read as the wanted one.
local function makePinPlan()
    local cells, why, locked = readCells()
    if not cells then
        return nil, why
    end
    if locked then
        return {}, true
    end
    local target, count = targetOf(cells)
    local first, second = rounds(target, count)
    local function swapsOf(pairs)
        local swaps = {}
        for _, pair in ipairs(pairs) do
            local a, b = cells[pair[1]], cells[pair[2]]
            if a.item or b.item then -- two empty slots need no swap
                swaps[#swaps + 1] = { a = a, b = b }
            end
        end
        return swaps
    end
    return { swapsOf(first), swapsOf(second) }, false
end

-- One swap: pick the item up, put it down on the target (the target's item, if any, comes back to the
-- source slot - that is what a second PickupContainerItem on an occupied slot does).
local function doMove(move)
    local api = C_Container
    local ok1 = pcall(api.PickupContainerItem, move.from.bag, move.from.slot)
    if not ok1 or not cursorHoldsSomething() then
        return false, "could not pick the item up"
    end
    local ok2 = pcall(api.PickupContainerItem, move.to.bag, move.to.slot)
    if not ok2 or cursorHoldsSomething() then -- (a hand still full: the client refused the slot)
        if type(ClearCursor) == "function" then
            pcall(ClearCursor)
        end
        return false, "could not put the item down"
    end
    Sort.stats.moves = Sort.stats.moves + 1
    return true
end

local function startClientSort()
    local api = C_Container
    setState("sorting")
    ownSort = true
    local ok = pcall(api.SortBags)
    ownSort = false
    if not ok then
        return stop("SortBags raised")
    end
    waitingSince = now()
end

-- FILLING: one move per step, each waited out
local function fillStep()
    local moves, why = makeFillPlan()
    if not moves then
        return stop(why)
    end
    if #moves == 0 then
        if why then
            return -- something is still landing: the next lock change or BAG_UPDATE_DELAYED comes back here
        end
        if following and Sort.stats.filledThisRun == 0 then
            following = false -- the client's sort just ran and nothing went into the pouch: straight to the pins
            setState("pinning")
            return
        end
        following = false
        return startClientSort() -- the pouch is as full as it gets: now the client's own sort
    end
    if Sort.stats.movesThisRun >= MAX_MOVES then
        return stop("more moves than any pin list should need - something is fighting back")
    end
    Sort.stats.movesThisRun = Sort.stats.movesThisRun + 1
    local ok, moveWhy = doMove(moves[1])
    if not ok then
        return stop(moveWhy)
    end
    Sort.stats.filled = Sort.stats.filled + 1
    Sort.stats.filledThisRun = Sort.stats.filledThisRun + 1
    waitingSince = now()
end

-- PINNING: the two rounds, a burst of swaps per step; a round goes out whole before the next starts, and
-- the next starts once every slot the round touched has unlocked
local function landed(touched)
    for _, cell in ipairs(touched) do
        local info, why = itemAt(cell.bag, cell.slot)
        if info == nil and why then
            return nil, why
        end
        if info and info.isLocked then
            return false
        end
    end
    return true
end

local function pinStep()
    if plan and #plan.queue == 0 then
        local ok, why = landed(plan.touched)
        if ok == nil then
            return stop(why)
        end
        if not ok then
            return -- the round is still landing: the next lock change or BAG_UPDATE_DELAYED comes back here
        end
        if plan.later then
            plan.queue, plan.later, plan.touched = plan.later, nil, {}
            Sort.stats.rounds = Sort.stats.rounds + 1
        else
            plan = nil -- both rounds are down: read the bags again - done, or a fresh plan if something else moved an item
        end
    end
    if not plan then
        local roundsOfSwaps, extra = makePinPlan()
        if not roundsOfSwaps then
            return stop(extra)
        end
        if extra then
            return -- something is still landing
        end
        if #roundsOfSwaps[1] == 0 and #roundsOfSwaps[2] == 0 then
            waitingSince = nil
            setState("done")
            return
        end
        plan = { queue = roundsOfSwaps[1], later = roundsOfSwaps[2], touched = {} }
        if #plan.queue == 0 then
            plan.queue, plan.later = plan.later, nil
        end
        Sort.stats.rounds = Sort.stats.rounds + 1
    end
    local issued = 0
    while #plan.queue > 0 and issued < BURST do
        if Sort.stats.movesThisRun >= MAX_MOVES then
            return stop("more moves than any pin list should need - something is fighting back")
        end
        local swap = table.remove(plan.queue, 1)
        local a, aWhy = itemAt(swap.a.bag, swap.a.slot)
        local b, bWhy = itemAt(swap.b.bag, swap.b.slot)
        if (a == nil and aWhy) or (b == nil and bWhy) then
            return stop(aWhy or bWhy)
        end
        if a or b then -- (two empty cells by now: nothing to swap)
            local from, to = swap.a, swap.b
            if not a then
                from, to = swap.b, swap.a -- an empty first cell: the move goes the other way
            end
            Sort.stats.movesThisRun = Sort.stats.movesThisRun + 1
            local ok, moveWhy = doMove({ from = from, to = to })
            if not ok then
                return stop(moveWhy)
            end
            plan.touched[#plan.touched + 1] = swap.a
            plan.touched[#plan.touched + 1] = swap.b
            issued = issued + 1
        end
    end
    waitingSince = now()
end

local function step()
    if (Sort.state ~= "pinning" and Sort.state ~= "filling") or stepping then
        return
    end
    if cursorHoldsSomething() then
        return -- the last move has not landed yet; the next event tries again
    end
    stepping = true
    if Sort.state == "filling" then
        fillStep()
    end
    if Sort.state == "pinning" then -- (a fill step with nothing to fill goes straight on)
        pinStep()
    end
    stepping = false
end

function Sort:Run(from)
    if InCombatLockdown() then
        ns:Print("not in a fight: sorting moves items, and the client will not have that in combat.")
        return false
    end
    if cursorHoldsSomething() then
        ns:Print("put down what you are holding first.")
        return false
    end
    local api = C_Container
    if type(api) ~= "table" or type(api.SortBags) ~= "function" then
        ns:Print("this client has no C_Container.SortBags.")
        return false
    end
    if Sort.state == "sorting" or Sort.state == "pinning" then
        return false -- already at it
    end
    Sort.stats.runs = Sort.stats.runs + 1
    Sort.stats.movesThisRun, Sort.stats.filledThisRun = 0, 0
    following, plan = false, nil
    ns:Log("sort_run", { from = from or "?", pins = #self:GetPins() })
    setState("filling")
    waitingSince = now()
    step() -- the pouch first; when it has nothing left to take, the client's sort
    return true
end

-- Blizzard's sort, and every move of ours, ends in BAG_UPDATE_DELAYED
ns:On("BAG_UPDATE_DELAYED", function()
    if Sort.state == "sorting" then
        setState(following and "filling" or "pinning") -- a sort of the client's own: the pouch first
        step()
    elseif Sort.state == "pinning" or Sort.state == "filling" then
        step()
    end
end)

-- a move lands when its slots unlock; that is another chance to go on
ns:On("ITEM_LOCK_CHANGED", function()
    if (Sort.state == "pinning" or Sort.state == "filling") and not cursorHoldsSomething() then
        step()
    end
end)

-- nothing waits forever: a client that never answers ends the run rather than leaving it hanging
ns:On("BAG_UPDATE", function()
    if waitingSince and (Sort.state == "sorting" or Sort.state == "pinning") and now() - waitingSince > SETTLE_SECONDS * 4 then
        stop("the client did not finish in time")
    end
end)

------------------------------------------------------------------------
-- After the client's own sort - Blizzard's button, /sort - the same pass as /fbags sort, minus the sort
-- itself: the pouch fill (and, if anything went in, one more sort of the client's to close the gaps it
-- left), then the pins. A post-hook on C_Container.SortBags: the client's call runs first and untouched;
-- the hook only notes that a sort is in flight, and the work happens on the events that follow it. Our
-- own SortBags call is told apart by a flag. Hands off in a fight, while a run is already going, and when
-- '/fbags sort auto off' said so.
------------------------------------------------------------------------
local function pinsText()
    local pins = Sort:GetPins()
    if #pins == 0 then
        return "nothing pinned (/fbags pin <item>)"
    end
    local names = {}
    for index, pin in ipairs(pins) do
        names[index] = tostring(pin)
    end
    return "to the bottom: " .. table.concat(names, ", ")
end

local function followClientSort()
    if ownSort or not ns:GetOption("sortFollow") then
        return
    end
    if InCombatLockdown() or Sort.state == "filling" or Sort.state == "sorting" or Sort.state == "pinning" then
        return
    end
    Sort.stats.runs = Sort.stats.runs + 1
    Sort.stats.movesThisRun, Sort.stats.filledThisRun = 0, 0
    following, plan = true, nil
    ns:Log("sort_run", { from = "client", pins = #Sort:GetPins() })
    setState("sorting")
    waitingSince = now()
end

ns:Listen("LOGIN", function()
    local api = C_Container
    if type(hooksecurefunc) == "function" and type(api) == "table" and type(api.SortBags) == "function" then
        hooksecurefunc(api, "SortBags", followClientSort)
        Sort.hooked = true
    end
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns:RegisterCommand("sort", "the reagent pouch filled first, the client's sort, then the pinned items at the very bottom; 'sort auto on|off': whether the client's own sort (Blizzard's button, /sort) gets the pouch fill and the pins too (default on)", function(rest)
    local mode = string.match(string.lower(rest or ""), "^auto%s*(%a*)")
    if mode then
        if mode == "on" or mode == "off" then
            ns:SetOption("sortFollow", mode == "on")
        end
        ns:Print("sort auto:", ns:GetOption("sortFollow") and "the client's own sort is followed by the pouch fill and the pins." or "the client's own sort is left alone.",
            Sort.hooked and "" or "(This client's sort could not be hooked.)")
        return
    end
    Sort:Run("command")
end)

ns:RegisterCommand("pin", "'/fbags pin <item name or link>' keeps that item at the bottom of the bag after a sort; 'pins' lists; 'unpin <item>' forgets", function(rest)
    local pin = normalisePin(rest)
    if not pin then
        ns:Print("pinned: " .. pinsText())
        return
    end
    local list = {}
    for _, existing in ipairs(Sort:GetPins()) do
        if tostring(existing) ~= tostring(pin) and not (type(existing) == "string" and type(pin) == "string"
            and string.lower(existing) == string.lower(pin)) then
            list[#list + 1] = existing
        end
    end
    list[#list + 1] = pin
    ns:SetOption("pins", list)
    ns:Print("pinned: " .. pinsText())
end)

ns:RegisterCommand("unpin", "forget a pinned item", function(rest)
    local pin = normalisePin(rest)
    if not pin then
        ns:Print("usage: /fbags unpin <item name or link>")
        return
    end
    local list, dropped = {}, false
    for _, existing in ipairs(Sort:GetPins()) do
        local same = tostring(existing) == tostring(pin) or (type(existing) == "string" and type(pin) == "string"
            and string.lower(existing) == string.lower(pin))
        if same then
            dropped = true
        else
            list[#list + 1] = existing
        end
    end
    ns:SetOption("pins", list)
    ns:Print(dropped and ("unpinned. " .. pinsText()) or ("that was not pinned. " .. pinsText()))
end)

ns:RegisterCommand("pins", "list the pinned items", function()
    ns:Print(pinsText())
end)

function Sort:Report()
    local family, free = pouchFamily()
    return { state = self.state, stats = self.stats, pins = self:GetPins(), hooked = self.hooked,
        follow = ns:GetOption("sortFollow") and true or false,
        pouch = family and { family = family, free = free } or "none" }
end
