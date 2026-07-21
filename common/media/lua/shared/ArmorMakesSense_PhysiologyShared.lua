ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Models = ArmorMakesSense.Models or {}

local Models = ArmorMakesSense.Models
Models.Physiology = Models.Physiology or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = require "ArmorMakesSense_StatsShared"
local BreathingModel = require "ArmorMakesSense_BreathingModel"
local EnduranceModel = require "ArmorMakesSense_EnduranceModel"
local SleepModel = require "ArmorMakesSense_SleepModel"
local ThermalModel = require "ArmorMakesSense_ThermalModel"
local Physiology = Models.Physiology

-- -----------------------------------------------------------------------------
-- Physiological load + recovery model
-- -----------------------------------------------------------------------------

local function getCompat()
    return ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
end

local function isCmsFatigueCompatActive()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("CaffeineMakesSense", "fatigue_coordinator")
end

local function isMultiplayerClientSession()
    return ((type(isClient) == "function" and isClient() == true)
        or (GameClient and GameClient.bClient == true))
        and not ((type(isServer) == "function" and isServer() == true)
            or (GameServer and GameServer.bServer == true))
end

local function isMultiplayerServerSession()
    return ((type(isServer) == "function" and isServer() == true)
        or (GameServer and GameServer.bServer == true))
end

local function isCmsWakeAdjustmentCompatActive()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("CaffeineMakesSense", "sleep_wake_adjustment_coordinator")
end

local function clampValue(value, minimum, maximum)
    return Utils.clamp(value, minimum, maximum)
end

function Physiology.getUiRuntimeSnapshot(player, state, options)
    local resolvedState = state
    if type(resolvedState) ~= "table" then
        return nil
    end
    local isMp = Utils.isMultiplayer()
    if isMp and type(resolvedState.mpServerSnapshot) == "table" then
        local snapshot = resolvedState.mpServerSnapshot
        return {
            loadNorm = tonumber(snapshot.loadNorm) or 0,
            physicalLoad = tonumber(snapshot.physicalLoad) or 0,
            thermalResistance = tonumber(snapshot.thermalResistance) or 0,
            airflowResistance = tonumber(snapshot.airflowResistance) or 0,
            sealedRestriction = tonumber(snapshot.sealedRestriction) or 0,
            rigidityLoad = tonumber(snapshot.rigidityLoad) or 0,
            driverCount = tonumber(snapshot.driverCount) or 0,
            effectiveLoad = tonumber(snapshot.effectiveLoad) or 0,
            hotPressure = tonumber(snapshot.hotPressure) or 0,
            coldSuitability = tonumber(snapshot.coldSuitability) or 0,
            thermalStrainScale = tonumber(snapshot.thermalStrainScale) or 0,
            metabolicRate = tonumber(snapshot.metabolicRate) or 1.5,
            metabolicDemand = tonumber(snapshot.metabolicDemand) or 1.5,
            metabolicNorm = tonumber(snapshot.metabolicNorm) or 0,
            breathingEffortRamp = tonumber(snapshot.breathingEffortRamp) or 0,
            breathingDynamicLoad = tonumber(snapshot.breathingDynamicLoad) or 0,
            breathingSealedLoad = tonumber(snapshot.breathingSealedLoad) or 0,
            activityLabel = tostring(snapshot.activityLabel or "idle"),
            updatedMinute = tonumber(snapshot.updatedMinute) or 0,
            drivers = type(snapshot.drivers) == "table" and snapshot.drivers or {},
        }
    end
    local snapshot = resolvedState.uiRuntimeSnapshot
    if type(snapshot) ~= "table" then
        return nil
    end
    return {
        loadNorm = tonumber(snapshot.loadNorm) or 0,
        effectiveLoad = tonumber(snapshot.effectiveLoad) or 0,
        thermalResistance = tonumber(snapshot.thermalResistance) or 0,
        hotPressure = tonumber(snapshot.hotPressure) or 0,
        coldSuitability = tonumber(snapshot.coldSuitability) or 0,
        thermalStrainScale = tonumber(snapshot.thermalStrainScale) or 0,
        activityLabel = tostring(snapshot.activityLabel or "idle"),
        updatedMinute = tonumber(snapshot.updatedMinute) or 0,
    }
end

local function playerHasTrait(player, traitName, traitEnum)
    local safeMethod = Utils.safeMethod
    if not player then
        return false
    end
    if traitEnum and _G.CharacterTrait and CharacterTrait[traitEnum] ~= nil then
        return safeMethod(player, "hasTrait", CharacterTrait[traitEnum]) == true
    end
    return safeMethod(player, "hasTrait", traitName) == true
end

local function buildSleepModelInput(player, bedType, fatigue, rigidityLoad, dtMinutes)
    return {
        bedType = tostring(bedType or ""),
        fatigue = tonumber(fatigue),
        rigidityLoad = tonumber(rigidityLoad) or 0,
        dtMinutes = math.max(0, tonumber(dtMinutes) or 0),
        insomniac = playerHasTrait(player, "Insomniac", "INSOMNIAC"),
        nightOwl = playerHasTrait(player, "NightOwl", "NIGHT_OWL"),
        needsLessSleep = playerHasTrait(player, "NeedsLessSleep", "NEEDS_LESS_SLEEP"),
        needsMoreSleep = playerHasTrait(player, "NeedsMoreSleep", "NEEDS_MORE_SLEEP"),
    }
end

local function getPendingSleepBedType(state)
    local bedType = type(state) == "table" and tostring(state.pendingSleepBedType or "") or ""
    if bedType == "" then
        return nil
    end
    return bedType
end

local function resolveSleepBedType(player, state)
    local safeMethod = Utils.safeMethod
    local bedType = tostring(safeMethod(player, "getBedType") or "")
    if bedType == "" then
        bedType = getPendingSleepBedType(state) or ""
    end
    return bedType
end

local function getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
    local fatigue = tonumber(currentFatigue)
    if fatigue == nil then
        fatigue = Stats.getFatigue(player)
    end
    if fatigue == nil then
        return 0
    end

    local result = SleepModel.calculatePenalty(options, buildSleepModelInput(
        player,
        snapshot and snapshot.bedType,
        fatigue,
        snapshot and snapshot.rigidityLoad,
        0
    ))
    return result.penaltyFraction
end

local function applySleepWakeFatigueAdjustment(player, state, currentFatigue)
    if isCmsWakeAdjustmentCompatActive() then
        if type(state) == "table" then
            state.lastSleepWakeAdjustment = 0
        end
        return 0
    end

    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.computeSleepWakeFatigueDelta) ~= "function" then
        if type(state) == "table" then
            state.lastSleepWakeAdjustment = 0
        end
        return 0
    end

    local snapshot = type(state) == "table" and state.sleepSnapshot or nil
    if type(snapshot) ~= "table" then
        if type(state) == "table" then
            state.lastSleepWakeAdjustment = 0
        end
        return 0
    end

    local nowMinutes = tonumber(Utils.getWorldAgeMinutes())
    local startMinute = tonumber(snapshot.startMinute)
    if nowMinutes == nil or startMinute == nil then
        if type(state) == "table" then
            state.lastSleepWakeAdjustment = 0
        end
        return 0
    end

    local fatigue = tonumber(currentFatigue)
    if fatigue == nil then
        fatigue = Stats.getFatigue(player)
    end
    local referenceFatigue = tonumber(snapshot.lastFatigue)
    if referenceFatigue == nil then
        referenceFatigue = fatigue
    end
    local sleptHours = math.max(0, nowMinutes - startMinute) / 60.0
    local expectedWakeAdjustment = tonumber(compat.computeSleepWakeFatigueDelta(snapshot.bedType, sleptHours)) or 0

    if fatigue ~= nil and referenceFatigue ~= nil then
        local observedAdjustment = clampValue(fatigue, 0, 1) - referenceFatigue
        if math.abs(observedAdjustment) > 0.002 then
            local trustObserved = true
            if isMultiplayerServerSession() and expectedWakeAdjustment ~= 0 then
                trustObserved = (observedAdjustment < 0 and expectedWakeAdjustment < 0)
                    or (observedAdjustment > 0 and expectedWakeAdjustment > 0)
            end
            if trustObserved then
                state.lastSleepWakeAdjustment = observedAdjustment
                return observedAdjustment
            end
        end
    end

    if not isMultiplayerServerSession() then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local wakeAdjustment = expectedWakeAdjustment
    state.lastSleepWakeAdjustment = wakeAdjustment

    if wakeAdjustment == 0 then
        return 0
    end

    if referenceFatigue == nil then
        return wakeAdjustment
    end

    Stats.setFatigue(player, clampValue(referenceFatigue + wakeAdjustment, 0, 1))

    return wakeAdjustment
end

function Physiology.applySleepTransition(player, state, options, dtMinutes, profile)
    local result = Physiology.computeSleepPenaltyContribution(
        player,
        state,
        options,
        dtMinutes,
        profile,
        nil
    )
    result.extraFatigue = 0
    result.wroteFatigue = false

    if isCmsFatigueCompatActive() or isMultiplayerClientSession() then
        return result
    end

    local fatigue = Stats.getFatigue(player)
    local penaltyFraction = clampValue(tonumber(result and result.penaltyFraction) or 0, 0, 0.95)
    local sampleMinutes = math.max(0, tonumber(dtMinutes) or 0)
    local extraFatigue = 0
    if fatigue ~= nil and penaltyFraction > 0 and sampleMinutes > 0 then
        local snapshot = state and state.sleepSnapshot or {}
        local applied = SleepModel.calculateAppliedPenalty(options, buildSleepModelInput(
            player,
            snapshot.bedType,
            fatigue,
            snapshot.rigidityLoad,
            sampleMinutes
        ))
        extraFatigue = applied.extraFatigue
    end
    if extraFatigue > 0 then
        if fatigue ~= nil then
            local cappedFatigue = math.min(0.85, fatigue + extraFatigue)
            if cappedFatigue > fatigue then
                Stats.setFatigue(player, cappedFatigue)
                result.wroteFatigue = true
            end
        end
    end
    result.extraFatigue = extraFatigue
    return result
end

function Physiology.computeSleepPlannerPenalty(player, state, options, profile, currentFatigue)
    if not options.EnableSleepPenaltyModel then
        return {
            penaltyFraction = 0,
            sleeping = false,
        }
    end

    local resolvedProfile = type(profile) == "table" and profile or {}
    local resolvedState = type(state) == "table" and state or {}
    local snapshot = {
        rigidityLoad = tonumber(resolvedProfile.rigidityLoad) or 0,
    }
    local penaltyFraction = getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
    resolvedState.lastSleepPenaltyFraction = penaltyFraction

    return {
        penaltyFraction = penaltyFraction,
        sleeping = false,
    }
end

function Physiology.computeSleepPenaltyContribution(player, state, options, dtMinutes, profile, currentFatigue)
    local sleeping = Utils.toBoolean(Utils.safeMethod(player, "isAsleep"))
    local wasSleeping = Utils.toBoolean(state.wasSleeping)
    if sleeping and not wasSleeping then
        state.sleepSnapshot = {
            rigidityLoad = tonumber(profile.rigidityLoad) or 0,
            bedType = resolveSleepBedType(player, state),
            startMinute = tonumber(Utils.getWorldAgeMinutes()),
            lastFatigue = tonumber(currentFatigue) or Stats.getFatigue(player),
        }
    end

    if sleeping then
        if not state.sleepSnapshot then
            state.sleepSnapshot = {
                rigidityLoad = tonumber(profile.rigidityLoad) or 0,
                bedType = resolveSleepBedType(player, state),
                startMinute = tonumber(Utils.getWorldAgeMinutes()),
                lastFatigue = tonumber(currentFatigue) or Stats.getFatigue(player),
            }
        end
        local snapshot = state.sleepSnapshot
        if snapshot.rigidityLoad == nil then
            snapshot.rigidityLoad = tonumber(profile.rigidityLoad) or 0
        end
        if snapshot.bedType == nil or tostring(snapshot.bedType or "") == "" then
            snapshot.bedType = resolveSleepBedType(player, state)
        end
        if snapshot.startMinute == nil then
            snapshot.startMinute = tonumber(Utils.getWorldAgeMinutes())
        end
        snapshot.lastFatigue = tonumber(currentFatigue) or Stats.getFatigue(player)
        local penaltyFraction = 0
        if options.EnableSleepPenaltyModel then
            penaltyFraction = getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
        end
        state.lastSleepPenaltyFraction = penaltyFraction
        state.lastSleepWakeAdjustment = 0
        state.wasSleeping = sleeping
        return {
            penaltyFraction = penaltyFraction,
            sleeping = true,
        }
    end

    if (not sleeping) and wasSleeping and state.sleepSnapshot then
        applySleepWakeFatigueAdjustment(player, state, currentFatigue)
        state.sleepSnapshot = nil
        state.pendingSleepBedType = nil
    end
    state.wasSleeping = sleeping
    state.lastSleepPenaltyFraction = 0

    return {
        penaltyFraction = 0,
        sleeping = sleeping,
    }
end

local function computeThermalContribution(player, state, options, dtMinutes)
    if type(state.thermalModelState) ~= "table" then
        state.thermalModelState = {}
    end
    return ThermalModel.advance(
        ThermalModel.sample(player),
        state.thermalModelState,
        dtMinutes,
        options
    )
end

local function resolveNmsEnduranceContribution(player, dtMinutes, naturalDelta, endurance, previous)
    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.getCallback) ~= "function" then
        return nil
    end

    local callback = compat:getCallback("NutritionMakesSense", "computeEnduranceContribution")
    if type(callback) ~= "function" then
        return nil
    end

    local ok, contribution = pcall(callback, player, {
        dtMinutes = dtMinutes,
        dtHours = math.max(0, tonumber(dtMinutes) or 0) / 60.0,
        naturalDelta = naturalDelta,
        currentEndurance = endurance,
        previousEndurance = previous,
    })
    if not ok or type(contribution) ~= "table" then
        return nil
    end

    return contribution
end

local function recordNmsEnduranceResult(player, controlledEndurance, regenScale, extraDrain)
    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.getCallback) ~= "function" then
        return
    end

    local callback = compat:getCallback("NutritionMakesSense", "recordEnduranceResult")
    if type(callback) ~= "function" then
        return
    end

    pcall(callback, player, {
        controlledEndurance = controlledEndurance,
        regenScale = regenScale,
        extraDrain = extraDrain,
    })
end

local function applyEnduranceCorrection(player, controlled, endurance)
    controlled = Utils.clamp(controlled, 0, 1)
    if math.abs(controlled - endurance) > 0.0002 then
        Stats.setEndurance(player, controlled)
    end
    return controlled
end

function Physiology.applyEnduranceModel(player, state, options, dtMinutes, profile, activityFactor, activityLabel, postureLabel)
    local endurance = Stats.getEndurance(player)
    if endurance == nil then
        return nil
    end
    local sampleMinutes = math.max(0, tonumber(dtMinutes) or 0)
    local canApplyEndurance = sampleMinutes > 0

    local physicalLoad = tonumber(profile.physicalLoad) or 0
    local thermal = computeThermalContribution(player, state, options, sampleMinutes)
    local thermalContribution = thermal.contribution
    local breathing = BreathingModel.calculate(options, {
        airflowResistance = profile.airflowResistance,
        sealedRestriction = profile.sealedRestriction,
        metabolicRate = Stats.getMetabolicRate(player),
        activityLabel = activityLabel,
    })
    local breathingContribution = breathing.contribution
    local airflowResistance = breathing.airflowResistance
    local sealedRestriction = breathing.sealedRestriction
    local effectiveLoad = physicalLoad + thermalContribution + breathingContribution
    local loadMin = tonumber(options.ArmorLoadMin)
    assert(loadMin ~= nil, "resolved ArmorLoadMin required")
    loadMin = math.max(0, loadMin)
    local loadNorm = Utils.softNorm(effectiveLoad - loadMin, 50.0, 2.5)
    loadNorm = Utils.clamp(loadNorm, 0, 2.8)
    local activityLoadScale = Utils.clamp((0.55 + (0.45 * (tonumber(activityFactor) or 1.0))), 0.45, 1.85)
    local previous = state.lastEnduranceObserved
    local naturalDelta = 0
    if previous ~= nil then
        naturalDelta = endurance - previous
    end
    local isSitting = postureLabel and (string.find(postureLabel, "sit", 1, true) ~= nil)
    local nmsContribution = nil
    if canApplyEndurance then
        nmsContribution = resolveNmsEnduranceContribution(player, sampleMinutes, naturalDelta, endurance, previous)
    end
    local nmsRegenScale = tonumber(nmsContribution and nmsContribution.regenScale) or 1.0
    local nmsDrain = math.max(0, tonumber(nmsContribution and nmsContribution.extraDrain) or 0)

    local endMoodle = -1
    local moodles = Utils.safeMethod(player, "getMoodles")
    if moodles and MoodleType and MoodleType.ENDURANCE then
        endMoodle = tonumber(Utils.safeMethod(moodles, "getMoodleLevel", MoodleType.ENDURANCE)) or -1
    end

    local enduranceResult = EnduranceModel.calculate(options, {
        previous = previous,
        current = endurance,
        naturalDelta = naturalDelta,
        loadNorm = loadNorm,
        activityLoadScale = activityLoadScale,
        activityLabel = activityLabel,
        isSitting = isSitting,
        enduranceMoodle = endMoodle,
        dtMinutes = sampleMinutes,
        nmsRegenScale = nmsRegenScale,
        nmsDrain = nmsDrain,
    })
    local controlled = enduranceResult.controlledEndurance

    if canApplyEndurance then
        controlled = applyEnduranceCorrection(player, controlled, endurance)
        recordNmsEnduranceResult(
            player,
            controlled,
            enduranceResult.nmsRegenScale,
            enduranceResult.nmsDrainApplied
        )
    end

    local enduranceDelta = controlled - endurance
    state.lastEnduranceObserved = controlled
    local nowMinute = tonumber(Utils.getWorldAgeMinutes()) or 0
    local hotPressure = tonumber(thermal.hotPressure) or 0
    local coldSuitability = tonumber(thermal.coldSuitability) or 0
    local thermalUiState = hotPressure > 0.24 and "hot" or (coldSuitability > 0.45 and "cold" or "neutral")
    state.uiRuntimeSnapshot = {
        loadNorm = loadNorm,
        effectiveLoad = effectiveLoad,
        physicalLoad = physicalLoad,
        thermalAvailable = thermal.available == true,
        thermalResistance = tonumber(thermal.resistance) or 0,
        airflowResistance = airflowResistance,
        sealedRestriction = sealedRestriction,
        metabolicRate = breathing.metabolicRate,
        metabolicDemand = breathing.metabolicDemand,
        metabolicNorm = breathing.metabolicNorm,
        breathingEffortRamp = breathing.effortRamp,
        breathingDynamicLoad = breathing.dynamicLoad,
        breathingSealedLoad = breathing.sealedDynamicLoad,
        thermalContribution = thermalContribution,
        breathingContribution = breathingContribution,
        muscleContribution = 0,
        recoveryContribution = 0,
        hotPressure = hotPressure,
        bodyTemp = tonumber(thermal.bodyTemp) or nil,
        coldSuitability = coldSuitability,
        thermalStrainScale = tonumber(thermal.strainScale) or 0,
        enduranceBeforeAms = endurance,
        enduranceAfterAms = controlled,
        enduranceNaturalDelta = naturalDelta,
        enduranceAppliedDelta = enduranceDelta,
        amsEnduranceRegenScale = enduranceResult.amsRegenScale,
        nmsEnduranceRegenScale = enduranceResult.nmsRegenScale,
        composedEnduranceRegenScale = enduranceResult.composedRegenScale,
        amsEnduranceDrainApplied = enduranceResult.amsDrainApplied,
        nmsEnduranceDrainApplied = enduranceResult.nmsDrainApplied,
        activityLabel = activityLabel,
        thermalUiState = thermalUiState,
        updatedMinute = nowMinute,
    }
    return enduranceDelta
end

function Physiology.buildCompatTraceSnapshot(state)
    local snapshot = type(state) == "table" and type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or {}
    return {
        activity_label = tostring(snapshot.activityLabel or ""),
        load_norm = tonumber(snapshot.loadNorm) or 0,
        effective_load = tonumber(snapshot.effectiveLoad) or 0,
        physical_load = tonumber(snapshot.physicalLoad) or 0,
        thermal_resistance = tonumber(snapshot.thermalResistance) or 0,
        airflow_resistance = tonumber(snapshot.airflowResistance) or 0,
        sealed_restriction = tonumber(snapshot.sealedRestriction) or 0,
        metabolic_rate = tonumber(snapshot.metabolicRate) or 1.5,
        metabolic_demand = tonumber(snapshot.metabolicDemand) or 1.5,
        thermal_contribution = tonumber(snapshot.thermalContribution) or 0,
        breathing_contribution = tonumber(snapshot.breathingContribution) or 0,
        hot_pressure = tonumber(snapshot.hotPressure) or 0,
        thermal_strain_scale = tonumber(snapshot.thermalStrainScale) or 0,
        cold_suitability = tonumber(snapshot.coldSuitability) or 0,
        endurance_before = tonumber(snapshot.enduranceBeforeAms) or nil,
        endurance_after = tonumber(snapshot.enduranceAfterAms) or nil,
        endurance_natural_delta = tonumber(snapshot.enduranceNaturalDelta) or 0,
        endurance_applied_delta = tonumber(snapshot.enduranceAppliedDelta) or 0,
        ams_regen_scale = tonumber(snapshot.amsEnduranceRegenScale) or 1,
        nms_regen_scale = tonumber(snapshot.nmsEnduranceRegenScale) or 1,
        composed_regen_scale = tonumber(snapshot.composedEnduranceRegenScale) or 1,
        ams_drain_applied = tonumber(snapshot.amsEnduranceDrainApplied) or 0,
        nms_drain_applied = tonumber(snapshot.nmsEnduranceDrainApplied) or 0,
        sleep_penalty_fraction = tonumber(state and state.lastSleepPenaltyFraction) or 0,
        sleep_wake_adjustment = tonumber(state and state.lastSleepWakeAdjustment) or 0,
        sleep_bed_type = tostring(state and state.sleepSnapshot and state.sleepSnapshot.bedType or ""),
    }
end

return Physiology
