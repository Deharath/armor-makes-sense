ArmorMakesSense = ArmorMakesSense or {}

local MP = require "ArmorMakesSense_MPCompat"
require "ArmorMakesSense_Compat"
local RuntimeState = require "ArmorMakesSense_RuntimeState"
local SleepOwnership = require "ArmorMakesSense_SleepOwnership"
local Utils = require "ArmorMakesSense_UtilsShared"
local MPClientRuntime = {}
ArmorMakesSense.MPClientRuntime = MPClientRuntime

local SnapshotCodec = require "ArmorMakesSense_MPSnapshotCodec"

local IncidentTrace = require "core/ArmorMakesSense_IncidentTrace"
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Options = require "ArmorMakesSense_Options"
local UI = require "core/ArmorMakesSense_UI"

local SNAPSHOT_INTERVAL_SECONDS = math.max(1, math.floor(tonumber(MP.SNAPSHOT_FALLBACK_SECONDS) or 2))
local SNAPSHOT_STALE_SECONDS = math.max(10, SNAPSHOT_INTERVAL_SECONDS * 4)
local uiHooksEnsured = false
local markUiDirty
local SLEEP_FATIGUE_CORRECTION_EPSILON = 0.002

local function log(message)
    print("[ArmorMakesSense][MP][CLIENT] " .. tostring(message))
end

local function isMultiplayerClientSession(playerObj)
    if GameClient and GameClient.bClient ~= nil then
        return GameClient.bClient == true
    end
    local onlineId = tonumber(playerObj and Utils.safeMethod(playerObj, "getOnlineID") or nil)
    return onlineId ~= nil and onlineId >= 0
end

local function ensureState(playerObj)
    local state = RuntimeState.get(playerObj, RuntimeState.ROLE_MP_CLIENT)
    if not state then
        return nil
    end
    state.mpClient = type(state.mpClient) == "table" and state.mpClient or {}

    local mpClient = state.mpClient
    mpClient.lastRequestWallSecond = tonumber(mpClient.lastRequestWallSecond) or 0
    mpClient.lastSnapshotWallSecond = tonumber(mpClient.lastSnapshotWallSecond) or 0

    return state, mpClient
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
        mpClient.firstSnapshotLogged = false
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
    local ageSeconds = Utils.getWallClockSeconds() - lastSnapshot
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
    pcall(UI.markDirty)
end

local function ensureMpUiHooks(playerObj)
    if uiHooksEnsured then
        return true
    end
    local okUpdate = pcall(UI.update, playerObj or ClientRuntime.getLocalPlayer(), nil, Options.get())
    if okUpdate then
        uiHooksEnsured = true
        log("MP UI hooks ensured (Burden tab/fallback active)")
        return true
    end
    return false
end

local function getFatigue(playerObj)
    local stats = Utils.safeMethod(playerObj, "getStats")
    if not stats then
        return nil
    end
    local fatigue = tonumber(Utils.safeMethod(stats, "getFatigue"))
    if fatigue ~= nil then
        return fatigue
    end
    if CharacterStat and CharacterStat.FATIGUE then
        return tonumber(Utils.safeMethod(stats, "get", CharacterStat.FATIGUE))
    end
    return nil
end

local function setFatigue(playerObj, value)
    local stats = Utils.safeMethod(playerObj, "getStats")
    if not stats then
        return false
    end
    local clamped = math.max(0, math.min(1, tonumber(value) or 0))
    if type(stats.setFatigue) == "function" then
        Utils.safeMethod(stats, "setFatigue", clamped)
        return true
    end
    if CharacterStat and CharacterStat.FATIGUE then
        Utils.safeMethod(stats, "set", CharacterStat.FATIGUE, clamped)
        return true
    end
    return false
end

local function reconcileAuthoritativeWakeState(playerObj, snapshot)
    if not playerObj or type(snapshot) ~= "table" then
        return false
    end
    if snapshot.serverSleeping ~= false or tostring(snapshot.reason or "") ~= "WakeTransition" then
        return false
    end
    if not SleepOwnership.amsOwnsFatigue(Options.get()) then
        return false
    end
    if not Utils.toBoolean(Utils.safeMethod(playerObj, "isAsleep")) then
        return false
    end

    if type(getSleepingEvent) ~= "function" then
        log("authoritative wake could not resolve vanilla SleepingEvent")
        return false
    end
    local okEvent, sleepingEvent = pcall(getSleepingEvent)
    if not okEvent or not sleepingEvent then
        log("authoritative wake could not resolve vanilla SleepingEvent")
        return false
    end
    local okWake, wakeFailure = pcall(function()
        sleepingEvent:wakeUp(playerObj, true)
    end)
    if not okWake then
        log("authoritative vanilla wake failed: " .. tostring(wakeFailure))
        return false
    end
    log("reconciled local wake state from authoritative server snapshot")
    return true
end

local function applyAuthoritativeFatigue(playerObj, snapshot)
    if not playerObj or type(snapshot) ~= "table" then
        return false
    end
    if not SleepOwnership.amsOwnsFatigue(Options.get()) then
        return false
    end
    local serverSleeping = snapshot.serverSleeping == true
    local reason = tostring(snapshot.reason or "")
    if (not serverSleeping) and reason ~= "WakeTransition" then
        return false
    end
    local authoritative = tonumber(snapshot.authoritativeFatigue)
    if authoritative == nil then
        return false
    end
    local current = getFatigue(playerObj)
    if current ~= nil and math.abs(current - authoritative) <= SLEEP_FATIGUE_CORRECTION_EPSILON then
        return false
    end
    local applied = setFatigue(playerObj, authoritative)
    if applied then
        if serverSleeping then
            log(string.format(
                "applied authoritative sleep fatigue current=%.3f server=%.3f",
                tonumber(current) or -1,
                tonumber(authoritative) or -1
            ))
        else
            log(string.format(
                "applied authoritative wake fatigue current=%.3f server=%.3f",
                tonumber(current) or -1,
                tonumber(authoritative) or -1
            ))
        end
    end
    return applied
end

local function sendSnapshotRequest(playerObj, reason)
    if not canSendRequest(playerObj) then
        return false
    end

    local state, mpClient = ensureState(playerObj)
    if not state or not mpClient then
        return false
    end

    local nowSecond = Utils.getWallClockSeconds()
    local lastRequest = tonumber(mpClient.lastRequestWallSecond) or 0
    if lastRequest > 0
        and nowSecond >= lastRequest
        and (nowSecond - lastRequest) < SNAPSHOT_INTERVAL_SECONDS then
        return false
    end

    local args = {
        reason = tostring(reason or "fallback"),
        incident_seq = tonumber(IncidentTrace.getSeq()) or 0,
    }

    local ok, err = pcall(
        sendClientCommand,
        playerObj,
        tostring(MP.NET_MODULE),
        tostring(MP.REQUEST_SNAPSHOT_COMMAND),
        args
    )
    if not ok then
        log("snapshot request send failed: " .. tostring(err))
        return false
    end

    mpClient.lastRequestWallSecond = math.max(1, nowSecond)
    return true
end

local function resolveSnapshotPlayer(args)
    local expectedOnlineId = tonumber(args and args.player_online_id)
    local fallback = nil
    local matched = nil
    ClientRuntime.forEachLocalPlayer(function(playerObj)
        fallback = fallback or playerObj
        local onlineId = tonumber(Utils.safeMethod(playerObj, "getOnlineID"))
        if expectedOnlineId ~= nil and onlineId == expectedOnlineId then
            matched = playerObj
        end
    end)
    return matched or fallback
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end

    if tostring(command) == tostring(MP.SNAPSHOT_COMMAND) then
        local playerObj = resolveSnapshotPlayer(args)
        local state, mpClient = ensureState(playerObj)
        if not state or not mpClient then
            return
        end

        local snapshot, decodeError = SnapshotCodec.decode(args)
        if not snapshot then
            log("snapshot rejected: " .. tostring(decodeError))
            return
        end

        reconcileAuthoritativeWakeState(playerObj, snapshot)
        applyAuthoritativeFatigue(playerObj, snapshot)
        state.mpServerSnapshot = snapshot
        mpClient.lastSnapshotWallSecond = Utils.getWallClockSeconds()
        if type(args.incident_trace) == "table" then
            IncidentTrace.applyServerIncident(args.incident_trace)
        end
        if not mpClient.firstSnapshotLogged then
            mpClient.firstSnapshotLogged = true
            log(string.format(
                "received first snapshot load_norm=%.3f physical=%.2f drivers=%d activity=%s hot=%s cold=%s updated_minute=%.2f",
                tonumber(snapshot.loadNorm) or 0,
                tonumber(snapshot.physicalLoad) or 0,
                #(snapshot.drivers or {}),
                tostring(snapshot.activityLabel or "idle"),
                tostring((tonumber(snapshot.hotPressure) or 0) > 0),
                tostring((tonumber(snapshot.coldSuitability) or 0) > 0),
                tonumber(snapshot.updatedMinute) or 0
            ))
        end
        markUiDirty()
        return
    end
end

local function onConnected()
    IncidentTrace.clear()
    ClientRuntime.forEachLocalPlayer(function(player)
        clearSnapshotState(player, true)
        ensureMpUiHooks(player)
        sendSnapshotRequest(player, "OnConnected")
    end)
end

function ams_mp_snapshot_status()
    local state, mpClient = ensureState(ClientRuntime.getLocalPlayer())
    local snapshot = state and state.mpServerSnapshot or nil
    if type(snapshot) ~= "table" then
        log("snapshot status: none yet")
        return nil
    end
    local nowSecond = Utils.getWallClockSeconds()
    local ageSeconds = nowSecond - (tonumber(mpClient and mpClient.lastSnapshotWallSecond) or nowSecond)
    log(string.format(
        "snapshot status: load_norm=%.3f physical=%.2f drivers=%d activity=%s hot=%s cold=%s updated_minute=%.2f age_s=%.1f",
        tonumber(snapshot.loadNorm) or 0,
        tonumber(snapshot.physicalLoad) or 0,
        #(snapshot.drivers or {}),
        tostring(snapshot.activityLabel or "idle"),
        tostring((tonumber(snapshot.hotPressure) or 0) > 0),
        tostring((tonumber(snapshot.coldSuitability) or 0) > 0),
        tonumber(snapshot.updatedMinute) or 0,
        tonumber(ageSeconds) or 0
    ))
    return snapshot
end

local function onCreatePlayer(_playerIndex, playerObj)
    if playerObj and type(playerObj.isLocalPlayer) == "function" and not playerObj:isLocalPlayer() then
        return
    end
    local player = playerObj or ClientRuntime.getLocalPlayer()
    clearSnapshotState(player, true)
    IncidentTrace.clear()
    ensureMpUiHooks(player)
    sendSnapshotRequest(player, "OnCreatePlayer")
end

local function onClothingUpdated(changedPlayer)
    if changedPlayer and not ClientRuntime.isLocalPlayer(changedPlayer) then
        return
    end
    if changedPlayer then
        expireStaleSnapshot(changedPlayer)
        sendSnapshotRequest(changedPlayer, "OnClothingUpdated")
        return
    end
    ClientRuntime.forEachLocalPlayer(function(player)
        expireStaleSnapshot(player)
        sendSnapshotRequest(player, "OnClothingUpdated")
    end)
end

local function onEveryOneMinute()
    ClientRuntime.forEachLocalPlayer(function(player)
        local expired = expireStaleSnapshot(player)
        ensureMpUiHooks(player)
        local state = ensureState(player)
        if expired or not (state and type(state.mpServerSnapshot) == "table") then
            sendSnapshotRequest(player, "SnapshotRecovery")
        end
    end)
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

function MPClientRuntime.registerEvents(mod)
    local requiredEvents = {
        "OnServerCommand",
        "OnConnected",
        "OnCreatePlayer",
        "OnClothingUpdated",
        "EveryOneMinute",
    }
    for i = 1, #requiredEvents do
        local name = requiredEvents[i]
        if not (Events and Events[name] and type(Events[name].Add) == "function") then
            log("runtime registration failed: Events." .. name .. ".Add unavailable")
            return false
        end
    end

    local previousHandlers = mod and mod._mpClientRuntimeHandlers or nil
    for eventName, handler in pairs(previousHandlers or {}) do
        local event = Events[eventName]
        if event and type(event.Remove) == "function" then
            pcall(event.Remove, handler)
        end
    end

    local handlers = {
        OnServerCommand = onServerCommand,
        OnConnected = onConnected,
        OnCreatePlayer = onCreatePlayer,
        OnClothingUpdated = onClothingUpdated,
        EveryOneMinute = onEveryOneMinute,
    }
    local added = {}
    for eventName, handler in pairs(handlers) do
        local ok, failure = pcall(Events[eventName].Add, handler)
        if not ok then
            for addedEventName, addedHandler in pairs(added) do
                local event = Events[addedEventName]
                if event and type(event.Remove) == "function" then
                    pcall(event.Remove, addedHandler)
                end
            end
            ArmorMakesSense._mpClientRuntimeRegistered = false
            log("runtime registration failed: Events." .. eventName .. ".Add raised " .. tostring(failure))
            return false
        end
        added[eventName] = handler
    end
    ArmorMakesSense._mpClientRuntimeRegistered = true
    if mod then
        mod._mpClientRuntimeHandlers = handlers
    end
    logBootBanner("load")
    ClientRuntime.forEachLocalPlayer(function(player)
        clearSnapshotState(player, true)
        sendSnapshotRequest(player, "load")
    end)
    return true
end

return MPClientRuntime
