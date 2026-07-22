ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local MP = require "ArmorMakesSense_MPCompat"
local RuntimeState = require "ArmorMakesSense_RuntimeState"
local Utils = require "ArmorMakesSense_UtilsShared"
local State = require "core/ArmorMakesSense_State"

local Core = ArmorMakesSense.Core
Core.ClientRuntime = Core.ClientRuntime or {}

local ClientRuntime = Core.ClientRuntime
local warned = {}
local errorKeys = {}
local runtimeDisabled = false
local startupCheckedPlayers = setmetatable({}, { __mode = "k" })

ClientRuntime.SCRIPT_VERSION = tostring(MP.SCRIPT_VERSION)
ClientRuntime.SCRIPT_BUILD = tostring(MP.SCRIPT_BUILD)

function ClientRuntime.log(message)
    print("[ArmorMakesSense] " .. tostring(message))
end

function ClientRuntime.logError(message)
    print("[ArmorMakesSense][ERROR] " .. tostring(message))
end

function ClientRuntime.logOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    ClientRuntime.log(message)
end

function ClientRuntime.logErrorOnce(key, message)
    if errorKeys[key] then
        return
    end
    errorKeys[key] = true
    ClientRuntime.logError(message)
end

function ClientRuntime.safeMethod(target, methodName, ...)
    return Utils.safeMethodWithOptions(target, methodName, {
        onError = function(failedMethod, failedTarget, failure)
            local targetName = tostring(failedTarget)
            local key = "safe:" .. tostring(failedMethod) .. ":" .. targetName
            ClientRuntime.logErrorOnce(
                key,
                "safeMethod failed for " .. tostring(failedMethod) .. " on " .. targetName .. " :: " .. tostring(failure)
            )
        end,
    }, ...)
end

function ClientRuntime.getLocalPlayer()
    local fn = _G.getPlayer
    if type(fn) ~= "function" then
        return nil
    end
    local ok, player = pcall(fn)
    if not ok then
        ClientRuntime.logErrorOnce("getLocalPlayer_failed", "getPlayer() failed: " .. tostring(player))
        return nil
    end
    return player
end

function ClientRuntime.forEachLocalPlayer(callback)
    if type(callback) ~= "function" then
        return 0
    end

    local visited = {}
    local count = 0
    local activeCount = nil
    if type(_G.getNumActivePlayers) == "function" then
        local ok, value = pcall(_G.getNumActivePlayers)
        if ok then
            activeCount = math.max(0, math.floor(tonumber(value) or 0))
        end
    end

    if activeCount and type(_G.getSpecificPlayer) == "function" then
        for playerIndex = 0, activeCount - 1 do
            local ok, player = pcall(_G.getSpecificPlayer, playerIndex)
            if ok and player and not visited[player] then
                visited[player] = true
                count = count + 1
                callback(player, playerIndex)
            end
        end
    end

    if count == 0 then
        local player = ClientRuntime.getLocalPlayer()
        if player then
            callback(player, 0)
            count = 1
        end
    end
    return count
end

function ClientRuntime.isLocalPlayer(playerObj)
    if not playerObj then
        return false
    end
    if type(playerObj.isLocalPlayer) == "function" then
        local ok, localPlayer = pcall(playerObj.isLocalPlayer, playerObj)
        if ok then
            return localPlayer == true
        end
    end

    local matched = false
    ClientRuntime.forEachLocalPlayer(function(candidate)
        if candidate == playerObj then
            matched = true
        end
    end)
    return matched
end

function ClientRuntime.getLoadedModVersion()
    local info = type(getModInfoByID) == "function" and getModInfoByID("ArmorMakesSense") or nil
    local version = ClientRuntime.safeMethod(info, "getVersion") or ClientRuntime.safeMethod(info, "getModVersion")
    return version ~= nil and tostring(version) or ClientRuntime.SCRIPT_VERSION
end

function ClientRuntime.getGameVersionTag()
    local core = type(getCore) == "function" and getCore() or nil
    if not core then
        return "unknown"
    end
    local version = ClientRuntime.safeMethod(core, "getVersionNumber")
        or ClientRuntime.safeMethod(core, "getVersion")
        or ClientRuntime.safeMethod(core, "getGameVersion")
    return version ~= nil and tostring(version) or "unknown"
end

function ClientRuntime.ensureState(player)
    if Utils.isClientSide() then
        return RuntimeState.get(player, RuntimeState.ROLE_MP_CLIENT) or {}
    end
    return State.ensureState(player)
end

function ClientRuntime.isDisabled()
    return runtimeDisabled
end

function ClientRuntime.setDisabled(value)
    runtimeDisabled = Utils.toBoolean(value)
end

function ClientRuntime.runGuarded(label, fn, ...)
    if runtimeDisabled then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        runtimeDisabled = true
        ClientRuntime.logError("runtime disabled after " .. tostring(label) .. " failure: " .. tostring(result))
        return nil
    end
    return result
end

local function hasFunction(target, name)
    return target and type(target[name]) == "function"
end

function ClientRuntime.runPlayerStartupChecks(player)
    if runtimeDisabled or (player and startupCheckedPlayers[player]) then
        return not runtimeDisabled
    end
    if not player then
        return true
    end

    local issues = {}
    local stats = ClientRuntime.safeMethod(player, "getStats")
    if not stats then
        issues[#issues + 1] = "player:getStats unavailable"
    else
        local canGet = hasFunction(stats, "get")
        local canSet = hasFunction(stats, "set")
        local canReadEnd = hasFunction(stats, "getEndurance") or (CharacterStat and CharacterStat.ENDURANCE and canGet)
        local canWriteEnd = hasFunction(stats, "setEndurance") or (CharacterStat and CharacterStat.ENDURANCE and canSet)
        local canReadFatigue = hasFunction(stats, "getFatigue") or (CharacterStat and CharacterStat.FATIGUE and canGet)
        local canWriteFatigue = hasFunction(stats, "setFatigue") or (CharacterStat and CharacterStat.FATIGUE and canSet)
        if not canReadEnd or not canWriteEnd then
            issues[#issues + 1] = "ENDURANCE bindings missing"
        end
        if not canReadFatigue or not canWriteFatigue then
            issues[#issues + 1] = "FATIGUE bindings missing"
        end
    end

    if #issues > 0 then
        runtimeDisabled = true
        ClientRuntime.logError("startup check failed: " .. table.concat(issues, " | "))
        return false
    end

    startupCheckedPlayers[player] = true
    ClientRuntime.log(string.format(
        "[BOOT] startup checks passed version=%s build=%s",
        ClientRuntime.getLoadedModVersion(),
        ClientRuntime.SCRIPT_BUILD
    ))
    return true
end

return ClientRuntime
