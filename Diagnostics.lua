-- /fbags diag: a report of what this client does with the bag windows, saved with the settings
-- (ForeverBagsDB.diag) so that it can be read from the SavedVariables file after a /reload or logout.
-- Read-only on Blizzard's side; nothing here looks at a value before ns.IsSecret cleared it.
local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function sanitize(value, depth)
    depth = depth or 0
    if ns.IsSecret(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "table" then
        if depth >= 7 then
            return "<too deep>"
        end
        local copy = {}
        for k, v in pairs(value) do
            local key = k
            if ns.IsSecret(k) then
                key = "<secret key>"
            elseif type(k) ~= "string" and type(k) ~= "number" then
                key = tostring(k)
            end
            copy[key] = sanitize(v, depth + 1)
        end
        return copy
    elseif kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "nil" then
        return nil
    end
    return "<" .. kind .. ">"
end

-- One getter's first result - "<secret>", "n/a" (no such method) or "error: ..." instead of a surprise.
local function ask(fn, ...)
    if type(fn) ~= "function" then
        return "n/a"
    end
    local ok, value = pcall(fn, ...)
    if not ok then
        return "error: " .. tostring(value)
    end
    return sanitize(value)
end

local function nameOf(object)
    if ns.IsSecret(object) then
        return "<secret>"
    elseif type(object) == "table" and type(object.GetName) == "function" then
        return ask(object.GetName, object) or "<unnamed frame>"
    end
    return tostring(object)
end

-- (never sanitize() a frame: that would walk Blizzard's table)
local function anchorOf(frame)
    local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then
        return "unreadable"
    end
    return sanitize({ point = point, relativeTo = nameOf(relativeTo), relativePoint = relativePoint, x = x, y = y })
end

local function describeWindow(window)
    local info = {
        shown = ask(window.IsShown, window), bag = ask(window.GetID, window), protected = ask(window.IsProtected, window),
        width = ask(window.GetWidth, window), height = ask(window.GetHeight, window), scale = ask(window.GetScale, window),
        left = ask(window.GetLeft, window), bottom = ask(window.GetBottom, window), strata = ask(window.GetFrameStrata, window),
        level = ask(window.GetFrameLevel, window), anchor = anchorOf(window),
    }
    local items = window.Items -- (read only)
    if type(items) == "table" then
        info.itemButtons = #items
        info.samples = {}
        for _, index in ipairs({ 1, #items }) do
            local button = items[index]
            if type(button) == "table" and type(button.GetPoint) == "function" then
                info.samples[#info.samples + 1] = {
                    index = index, slot = ask(button.GetID, button), shown = ask(button.IsShown, button),
                    protected = ask(button.IsProtected, button), strata = ask(button.GetFrameStrata, button),
                    left = ask(button.GetLeft, button), bottom = ask(button.GetBottom, button), anchor = anchorOf(button),
                }
            end
        end
    end
    return info
end

-- What the CLIENT says this addon costs. Only asked when a report is made.
function Diagnostics:Performance()
    local result = {}
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
        result.memoryKB = ask(GetAddOnMemoryUsage, ns.name)
    end
    local profiler, metrics = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if type(profiler) == "table" and type(profiler.GetAddOnMetric) == "function" and type(metrics) == "table" then
        result.profilerEnabled = ask(profiler.IsEnabled)
        result.metricsMs = {}
        for name, id in pairs(metrics) do
            if type(name) == "string" then
                result.metricsMs[name] = ask(profiler.GetAddOnMetric, ns.name, id)
            end
        end
    else
        result.profiler = "this client has no C_AddOnProfiler"
    end
    return result
end

function Diagnostics:Collect()
    local report = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or "?",
        addonVersion = ns.version,
        character = ns.characterKey,
        savedStateSource = ns.savedStateSource,
        savedVariableLoads = ns.db and ns.db.loads,
        inCombat = InCombatLockdown() and true or false,
        options = {
            merge = ns:GetOption("merge"), reagentsShown = ns:GetOption("reagentsShown"),
            backpackKeyOpensAll = ns:GetOption("backpackKeyOpensAll"),
        },
        -- the performance promise, measured: our own gauge, the addon's memory, and the client's profiler
        work = ns.Reagents.work,
        performance = Diagnostics:Performance(),
        reagents = {
            state = ns.Reagents.state, moved = ns.Reagents.moved, raises = ns.Reagents.raises, hooks = ns.Reagents.hooks,
            keys = ns.Reagents.keys, combinedSetting = ask((C_CVar and C_CVar.GetCVar) or GetCVar, "combinedBags"),
        },
        bagSlots = {},
        windows = {},
        errors = {},
        blockedActions = ns.blockedActions,
        unknownEvents = ns.unknownEvents,
        log = ns.sessionLog,
    }
    if GetBuildInfo then
        local version, build, buildDate, toc = GetBuildInfo()
        report.build = { version = version, build = build, date = buildDate, toc = toc }
    end
    for bag = 0, 5 do
        report.bagSlots[tostring(bag)] = ask(C_Container and C_Container.GetContainerNumSlots, bag)
    end
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame6", "ForeverBagsReagentSlots" }) do
        local window = _G[name]
        if type(window) == "table" and type(window.GetPoint) == "function" then
            report.windows[name] = describeWindow(window)
        else
            report.windows[name] = "absent"
        end
    end
    for message, count in pairs(ns.errors) do
        report.errors[#report.errors + 1] = { message = message, count = count }
    end
    return sanitize(report)
end

function Diagnostics:Save()
    if ns.db then
        ns.db.diag = self:Collect()
    end
end

ns:RegisterCommand("diag", "save a report into the settings file (then /reload, so that it is written to disk)", function()
    Diagnostics:Save()
    ns:Print("report saved - /reload (or log out) writes it to disk. Reagent bag:", ns.Reagents.state)
end)

ns:On("PLAYER_LOGOUT", function()
    Diagnostics:Save()
end)
