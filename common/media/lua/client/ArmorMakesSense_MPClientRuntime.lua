ArmorMakesSense = ArmorMakesSense or {}

local okMpCompat, mpCompatOrErr = pcall(require, "ArmorMakesSense_MPCompat")
if not okMpCompat then
    print("[ArmorMakesSense][MP][CLIENT][ERROR] optional require failed: ArmorMakesSense_MPCompat :: " .. tostring(mpCompatOrErr))
    return
end

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or ArmorMakesSense.MP
if type(MP) ~= "table" then
    print("[ArmorMakesSense][MP][CLIENT][ERROR] MP compat constants unavailable; runtime disabled")
    return
end

local STATE_KEY = tostring(MP.MOD_STATE_KEY or "ArmorMakesSenseState")
local SNAPSHOT_INTERVAL_SECONDS = math.max(1, math.floor(tonumber(MP.SNAPSHOT_FALLBACK_SECONDS) or 2))
local SNAPSHOT_STALE_SECONDS = math.max(10, SNAPSHOT_INTERVAL_SECONDS * 4)
local firstSnapshotLogged = false
local uiHooksEnsured = false
local markUiDirty

local function log(message)
    print("[ArmorMakesSense][MP][CLIENT] " .. tostring(message))
end

local function toBoolean(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "string" then
        local lowered = string.lower(value)
        return lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "on"
    end
    if type(value) == "number" then
        return value ~= 0
    end
    return false
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

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, playerObj = pcall(getPlayer)
    if not ok then
        return nil
    end
    return playerObj
end

local function getWallClockSeconds()
    if type(getTimestampMs) == "function" then
        local nowMs = tonumber(getTimestampMs())
        if nowMs ~= nil then
            return math.floor(nowMs / 1000)
        end
    end
    if type(getTimestamp) == "function" then
        local nowSeconds = tonumber(getTimestamp())
        if nowSeconds ~= nil then
            return math.floor(nowSeconds)
        end
    end
    return 0
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local worldAgeHours = tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
    if worldAgeHours == nil then
        return 0
    end
    return worldAgeHours * 60.0
end

local function isMultiplayerClientSession(playerObj)
    if GameClient and GameClient.bClient ~= nil then
        return GameClient.bClient == true
    end
    local onlineId = tonumber(playerObj and safeCall(playerObj, "getOnlineID") or nil)
    return onlineId ~= nil and onlineId >= 0
end

local function ensureState(playerObj)
    if not playerObj then
        return nil
    end
    local modData = safeCall(playerObj, "getModData")
    if type(modData) ~= "table" then
        return nil
    end

    modData[STATE_KEY] = modData[STATE_KEY] or {}
    local state = modData[STATE_KEY]
    state.mpClient = type(state.mpClient) == "table" and state.mpClient or {}

    local mpClient = state.mpClient
    mpClient.lastRequestWallSecond = tonumber(mpClient.lastRequestWallSecond) or 0
    mpClient.lastSnapshotWallSecond = tonumber(mpClient.lastSnapshotWallSecond) or 0

    return state, mpClient
end

local function readLatestSnapshotState()
    local playerObj = getLocalPlayer()
    local state, mpClient = ensureState(playerObj)
    return playerObj, state, mpClient
end

local function clearSnapshotState(playerObj, resetLogLatch)
    local state, mpClient = ensureState(playerObj)
    if not state or not mpClient then
        return false
    end
    local hadSnapshot = type(state.mpServerSnapshot) == "table"
    state.mpServerSnapshot = nil
    mpClient.lastSnapshotWallSecond = 0
    if resetLogLatch then
        firstSnapshotLogged = false
    end
    if hadSnapshot then
        markUiDirty()
    end
    return hadSnapshot
end

local function expireStaleSnapshot(playerObj)
    local state, mpClient = ensureState(playerObj)
    if not state or not mpClient or type(state.mpServerSnapshot) ~= "table" then
        return false
    end
    local lastSnapshot = tonumber(mpClient.lastSnapshotWallSecond) or 0
    if lastSnapshot <= 0 then
        return false
    end
    local ageSeconds = getWallClockSeconds() - lastSnapshot
    if ageSeconds < SNAPSHOT_STALE_SECONDS then
        return false
    end
    clearSnapshotState(playerObj, false)
    log(string.format("expired stale snapshot age_s=%.1f", tonumber(ageSeconds) or 0))
    return true
end

local function canSendRequest(playerObj)
    if not playerObj then
        return false
    end
    if not isMultiplayerClientSession(playerObj) then
        return false
    end
    if type(isClient) == "function" and not isClient() then
        return false
    end
    if type(sendClientCommand) ~= "function" then
        return false
    end
    if GameClient and GameClient.ingame ~= nil and GameClient.ingame ~= true then
        return false
    end
    if type(playerObj.isLocalPlayer) == "function" and not playerObj:isLocalPlayer() then
        return false
    end
    return true
end

function markUiDirty()
    local ui = ArmorMakesSense and ArmorMakesSense.Core and ArmorMakesSense.Core.UI or nil
    if ui and type(ui.markDirty) == "function" then
        pcall(ui.markDirty)
    end

    local screenClass = _G.ISCharacterInfoWindow
    local existing = screenClass and screenClass.instance or nil
    if existing and existing._amsBurdenPanel and type(existing._amsBurdenPanel.markDirty) == "function" then
        pcall(existing._amsBurdenPanel.markDirty, existing._amsBurdenPanel)
    end
end

local function ensureMpUiHooks(playerObj)
    if uiHooksEnsured then
        return true
    end
    local ui = ArmorMakesSense and ArmorMakesSense.Core and ArmorMakesSense.Core.UI or nil
    if type(ui) ~= "table" or type(ui.update) ~= "function" then
        return false
    end

    local options = {}
    local stateModule = ArmorMakesSense and ArmorMakesSense.Core and ArmorMakesSense.Core.State or nil
    if stateModule and type(stateModule.getOptions) == "function" then
        local okOptions, resolved = pcall(stateModule.getOptions)
        if okOptions and type(resolved) == "table" then
            options = resolved
        end
    end

    local okUpdate = pcall(ui.update, playerObj or getLocalPlayer(), nil, options)
    if okUpdate then
        uiHooksEnsured = true
        log("MP UI hooks ensured (Burden tab/fallback active)")
        return true
    end
    return false
end

local function getClientActivityLabel(playerObj)
    if not playerObj then
        return "idle"
    end
    if toBoolean(safeCall(playerObj, "isSprinting")) then
        return "sprint"
    end
    if toBoolean(safeCall(playerObj, "isRunning")) then
        return "run"
    end
    local moving = toBoolean(safeCall(playerObj, "isPlayerMoving")) or toBoolean(safeCall(playerObj, "isMoving"))
    if moving then
        return "walk"
    end
    if toBoolean(safeCall(playerObj, "isAttackStarted")) or toBoolean(safeCall(playerObj, "isAiming")) then
        return "combat"
    end
    return "idle"
end

local function sendSnapshotRequest(playerObj, reason, force)
    if not canSendRequest(playerObj) then
        return false
    end

    local state, mpClient = ensureState(playerObj)
    if not state or not mpClient then
        return false
    end

    local nowSecond = getWallClockSeconds()
    if (not force) and (nowSecond - mpClient.lastRequestWallSecond) < SNAPSHOT_INTERVAL_SECONDS then
        return false
    end

    local args = {
        reason = tostring(reason or "fallback"),
        world_minute = math.floor(getWorldAgeMinutes()),
        activity_label = tostring(getClientActivityLabel(playerObj)),
        script_version = tostring(MP.SCRIPT_VERSION),
        script_build = tostring(MP.SCRIPT_BUILD),
    }

    local ok, err = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.REQUEST_SNAPSHOT_COMMAND), args)
    if not ok then
        log("snapshot request send failed: " .. tostring(err))
        return false
    end

    mpClient.lastRequestWallSecond = nowSecond
    return true
end

local function parseServerSnapshot(args)
    if type(args) ~= "table" then
        return nil
    end
    local parsedDrivers = {}
    if type(args.drivers) == "table" then
        for i = 1, #args.drivers do
            local row = args.drivers[i]
            if type(row) == "table" then
                parsedDrivers[#parsedDrivers + 1] = {
                    label = tostring(row.label or "Unknown Item"),
                    physical = tonumber(row.physical) or 0,
                }
            end
        end
    end
    return {
        loadNorm = tonumber(args.load_norm) or 0,
        physicalLoad = tonumber(args.physical_load) or 0,
        thermalLoad = tonumber(args.thermal_load) or 0,
        breathingLoad = tonumber(args.breathing_load) or 0,
        rigidityLoad = tonumber(args.rigidity_load) or 0,
        armorCount = tonumber(args.armor_count) or 0,
        effectiveLoad = tonumber(args.effective_load) or 0,
        drivers = parsedDrivers,
        activityLabel = tostring(args.activity_label or "idle"),
        hotStrain = toBoolean(args.thermal_hot) and 1 or 0,
        coldAppropriateness = toBoolean(args.thermal_cold) and 1 or 0,
        thermalPressureScale = tonumber(args.thermal_pressure_scale) or 0,
        enduranceEnvFactor = tonumber(args.endurance_env_factor) or 1,
        updatedMinute = tonumber(args.updated_minute) or 0,
        source = "server_snapshot",
    }
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end

    if tostring(command) == tostring(MP.SNAPSHOT_COMMAND) then
        local playerObj = getLocalPlayer()
        local state, mpClient = ensureState(playerObj)
        if not state or not mpClient then
            return
        end

        local snapshot = parseServerSnapshot(args)
        if not snapshot then
            return
        end

        state.mpServerSnapshot = snapshot
        mpClient.lastSnapshotWallSecond = getWallClockSeconds()
        if not firstSnapshotLogged then
            firstSnapshotLogged = true
            log(string.format(
                "received first snapshot load_norm=%.3f physical=%.2f drivers=%d activity=%s hot=%s cold=%s updated_minute=%.2f",
                tonumber(snapshot.loadNorm) or 0,
                tonumber(snapshot.physicalLoad) or 0,
                #(snapshot.drivers or {}),
                tostring(snapshot.activityLabel or "idle"),
                tostring((tonumber(snapshot.hotStrain) or 0) > 0),
                tostring((tonumber(snapshot.coldAppropriateness) or 0) > 0),
                tonumber(snapshot.updatedMinute) or 0
            ))
        end
        markUiDirty()
        return
    end
end

local function onConnected()
    clearSnapshotState(getLocalPlayer(), true)
    ensureMpUiHooks(getLocalPlayer())
    sendSnapshotRequest(getLocalPlayer(), "OnConnected", true)
end

function ams_mp_snapshot_status()
    local _, state, mpClient = readLatestSnapshotState()
    local snapshot = state and state.mpServerSnapshot or nil
    if type(snapshot) ~= "table" then
        log("snapshot status: none yet")
        return nil
    end
    local nowSecond = getWallClockSeconds()
    local ageSeconds = nowSecond - (tonumber(mpClient and mpClient.lastSnapshotWallSecond) or nowSecond)
    log(string.format(
        "snapshot status: load_norm=%.3f physical=%.2f drivers=%d activity=%s hot=%s cold=%s updated_minute=%.2f age_s=%.1f",
        tonumber(snapshot.loadNorm) or 0,
        tonumber(snapshot.physicalLoad) or 0,
        #(snapshot.drivers or {}),
        tostring(snapshot.activityLabel or "idle"),
        tostring((tonumber(snapshot.hotStrain) or 0) > 0),
        tostring((tonumber(snapshot.coldAppropriateness) or 0) > 0),
        tonumber(snapshot.updatedMinute) or 0,
        tonumber(ageSeconds) or 0
    ))
    return snapshot
end

local function onCreatePlayer(playerIndex, playerObj)
    if playerObj and type(playerObj.isLocalPlayer) == "function" and not playerObj:isLocalPlayer() then
        return
    end
    local player = playerObj or getLocalPlayer()
    clearSnapshotState(player, true)
    ensureMpUiHooks(player)
    sendSnapshotRequest(player, "OnCreatePlayer", true)
end

local function onClothingUpdated()
    local player = getLocalPlayer()
    expireStaleSnapshot(player)
    sendSnapshotRequest(player, "OnClothingUpdated", true)
end

local function onEveryOneMinute()
    local player = getLocalPlayer()
    expireStaleSnapshot(player)
    ensureMpUiHooks(player)
    sendSnapshotRequest(player, "EveryOneMinute", false)
end

local function onPlayerUpdate(playerObj)
    local player = playerObj or getLocalPlayer()
    if not player then
        return
    end
    expireStaleSnapshot(player)
    ensureMpUiHooks(player)
    sendSnapshotRequest(player, "OnPlayerUpdate", false)
end

local function logBootBanner(contextTag)
    log(string.format(
        "[BOOT_MP] context=%s side=client isClient=%s isServer=%s ingame=%s scriptVersion=%s build=%s",
        tostring(contextTag or "load"),
        tostring(type(isClient) == "function" and isClient() or false),
        tostring(type(isServer) == "function" and isServer() or false),
        tostring(GameClient and GameClient.ingame or false),
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end

local function registerEvents()
    if ArmorMakesSense._mpClientRuntimeRegistered then
        return
    end
    ArmorMakesSense._mpClientRuntimeRegistered = true

    if Events and Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(onServerCommand)
    end
    if Events and Events.OnConnected and type(Events.OnConnected.Add) == "function" then
        Events.OnConnected.Add(onConnected)
    end
    if Events and Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
        Events.OnCreatePlayer.Add(onCreatePlayer)
    end
    if Events and Events.OnClothingUpdated and type(Events.OnClothingUpdated.Add) == "function" then
        Events.OnClothingUpdated.Add(onClothingUpdated)
    end
    if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    end
    if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    end
end

registerEvents()
logBootBanner("load")
clearSnapshotState(getLocalPlayer(), true)
sendSnapshotRequest(getLocalPlayer(), "load", true)
