ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local MP = require "ArmorMakesSense_MPCompat"
require "ArmorMakesSense_Compat"
local Logger = require "ArmorMakesSense_Logger"
local Options = require "ArmorMakesSense_Options"
local SleepOwnership = require "ArmorMakesSense_SleepOwnership"
local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = require "ArmorMakesSense_StatsShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local Strain = require "ArmorMakesSense_StrainShared"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local RequestPolicy = require "ArmorMakesSense_MPRequestPolicy"
local SnapshotCodec = require "ArmorMakesSense_MPSnapshotCodec"
local SnapshotBuilder = require "ArmorMakesSense_MPSnapshotBuilder"
local RuntimeState = require "ArmorMakesSense_RuntimeState"
local Simulation = require "ArmorMakesSense_Simulation"
local FATIGUE_STAT_MASK = 16
local SLEEP_FATIGUE_SYNC_INTERVAL_WALL_SECONDS = 5
local SLEEP_REALTIME_UPDATE_WALL_SECONDS = 1
local WORN_PROFILE_CACHE_WALL_SECONDS = 1
local MAX_APPLIED_ENDURANCE_DROP_PER_INVOCATION = 0.12
local lastSleepScanWallSecond = 0

local function log(message)
    Logger.debug("role=mp-server " .. tostring(message))
end

local safeCall = Utils.safeMethod
local toBoolean = Utils.toBoolean
local getWorldAgeMinutes = Utils.getWorldAgeMinutes
local getEndurance = Stats.getEndurance
local getFatigue = Stats.getFatigue
local getWallClockSeconds = Utils.getWallClockSeconds

local function playerName(playerObj)
    if not playerObj then
        return "unknown"
    end
    local username = safeCall(playerObj, "getUsername")
    if username ~= nil and tostring(username) ~= "" then
        return tostring(username)
    end
    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName ~= nil and tostring(displayName) ~= "" then
        return tostring(displayName)
    end
    return "unknown"
end

local function ensurePlayerState(playerObj)
    local state = RuntimeState.get(playerObj, RuntimeState.ROLE_MP_SERVER)
    if not state then
        return nil
    end
    state.mpServer = type(state.mpServer) == "table" and state.mpServer or {}

    local mpState = state.mpServer
    mpState.lastUpdateGameMinutes = tonumber(mpState.lastUpdateGameMinutes) or getWorldAgeMinutes()
    mpState.lastEnduranceObserved = tonumber(mpState.lastEnduranceObserved)
        or tonumber(getEndurance(playerObj))
    mpState.wasSleeping = toBoolean(mpState.wasSleeping)
    mpState.lastSleepFatigueSyncWallSecond = tonumber(mpState.lastSleepFatigueSyncWallSecond) or 0
    mpState.lastSleepRealtimeUpdateWallSecond = tonumber(mpState.lastSleepRealtimeUpdateWallSecond) or 0
    mpState.lastSleepBedHintWallSecond = tonumber(mpState.lastSleepBedHintWallSecond) or 0
    mpState.lastClientSnapshotRequestWallSecond = tonumber(mpState.lastClientSnapshotRequestWallSecond) or 0
    mpState.pendingSnapshotRequest = mpState.pendingSnapshotRequest == true
    mpState.pendingCatchupMinutes = math.max(0, tonumber(mpState.pendingCatchupMinutes) or 0)
    local pendingSleepBedType = tostring(mpState.pendingSleepBedType or "")
    mpState.pendingSleepBedType = pendingSleepBedType ~= "" and pendingSleepBedType or nil
    mpState.runtimeSnapshot = type(mpState.runtimeSnapshot) == "table" and mpState.runtimeSnapshot or nil
    mpState.cachedWornProfile = type(mpState.cachedWornProfile) == "table" and mpState.cachedWornProfile or nil
    mpState.cachedWornProfileWallSecond = tonumber(mpState.cachedWornProfileWallSecond) or 0
    if type(mpState.lastWakeSyncAsleepFlag) ~= "boolean" then
        mpState.lastWakeSyncAsleepFlag = nil
    end

    return state, mpState
end

local function recordSleepBedType(playerObj, args)
    if not Options.get().EnableSleepPenaltyModel then
        return
    end
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState or not toBoolean(safeCall(playerObj, "isAsleep")) then
        return
    end

    local bedType = tostring(args and args.bed_type or "")
    if bedType == "" or #bedType > 64 then
        return
    end
    local validPrefix = string.find(bedType, "goodBed", 1, true) == 1
        or string.find(bedType, "averageBed", 1, true) == 1
        or string.find(bedType, "badBed", 1, true) == 1
        or string.find(bedType, "floor", 1, true) == 1
    if not validPrefix then
        return
    end
    local nowSecond = getWallClockSeconds()
    local lastHint = tonumber(mpState.lastSleepBedHintWallSecond) or 0
    if lastHint > 0 and nowSecond >= lastHint and (nowSecond - lastHint) < 2 then
        return
    end
    mpState.lastSleepBedHintWallSecond = nowSecond

    mpState.pendingSleepBedType = bedType
    safeCall(playerObj, "setBedType", bedType)

    if type(mpState.sleepSnapshot) == "table"
        and tostring(mpState.sleepSnapshot.bedType or "") == "" then
        mpState.sleepSnapshot.bedType = bedType
    end

    log("sleep bed type from client: player=" .. tostring(playerName(playerObj)) .. " bed=" .. bedType)
end

local function isPlayerAsleep(playerObj)
    return toBoolean(safeCall(playerObj, "isAsleep"))
end

local function sendSleepState(playerObj, reason)
    if type(sendServerCommand) ~= "function" then
        return false
    end
    local args = {
        player_online_id = tonumber(safeCall(playerObj, "getOnlineID")) or -1,
        authoritativeFatigue = tonumber(getFatigue(playerObj)) or 0,
        serverSleeping = isPlayerAsleep(playerObj),
        reason = tostring(reason or "SleepSync"),
    }
    local ok, err = pcall(
        sendServerCommand,
        playerObj,
        tostring(MP.NET_MODULE),
        tostring(MP.SLEEP_STATE_COMMAND),
        args
    )
    if not ok then
        Logger.error(
            "role=mp-server sleep state send failed player="
            .. tostring(playerName(playerObj)) .. " err=" .. tostring(err)
        )
        return false
    end
    return true
end

local function syncFatigueToClient(playerObj, phaseTag)
    if type(syncPlayerStats) ~= "function" then
        return false
    end
    local ok, err = pcall(syncPlayerStats, playerObj, FATIGUE_STAT_MASK)
    if not ok then
        Logger.error("role=mp-server syncPlayerStats fatigue send failed phase=" .. tostring(phaseTag or "unknown")
            .. " player=" .. tostring(playerName(playerObj))
            .. " err=" .. tostring(err))
        return false
    end
    return true
end

local function syncWakeFatigueToClient(playerObj)
    return syncFatigueToClient(playerObj, "wake")
end

local function syncSleepingFatigueToClient(playerObj, mpState)
    if type(mpState) ~= "table" then
        return false
    end
    local nowSecond = getWallClockSeconds()
    local lastSync = tonumber(mpState.lastSleepFatigueSyncWallSecond) or 0
    if lastSync > 0 and (nowSecond - lastSync) < SLEEP_FATIGUE_SYNC_INTERVAL_WALL_SECONDS then
        return false
    end
    local sent = syncFatigueToClient(playerObj, "sleep")
    if sent then
        mpState.lastSleepFatigueSyncWallSecond = nowSecond
        sendSleepState(playerObj, "SleepSync")
    end
    return sent
end

local prepareRuntimeInputs

local function registerCompatProvider()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or type(compat.registerProvider) ~= "function" then
        return
    end

    local options = Options.get()
    local capabilities = {
        endurance_coordinator = true,
    }
    local callbacks = {
        buildTraceSnapshot = function(playerObj, _args)
            local _, mpState = ensurePlayerState(playerObj)
            if not mpState or type(Physiology.buildCompatTraceSnapshot) ~= "function" then
                return {}
            end
            return Physiology.buildCompatTraceSnapshot(mpState)
        end,
    }
    if options.EnableSleepPenaltyModel then
        capabilities.sleep_penalty_provider = true
        capabilities.sleep_planner_penalty_provider = true
        callbacks.computeSleepPenaltyContribution = function(playerObj, args)
            local _, mpState = ensurePlayerState(playerObj)
            if not mpState or type(Physiology.computeSleepPenaltyContribution) ~= "function" then
                return {
                    penaltyFraction = 0,
                    sleeping = false,
                }
            end

            local callbackOptions = Options.get()
            local profile = prepareRuntimeInputs(playerObj, mpState, callbackOptions)
            return Physiology.computeSleepPenaltyContribution(
                playerObj,
                mpState,
                callbackOptions,
                tonumber(args and args.dtMinutes) or 0,
                profile,
                tonumber(args and args.currentFatigue)
            )
        end
        callbacks.estimateSleepPlannerPenalty = function(playerObj, args)
            local _, mpState = ensurePlayerState(playerObj)
            if not mpState or type(Physiology.computeSleepPlannerPenalty) ~= "function" then
                return { penaltyFraction = 0 }
            end

            local callbackOptions = Options.get()
            local profile = prepareRuntimeInputs(playerObj, mpState, callbackOptions)
            return Physiology.computeSleepPlannerPenalty(
                playerObj,
                mpState,
                callbackOptions,
                profile,
                tonumber(args and args.currentFatigue)
            )
        end
    end

    compat:registerProvider("ArmorMakesSense", {
        capabilities = capabilities,
        callbacks = callbacks,
    })
end

registerCompatProvider()

prepareRuntimeInputs = function(playerObj, mpState, options, sleepOnly)
    local analysis = LoadModel.analyzeWornGear(playerObj)
    local profile = analysis.profile
    mpState.cachedWornProfile = profile
    mpState.cachedWornProfileWallSecond = getWallClockSeconds()

    local sleeping = sleepOnly == true
    local drivers = sleeping and {} or analysis.costDrivers
    local activity = Environment.resolveActivity(playerObj, options)
    local activityLabel = activity.label
    local activityFactor = activity.factor
    local postureLabel = sleeping and "sleep" or Environment.getPostureLabel(playerObj)

    return profile, drivers, activityFactor or 1.0,
        tostring(activityLabel or "idle"), tostring(postureLabel or "stand"), analysis
end

local function buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
    return SnapshotBuilder.build(mpState, profile, drivers, activityLabel, getWorldAgeMinutes())
end

local function refreshPresentationSnapshot(playerObj, mpState)
    local options = Options.get()
    local profile, drivers, activityFactor, activityLabel, postureLabel =
        prepareRuntimeInputs(playerObj, mpState, options, false)
    local uiSnapshot = Physiology.projectRuntimeSnapshot(
        playerObj,
        mpState,
        options,
        profile,
        activityFactor,
        activityLabel,
        postureLabel
    )
    if type(uiSnapshot) ~= "table" then
        error("presentation projection did not produce a runtime snapshot")
    end
    local projectionState = {
        uiRuntimeSnapshot = uiSnapshot,
        lastAppliedDtMinutes = mpState.lastAppliedDtMinutes,
        pendingCatchupMinutes = mpState.pendingCatchupMinutes,
    }
    local snapshot = SnapshotBuilder.build(
        projectionState,
        profile,
        drivers,
        activityLabel,
        getWorldAgeMinutes()
    )
    mpState.runtimeSnapshot = snapshot
    return snapshot
end

local function sendSnapshot(playerObj, snapshot)
    if type(sendServerCommand) ~= "function" then
        return
    end
    if type(snapshot) ~= "table" then
        return
    end

    local args = SnapshotCodec.encode(snapshot, true)
    args.player_online_id = tonumber(safeCall(playerObj, "getOnlineID")) or -1

    local ok, err = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.SNAPSHOT_COMMAND), args)
    if not ok then
        Logger.error(
            "role=mp-server snapshot send failed player="
            .. tostring(playerName(playerObj)) .. " err=" .. tostring(err)
        )
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

local function resetCatchupState(playerObj, mpState, nowMinute)
    mpState.lastUpdateGameMinutes = tonumber(nowMinute) or 0
    mpState.pendingCatchupMinutes = 0
    mpState.lastAppliedDtMinutes = 0
    mpState.lastSleepFatigueSyncWallSecond = 0
    mpState.lastSleepRealtimeUpdateWallSecond = 0
    mpState.lastWakeSyncAsleepFlag = nil
    mpState.lastEnduranceObserved = tonumber(getEndurance(playerObj))
end

local function updatePlayer(playerObj, sleepingOverride)
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end

    local nowMinute = tonumber(getWorldAgeMinutes()) or 0
    Simulation.accumulateElapsed(mpState, nowMinute)

    local sleepingNow = type(sleepingOverride) == "boolean" and sleepingOverride or isPlayerAsleep(playerObj)
    if sleepingNow then
        mpState.lastWakeSyncAsleepFlag = true
    end
    local catchupCapped, pendingBeforeCap = Simulation.capActiveCatchup(
        mpState,
        not sleepingNow,
        getEndurance(playerObj)
    )
    if catchupCapped then
        log(string.format(
            "discarding stale active endurance catchup player=%s pending=%.3f cap=%.3f",
            tostring(playerName(playerObj)),
            tonumber(pendingBeforeCap) or 0,
            Simulation.ACTIVE_CATCHUP_MAX_MINUTES
        ))
    end

    if mpState.pendingCatchupMinutes <= 0 then
        flushPendingSnapshot(playerObj, mpState)
        return
    end

    local options = Options.get()
    local snapshot = nil

    if sleepingNow then
        local okInputs, profile, drivers, activityFactor, activityLabel, postureLabel =
            pcall(prepareRuntimeInputs, playerObj, mpState, options, true)
        if not okInputs then
            resetCatchupState(playerObj, mpState, nowMinute)
            Logger.error(
                "role=mp-server sleep input prep failed; pending catchup discarded player="
                .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile)
            )
            return
        end

        local result = Simulation.advance({
            player = playerObj,
            state = mpState,
            options = options,
            nowMinutes = nowMinute,
            profile = profile,
            activityFactor = activityFactor,
            activityLabel = activityLabel,
            postureLabel = postureLabel,
            applySleepTransition = Physiology.applySleepTransition,
        })
        if result.failurePhase then
            Logger.error(string.format(
                "role=mp-server %s model failed player=%s err=%s",
                tostring(result.failurePhase),
                tostring(playerName(playerObj)),
                tostring(result.failure)
            ))
        end

        snapshot = buildRuntimeSnapshot(mpState, profile, {}, "sleep")
        if SleepOwnership.amsOwnsFatigue(options) then
            syncSleepingFatigueToClient(playerObj, mpState)
        end
        if snapshot then
            mpState.runtimeSnapshot = snapshot
            flushPendingSnapshot(playerObj, mpState)
        end
        return
    end

    local okInputs, profile, drivers, activityFactor, activityLabel, postureLabel =
        pcall(prepareRuntimeInputs, playerObj, mpState, options)
    if not okInputs then
        resetCatchupState(playerObj, mpState, nowMinute)
        Logger.error(
            "role=mp-server shared model input prep failed; pending catchup discarded player="
            .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile)
        )
        return
    end

    local cumulativeAppliedDrop = 0
    local result = Simulation.advance({
        player = playerObj,
        state = mpState,
        options = options,
        nowMinutes = nowMinute,
        profile = profile,
        activityFactor = activityFactor,
        activityLabel = activityLabel,
        postureLabel = postureLabel,
        applySleepTransition = Physiology.applySleepTransition,
        applyEnduranceModel = Physiology.applyEnduranceModel,
        afterSlice = function(slice)
            snapshot = buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
            local appliedDelta = tonumber(slice and slice.enduranceResult) or 0
            if appliedDelta < 0 then
                cumulativeAppliedDrop = cumulativeAppliedDrop - appliedDelta
            end
            if cumulativeAppliedDrop >= MAX_APPLIED_ENDURANCE_DROP_PER_INVOCATION then
                return { abort = true, clearPending = true }
            end
        end,
    })
    if result.failurePhase then
        Logger.error(string.format(
            "role=mp-server %s model failed player=%s err=%s",
            tostring(result.failurePhase),
            tostring(playerName(playerObj)),
            tostring(result.failure)
        ))
    end

    if snapshot == nil and type(mpState.runtimeSnapshot) == "table" then
        snapshot = mpState.runtimeSnapshot
    end
    if snapshot then
        mpState.runtimeSnapshot = snapshot
        flushPendingSnapshot(playerObj, mpState)
    end
end

local function updateSleepPlayer(playerObj)
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end

    local sleepingNow = isPlayerAsleep(playerObj)
    local wasSleeping = mpState.lastWakeSyncAsleepFlag == true

    if wasSleeping and not sleepingNow then
        updatePlayer(playerObj, true)
        mpState.lastWakeSyncAsleepFlag = false
        mpState.lastSleepRealtimeUpdateWallSecond = 0
        if SleepOwnership.amsOwnsFatigue(Options.get()) then
            syncWakeFatigueToClient(playerObj)
            sendSleepState(playerObj, "WakeTransition")
        end
        return
    end

    mpState.lastWakeSyncAsleepFlag = sleepingNow
    if not sleepingNow then
        mpState.lastSleepRealtimeUpdateWallSecond = 0
        return
    end

    local nowWallSecond = getWallClockSeconds()
    local lastSleepRealtime = tonumber(mpState.lastSleepRealtimeUpdateWallSecond) or 0
    if lastSleepRealtime > 0 and (nowWallSecond - lastSleepRealtime) < SLEEP_REALTIME_UPDATE_WALL_SECONDS then
        return
    end
    mpState.lastSleepRealtimeUpdateWallSecond = nowWallSecond
    updatePlayer(playerObj, true)
end

local function onPlayerUpdate(_playerObj)
    if not Options.get().EnableSleepPenaltyModel then
        return
    end
    local nowWallSecond = getWallClockSeconds()
    if lastSleepScanWallSecond > 0
        and nowWallSecond >= lastSleepScanWallSecond
        and (nowWallSecond - lastSleepScanWallSecond) < SLEEP_REALTIME_UPDATE_WALL_SECONDS then
        return
    end
    lastSleepScanWallSecond = nowWallSecond

    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and safeCall(onlinePlayers, "size")) or 0
    for i = 0, count - 1 do
        local playerObj = safeCall(onlinePlayers, "get", i)
        if playerObj then
            updateSleepPlayer(playerObj)
        end
    end
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) == tostring(MP.SLEEP_BED_TYPE_COMMAND) then
        recordSleepBedType(playerObj, args)
        return
    end
    if tostring(command) ~= tostring(MP.REQUEST_SNAPSHOT_COMMAND) then
        return
    end

    local _, mpState = ensurePlayerState(playerObj)
    if not mpState or not RequestPolicy.acceptSnapshotRequest(
        mpState,
        getWallClockSeconds(),
        MP.SNAPSHOT_REQUEST_MIN_SECONDS
    ) then
        return
    end

    RequestPolicy.queueSnapshotRequest(mpState)
    local okRefresh, refreshFailure = pcall(refreshPresentationSnapshot, playerObj, mpState)
    if not okRefresh then
        Logger.error("role=mp-server presentation snapshot refresh failed player=" .. tostring(playerName(playerObj))
            .. " err=" .. tostring(refreshFailure))
    end
    flushPendingSnapshot(playerObj, mpState)
end

local function onEveryOneMinute()
    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and safeCall(onlinePlayers, "size")) or 0

    for i = 0, count - 1 do
        local playerObj = safeCall(onlinePlayers, "get", i)
        if playerObj and not isPlayerAsleep(playerObj) then
            updatePlayer(playerObj)
        end
    end
end

local function onWeaponSwing(attacker, weapon)
    local playerObj = attacker
    if not playerObj then
        return
    end

    local options = Options.get()
    if not weapon or not toBoolean(options.EnableMuscleStrainModel) then
        return
    end

    local _, mpState = ensurePlayerState(playerObj)
    local profile = mpState and mpState.cachedWornProfile or nil
    local nowWallSecond = getWallClockSeconds()
    local profileAge = nowWallSecond - (tonumber(mpState and mpState.cachedWornProfileWallSecond) or 0)
    if type(profile) ~= "table"
        or profileAge < 0
        or profileAge >= WORN_PROFILE_CACHE_WALL_SECONDS then
        profile = LoadModel.computeWornProfile(playerObj)
        if mpState then
            mpState.cachedWornProfile = profile
            mpState.cachedWornProfileWallSecond = nowWallSecond
        end
    end

    local okOverlay, extraOrErr = pcall(
        Strain.applyArmorStrainOverlay,
        playerObj,
        weapon,
        options,
        profile
    )
    if not okOverlay then
        Logger.error(
            "role=mp-server strain overlay failed player="
            .. tostring(playerName(playerObj)) .. " err=" .. tostring(extraOrErr)
        )
        return
    end
end

local function logBootBanner()
    Logger.info(string.format(
        "[BOOT] loaded version=%s build=%s role=mp-server",
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end

local function registerEvents()
    local requiredHandlers = {
        OnClientCommand = onClientCommand,
        EveryOneMinute = onEveryOneMinute,
    }
    local optionalHandlers = {
        OnWeaponSwing = onWeaponSwing,
    }
    if Options.get().EnableSleepPenaltyModel then
        optionalHandlers.OnPlayerUpdate = onPlayerUpdate
    end
    for eventName in pairs(requiredHandlers) do
        local event = Events and Events[eventName] or nil
        if not event or type(event.Add) ~= "function" then
            ArmorMakesSense._mpServerRuntimeRegistered = false
            Logger.error("role=mp-server runtime registration failed: Events." .. eventName .. ".Add unavailable")
            return false
        end
    end

    for eventName, handler in pairs(ArmorMakesSense._mpServerRuntimeHandlers or {}) do
        local event = Events[eventName]
        if event and type(event.Remove) == "function" then
            pcall(event.Remove, handler)
        end
    end
    local handlers = {}
    for eventName, handler in pairs(requiredHandlers) do
        handlers[eventName] = handler
    end
    for eventName, handler in pairs(optionalHandlers) do
        local event = Events and Events[eventName] or nil
        if event and type(event.Add) == "function" then
            handlers[eventName] = handler
        else
            Logger.warnOnce(
                "mp-server:optional_event:" .. tostring(eventName),
                "role=mp-server optional runtime event unavailable: Events." .. eventName .. ".Add"
            )
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

if registerEvents() then
    logBootBanner()
end
