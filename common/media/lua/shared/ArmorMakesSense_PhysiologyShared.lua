ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Models = ArmorMakesSense.Models or {}

local Models = ArmorMakesSense.Models
Models.Physiology = Models.Physiology or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = require "ArmorMakesSense_StatsShared"
local BreathingModel = require "ArmorMakesSense_BreathingModel"
local EnduranceModel = require "ArmorMakesSense_EnduranceModel"
local SleepPhysiology = require "ArmorMakesSense_SleepPhysiology"
local ThermalModel = require "ArmorMakesSense_ThermalModel"
local Physiology = Models.Physiology

-- -----------------------------------------------------------------------------
-- Physiological load + recovery model
-- -----------------------------------------------------------------------------

local function getCompat()
    return ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
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

function Physiology.applySleepTransition(player, state, options, dtMinutes, profile)
    return SleepPhysiology.applyTransition(player, state, options, dtMinutes, profile)
end

function Physiology.computeSleepPlannerPenalty(player, state, options, profile, currentFatigue)
    return SleepPhysiology.computePlannerPenalty(player, state, options, profile, currentFatigue)
end

function Physiology.computeSleepPenaltyContribution(player, state, options, dtMinutes, profile, currentFatigue)
    return SleepPhysiology.computePenaltyContribution(
        player,
        state,
        options,
        dtMinutes,
        profile,
        currentFatigue
    )
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
