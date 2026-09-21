-- ForeverBags core: namespace, safe calls, event dispatch, message bus, saved variables,
-- session log and slash commands.
--
-- The mission of this addon family: minimalistic UI additions that bring out the utility Blizzard's UI does
-- not give - minimal in nature, no Lua errors, always smooth. So: nothing runs on a timer, every entry
-- point goes through ns.SafeCall, and every error or blocked action is kept for /fbags diag.
--
-- House rules for this addon - the bag code is where "blocked action" taint traditionally starts:
--   * Blizzard's bag functions (OpenBag, ToggleAllBags, frame:Update ...) are NEVER called from here:
--     run by an addon they would write tainted values into Blizzard's bag frames.
--   * on Blizzard's frames only widget methods are called (SetPoint, SetHeight, Raise ...);
--     no field is ever written on them. What we need to remember lives in our own tables.
--   * whatever a getter on one of Blizzard's frames returns may be a secret value: it is checked with
--     ns.IsSecret before it is looked at, and "unreadable" always means "hands off".
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "dev"
if string.find(ns.version, "@", 1, true) then
    ns.version = "dev" -- a working copy: the packager has not replaced the @project-version@ token
end
ns.version = (string.gsub(ns.version, "^v", "")) -- release tags are "v0.2.0"; we print the "v" ourselves

local PRINT_PREFIX = "|cff5fd38dForeverBags|r: "

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    print(PRINT_PREFIX .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Secret values. WoW: Forever runs the Midnight-era API, where some
-- values handed to addons may be held but not inspected.
------------------------------------------------------------------------
local issecret = type(issecretvalue) == "function" and issecretvalue or nil

function ns.IsSecret(value)
    if issecret then
        return issecret(value) and true or false
    end
    return false
end

function ns.AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

-- The results of a getter as a list - or nil when the call failed or any result is secret.
function ns.Readable(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok or ns.AnySecret(a, b, c, d, e) then
        return nil
    end
    return { a, b, c, d, e }
end

------------------------------------------------------------------------
-- Safe calls: every distinct error is kept for /fbags diag.
------------------------------------------------------------------------
ns.errors = {}

local function onError(err)
    err = tostring(err)
    local seen = ns.errors[err]
    ns.errors[err] = (seen or 0) + 1
    if not seen then
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            handler(err)
        end
    end
    return err
end

function ns.SafeCall(fn, ...)
    return xpcall(fn, onError, ...)
end

------------------------------------------------------------------------
-- Session log (ring buffer), saved with /fbags diag and on logout
------------------------------------------------------------------------
local LOG_MAX = 60
ns.sessionLog = {}

function ns:Log(kind, data)
    local log = ns.sessionLog
    log[#log + 1] = {
        t = math.floor(GetTime() * 1000) / 1000,
        k = kind,
        c = InCombatLockdown() and 1 or nil,
        d = data,
    }
    if #log > LOG_MAX then
        table.remove(log, 1)
    end
end

------------------------------------------------------------------------
-- Internal message bus
------------------------------------------------------------------------
local listeners = {}

function ns:Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], message, ...)
    end
end

------------------------------------------------------------------------
-- Game events. Registration is pcall'd so an event that a future client
-- drops shows up in /fbags diag instead of breaking the addon at load.
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
ns.unknownEvents = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], event, ...)
    end
end)

function ns:On(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents[event] = true
        end
    end
    table.insert(eventHandlers[event], fn)
end

------------------------------------------------------------------------
-- Blocked actions: the client stops the call without a Lua error and shows the "has been blocked"
-- dialog. These events name the function; kept so /fbags diag can say exactly what it was.
------------------------------------------------------------------------
ns.blockedActions = {}

local function onActionBlocked(event, addonName, functionName)
    if addonName ~= ADDON_NAME then
        return
    end
    local entry = { event = event, fn = tostring(functionName), combat = InCombatLockdown() and true or false }
    ns.blockedActions[#ns.blockedActions + 1] = entry
    ns:Log("action_blocked", entry)
end

ns:On("ADDON_ACTION_FORBIDDEN", onActionBlocked)
ns:On("ADDON_ACTION_BLOCKED", onActionBlocked)

------------------------------------------------------------------------
-- Saved variables: ONE account-wide table, per-character data under db.chars["Name - Realm"].
-- One file is what lets the beta workaround (tools/Install-SavedStateBridge.ps1) restore it: the
-- 1.60.1 client writes SavedVariables but never reads them back.
------------------------------------------------------------------------
local OPTION_DEFAULTS = {
    merge = true,               -- the reagent bag's slots go into the combined bag window
    reagentsShown = true,       -- ... and shown there (false: put away - the bag window looks stock)
    backpackKeyOpensAll = true, -- the backpack key opens the reagent bag as well (the merge needs it open)
}

-- The realm is squeezed ("Classic Beta PvE" -> "ClassicBetaPvE"): on a fresh login UnitFullName has no
-- realm yet and GetRealmName() gives the spaced display name, after a /reload UnitFullName gives the
-- normalized one. Unsqueezed, that would be two profiles for one character.
local function squeezeRealm(realm)
    return (string.gsub(realm, "[%s%-]", ""))
end

local function characterKey()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if not name then
        name = UnitName("player")
    end
    if not realm or realm == "" then
        realm = GetRealmName and GetRealmName()
    end
    return (name or "Unknown") .. " - " .. squeezeRealm(realm or "Unknown")
end

local function initDB()
    local bridge = ForeverBags_SavedStateBridge
    if type(ForeverBagsDB) ~= "table" then
        ForeverBagsDB = {}
        ns.savedStateSource = "none (first run, or the client did not load it)"
    elseif type(bridge) == "table" and bridge.table == ForeverBagsDB then
        ns.savedStateSource = "bridge addon"
    else
        ns.savedStateSource = "client"
    end
    local db = ForeverBagsDB

    db.schema = db.schema or 1
    db.loads = (db.loads or 0) + 1
    db.chars = db.chars or {}

    local key = characterKey()
    if type(db.chars[key]) ~= "table" then
        db.chars[key] = {}
    end
    local cdb = db.chars[key]
    cdb.options = cdb.options or {}

    ns.characterKey = key
    ns.db, ns.cdb = db, cdb
end

function ns:GetOption(key)
    local options = ns.cdb and ns.cdb.options
    local value = options and options[key]
    if value == nil then
        return OPTION_DEFAULTS[key]
    end
    return value
end

function ns:SetOption(key, value)
    ns.cdb.options[key] = value
    ns:Fire("OPTION_CHANGED", key, value)
end

------------------------------------------------------------------------
-- Slash commands: modules register their own sub-commands
------------------------------------------------------------------------
local commands, commandOrder = {}, {}

function ns:RegisterCommand(name, help, fn)
    commands[name] = { help = help, fn = fn }
    commandOrder[#commandOrder + 1] = name
end

SLASH_FOREVERBAGS1 = "/foreverbags"
SLASH_FOREVERBAGS2 = "/fbags"
SLASH_FOREVERBAGS3 = "/fbg"
SlashCmdList["FOREVERBAGS"] = function(message)
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    local command = commands[string.lower(name or "")]
    if command then
        ns.SafeCall(command.fn, rest or "")
        return
    end
    ns:Print("v" .. ns.version .. " commands:")
    for _, commandName in ipairs(commandOrder) do
        print("   |cffffd100/fbags " .. commandName .. "|r - " .. commands[commandName].help)
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    initDB()
end)

ns:On("PLAYER_LOGIN", function()
    ns:Log("login", {
        version = ns.version,
        character = ns.characterKey,
        loads = ns.db and ns.db.loads,
        savedState = ns.savedStateSource,
    })
    ns:Fire("LOGIN")
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    ns:Fire("COMBAT_END")
end)
