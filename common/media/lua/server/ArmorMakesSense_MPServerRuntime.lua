ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local MP = require "ArmorMakesSense_MPCompat"
require "ArmorMakesSense_Compat"
local Logger = require "ArmorMakesSense_Logger"
local Options = require "ArmorMakesSense_Options"
local Utils = require "ArmorMakesSense_UtilsShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Strain = require "ArmorMakesSense_StrainShared"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local RequestPolicy = require "ArmorMakesSense_MPRequestPolicy"
local SnapshotCodec = require "ArmorMakesSense_MPSnapshotCodec"
local RuntimeState = require "ArmorMakesSense_RuntimeState"

-- CharacterStat.FATIGUE bit in SyncPlayerStatsPacket's ordered-stat mask.
local FATIGUE_STAT_MASK = 16
local WORN_PROFILE_CACHE_WALL_SECONDS = 1

local safeCall = Utils.safeMethod
local getWallClockSeconds = Utils.getWallClockSeconds

local function log(message)
    Logger.debug("role=mp-server " .. tostring(message))
end

local function playerName(playerObj)
    local username = playerObj and safeCall(playerObj, "getUsername") or nil
    if username ~= nil and tostring(username) ~= "" then
        return tostring(username)
    end
    return "unknown"
end

local function ensurePlayerState(playerObj)
    local state = RuntimeState.get(playerObj, RuntimeState.ROLE_MP_SERVER)
    if not state then
        return nil
    end
    state.mpServer = type(state.mpServer) == "table" and state.mpServer or {}
    return state.mpServer
end

local function forEachOnlinePlayer(fn)
    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and safeCall(onlinePlayers, "size")) or 0
    for i = 0, count - 1 do
        local playerObj = safeCall(onlinePlayers, "get", i)
        if playerObj then
            fn(playerObj)
        end
    end
end

local function analyze(playerObj, mpState, options)
    local analysis = LoadModel.analyzeWornGear(playerObj, options)
    mpState.cachedWornProfile = analysis.profile
    mpState.cachedWornProfileWallSecond = getWallClockSeconds()
    return analysis
end

local function syncFatigue(playerObj)
    if type(syncPlayerStats) ~= "function" then
        return
    end
    local ok, err = pcall(syncPlayerStats, playerObj, FATIGUE_STAT_MASK)
    if not ok then
        Logger.error("role=mp-server fatigue sync failed player=" .. playerName(playerObj) .. " err=" .. tostring(err))
    end
end

local function sendSnapshot(playerObj, snapshot)
    if type(sendServerCommand) ~= "function" or type(snapshot) ~= "table" then
        return false
    end
    local args = SnapshotCodec.encode(snapshot)
    args.player_online_id = tonumber(safeCall(playerObj, "getOnlineID")) or -1
    local ok, err = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.SNAPSHOT_COMMAND), args)
    if not ok then
        Logger.error("role=mp-server snapshot send failed player=" .. playerName(playerObj) .. " err=" .. tostring(err))
        return false
    end
    return true
end

local function flushPendingSnapshot(playerObj, mpState)
    local snapshot = mpState.runtimeSnapshot
    if not RequestPolicy.canFlushSnapshot(mpState, snapshot) then
        return false
    end
    if not sendSnapshot(playerObj, snapshot) then
        return false
    end
    RequestPolicy.completeSnapshotRequest(mpState)
    return true
end

local function tickPlayer(playerObj)
    local mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end
    local options = Options.get()
    local analysis = analyze(playerObj, mpState, options)
    local snapshot = Physiology.tick(playerObj, mpState, options, analysis.profile, Utils.getWorldAgeMinutes())
    if (tonumber(mpState.lastSleepExtraFatigue) or 0) > 0 then
        syncFatigue(playerObj)
    end
    snapshot.drivers = analysis.costDrivers
    mpState.runtimeSnapshot = snapshot
    flushPendingSnapshot(playerObj, mpState)
end

local function onEveryOneMinute()
    forEachOnlinePlayer(function(playerObj)
        local ok, err = pcall(tickPlayer, playerObj)
        if not ok then
            Logger.error("role=mp-server tick failed player=" .. playerName(playerObj) .. " err=" .. tostring(err))
        end
    end)
end

local function refreshPresentationSnapshot(playerObj, mpState)
    local options = Options.get()
    local analysis = analyze(playerObj, mpState, options)
    local snapshot = Physiology.project(playerObj, mpState, options, analysis.profile)
    snapshot.drivers = analysis.costDrivers
    mpState.runtimeSnapshot = snapshot
end

local function onClientCommand(module, command, playerObj, _args)
    if tostring(module) ~= tostring(MP.NET_MODULE) or tostring(command) ~= tostring(MP.REQUEST_SNAPSHOT_COMMAND) then
        return
    end
    local mpState = ensurePlayerState(playerObj)
    if not mpState or not RequestPolicy.acceptSnapshotRequest(
        mpState,
        getWallClockSeconds(),
        MP.SNAPSHOT_REQUEST_MIN_SECONDS
    ) then
        return
    end
    RequestPolicy.queueSnapshotRequest(mpState)
    local ok, err = pcall(refreshPresentationSnapshot, playerObj, mpState)
    if not ok then
        Logger.error("role=mp-server snapshot refresh failed player=" .. playerName(playerObj) .. " err=" .. tostring(err))
    end
    flushPendingSnapshot(playerObj, mpState)
end

local function onWeaponSwing(playerObj, weapon)
    local options = Options.get()
    if not playerObj or not weapon or not Utils.toBoolean(options.EnableMuscleStrainModel) then
        return
    end
    local mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end
    local profile = mpState.cachedWornProfile
    local age = getWallClockSeconds() - (tonumber(mpState.cachedWornProfileWallSecond) or 0)
    if type(profile) ~= "table" or age < 0 or age >= WORN_PROFILE_CACHE_WALL_SECONDS then
        profile = analyze(playerObj, mpState, options).profile
    end
    local ok, err = pcall(Strain.applyArmorStrainOverlay, playerObj, weapon, options, profile)
    if not ok then
        Logger.error("role=mp-server strain overlay failed player=" .. playerName(playerObj) .. " err=" .. tostring(err))
    end
end

local function registerCompatProvider()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or type(compat.registerProvider) ~= "function" then
        return
    end
    local capabilities = { endurance_coordinator = true }
    local callbacks = {
        buildTraceSnapshot = function(playerObj, _args)
            local mpState = ensurePlayerState(playerObj)
            return mpState and Physiology.buildCompatTraceSnapshot(mpState) or {}
        end,
    }
    if Options.get().EnableSleepPenaltyModel then
        capabilities.sleep_penalty_provider = true
        capabilities.sleep_planner_penalty_provider = true
        local function contribution(playerObj)
            local options = Options.get()
            return Physiology.sleepPenaltyContribution(
                playerObj,
                options,
                playerObj and LoadModel.computeWornProfile(playerObj, options) or nil
            )
        end
        callbacks.computeSleepPenaltyContribution = function(playerObj, _args)
            return contribution(playerObj)
        end
        callbacks.estimateSleepPlannerPenalty = function(playerObj, _args)
            return { penaltyFraction = contribution(playerObj).penaltyFraction }
        end
    end
    compat:registerProvider("ArmorMakesSense", {
        capabilities = capabilities,
        callbacks = callbacks,
    })
end

local function registerEvents()
    local handlers = {
        OnClientCommand = onClientCommand,
        EveryOneMinute = onEveryOneMinute,
        OnWeaponSwing = onWeaponSwing,
    }
    for eventName, handler in pairs(ArmorMakesSense._mpServerRuntimeHandlers or {}) do
        local event = Events and Events[eventName] or nil
        if event and type(event.Remove) == "function" then
            pcall(event.Remove, handler)
        end
    end
    for eventName in pairs(handlers) do
        local event = Events and Events[eventName] or nil
        if not event or type(event.Add) ~= "function" then
            ArmorMakesSense._mpServerRuntimeRegistered = false
            Logger.error("role=mp-server runtime registration failed: Events." .. eventName .. ".Add unavailable")
            return false
        end
    end
    for eventName, handler in pairs(handlers) do
        Events[eventName].Add(handler)
    end
    ArmorMakesSense._mpServerRuntimeHandlers = handlers
    ArmorMakesSense._mpServerRuntimeRegistered = true
    log("authoritative runtime handlers registered")
    return true
end

registerCompatProvider()

if registerEvents() then
    Logger.info(string.format(
        "[BOOT] loaded version=%s build=%s role=mp-server",
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end
