ArmorMakesSense = ArmorMakesSense or {}

local runningOnClient = (type(isClient) == "function") and (isClient() == true)
if not runningOnClient then
    return
end

local MP = require "ArmorMakesSense_MPCompat"

-- Lines are `[TAG] key=value ...` for tools/armor_makes_sense/scripts/parse_debug.py.

local lastDiagDump = nil
local sleepTrace = {}

local function log(message)
    print("[ArmorMakesSense][MP][DIAG][CLIENT] " .. tostring(message))
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function fmt(value)
    if type(value) == "number" then
        if value == math.floor(value) and math.abs(value) < 1e9 then
            return tostring(math.floor(value))
        end
        return string.format("%.6f", value)
    end
    return (tostring(value):gsub("%s", "_"))
end

-- All scalar payload fields, sorted, so client and server dumps line up.
local function scalarFields(payload)
    local keys = {}
    for key, value in pairs(payload) do
        local kind = type(value)
        if kind == "number" or kind == "string" or kind == "boolean" then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        parts[#parts + 1] = keys[i] .. "=" .. fmt(payload[keys[i]])
    end
    return table.concat(parts, " ")
end

local function getWorldAgeMinutes()
    return (tonumber(getGameTime():getWorldAgeHours()) or 0) * 60.0
end

local function getFatigue(playerObj)
    local stats = safeCall(playerObj, "getStats")
    return stats and CharacterStat and tonumber(safeCall(stats, "get", CharacterStat.FATIGUE)) or nil
end

local function canSendRequest(playerObj)
    if not playerObj then
        return false
    end
    if GameClient and GameClient.ingame ~= nil and GameClient.ingame ~= true then
        return false
    end
    return safeCall(playerObj, "isLocalPlayer") ~= false
end

-- AMS adds sleep fatigue on the server; a drop while awake means a sync
-- overwrote the client's value and is worth seeing.
local function emitSleepDiagnostics()
    local playerObj = getPlayer()
    if not playerObj then
        return
    end
    local world = getWorldAgeMinutes()
    local sleeping = safeCall(playerObj, "isAsleep") == true
    local fatigue = tonumber(getFatigue(playerObj)) or -1

    if sleepTrace.lastSleeping ~= sleeping then
        log(string.format(
            "[SLEEP] side=client transition=%s world=%.2f fatigue=%.4f",
            sleeping and "start" or "end",
            world,
            fatigue
        ))
    end
    if sleepTrace.lastFatigue ~= nil and not sleeping and fatigue < (sleepTrace.lastFatigue - 0.002) then
        log(string.format(
            "[SLEEP_ANOM] side=client kind=awake_fatigue_drop world=%.2f fatigue=%.4f previous=%.4f",
            world,
            fatigue,
            sleepTrace.lastFatigue
        ))
    end
    sleepTrace.lastSleeping = sleeping
    sleepTrace.lastFatigue = fatigue
end

function ams_mp_diag_dump(reason)
    local playerObj = getPlayer()
    if not canSendRequest(playerObj) then
        log("diag dump request blocked (not ready)")
        return false
    end
    local args = {
        reason = tostring(reason or "manual"),
        world_minute = math.floor(getWorldAgeMinutes()),
        script_version = tostring(MP.SCRIPT_VERSION),
        script_build = tostring(MP.SCRIPT_BUILD),
    }
    sendClientCommand(playerObj, tostring(MP.NET_MODULE), tostring(MP.DIAG_DUMP_REQUEST_COMMAND), args)
    log(string.format("diag dump requested reason=%s version=%s build=%s", args.reason, args.script_version, args.script_build))
    return true
end

function ams_mp_diag_last()
    if type(lastDiagDump) ~= "table" then
        log("diag last: none")
        return nil
    end
    log("diag last: " .. scalarFields(lastDiagDump) .. " drivers=" .. tostring(#(lastDiagDump.drivers or {})))
    return lastDiagDump
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) or tostring(command) ~= tostring(MP.DIAG_DUMP_COMMAND) then
        return
    end
    if type(args) ~= "table" then
        return
    end
    lastDiagDump = args
    log("diag dump recv " .. scalarFields(args) .. " drivers=" .. tostring(#(args.drivers or {})))
end

local function registerEvents()
    if ArmorMakesSense._mpDiagnosticsClientRegistered then
        return
    end
    ArmorMakesSense._mpDiagnosticsClientRegistered = true
    Events.OnServerCommand.Add(onServerCommand)
    Events.EveryOneMinute.Add(emitSleepDiagnostics)
end

registerEvents()
log("diagnostics module active")
