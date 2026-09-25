ArmorMakesSense = ArmorMakesSense or {}

local MP = require "ArmorMakesSense_MPCompat"
require "ArmorMakesSense_Compat"
local Logger = require "ArmorMakesSense_Logger"
local RuntimeState = require "ArmorMakesSense_RuntimeState"
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

local function log(message)
    Logger.debug("role=mp-client " .. tostring(message))
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
        Logger.error("role=mp-client snapshot request send failed: " .. tostring(err))
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
            Logger.warn("role=mp-client snapshot rejected: " .. tostring(decodeError))
            return
        end

        state.mpServerSnapshot = snapshot
        mpClient.lastSnapshotWallSecond = Utils.getWallClockSeconds()
        mpClient.snapshotRequestPending = false
        if not mpClient.firstSnapshotLogged then
            mpClient.firstSnapshotLogged = true
            log(string.format(
                "received first snapshot load_fraction=%.3f burden_kg=%.2f drivers=%d activity=%s hot=%s cold=%s updated_minute=%.2f",
                tonumber(snapshot.loadFraction) or 0,
                tonumber(snapshot.burdenKg) or 0,
                #(snapshot.drivers or {}),
                tostring(snapshot.activityLabel or "idle"),
                tostring((tonumber(snapshot.hotPressure) or 0) > 0),
                tostring((tonumber(snapshot.coldSuitability) or 0) > 0),
                tonumber(snapshot.updatedMinute) or 0
            ))
        end
        markUiDirty()
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
        Logger.info("role=mp-client snapshot status: none yet")
        return nil
    end
    local nowSecond = Utils.getWallClockSeconds()
    local ageSeconds = nowSecond - (tonumber(mpClient and mpClient.lastSnapshotWallSecond) or nowSecond)
    Logger.info(string.format(
        "role=mp-client snapshot status: load_fraction=%.3f burden_kg=%.2f drivers=%d activity=%s hot=%s cold=%s updated_minute=%.2f age_s=%.1f",
        tonumber(snapshot.loadFraction) or 0,
        tonumber(snapshot.burdenKg) or 0,
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

local function logBootBanner()
    Logger.info(string.format(
        "[BOOT] loaded version=%s build=%s role=mp-client",
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
            Logger.error("role=mp-client runtime registration failed: Events." .. name .. ".Add unavailable")
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
            Logger.error(
                "role=mp-client runtime registration failed: Events."
                .. eventName .. ".Add raised " .. tostring(failure)
            )
            return false
        end
        added[eventName] = handler
    end
    ArmorMakesSense._mpClientRuntimeRegistered = true
    if mod then
        mod._mpClientRuntimeHandlers = handlers
    end
    logBootBanner()
    ClientRuntime.forEachLocalPlayer(function(player)
        clearSnapshotState(player, true)
    end)
    return true
end

return MPClientRuntime
