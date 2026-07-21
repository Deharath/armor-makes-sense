ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local MP = require "ArmorMakesSense_MPCompat"
require "ArmorMakesSense_Compat"
local Options = require "ArmorMakesSense_Options"
local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = require "ArmorMakesSense_StatsShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local Strain = require "ArmorMakesSense_StrainShared"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local IncidentRecorder = require "ArmorMakesSense_MPIncidentRecorder"
local SnapshotCodec = require "ArmorMakesSense_MPSnapshotCodec"
local RuntimeState = require "ArmorMakesSense_RuntimeState"
local Simulation = require "ArmorMakesSense_Simulation"
local FATIGUE_STAT_MASK = 16
local SLEEP_FATIGUE_SYNC_INTERVAL_WALL_SECONDS = 5
local SLEEP_REALTIME_SNAPSHOT_WALL_SECONDS = 1

local function log(message)
    print("[ArmorMakesSense][MP][SERVER] " .. tostring(message))
end

local safeCall = Utils.safeMethod
local clamp = Utils.clamp
local lower = Utils.lower
local toBoolean = Utils.toBoolean
local getWorldAgeMinutes = Utils.getWorldAgeMinutes
local getEndurance = Stats.getEndurance
local setEndurance = Stats.setEndurance
local getFatigue = Stats.getFatigue
local setFatigue = Stats.setFatigue
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
    mpState.wasSleeping = toBoolean(mpState.wasSleeping)
    mpState.lastSleepSnapshotSentWallSecond = tonumber(mpState.lastSleepSnapshotSentWallSecond) or 0
    mpState.lastSleepFatigueSyncWallSecond = tonumber(mpState.lastSleepFatigueSyncWallSecond) or 0
    mpState.lastSleepRealtimeUpdateWallSecond = tonumber(mpState.lastSleepRealtimeUpdateWallSecond) or 0
    mpState.pendingCatchupMinutes = math.max(0, tonumber(mpState.pendingCatchupMinutes) or 0)
    local pendingSleepBedType = tostring(mpState.pendingSleepBedType or "")
    mpState.pendingSleepBedType = pendingSleepBedType ~= "" and pendingSleepBedType or nil
    mpState.runtimeSnapshot = type(mpState.runtimeSnapshot) == "table" and mpState.runtimeSnapshot or nil
    if type(mpState.lastWakeSyncAsleepFlag) ~= "boolean" then
        mpState.lastWakeSyncAsleepFlag = nil
    end

    return state, mpState
end

local function recordSleepBedType(playerObj, args)
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end

    local bedType = tostring(args and args.bed_type or "")
    if bedType == "" then
        return
    end

    mpState.pendingSleepBedType = bedType

    if type(mpState.sleepSnapshot) == "table"
        and tostring(mpState.sleepSnapshot.bedType or "") == "" then
        mpState.sleepSnapshot.bedType = bedType
    end

    log("sleep bed type from client: player=" .. tostring(playerName(playerObj)) .. " bed=" .. bedType)
end

local function isPlayerAsleep(playerObj)
    return toBoolean(safeCall(playerObj, "isAsleep"))
end

local function syncFatigueToClient(playerObj, phaseTag)
    if type(syncPlayerStats) ~= "function" then
        return false
    end
    local ok, err = pcall(syncPlayerStats, playerObj, FATIGUE_STAT_MASK)
    if not ok then
        log("syncPlayerStats fatigue send failed phase=" .. tostring(phaseTag or "unknown")
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
    end
    return sent
end

local prepareRuntimeInputs

local function registerCompatProvider()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or type(compat.registerProvider) ~= "function" then
        return
    end

    compat:registerProvider("ArmorMakesSense", {
        capabilities = {
            endurance_coordinator = true,
            sleep_penalty_provider = true,
            sleep_planner_penalty_provider = true,
        },
        callbacks = {
            computeSleepPenaltyContribution = function(playerObj, args)
                local _, mpState = ensurePlayerState(playerObj)
                if not mpState or type(Physiology.computeSleepPenaltyContribution) ~= "function" then
                    return {
                        penaltyFraction = 0,
                        sleeping = false,
                    }
                end

                local options = Options.get()
                local profile = prepareRuntimeInputs(playerObj, mpState, options)
                return Physiology.computeSleepPenaltyContribution(
                    playerObj,
                    mpState,
                    options,
                    tonumber(args and args.dtMinutes) or 0,
                    profile,
                    tonumber(args and args.currentFatigue)
                )
            end,
            estimateSleepPlannerPenalty = function(playerObj, args)
                local _, mpState = ensurePlayerState(playerObj)
                if not mpState or type(Physiology.computeSleepPlannerPenalty) ~= "function" then
                    return { penaltyFraction = 0 }
                end

                local options = Options.get()
                local profile = prepareRuntimeInputs(playerObj, mpState, options)
                return Physiology.computeSleepPlannerPenalty(
                    playerObj,
                    mpState,
                    options,
                    profile,
                    tonumber(args and args.currentFatigue)
                )
            end,
            buildTraceSnapshot = function(playerObj, _args)
                local _, mpState = ensurePlayerState(playerObj)
                if not mpState or type(Physiology.buildCompatTraceSnapshot) ~= "function" then
                    return {}
                end
                return Physiology.buildCompatTraceSnapshot(mpState)
            end,
        },
    })
end

registerCompatProvider()

prepareRuntimeInputs = function(playerObj, mpState, options, sleepOnly)
    local analysis = LoadModel.analyzeWornGear(playerObj)
    local profile = analysis.profile

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
    local uiSnapshot = type(mpState.uiRuntimeSnapshot) == "table" and mpState.uiRuntimeSnapshot or {}
    return {
        loadNorm = tonumber(uiSnapshot.loadNorm) or 0,
        physicalLoad = tonumber(profile.physicalLoad) or 0,
        thermalResistance = tonumber(uiSnapshot.thermalResistance) or 0,
        airflowResistance = tonumber(profile.airflowResistance) or 0,
        sealedRestriction = tonumber(profile.sealedRestriction) or 0,
        rigidityLoad = tonumber(profile.rigidityLoad) or 0,
        driverCount = tonumber(profile.driverCount) or 0,
        effectiveLoad = tonumber(uiSnapshot.effectiveLoad) or tonumber(profile.physicalLoad) or 0,
        thermalContribution = tonumber(uiSnapshot.thermalContribution) or 0,
        breathingContribution = tonumber(uiSnapshot.breathingContribution) or 0,
        drivers = drivers or {},
        activityLabel = tostring(activityLabel or uiSnapshot.activityLabel or "idle"),
        hotPressure = tonumber(uiSnapshot.hotPressure) or 0,
        coldSuitability = tonumber(uiSnapshot.coldSuitability) or 0,
        thermalStrainScale = tonumber(uiSnapshot.thermalStrainScale) or 0,
        enduranceBeforeAms = tonumber(uiSnapshot.enduranceBeforeAms) or 0,
        enduranceAfterAms = tonumber(uiSnapshot.enduranceAfterAms) or 0,
        enduranceNaturalDelta = tonumber(uiSnapshot.enduranceNaturalDelta) or 0,
        enduranceAppliedDelta = tonumber(uiSnapshot.enduranceAppliedDelta) or 0,
        lastAppliedDtMinutes = tonumber(mpState.lastAppliedDtMinutes) or 0,
        catchupPendingMinutes = tonumber(mpState.pendingCatchupMinutes) or 0,
        updatedMinute = tonumber(uiSnapshot.updatedMinute) or getWorldAgeMinutes(),
    }
end

local function getMovementFlags(playerObj)
    return {
        moving = toBoolean(safeCall(playerObj, "isMoving")),
        playerMoving = toBoolean(safeCall(playerObj, "isPlayerMoving")),
        running = toBoolean(safeCall(playerObj, "isRunning")),
        sprinting = toBoolean(safeCall(playerObj, "isSprinting")),
        aiming = toBoolean(safeCall(playerObj, "isAiming")),
        attackStarted = toBoolean(safeCall(playerObj, "isAttackStarted")),
    }
end

local function buildTopDriverLabels(drivers)
    local parts = {}
    if type(drivers) ~= "table" then
        return parts
    end
    local limit = math.min(3, #drivers)
    for i = 1, limit do
        local driver = drivers[i] or {}
        parts[#parts + 1] = string.format(
            "%s (%s)",
            tostring(driver.label or "Unknown Item"),
            string.format("%.1f", tonumber(driver.physical) or 0)
        )
    end
    return parts
end

local function buildIncidentSlice(playerObj, reason, dtMinutes, mpState, profile, drivers, snapshot, activityLabel, analysis)
    local uiSnapshot = type(mpState.uiRuntimeSnapshot) == "table" and mpState.uiRuntimeSnapshot or {}
    local flags = getMovementFlags(playerObj)
    return {
        worldMinute = tonumber(getWorldAgeMinutes()) or 0,
        reason = tostring(reason or "tick"),
        dtMinutes = tonumber(dtMinutes) or 0,
        pendingCatchupMinutes = tonumber(mpState.pendingCatchupMinutes) or 0,
        activityLabel = tostring(activityLabel or snapshot.activityLabel or "idle"),
        moving = flags.moving == true,
        playerMoving = flags.playerMoving == true,
        running = flags.running == true,
        sprinting = flags.sprinting == true,
        aiming = flags.aiming == true,
        attackStarted = flags.attackStarted == true,
        enduranceBeforeAms = tonumber(uiSnapshot.enduranceBeforeAms) or 0,
        enduranceAfterAms = tonumber(uiSnapshot.enduranceAfterAms) or 0,
        enduranceNaturalDelta = tonumber(uiSnapshot.enduranceNaturalDelta) or 0,
        enduranceAppliedDelta = tonumber(uiSnapshot.enduranceAppliedDelta) or 0,
        effectiveLoad = tonumber(snapshot.effectiveLoad) or 0,
        loadNorm = tonumber(snapshot.loadNorm) or 0,
        physicalLoad = tonumber(profile.physicalLoad) or 0,
        thermalResistance = tonumber(snapshot.thermalResistance) or 0,
        airflowResistance = tonumber(profile.airflowResistance) or 0,
        sealedRestriction = tonumber(profile.sealedRestriction) or 0,
        rigidityLoad = tonumber(profile.rigidityLoad) or 0,
        thermalContribution = tonumber(snapshot.thermalContribution) or 0,
        breathingContribution = tonumber(snapshot.breathingContribution) or 0,
        hotPressure = tonumber(snapshot.hotPressure) or 0,
        thermalStrainScale = tonumber(snapshot.thermalStrainScale) or 0,
        coldSuitability = tonumber(snapshot.coldSuitability) or 0,
        equipSignature = tostring(analysis and analysis.equipmentSignature or ""),
        wornCount = tonumber(analysis and analysis.wornCount) or 0,
        topDrivers = buildTopDriverLabels(drivers),
    }
end

local function sendSnapshot(playerObj, mpState, snapshot, reason, clientIncidentSeq, lightweight)
    if type(sendServerCommand) ~= "function" then
        return
    end
    if type(snapshot) ~= "table" then
        return
    end

    local args = SnapshotCodec.encode(snapshot, {
        authoritativeFatigue = getFatigue(playerObj),
        serverSleeping = isPlayerAsleep(playerObj),
        reason = reason,
    }, not lightweight)

    if not lightweight then
        local incidentSeq, incidentPayload = IncidentRecorder.buildSnapshotIncidentPayload(playerObj, mpState, clientIncidentSeq)
        args.incident_seq = tonumber(incidentSeq) or 0
        if type(incidentPayload) == "table" then
            args.incident_trace = incidentPayload
        end

    else
        args.incident_seq = 0
    end

    local ok, err = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.SNAPSHOT_COMMAND), args)
    if not ok then
        log("snapshot send failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(err))
    end
end

local function shouldSendSleepingSnapshot(mpState)
    local nowSecond = getWallClockSeconds()
    local lastSent = tonumber(mpState.lastSleepSnapshotSentWallSecond) or 0
    if lastSent <= 0 or (nowSecond - lastSent) >= SLEEP_REALTIME_SNAPSHOT_WALL_SECONDS then
        mpState.lastSleepSnapshotSentWallSecond = nowSecond
        return true
    end
    return false
end

local function buildFreshSnapshot(playerObj, mpState, options, preserveEnduranceBaseline)
    local okInputs, profile, drivers, activityFactor, activityLabel, postureLabel =
        pcall(prepareRuntimeInputs, playerObj, mpState, options)
    if not okInputs then
        log("shared model input prep failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile))
        return nil
    end
    local okSleep, sleepErr = pcall(Physiology.applySleepTransition, playerObj, mpState, options, 0, profile)
    if not okSleep then
        log("sleep model failed during snapshot refresh player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(sleepErr))
        return nil
    end
    local previousEnduranceObserved = tonumber(mpState.lastEnduranceObserved)
    local okEndurance, enduranceErr = pcall(
        Physiology.applyEnduranceModel,
        playerObj,
        mpState,
        options,
        0,
        profile,
        activityFactor,
        activityLabel,
        postureLabel
    )
    if not okEndurance then
        log("endurance model failed during snapshot refresh player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(enduranceErr))
        return nil
    end
    if preserveEnduranceBaseline then
        mpState.lastEnduranceObserved = previousEnduranceObserved
    end
    return buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
end

local function isSessionBoundaryReason(reason)
    return reason == "onconnected" or reason == "oncreateplayer"
end

local function resetCatchupState(playerObj, mpState, nowMinute)
    mpState.lastUpdateGameMinutes = tonumber(nowMinute) or 0
    mpState.pendingCatchupMinutes = 0
    mpState.lastAppliedDtMinutes = 0
    mpState.lastSleepSnapshotSentWallSecond = 0
    mpState.lastSleepFatigueSyncWallSecond = 0
    mpState.lastSleepRealtimeUpdateWallSecond = 0
    mpState.lastWakeSyncAsleepFlag = nil
    mpState.lastEnduranceObserved = tonumber(getEndurance(playerObj))
end

local function updatePlayer(playerObj, reason, requestArgs)
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end

    local normalizedReason = lower(reason)
    local nowMinute = tonumber(getWorldAgeMinutes()) or 0
    if isSessionBoundaryReason(normalizedReason) then
        resetCatchupState(playerObj, mpState, nowMinute)
        IncidentRecorder.clearSession(playerObj, mpState, nowMinute)
    end
    Simulation.accumulateElapsed(mpState, nowMinute)

    local sleepingNow = isPlayerAsleep(playerObj)
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
        if normalizedReason ~= "minute" and normalizedReason ~= "tick" then
            local options = Options.get()
            local freshSnapshot = buildFreshSnapshot(playerObj, mpState, options, not isSessionBoundaryReason(normalizedReason))
            if freshSnapshot then
                mpState.runtimeSnapshot = freshSnapshot
                sendSnapshot(playerObj, mpState, freshSnapshot, reason, requestArgs and requestArgs.incident_seq)
                return
            end
        end
        if type(mpState.runtimeSnapshot) == "table" then
            sendSnapshot(playerObj, mpState, mpState.runtimeSnapshot, reason, requestArgs and requestArgs.incident_seq)
        end
        return
    end

    local options = Options.get()
    local snapshot = nil

    if sleepingNow then
        local okInputs, profile, drivers, activityFactor, activityLabel, postureLabel =
            pcall(prepareRuntimeInputs, playerObj, mpState, options, true)
        if not okInputs then
            resetCatchupState(playerObj, mpState, nowMinute)
            log("sleep input prep failed; pending catchup discarded player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile))
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
            log(string.format(
                "%s model failed player=%s err=%s",
                tostring(result.failurePhase),
                tostring(playerName(playerObj)),
                tostring(result.failure)
            ))
        end

        snapshot = buildRuntimeSnapshot(mpState, profile, {}, "sleep")
        syncSleepingFatigueToClient(playerObj, mpState)
        if snapshot then
            mpState.runtimeSnapshot = snapshot
            if shouldSendSleepingSnapshot(mpState) then
                sendSnapshot(playerObj, mpState, snapshot, reason, requestArgs and requestArgs.incident_seq, true)
            end
        end
        return
    end

    IncidentRecorder.beginInvocation(playerObj, mpState, {
        reason = normalizedReason,
        worldMinute = nowMinute,
    })

    local okInputs, profile, drivers, activityFactor, activityLabel, postureLabel, analysis =
        pcall(prepareRuntimeInputs, playerObj, mpState, options)
    if not okInputs then
        IncidentRecorder.finishInvocation(playerObj, mpState)
        resetCatchupState(playerObj, mpState, nowMinute)
        log("shared model input prep failed; pending catchup discarded player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile))
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
        applyEnduranceModel = Physiology.applyEnduranceModel,
        afterSlice = function(slice)
            snapshot = buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
            local incidentResult = IncidentRecorder.recordSlice(
                playerObj,
                mpState,
                buildIncidentSlice(
                    playerObj,
                    reason,
                    slice.dtMinutes,
                    mpState,
                    profile,
                    drivers,
                    snapshot,
                    activityLabel,
                    analysis
                )
            )
            if incidentResult.abortReplay then
                mpState.pendingCatchupMinutes = 0
                snapshot = buildFreshSnapshot(playerObj, mpState, options, false) or snapshot
                return { abort = true, clearPending = true }
            end
        end,
    })
    IncidentRecorder.finishInvocation(playerObj, mpState)
    if result.failurePhase then
        log(string.format(
            "%s model failed player=%s err=%s",
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
        sendSnapshot(playerObj, mpState, snapshot, reason, requestArgs and requestArgs.incident_seq)
    end
end

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end

    local sleepingNow = isPlayerAsleep(playerObj)
    local wasSleeping = mpState.lastWakeSyncAsleepFlag
    if type(wasSleeping) ~= "boolean" then
        wasSleeping = mpState.wasSleeping == true
    end
    mpState.lastWakeSyncAsleepFlag = sleepingNow

    if wasSleeping == true and sleepingNow == false then
        updatePlayer(playerObj, "WakeTransition")
        syncWakeFatigueToClient(playerObj)
        return
    end

    if sleepingNow then
        local nowWallSecond = getWallClockSeconds()
        local lastSleepRealtime = tonumber(mpState.lastSleepRealtimeUpdateWallSecond) or 0
        if lastSleepRealtime <= 0 or (nowWallSecond - lastSleepRealtime) >= SLEEP_REALTIME_SNAPSHOT_WALL_SECONDS then
            mpState.lastSleepRealtimeUpdateWallSecond = nowWallSecond
            updatePlayer(playerObj, "SleepRealtimeSync")
            return
        end
    else
        mpState.lastSleepRealtimeUpdateWallSecond = 0
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

    updatePlayer(playerObj, args and args.reason or "request", args)
end

local function onEveryOneMinute()
    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and safeCall(onlinePlayers, "size")) or 0

    for i = 0, count - 1 do
        local playerObj = safeCall(onlinePlayers, "get", i)
        if playerObj then
            updatePlayer(playerObj, "minute")
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

    local okOverlay, extraOrErr = pcall(
        Strain.applyArmorStrainOverlay,
        playerObj,
        weapon,
        options
    )
    if not okOverlay then
        log("strain overlay failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(extraOrErr))
        return
    end
end

local function logBootBanner(contextTag)
    log(string.format(
        "[BOOT_MP] context=%s side=server isClient=%s isServer=%s scriptVersion=%s build=%s",
        tostring(contextTag or "load"),
        tostring(type(isClient) == "function" and isClient() or false),
        tostring(type(isServer) == "function" and isServer() or false),
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end

local function registerEvents()
    if ArmorMakesSense._mpServerRuntimeRegistered then
        return
    end
    ArmorMakesSense._mpServerRuntimeRegistered = true

    if Events and Events.OnClientCommand and type(Events.OnClientCommand.Add) == "function" then
        Events.OnClientCommand.Add(onClientCommand)
        log("OnClientCommand runtime handler registered")
    else
        log("OnClientCommand.Add unavailable; MP runtime command channel inactive")
    end

    if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    else
        log("Events.EveryOneMinute.Add unavailable; server warm tick disabled")
    end

    if Events and Events.OnWeaponSwing and type(Events.OnWeaponSwing.Add) == "function" then
        Events.OnWeaponSwing.Add(onWeaponSwing)
    else
        log("Events.OnWeaponSwing.Add unavailable; server strain overlay disabled")
    end

    if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    else
        log("Events.OnPlayerUpdate.Add unavailable; wake-edge authority disabled")
    end

    if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
        Events.OnGameBoot.Add(function()
            logBootBanner("OnGameBoot")
        end)
    end
end

registerEvents()
logBootBanner("load")
