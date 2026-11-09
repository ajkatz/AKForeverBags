-- Offspec: gear you keep for another spec, marked with one key and sorted into a group of its own.
--
-- WHY. "I'd like to be able to easily mark a gear as offspec / gear to keep and sort it at the bottom /
-- separate" (the user, 2026-11-08). Choices made with the user: a KEY over the item (Key Bindings >
-- AddOns > AKForeverBags) marks or unmarks it - a click on the item itself would mean hooking Blizzard's
-- bag buttons, which this addon never does; the marked items sort into their own group right ABOVE the
-- pins (the totems keep the very bottom), each with a coloured border so the group stands out; and a mark
-- is the ITEM (its item id): every copy counts, and it survives the bank and the mailbox.
--
-- HOW. The key reads what is under the mouse (GetMouseFoci); a bag item button answers GetBagID() and
-- GetID() - read only, as Sort.lua reads the grid - and the client's GetContainerItemInfo says which item
-- sits there. The marks are saved per character (option "offspec": item id -> name). The sort's pin pass
-- (Sort.lua) puts the marked items into the cells right after the pinned ones, a stable move like the
-- pins. The borders are textures of OURS on a frame of ours (a child of the combined bag window, drawn
-- above its item buttons, never taking the mouse), anchored to the buttons that hold a marked item; they
-- are put right after every layout pass, every BAG_UPDATE_DELAYED and every change of the marks - and
-- cost nothing while nothing is marked. Without a key binding: the mark-mode button hanging under the bag
-- window's bottom-left corner (see "Mark mode" below).
local _, ns = ...

local Offspec = {}
ns.Offspec = Offspec

local BORDER = { 0.72, 0.42, 1.00, 0.95 } -- violet: not a quality colour, not the reagent slots' green
local THICK = 2
local BAGS = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true } -- the ordinary bags the sort works on

local holder          -- our frame on the combined bag window, created on first need
local borders = {}    -- pool: { top, bottom, left, right }
local shownCount = 0  -- borders shown right now

------------------------------------------------------------------------
-- The marks
------------------------------------------------------------------------
local function marks()
    local saved = ns:GetOption("offspec")
    return type(saved) == "table" and saved or {}
end

function Offspec:IsMarked(itemID)
    return type(itemID) == "number" and marks()[itemID] ~= nil
end

function Offspec:Count()
    local count = 0
    for _ in pairs(marks()) do
        count = count + 1
    end
    return count
end

-- toggles the mark of an item; returns true when it is now marked
function Offspec:Toggle(itemID, name)
    local copy = {}
    for id, saved in pairs(marks()) do
        copy[id] = saved
    end
    local nowMarked = copy[itemID] == nil
    copy[itemID] = nowMarked and (name or tostring(itemID)) or nil
    ns:SetOption("offspec", copy)
    ns:Log("offspec", { item = itemID, marked = nowMarked })
    return nowMarked
end

------------------------------------------------------------------------
-- The key: the bag slot under the mouse
------------------------------------------------------------------------
local function mouseFocus()
    if type(GetMouseFoci) == "function" then
        local answer = ns.Readable(GetMouseFoci)
        local foci = answer and answer[1]
        return type(foci) == "table" and foci[1] or nil
    end
    if type(GetMouseFocus) == "function" then
        local answer = ns.Readable(GetMouseFocus)
        return answer and answer[1]
    end
    return nil
end

-- bag, slot of the bag item button under the mouse, or nil
local function slotUnderMouse()
    local focus = mouseFocus()
    if type(focus) ~= "table" or type(focus.GetBagID) ~= "function" or type(focus.GetID) ~= "function" then
        return nil
    end
    local bag = ns.Readable(focus.GetBagID, focus)
    local slot = ns.Readable(focus.GetID, focus)
    bag, slot = bag and bag[1], slot and slot[1]
    if type(bag) ~= "number" or type(slot) ~= "number" then
        return nil
    end
    return bag, slot
end

local function itemInfo(bag, slot)
    local api = C_Container
    if type(api) ~= "table" or type(api.GetContainerItemInfo) ~= "function" then
        return nil
    end
    local answer = ns.Readable(api.GetContainerItemInfo, bag, slot)
    local info = answer and answer[1]
    if type(info) ~= "table" or ns.IsSecret(info.itemID) or type(info.itemID) ~= "number" then
        return nil
    end
    return info
end

function Offspec:MarkUnderMouse()
    local bag, slot = slotUnderMouse()
    if not bag then
        ns:Print("offspec: hold the mouse over an item in your bags, then press the key.")
        return
    end
    local info = itemInfo(bag, slot)
    if not info then
        ns:Print("offspec: there is no item in that slot.")
        return
    end
    local name = type(info.itemName) == "string" and not ns.IsSecret(info.itemName) and info.itemName or nil
    local link = type(info.hyperlink) == "string" and not ns.IsSecret(info.hyperlink) and info.hyperlink or name or ("item " .. info.itemID)
    if self:Toggle(info.itemID, name) then
        ns:Print(link .. " marked offspec - it sorts above the pinned items at the bottom (mark it again to unmark).")
    else
        ns:Print(link .. " is no longer offspec.")
    end
end

-- the key binding (Bindings.xml)
BINDING_HEADER_AKFOREVERBAGS = "AKForeverBags"
BINDING_NAME_AKFOREVERBAGS_OFFSPEC = "Mark / unmark the item under the mouse as offspec"
function AKForeverBags_ToggleOffspec()
    ns.SafeCall(Offspec.MarkUnderMouse, Offspec)
end

------------------------------------------------------------------------
-- The borders
------------------------------------------------------------------------
local function ensureHolder(combined)
    if holder then
        return holder
    end
    holder = CreateFrame("Frame", "AKForeverBagsOffspecMarks", combined)
    holder:SetAllPoints(combined)
    if holder.EnableMouse then
        holder:EnableMouse(false)
    end
    return holder
end

local function border(index)
    local item = borders[index]
    if not item then
        item = {}
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            local texture = holder:CreateTexture(nil, "OVERLAY")
            texture:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
            item[side] = texture
        end
        borders[index] = item
    end
    return item
end

local function place(item, button)
    item.top:ClearAllPoints()
    item.top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    item.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    item.top:SetHeight(THICK)
    item.bottom:ClearAllPoints()
    item.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    item.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    item.bottom:SetHeight(THICK)
    item.left:ClearAllPoints()
    item.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    item.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    item.left:SetWidth(THICK)
    item.right:ClearAllPoints()
    item.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    item.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    item.right:SetWidth(THICK)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        item[side]:Show()
    end
end

local function hideFrom(first)
    for index = first, #borders do
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            borders[index][side]:Hide()
        end
    end
end

function Offspec:Refresh()
    if shownCount == 0 and next(marks()) == nil then
        return -- nothing marked, nothing drawn: no work at all
    end
    local combined = _G.ContainerFrameCombinedBags
    local open = type(combined) == "table" and combined.IsShown and ns.Readable(combined.IsShown, combined)
    local cells = open and open[1] == true and ns.Reagents and ns.Reagents.Cells and ns.Reagents:Cells()
    if not cells then
        hideFrom(1)
        shownCount = 0
        return
    end
    ensureHolder(combined)
    local count, level = 0, nil
    for _, cell in ipairs(cells) do
        if cell.button and BAGS[cell.bag] then
            local info = itemInfo(cell.bag, cell.slot)
            if info and self:IsMarked(info.itemID) then
                count = count + 1
                place(border(count), cell.button)
                if not level then
                    local answer = ns.Readable(cell.button.GetFrameLevel, cell.button)
                    level = answer and type(answer[1]) == "number" and answer[1] or nil
                end
            end
        end
    end
    if level then
        holder:SetFrameLevel(level + 2) -- above the item buttons: a border over the icon, not behind it
    end
    hideFrom(count + 1)
    shownCount = count
end

local function refresh()
    ns.SafeCall(Offspec.Refresh, Offspec)
end

------------------------------------------------------------------------
-- Mark mode: a button of ours hanging under the bag window's bottom-left corner - like a tab, the way the
-- docked bag bar hangs under its right end; inside, the bottom left is the money row's (the user,
-- 2026-11-08: it sat under the gold display) - for marking without a key binding (the
-- user, 2026-11-08: "a toggle in the bag area that allows you to mark an item without having to
-- keybind"). Click it: mark mode is on (the button glows violet). A plain left-click on an item then
-- marks or unmarks it. That click still reaches Blizzard's item button - nothing of ours covers or hooks
-- it - so the client picks the item up; the mark is made on GLOBAL_MOUSE_DOWN, and on GLOBAL_MOUSE_UP
-- (and once more a frame later, as the order of the event and Blizzard's OnClick is the client's secret)
-- the cursor is cleared if it holds that very item, which puts it straight back in its slot. A click
-- with a modifier, a right-click, or one while the cursor already holds something is left alone. The
-- button again, or the bag window closing, ends mark mode.
------------------------------------------------------------------------
-- A closed padlock says "kept gear" (the user chose it, 2026-11-08, over crossed swords). The client's own
-- lock atlases first - asked for by name, so one this client lacks is simply skipped - then the padlock
-- file every client since the first has carried.
local MODE_ATLASES = { "AdventureMapIcon-Lock", "Forge-Lock" }
local MODE_FILE = "Interface\\Buttons\\LockButton-Locked-Up"

local function setPadlock(texture)
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo
    if type(atlasInfo) == "function" and type(texture.SetAtlas) == "function" then
        for _, atlas in ipairs(MODE_ATLASES) do
            local answer = ns.Readable(atlasInfo, atlas)
            if answer and type(answer[1]) == "table" then
                texture:SetAtlas(atlas)
                return atlas
            end
        end
    end
    texture:SetTexture(MODE_FILE)
    return MODE_FILE
end
local modeButton
local pressedItem -- the item marked by the left button that is down right now
Offspec.markMode = false

local function cursorItem()
    if type(GetCursorInfo) ~= "function" then
        return nil
    end
    local answer = ns.Readable(GetCursorInfo)
    if not answer then
        return nil
    end
    return answer[1], answer[2]
end

local function paintModeButton()
    if not modeButton then
        return
    end
    if Offspec.markMode then
        modeButton.glow:Show()
    else
        modeButton.glow:Hide()
    end
end

function Offspec:SetMarkMode(on)
    on = on and true or false
    if self.markMode == on then
        return
    end
    self.markMode = on
    pressedItem = nil
    paintModeButton()
    ns:Log("offspec_mode", on)
    if on then
        ns:Print("offspec mark mode: left-click items in your bags to mark or unmark them; the button again ends it.")
    end
end

local function ensureModeButton(combined)
    if modeButton then
        return modeButton
    end
    modeButton = CreateFrame("Button", "AKForeverBagsOffspecMode", combined)
    modeButton:SetSize(18, 18)
    modeButton:SetPoint("TOPLEFT", combined, "BOTTOMLEFT", 4, -2) -- under the window, never on anything in it
    modeButton.icon = modeButton:CreateTexture(nil, "ARTWORK")
    modeButton.icon:SetAllPoints(modeButton)
    modeButton.iconName = setPadlock(modeButton.icon)
    modeButton.glow = modeButton:CreateTexture(nil, "OVERLAY")
    modeButton.glow:SetPoint("TOPLEFT", modeButton, "TOPLEFT", -3, 3)
    modeButton.glow:SetPoint("BOTTOMRIGHT", modeButton, "BOTTOMRIGHT", 3, -3)
    modeButton.glow:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 0.45)
    modeButton.glow:Hide()
    modeButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    modeButton:SetScript("OnClick", function()
        Offspec:SetMarkMode(not Offspec.markMode)
    end)
    modeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Offspec.markMode and "Offspec mark mode: on" or "Offspec mark mode")
        GameTooltip:AddLine(Offspec.markMode and "Left-click items to mark or unmark them. Click here to finish."
            or "Click, then left-click items to mark them as offspec: after a sort they stand together above the pinned items.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Marked: " .. Offspec:Count() .. " (AKForeverBags)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    modeButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    paintModeButton()
    return modeButton
end

-- comes and goes with the bag window (a child of it); the window closing ends mark mode
local function updateModeButton()
    local combined = _G.ContainerFrameCombinedBags
    local open = type(combined) == "table" and combined.IsShown and ns.Readable(combined.IsShown, combined)
    if open and open[1] == true then
        ensureModeButton(combined):Show()
    else
        Offspec:SetMarkMode(false)
    end
end

local function putBack(itemID)
    local kind, held = cursorItem()
    if kind == "item" and held == itemID and type(ClearCursor) == "function" then
        pcall(ClearCursor) -- an item on the cursor goes back where it came from
    end
end

ns:On("GLOBAL_MOUSE_DOWN", function(_, mouseButton)
    if not Offspec.markMode or mouseButton ~= "LeftButton" then
        return
    end
    if type(IsModifierKeyDown) == "function" and IsModifierKeyDown() then
        return -- shift-click links, ctrl-click previews: Blizzard's
    end
    if cursorItem() ~= nil then
        return -- a hand already full: this click is a drop, not a mark
    end
    local bag, slot = slotUnderMouse()
    local info = bag and itemInfo(bag, slot)
    if not info then
        return
    end
    pressedItem = info.itemID
    Offspec:MarkUnderMouse()
end)

ns:On("GLOBAL_MOUSE_UP", function(_, mouseButton)
    if mouseButton ~= "LeftButton" or not pressedItem then
        return
    end
    local itemID = pressedItem
    pressedItem = nil
    putBack(itemID)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            putBack(itemID)
        end)
    end
end)

ns:Listen("LAID_OUT", function()
    ns.SafeCall(updateModeButton)
end)
ns:Listen("LAID_OUT", refresh)
ns:On("BAG_UPDATE_DELAYED", refresh)
ns:Listen("OPTION_CHANGED", function(_, key)
    if key == "offspec" then
        refresh()
    end
end)

------------------------------------------------------------------------
-- The command: the list, and a way to start over
------------------------------------------------------------------------
ns:RegisterCommand("offspec", "lists the items marked offspec (bind 'Mark / unmark the item under the mouse' in Key Bindings > AddOns to mark one); 'offspec clear' unmarks them all", function(rest)
    if string.lower(rest or "") == "clear" then
        ns:SetOption("offspec", {})
        ns:Print("offspec: nothing is marked any more.")
        return
    end
    local names = {}
    for id, name in pairs(marks()) do
        names[#names + 1] = tostring(name) .. " (" .. tostring(id) .. ")"
    end
    table.sort(names)
    if #names == 0 then
        ns:Print("offspec: nothing marked. Bind the key in Key Bindings > AddOns > AKForeverBags, hold the mouse over an item in your bags and press it.")
        return
    end
    ns:Print("offspec (" .. #names .. "): " .. table.concat(names, ", "))
end)

function Offspec:Report()
    return { marked = self:Count(), borders = shownCount, markMode = self.markMode, button = modeButton ~= nil,
        icon = modeButton and modeButton.iconName or nil }
end
