-- Labels: every item in the bags can carry a label, and a sort stacks the labels in groups of their own.
--
-- WHY. It began as one mark, "offspec" ("I'd like to be able to easily mark a gear as offspec / gear to
-- keep and sort it at the bottom / separate" - the user, 2026-11-08). Then, the same day: wearing the
-- offspec, the mainspec gear got mixed in with everything else - "maybe instead we have a label system:
-- main spec, off spec, consumables, permanent inventory (totems), trade items, more?". Chosen with the user:
--   * EIGHT LABELS, stacked from the bottom up: Permanent (the pinned totems at the very bottom), Profession
--     tools, Main spec, Off spec, Trade goods, Consumables, Quest items; then everything unlabelled, as the
--     sort left it; Junk (greys) at the very top, handy for selling.
--   * SOME LABEL THEMSELVES, from the item alone (GetItemInfoInstant's class, the slot's quality): trade goods
--     (class 7), consumables (class 0), quest items (class 12), junk (poor quality), profession tools (a
--     list of the old tools, and fishing poles by subclass), and Permanent from the pin list (Sort.lua).
--     Main spec and Off spec are only ever set by hand. A label set by hand always wins - "No label" too,
--     which keeps an item out of its automatic group. '/fbags labels auto off' turns the automatic ones off.
--   * LABELLING: the padlock button under the bag window opens a short list of the labels; pick one and mark
--     mode is on for it (the button glows in the label's colour) - every plain left-click on an item gives it
--     that label, and clicking an item that already has it takes it off again. The key binding (Key Bindings
--     > AddOns) does the same for the item under the mouse, with the label picked last (Off spec at first).
--   * A label is the ITEM (its item id): every copy counts, and it survives the bank and the mailbox.
--
-- HOW. Nothing of Blizzard's is hooked, covered or called beyond reading: a bag item button answers
-- GetBagID()/GetID(), the client's GetContainerItemInfo says what sits there. The hand-set labels are saved
-- per character (option "labels": item id -> { label, name }). The sort's last pass (Sort.lua) puts the
-- groups in place as one stable move. The labels you set by hand get a border in the label's colour, and
-- so do trade goods and quest items when they label themselves (the user, 2026-11-08: "can quest items and
-- trade goods be automatically marked and color coded?"; the other automatic groups go without - a potion
-- looks like a potion, and a grey is grey already) - textures of OURS on a frame of ours above the item
-- buttons, never taking the mouse; the borders cost nothing while nothing is labelled by hand and the
-- automatic labels are off.
--
-- MARK MODE AND THE CLICK. The click still reaches Blizzard's item button, so the client picks the item up;
-- the label is set on GLOBAL_MOUSE_DOWN, and on GLOBAL_MOUSE_UP (and once more a frame later, as the order
-- of the event and Blizzard's OnClick is the client's secret) the cursor is cleared if it holds that very
-- item, which puts it straight back in its slot (proven in game 2026-11-08). A click with a modifier, a
-- right-click, or one while the cursor already holds something is left alone. The padlock again, or the
-- bag window closing, ends mark mode.
local _, ns = ...

local Labels = {}
ns.Labels = Labels

-- the order IS the stacking order, bottom up; "top" ones go above the unlabelled items
Labels.LIST = {
    { key = "permanent",  name = "Permanent",        color = { 0.85, 0.85, 0.85 } },
    { key = "tools",      name = "Profession tools", color = { 0.80, 0.55, 0.30 } },
    { key = "main",       name = "Main spec",        color = { 1.00, 0.82, 0.00 } },
    { key = "off",        name = "Off spec",         color = { 0.72, 0.42, 1.00 } },
    { key = "trade",      name = "Trade goods",      color = { 0.30, 0.80, 0.90 }, autoBorder = true },
    { key = "consumable", name = "Consumables",      color = { 1.00, 0.45, 0.60 } },
    { key = "quest",      name = "Quest items",      color = { 1.00, 0.60, 0.15 }, autoBorder = true },
    { key = "junk",       name = "Junk",             color = { 0.55, 0.55, 0.55 }, top = true },
}
Labels.NONE = "none" -- set by hand: no label, not even an automatic one
local BY_KEY = {}
for index, label in ipairs(Labels.LIST) do
    label.order = index
    BY_KEY[label.key] = label
end
local NONE_LABEL = { key = Labels.NONE, name = "No label", color = { 0.35, 0.35, 0.35 } }

local THICK = 2
local BAGS = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true } -- the ordinary bags the sort works on

-- the old world's profession tools (item ids), and the fishing pole subclass of weapons
local TOOLS = {
    [2901] = true,  -- Mining Pick
    [7005] = true,  -- Skinning Knife
    [5956] = true,  -- Blacksmith Hammer
    [6219] = true,  -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [6218] = true,  -- Runed Copper Rod
    [6339] = true,  -- Runed Silver Rod
    [11130] = true, -- Runed Golden Rod
    [11145] = true, -- Runed Truesilver Rod
    [16207] = true, -- Runed Arcanite Rod
    [9149] = true,  -- Philosopher's Stone
    [4471] = true,  -- Flint and Tinder
    [6256] = true,  -- Fishing Pole
}
local CLASS_CONSUMABLE, CLASS_WEAPON, CLASS_TRADE, CLASS_QUEST = 0, 2, 7, 12
local SUBCLASS_FISHING_POLE = 20
local QUALITY_POOR = 0

local holder          -- our frame on the combined bag window, created on first need
local borders = {}    -- pool: { top, bottom, left, right }
local shownCount = 0  -- borders shown right now
local classCache = {} -- [itemID] = { classID, subclassID } | false

------------------------------------------------------------------------
-- The labels set by hand
------------------------------------------------------------------------
local function manual()
    local saved = ns:GetOption("labels")
    return type(saved) == "table" and saved or {}
end

function Labels:Get(key)
    return BY_KEY[key] or (key == self.NONE and NONE_LABEL) or nil
end

-- the label set by hand for an item: a key, "none", or nil
function Labels:Manual(itemID)
    local entry = type(itemID) == "number" and manual()[itemID]
    return type(entry) == "table" and entry.label or nil
end

function Labels:Count()
    local count = 0
    for _ in pairs(manual()) do
        count = count + 1
    end
    return count
end

-- sets (or with key nil, removes) the label set by hand
function Labels:Set(itemID, key, name)
    local copy = {}
    for id, entry in pairs(manual()) do
        copy[id] = entry
    end
    copy[itemID] = key and { label = key, name = name or tostring(itemID) } or nil
    ns:SetOption("labels", copy)
    ns:Log("label", { item = itemID, label = key or "auto" })
end

-- the 0.5.0 working copies' offspec marks become Off spec labels, once
local function migrate()
    local old = ns:GetOption("offspec")
    if type(old) ~= "table" or next(old) == nil then
        return
    end
    local copy = {}
    for id, entry in pairs(manual()) do
        copy[id] = entry
    end
    for id, name in pairs(old) do
        if type(id) == "number" and copy[id] == nil then
            copy[id] = { label = "off", name = tostring(name) }
        end
    end
    ns.cdb.options.offspec = nil
    ns:SetOption("labels", copy)
    ns:Log("labels_migrated", "offspec")
end
ns:Listen("LOGIN", function()
    ns.SafeCall(migrate)
end)

------------------------------------------------------------------------
-- The labels that set themselves
------------------------------------------------------------------------
local function classOf(itemID)
    local cached = classCache[itemID]
    if cached ~= nil then
        return cached
    end
    local instant = (type(C_Item) == "table" and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(instant) ~= "function" then
        return false
    end
    -- the class is the 6th answer, past what ns.Readable keeps
    local ok, _, _, _, _, _, classID, subclassID = pcall(instant, itemID)
    if not ok or ns.AnySecret(classID, subclassID) or type(classID) ~= "number" then
        return false -- not known (yet): no automatic label, and asked again next time
    end
    cached = { classID, subclassID }
    classCache[itemID] = cached
    return cached
end

local function automatic(info)
    if ns.Sort and ns.Sort.IsPinned and ns.Sort:IsPinned(info) then
        return "permanent"
    end
    if not ns:GetOption("labelsAuto") then
        return nil
    end
    local itemID = info.itemID
    if TOOLS[itemID] then
        return "tools"
    end
    local quality = info.quality
    if type(quality) == "number" and not ns.IsSecret(quality) and quality == QUALITY_POOR then
        return "junk"
    end
    local class = classOf(itemID)
    if not class then
        return nil
    end
    if class[1] == CLASS_WEAPON and class[2] == SUBCLASS_FISHING_POLE then
        return "tools"
    end
    if class[1] == CLASS_TRADE then
        return "trade"
    end
    if class[1] == CLASS_CONSUMABLE then
        return "consumable"
    end
    if class[1] == CLASS_QUEST then
        return "quest"
    end
    return nil
end

-- an item's label (a key of LIST) or nil: the one set by hand, else the automatic one
function Labels:Of(info)
    if type(info) ~= "table" or type(info.itemID) ~= "number" then
        return nil
    end
    local set = self:Manual(info.itemID)
    if set == self.NONE then
        return nil
    end
    if set and BY_KEY[set] then
        return set
    end
    return automatic(info)
end

------------------------------------------------------------------------
-- The bag slot under the mouse
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

Labels.active = "off" -- the label mark mode and the key give; the one picked last

-- gives the item under the mouse the active label, or takes it off when it already has it
function Labels:LabelUnderMouse()
    local bag, slot = slotUnderMouse()
    if not bag then
        ns:Print("labels: hold the mouse over an item in your bags, then press the key.")
        return
    end
    local info = itemInfo(bag, slot)
    if not info then
        ns:Print("labels: there is no item in that slot.")
        return
    end
    local name = type(info.itemName) == "string" and not ns.IsSecret(info.itemName) and info.itemName or nil
    local link = type(info.hyperlink) == "string" and not ns.IsSecret(info.hyperlink) and info.hyperlink or name or ("item " .. info.itemID)
    local active = self:Get(self.active) or BY_KEY.off
    if self:Manual(info.itemID) == active.key then
        self:Set(info.itemID, nil)
        local now = self:Get(self:Of(info))
        ns:Print(link .. " is no longer labelled " .. active.name .. (now and (" - back to " .. now.name .. ".") or "."))
    else
        self:Set(info.itemID, active.key, name)
        if active.key == self.NONE then
            ns:Print(link .. ": no label - it stays with the unlabelled items (again to undo).")
        else
            ns:Print(link .. " labelled " .. active.name .. " (again to undo).")
        end
    end
end

-- the key binding (Bindings.xml; the binding's name stays from 0.5.0's working copies)
BINDING_HEADER_AKFOREVERBAGS = "AKForeverBags"
BINDING_NAME_AKFOREVERBAGS_OFFSPEC = "Label the item under the mouse (with the label picked last; Off spec at first)"
function AKForeverBags_ToggleOffspec()
    ns.SafeCall(Labels.LabelUnderMouse, Labels)
end

------------------------------------------------------------------------
-- The borders: on the labels set by hand
------------------------------------------------------------------------
local function ensureHolder(combined)
    if holder then
        return holder
    end
    holder = CreateFrame("Frame", "AKForeverBagsLabelMarks", combined)
    holder:SetAllPoints(combined)
    if holder.EnableMouse then
        holder:EnableMouse(false)
    end
    return holder
end

local SIDES = { "top", "bottom", "left", "right" }

local function border(index)
    local item = borders[index]
    if not item then
        item = {}
        for _, side in ipairs(SIDES) do
            item[side] = holder:CreateTexture(nil, "OVERLAY")
        end
        borders[index] = item
    end
    return item
end

local function place(item, button, color)
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
    for _, side in ipairs(SIDES) do
        item[side]:SetColorTexture(color[1], color[2], color[3], 0.95)
        item[side]:Show()
    end
    item.color, item.button = color, button
end

-- the borders shown now: { button, color } each (for the report and the tests)
function Labels.borderList()
    local out = {}
    for index = 1, shownCount do
        out[index] = { button = borders[index].button, color = borders[index].color }
    end
    return out
end

local function hideFrom(first)
    for index = first, #borders do
        for _, side in ipairs(SIDES) do
            borders[index][side]:Hide()
        end
    end
end

-- the label whose border an item wears, or nil: a hand-set label, or trade goods / quest items by themselves
function Labels:BorderOf(info)
    local key = info and self:Of(info)
    local label = key and BY_KEY[key]
    if label and (label.autoBorder or self:Manual(info.itemID) == key) then
        return label
    end
    return nil -- an automatic label without a border of its own (a potion, a grey, a pin)
end

-- the bag slots whose items wear a border: { ["bag:slot"] = label } and how many - asked of the
-- container API alone, so empty bags or bags with nothing to border read none of Blizzard's frames
local function bordered()
    local api = C_Container
    local found, count = {}, 0
    if type(api) ~= "table" or type(api.GetContainerNumSlots) ~= "function" then
        return found, 0
    end
    for bag in pairs(BAGS) do
        local slots = ns.Readable(api.GetContainerNumSlots, bag)
        slots = slots and type(slots[1]) == "number" and slots[1] or 0
        for slot = 1, slots do
            local label = Labels:BorderOf(itemInfo(bag, slot))
            if label then
                found[bag .. ":" .. slot] = label
                count = count + 1
            end
        end
    end
    return found, count
end

function Labels:Refresh()
    if shownCount == 0 and next(manual()) == nil and not ns:GetOption("labelsAuto") then
        return -- nothing labelled by hand, no automatic borders, nothing drawn: no work at all
    end
    local wanted, wantedCount = bordered()
    if wantedCount == 0 and shownCount == 0 then
        return -- nothing to border: not one of Blizzard's frames asked
    end
    local combined = _G.ContainerFrameCombinedBags
    local open = wantedCount > 0 and type(combined) == "table" and combined.IsShown and ns.Readable(combined.IsShown, combined)
    local cells = open and open[1] == true and ns.Reagents and ns.Reagents.Cells and ns.Reagents:Cells()
    if not cells then
        hideFrom(1)
        shownCount = 0
        return
    end
    ensureHolder(combined)
    local count, level = 0, nil
    for _, cell in ipairs(cells) do
        local label = cell.button and wanted[cell.bag .. ":" .. cell.slot]
        if label then
            count = count + 1
            place(border(count), cell.button, label.color)
            if not level then
                local answer = ns.Readable(cell.button.GetFrameLevel, cell.button)
                level = answer and type(answer[1]) == "number" and answer[1] or nil
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
    ns.SafeCall(Labels.Refresh, Labels)
end

------------------------------------------------------------------------
-- The padlock: the label list, and mark mode
------------------------------------------------------------------------
-- A closed padlock says "kept gear" (the user chose it, 2026-11-08, over crossed swords). The client's own
-- lock atlases first - asked for by name, so one this client lacks is simply skipped - then the padlock
-- file every client since the first has carried.
local MODE_ATLASES = { "AdventureMapIcon-Lock", "Forge-Lock" }
local MODE_FILE = "Interface\\Buttons\\LockButton-Locked-Up"
local ROW_HEIGHT, MENU_WIDTH = 16, 150

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

local modeButton, menu
local pressedItem -- the item labelled by the left button that is down right now
Labels.markMode = false

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
    if Labels.markMode then
        local color = (Labels:Get(Labels.active) or BY_KEY.off).color
        modeButton.glow:SetColorTexture(color[1], color[2], color[3], 0.45)
        modeButton.glow:Show()
    else
        modeButton.glow:Hide()
    end
end

local function hideMenu()
    if menu then
        menu:Hide()
    end
end

function Labels:SetMarkMode(on)
    on = on and true or false
    if on then
        hideMenu()
    end
    if self.markMode == on then
        paintModeButton()
        return
    end
    self.markMode = on
    pressedItem = nil
    paintModeButton()
    ns:Log("label_mode", on and self.active or false)
    if on then
        local label = self:Get(self.active) or BY_KEY.off
        ns:Print("labelling " .. label.name .. ": left-click items in your bags to give them the label (again to take it off); the padlock again ends it.")
    end
end

-- picks the label mark mode gives, and turns mark mode on
function Labels:Pick(key)
    if not self:Get(key) then
        return false
    end
    self.active = key
    self:SetMarkMode(true)
    paintModeButton()
    return true
end

local function menuRow(index, label)
    local row = CreateFrame("Button", "AKForeverBagsLabelMenuRow" .. index, menu)
    row:SetSize(MENU_WIDTH - 8, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * ROW_HEIGHT)
    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(10, 10)
    row.swatch:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.swatch:SetColorTexture(label.color[1], label.color[2], label.color[3], 1)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 16, 0)
    row.text:SetText(label.name)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
    row.key = label.key
    row:SetScript("OnClick", function()
        Labels:Pick(label.key)
    end)
    return row
end

local function ensureMenu()
    if menu then
        return menu
    end
    -- beside the bag window's left edge, its bottom level with the window's: bags sit low on the screen,
    -- so a list hanging below it would run off the bottom
    menu = CreateFrame("Frame", "AKForeverBagsLabelMenu", modeButton)
    local entries = {}
    for _, label in ipairs(Labels.LIST) do
        entries[#entries + 1] = label
    end
    entries[#entries + 1] = NONE_LABEL
    menu:SetSize(MENU_WIDTH, #entries * ROW_HEIGHT + 8)
    menu:SetPoint("BOTTOMRIGHT", _G.ContainerFrameCombinedBags, "BOTTOMLEFT", -2, 0)
    menu:SetFrameStrata("DIALOG")
    menu.background = menu:CreateTexture(nil, "BACKGROUND")
    menu.background:SetAllPoints(menu)
    menu.background:SetColorTexture(0, 0, 0, 0.85)
    menu.rows = {}
    for index, label in ipairs(entries) do
        menu.rows[index] = menuRow(index, label)
    end
    menu:Hide()
    return menu
end

local function ensureModeButton(combined)
    if modeButton then
        return modeButton
    end
    modeButton = CreateFrame("Button", "AKForeverBagsLabelMode", combined)
    modeButton:SetSize(18, 18)
    modeButton:SetPoint("TOPLEFT", combined, "BOTTOMLEFT", 4, -2) -- under the window, never on anything in it
    modeButton.icon = modeButton:CreateTexture(nil, "ARTWORK")
    modeButton.icon:SetAllPoints(modeButton)
    modeButton.iconName = setPadlock(modeButton.icon)
    modeButton.glow = modeButton:CreateTexture(nil, "OVERLAY")
    modeButton.glow:SetPoint("TOPLEFT", modeButton, "TOPLEFT", -3, 3)
    modeButton.glow:SetPoint("BOTTOMRIGHT", modeButton, "BOTTOMRIGHT", 3, -3)
    modeButton.glow:Hide()
    modeButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    modeButton:SetScript("OnClick", function()
        if Labels.markMode then
            Labels:SetMarkMode(false)
            return
        end
        local list = ensureMenu()
        if list:IsShown() then
            list:Hide()
        else
            list:Show()
        end
    end)
    modeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local label = Labels:Get(Labels.active) or BY_KEY.off
        GameTooltip:SetText(Labels.markMode and ("Labelling: " .. label.name) or "Labels")
        GameTooltip:AddLine(Labels.markMode and "Left-click items to give them the label (again to take it off). Click here to finish."
            or "Click to pick a label, then left-click items to give it to them. After a sort each label stands in a group of its own.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Labelled by hand: " .. Labels:Count() .. " (AKForeverBags)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    modeButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    paintModeButton()
    return modeButton
end

-- comes and goes with the bag window (a child of it); the window closing ends mark mode and the list
local function updateModeButton()
    local combined = _G.ContainerFrameCombinedBags
    local open = type(combined) == "table" and combined.IsShown and ns.Readable(combined.IsShown, combined)
    if open and open[1] == true then
        ensureModeButton(combined):Show()
    else
        Labels:SetMarkMode(false)
        hideMenu()
    end
end

local function putBack(itemID)
    local kind, held = cursorItem()
    if kind == "item" and held == itemID and type(ClearCursor) == "function" then
        pcall(ClearCursor) -- an item on the cursor goes back where it came from
    end
end

ns:On("GLOBAL_MOUSE_DOWN", function(_, mouseButton)
    if not Labels.markMode or mouseButton ~= "LeftButton" then
        return
    end
    if type(IsModifierKeyDown) == "function" and IsModifierKeyDown() then
        return -- shift-click links, ctrl-click previews: Blizzard's
    end
    if cursorItem() ~= nil then
        return -- a hand already full: this click is a drop, not a label
    end
    local bag, slot = slotUnderMouse()
    local info = bag and itemInfo(bag, slot)
    if not info then
        return
    end
    pressedItem = info.itemID
    Labels:LabelUnderMouse()
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
    if key == "labels" or key == "labelsAuto" then
        refresh()
    end
end)

------------------------------------------------------------------------
-- The command: the list, the automatic labels, and a way to start over
------------------------------------------------------------------------
ns:RegisterCommand("labels", "lists the labels you set by hand (the padlock under the bag window sets them); 'labels auto on|off': consumables, trade goods, quest items, junk and profession tools labelled by themselves (default on); 'labels clear' takes every hand-set label off", function(rest)
    local word = string.lower(rest or "")
    if word == "clear" then
        ns:SetOption("labels", {})
        ns:Print("labels: none set by hand any more (the automatic ones stay).")
        return
    end
    local auto = string.match(word, "^auto%s*(%a*)$")
    if auto then
        if auto == "on" or auto == "off" then
            ns:SetOption("labelsAuto", auto == "on")
        end
        ns:Print("labels auto:", ns:GetOption("labelsAuto") and "on - consumables, trade goods, quest items, junk and profession tools label themselves." or "off - only the labels you set, and the pins.")
        return
    end
    local groups = {}
    for id, entry in pairs(manual()) do
        if type(entry) == "table" then
            local label = Labels:Get(entry.label)
            local key = label and label.name or tostring(entry.label)
            groups[key] = groups[key] or {}
            table.insert(groups[key], tostring(entry.name) .. " (" .. tostring(id) .. ")")
        end
    end
    local any = false
    for _, label in ipairs(Labels.LIST) do
        local names = groups[label.name]
        if names then
            table.sort(names)
            ns:Print(label.name .. " (" .. #names .. "): " .. table.concat(names, ", "))
            any = true
        end
    end
    if groups[NONE_LABEL.name] then
        table.sort(groups[NONE_LABEL.name])
        ns:Print("No label (" .. #groups[NONE_LABEL.name] .. "): " .. table.concat(groups[NONE_LABEL.name], ", "))
        any = true
    end
    if not any then
        ns:Print("labels: none set by hand. Click the padlock under the bag window, pick a label, then click items.")
    end
end)

function Labels:Report()
    return { labelled = self:Count(), borders = shownCount, markMode = self.markMode, active = self.active,
        button = modeButton ~= nil, menu = menu ~= nil and menu:IsShown() or false, auto = ns:GetOption("labelsAuto") and true or false,
        icon = modeButton and modeButton.iconName or nil }
end
