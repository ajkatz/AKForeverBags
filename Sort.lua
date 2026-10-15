-- Sort: a sort button where Blizzard's would be, and after the client's own sort, the items you asked
-- for pinned to the very bottom of the bag.
--
-- WHY. Blizzard's combined bag window has a sort button (BagItemAutoSortButton) at its top right, next
-- to the search box. MEASURED 2026-10-14 on this client: the button is there - shown, visible, parented,
-- 28 x 26 at TOPRIGHT -9, -34 - and draws nothing, with or without addons: its atlas
-- (bags-button-autosort-up) is missing here. So this addon puts a button of its own on that spot, drawn
-- from file textures that do exist, and it does what Blizzard's does: C_Container.SortBags().
--
-- THEN the pinning. "I like my totems at the very bottom of my bag." Blizzard's sort has its own idea of
-- order and no way to ask for one item last. So once its sort has settled (BAG_UPDATE_DELAYED), the items
-- on the pin list are moved into the bottom-right cells of the combined view - visually the bottom, in
-- either /fbags order - one swap at a time, each one waited out (items lock while they move), using
-- nothing but the client's own item-moving calls on plain bag and slot numbers. The bag window's grid
-- (Reagents.lua reads it from the buttons' anchors) says which bag slot each bottom cell is.
--
-- RULES, as everywhere in this addon: no Blizzard Lua is called, nothing is written on Blizzard's
-- frames; our button is a child of the window (it comes and goes with it), like the fold arrow.
-- C_Container.SortBags / PickupContainerItem / GetContainerItemInfo carry no restriction in the API
-- docs; their only flag is about SECRET arguments, and bag and slot numbers of ours are not secret.
-- Nothing runs in combat, and nothing starts while the cursor holds something.
local _, ns = ...

local Sort = {}
ns.Sort = Sort

-- On the left, in the blank title bar above the search box (the window is a PortraitFrameFlatTemplate;
-- the band above the search box is its title bar, 37 high and empty on this window): at the search
-- box's own x, so the two line up, centred in the band.
local BUTTON_W, BUTTON_H = 34, 22
local BUTTON_POINT = { "TOPLEFT", "TOPLEFT", 62, -7 }
local REAGENT_BAG = 5
-- Blizzard's classic panel button: the 80 x 22 art sits in the top left of a 128 x 32 file
local PANEL_BUTTON = { up = "Interface\\Buttons\\UI-Panel-Button-Up", down = "Interface\\Buttons\\UI-Panel-Button-Down",
    highlight = "Interface\\Buttons\\UI-Panel-Button-Highlight", coords = { 0, 0.625, 0, 0.6875 } }
local BAGS = { 0, 1, 2, 3, 4 }             -- the bags the combined window shows
local MAX_MOVES = 24                       -- a bound, not a budget
local SETTLE_SECONDS = 1.5                 -- how long to wait for the client between steps before giving up

-- what a shaman carries that belongs at the bottom; anything else is a `/fbags pin`
local CLASS_PINS = {
    SHAMAN = { "Earth Totem", "Fire Totem", "Water Totem", "Air Totem" },
}

Sort.state = "idle"        -- idle | filling | sorting | pinning | done | stopped: <why>
Sort.stats = { runs = 0, moves = 0, stopped = 0, movesThisRun = 0, filled = 0 }
local button
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

-- every pinned item in the bags, in PIN ORDER (the first pin ends up at the very bottom right)
local function findPinned()
    local pins = Sort:GetPins()
    local found = {}
    for _, pin in ipairs(pins) do
        for _, bag in ipairs(BAGS) do
            for slot = 1, slotsIn(bag) do
                local info, why = itemAt(bag, slot)
                if info == nil and why then
                    return nil, why
                end
                if info and pinMatches(pin, info) then
                    found[#found + 1] = { bag = bag, slot = slot, itemID = info.itemID, name = info.itemName, locked = info.isLocked }
                end
            end
        end
    end
    return found
end

------------------------------------------------------------------------
-- The bottom cells: which bag slot sits at each, from the window's grid
------------------------------------------------------------------------
local function bottomCells(count)
    local reagents = ns.Reagents
    if not reagents or type(reagents.BottomCells) ~= "function" then
        return nil, "the bag window's grid is not known"
    end
    local cells, why = reagents:BottomCells(count)
    if not cells then
        return nil, why or "the bag window's grid is not known"
    end
    return cells
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

-- Work out what is still out of place. Re-done after every move, because a swap moves two things.
local function makePinPlan()
    local pinned, why = findPinned()
    if not pinned then
        return nil, why
    end
    if #pinned == 0 then
        return {}
    end
    local cells, cellsWhy = bottomCells(#pinned)
    if not cells then
        return nil, cellsWhy
    end
    -- An item that is locked is mid-move: the client has not landed it yet. It is waited for, not
    -- picked up again - and so is a target slot whose occupant is locked.
    local moves, waiting = {}, false
    for index, item in ipairs(pinned) do
        local target = cells[index]
        if target and not (target.bag == item.bag and target.slot == item.slot) then
            local occupant, occupantWhy = itemAt(target.bag, target.slot)
            if occupant == nil and occupantWhy then
                return nil, occupantWhy
            end
            if item.locked or (occupant and occupant.isLocked) then
                waiting = true
            else
                moves[#moves + 1] = { from = { bag = item.bag, slot = item.slot }, to = target, name = item.name }
            end
        end
    end
    return moves, waiting
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
    if not ok2 then
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
    local ok = pcall(api.SortBags)
    if not ok then
        return stop("SortBags raised")
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
    local moves, why
    if Sort.state == "filling" then
        moves, why = makeFillPlan()
    else
        moves, why = makePinPlan()
    end
    if not moves then
        stepping = false
        return stop(why)
    end
    if #moves == 0 then
        stepping = false
        if why then
            return -- something is still landing: the next lock change or BAG_UPDATE_DELAYED comes back here
        end
        if Sort.state == "filling" then
            return startClientSort() -- the pouch is as full as it gets: now the client's own sort
        end
        plan, waitingSince = nil, nil
        setState("done")
        return
    end
    if Sort.stats.movesThisRun >= MAX_MOVES then
        stepping = false
        return stop("more moves than any pin list should need - something is fighting back")
    end
    Sort.stats.movesThisRun = Sort.stats.movesThisRun + 1
    local ok, moveWhy = doMove(moves[1])
    stepping = false
    if not ok then
        return stop(moveWhy)
    end
    if moves[1].fill then
        Sort.stats.filled = Sort.stats.filled + 1
    end
    waitingSince = now()
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
    Sort.stats.movesThisRun = 0
    ns:Log("sort_run", { from = from or "?", pins = #self:GetPins() })
    setState("filling")
    waitingSince = now()
    step() -- the pouch first; when it has nothing left to take, the client's sort
    return true
end

-- Blizzard's sort, and every move of ours, ends in BAG_UPDATE_DELAYED
ns:On("BAG_UPDATE_DELAYED", function()
    if Sort.state == "sorting" then
        setState("pinning")
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
-- The button, on Blizzard's spot. A child of the combined window, like the fold arrow: it shows, hides
-- and scales with the bags by itself. Two arrows from file textures that exist on this client.
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

function Sort:EnsureButton()
    if button then
        return button
    end
    local window = _G.ContainerFrameCombinedBags
    if type(window) ~= "table" then
        return nil
    end
    button = CreateFrame("Button", "AKForeverBagsSortButton", window)
    button:SetSize(BUTTON_W, BUTTON_H)
    button:SetPoint(BUTTON_POINT[1], window, BUTTON_POINT[2], BUTTON_POINT[3], BUTTON_POINT[4])
    -- Well above the window's own children: the reagent-slot backdrop (window-sized, level + 1), and in
    -- the title bar the template's title container and the click-router button Blizzard anchors across
    -- it - either of which drew over a button at level + 3 (2026-10-14: "now I don^t see the sort button").
    local level = ns.Readable(window.GetFrameLevel, window)
    if level and type(level[1]) == "number" then
        button:SetFrameLevel(level[1] + 10)
    end
    -- the classic panel button, drawn from Blizzard's own files: a gold border, no colour of ours over
    -- the window. (A client without one of these methods simply gets the word on its own.)
    local coords = PANEL_BUTTON.coords
    local function state(setter, getter, file, blend)
        if type(button[setter]) ~= "function" then
            return
        end
        if blend then
            button[setter](button, file, blend)
        else
            button[setter](button, file)
        end
        local texture = type(button[getter]) == "function" and button[getter](button)
        if type(texture) == "table" and type(texture.SetTexCoord) == "function" then
            texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
    end
    state("SetNormalTexture", "GetNormalTexture", PANEL_BUTTON.up)
    state("SetPushedTexture", "GetPushedTexture", PANEL_BUTTON.down)
    state("SetHighlightTexture", "GetHighlightTexture", PANEL_BUTTON.highlight, "ADD")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 1)
    button.label:SetText("Sort")
    button:SetScript("OnClick", function()
        Sort:Run("button")
    end)
    button:SetScript("OnEnter", function(self)
        if type(GameTooltip) == "table" and type(GameTooltip.SetOwner) == "function" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Sort bags", 1, 0.82, 0)
            GameTooltip:AddLine(pinsText(), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then
            GameTooltip:Hide()
        end
    end)
    return button
end

ns:On("PLAYER_ENTERING_WORLD", function()
    Sort:EnsureButton()
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns:RegisterCommand("sort", "sort the bags (Blizzard's sort), then put the pinned items at the very bottom", function()
    Sort:EnsureButton()
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
    return { state = self.state, stats = self.stats, pins = self:GetPins(), button = button ~= nil,
        pouch = family and { family = family, free = free } or "none" }
end
