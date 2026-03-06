ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local MP = nil
do
    local ok, mod = pcall(require, "ArmorMakesSense_MPCompat")
    if ok and type(mod) == "table" then
        MP = mod
    else
        MP = ArmorMakesSense.MP
    end
end

if type(MP) ~= "table" then
    print("[ArmorMakesSense][MP_PHASE0][SERVER][ERROR] MP compat constants unavailable; harness disabled")
    return
end

local function diagnosticsEnabled()
    return true
end

if not diagnosticsEnabled() then
    return
end

local function boolGlobal(name)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return false
    end
    local ok, value = pcall(fn)
    if not ok then
        return false
    end
    return value == true
end

local function getWorldAgeMinutes()
    if type(getGameTime) ~= "function" then
        return 0
    end
    local okTime, gameTime = pcall(getGameTime)
    if not okTime or not gameTime then
        return 0
    end
    local okWorldAge, worldAgeHours = pcall(gameTime.getWorldAgeHours, gameTime)
    if not okWorldAge then
        return 0
    end
    return tonumber(worldAgeHours) and (tonumber(worldAgeHours) * 60.0) or 0
end

local function getLoadedModVersion()
    if type(getModInfoByID) ~= "function" then
        return tostring(MP.SCRIPT_VERSION or "unknown")
    end
    local okInfo, info = pcall(getModInfoByID, "ArmorMakesSense")
    if not okInfo or not info then
        return tostring(MP.SCRIPT_VERSION or "unknown")
    end
    local okVersion, version = pcall(info.getVersion, info)
    if okVersion and version then
        return tostring(version)
    end
    local okModVersion, modVersion = pcall(info.getModVersion, info)
    if okModVersion and modVersion then
        return tostring(modVersion)
    end
    return tostring(MP.SCRIPT_VERSION or "unknown")
end

local function playerName(playerObj)
    if not playerObj then
        return "unknown"
    end
    local okUser, username = pcall(playerObj.getUsername, playerObj)
    if okUser and username and tostring(username) ~= "" then
        return tostring(username)
    end
    local okDisplay, displayName = pcall(playerObj.getDisplayName, playerObj)
    if okDisplay and displayName and tostring(displayName) ~= "" then
        return tostring(displayName)
    end
    return "unknown"
end

local function playerOnlineID(playerObj)
    if not playerObj then
        return -1
    end
    local okId, onlineId = pcall(playerObj.getOnlineID, playerObj)
    if okId and onlineId ~= nil then
        return tonumber(onlineId) or -1
    end
    return -1
end

local function log(message)
    print("[ArmorMakesSense][MP_PHASE0][SERVER] " .. tostring(message))
end

local function logBootBanner(contextTag)
    log(string.format(
        "[BOOT_MP] context=%s side=server isClient=%s isServer=%s modVersion=%s scriptVersion=%s build=%s",
        tostring(contextTag or "load"),
        tostring(boolGlobal("isClient")),
        tostring(boolGlobal("isServer")),
        tostring(getLoadedModVersion()),
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end

local function sendDiagToPlayer(playerObj, echo)
    if type(sendServerCommand) ~= "function" then
        log("sendServerCommand unavailable; cannot return harness pong")
        return
    end
    local args = {
        status = "pong",
        echo = tostring(echo or "none"),
        server_minute = math.floor(getWorldAgeMinutes()),
        script_version = tostring(MP.SCRIPT_VERSION),
        script_build = tostring(MP.SCRIPT_BUILD),
    }
    local okSend, errSend = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.DIAG_COMMAND), args)
    if not okSend then
        log("failed to send diag pong: " .. tostring(errSend))
    end
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end

    if tostring(command) == tostring(MP.HARNESS_PING_COMMAND) then
        log(string.format(
            "received harness ping module=%s command=%s player=%s onlineId=%s reason=%s",
            tostring(module),
            tostring(command),
            tostring(playerName(playerObj)),
            tostring(playerOnlineID(playerObj)),
            tostring(args and args.reason)
        ))
        sendDiagToPlayer(playerObj, args and args.reason)
    end
end

local function onGameBoot()
    logBootBanner("OnGameBoot")
end

local function registerHarnessEvents()
    if ArmorMakesSense._mpServerHarnessRegistered then
        return
    end
    ArmorMakesSense._mpServerHarnessRegistered = true

    if Events and Events.OnClientCommand and type(Events.OnClientCommand.Add) == "function" then
        Events.OnClientCommand.Add(onClientCommand)
        log("OnClientCommand handler registered for module=" .. tostring(MP.NET_MODULE))
    else
        log("OnClientCommand.Add unavailable; harness inactive")
    end

    if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
        Events.OnGameBoot.Add(onGameBoot)
    end
end

registerHarnessEvents()
logBootBanner("load")
