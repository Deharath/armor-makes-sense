ArmorMakesSense = ArmorMakesSense or {}

local MP = require "ArmorMakesSense_MPCompat"
require "ArmorMakesSense_Compat"
local RuntimeState = require "ArmorMakesSense_RuntimeState"
local SleepOwnership = require "ArmorMakesSense_SleepOwnership"
local Utils = require "ArmorMakesSense_UtilsShared"
local MPClientRuntime = {}
ArmorMakesSense.MPClientRuntime = MPClientRuntime

local SnapshotCodec = require "ArmorMakesSense_MPSnapshotCodec"

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Options = require "ArmorMakesSense_Options"
local UI = require "core/ArmorMakesSense_UI"

local SNAPSHOT_REQUEST_MIN_SECONDS = math.max(1, math.floor(tonumber(MP.SNAPSHOT_REQUEST_MIN_SECONDS) or 5))
local SNAPSHOT_REQUEST_TIMEOUT_SECONDS = math.max(
    SNAPSHOT_REQUEST_MIN_SECONDS,
    math.floor(tonumber(MP.SNAPSHOT_REQUEST_TIMEOUT_SECONDS) or 60)
)
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
    mpClient.snapshotRequestPending = mpClient.snapshotRequestPending == true

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
    mpClient.snapshotRequestPending = false
    if resetLogLatch then
        mpClient.firstSnapshotLogged = false
    end
    if hadSnapshot then
        markUiDirty()
    end
    return hadSnapshot
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

local function sendSnapshotRequest(playerObj)
    if not canSendRequest(playerObj) then
        return false
    end

    local state, mpClient = ensureState(playerObj)
    if not state or not mpClient then
        return false
    end

    local nowSecond = Utils.getWallClockSeconds()
    local lastRequest = tonumber(mpClient.lastRequestWallSecond) or 0
    local requestAge = nowSecond - lastRequest
    if mpClient.snapshotRequestPending
        and lastRequest > 0
        and nowSecond >= lastRequest
        and requestAge < SNAPSHOT_REQUEST_TIMEOUT_SECONDS then
        return false, "pending"
    end
    if lastRequest > 0
        and nowSecond >= lastRequest
        and requestAge < SNAPSHOT_REQUEST_MIN_SECONDS then
        return false, "throttled"
    end

    local ok, err = pcall(
        sendClientCommand,
        playerObj,
        tostring(MP.NET_MODULE),
        tostring(MP.REQUEST_SNAPSHOT_COMMAND),
        {}
    )
    if not ok then
        log("snapshot request send failed: " .. tostring(err))
        return false, "send_failed"
    end

    mpClient.lastRequestWallSecond = math.max(1, nowSecond)
    mpClient.snapshotRequestPending = true
    return true, "sent"
end

function MPClientRuntime.requestSnapshot(playerObj, maxAgeSeconds)
    local player = playerObj or ClientRuntime.getLocalPlayer()
    local state, mpClient = ensureState(player)
    if not state or not mpClient then
        return false, "state_unavailable"
    end

    local maxAge = math.max(0, tonumber(maxAgeSeconds) or 0)
    local lastSnapshot = tonumber(mpClient.lastSnapshotWallSecond) or 0
    local snapshotAge = lastSnapshot > 0 and math.max(0, Utils.getWallClockSeconds() - lastSnapshot) or nil
    if type(state.mpServerSnapshot) == "table"
        and snapshotAge ~= nil
        and snapshotAge <= maxAge then
        return false, "fresh"
    end

    return sendSnapshotRequest(player)
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

        state.mpServerSnapshot = snapshot
        mpClient.lastSnapshotWallSecond = Utils.getWallClockSeconds()
        mpClient.snapshotRequestPending = false
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

    if tostring(command) == tostring(MP.SLEEP_STATE_COMMAND) then
        local playerObj = resolveSnapshotPlayer(args)
        if not playerObj then
            return
        end
        reconcileAuthoritativeWakeState(playerObj, args)
        applyAuthoritativeFatigue(playerObj, args)
        return
    end
end

local function onConnected()
    ClientRuntime.forEachLocalPlayer(function(player)
        clearSnapshotState(player, true)
        ensureMpUiHooks(player)
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
    ensureMpUiHooks(player)
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
    end)
    return true
end

return MPClientRuntime
