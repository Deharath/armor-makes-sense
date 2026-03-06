ArmorMakesSense = ArmorMakesSense or {}

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
    print("[ArmorMakesSense][MP_PHASE0][CLIENT][ERROR] MP compat constants unavailable; harness disabled")
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

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, player = pcall(getPlayer)
    if not ok then
        return nil
    end
    return player
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

local function log(message)
    print("[ArmorMakesSense][MP_PHASE0][CLIENT] " .. tostring(message))
end

local function logBootBanner(contextTag)
    log(string.format(
        "[BOOT_MP] context=%s side=client isClient=%s isServer=%s ingame=%s modVersion=%s scriptVersion=%s build=%s",
        tostring(contextTag or "load"),
        tostring(boolGlobal("isClient")),
        tostring(boolGlobal("isServer")),
        tostring(GameClient and GameClient.ingame or false),
        tostring(getLoadedModVersion()),
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end

local pingSent = false

local function canSend()
    local reasons = {}
    if not boolGlobal("isClient") then
        reasons[#reasons + 1] = "isClient=false"
    end
    local hasGameClientFlag = (GameClient ~= nil and GameClient.ingame ~= nil)
    if hasGameClientFlag and GameClient.ingame ~= true then
        reasons[#reasons + 1] = "GameClient.ingame=false"
    end
    if type(sendClientCommand) ~= "function" then
        reasons[#reasons + 1] = "sendClientCommand missing"
    end
    if getLocalPlayer() == nil then
        reasons[#reasons + 1] = "local player missing"
    end
    if #reasons > 0 then
        return false, reasons
    end
    return true, nil
end

local function trySendHarnessPing(reason)
    if pingSent then
        return false
    end
    local ready, reasons = canSend()
    if not ready then
        log("harness ping blocked: " .. table.concat(reasons or { "unknown" }, ", "))
        return false
    end

    local args = {
        reason = tostring(reason or "auto"),
        world_minute = math.floor(getWorldAgeMinutes()),
        script_version = tostring(MP.SCRIPT_VERSION),
        script_build = tostring(MP.SCRIPT_BUILD),
    }

    local ok, err = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.HARNESS_PING_COMMAND), args)
    if not ok then
        log("harness ping send failed: " .. tostring(err))
        return false
    end

    pingSent = true
    log(string.format(
        "sent harness ping module=%s command=%s reason=%s",
        tostring(MP.NET_MODULE),
        tostring(MP.HARNESS_PING_COMMAND),
        tostring(args.reason)
    ))
    return true
end

local function onCreatePlayer(playerIndex, playerObj)
    if playerObj and type(playerObj.isLocalPlayer) == "function" and not playerObj:isLocalPlayer() then
        return
    end
    trySendHarnessPing("OnCreatePlayer")
end

local function onEveryOneMinute()
    trySendHarnessPing("EveryOneMinute")
end

local function onConnected()
    trySendHarnessPing("OnConnected")
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.DIAG_COMMAND) then
        return
    end

    log(string.format(
        "received diag module=%s command=%s status=%s echo=%s server_minute=%s",
        tostring(module),
        tostring(command),
        tostring(args and args.status),
        tostring(args and args.echo),
        tostring(args and args.server_minute)
    ))
end

local function registerHarnessEvents()
    if ArmorMakesSense._mpClientHarnessRegistered then
        return
    end
    ArmorMakesSense._mpClientHarnessRegistered = true

    if Events and Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(onServerCommand)
    end
    if Events and Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(onCreatePlayer)
    end
    if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    end
    if Events and Events.OnConnected and type(Events.OnConnected.Add) == "function" then
        Events.OnConnected.Add(onConnected)
    end
end

function ams_mp_ping(reason)
    pingSent = false
    return trySendHarnessPing(reason or "manual")
end

registerHarnessEvents()
logBootBanner("load")
trySendHarnessPing("load")
