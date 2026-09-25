ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Models = ArmorMakesSense.Models or {}

local Models = ArmorMakesSense.Models
Models.Physiology = Models.Physiology or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = require "ArmorMakesSense_StatsShared"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local BreathingModel = require "ArmorMakesSense_BreathingModel"
local EnduranceModel = require "ArmorMakesSense_EnduranceModel"
local SleepModel = require "ArmorMakesSense_SleepModel"
local ThermalModel = require "ArmorMakesSense_ThermalModel"
local Physiology = Models.Physiology

-- One authoritative tick per game minute (SP local player, MP server).

local function getCompat()
    return ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
end

local function nmsCallback(name)
    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.getCallback) ~= "function" then
        return nil
    end
    local callback = compat:getCallback("NutritionMakesSense", name)
    return type(callback) == "function" and callback or nil
end

local function resolveNmsContribution(player, dtMinutes, naturalDelta, endurance, previous)
    local callback = nmsCallback("computeEnduranceContribution")
    if not callback then
        return 1, 0
    end
    local ok, contribution = pcall(callback, player, {
        dtMinutes = dtMinutes,
        dtHours = dtMinutes / 60.0,
        naturalDelta = naturalDelta,
        currentEndurance = endurance,
        previousEndurance = previous,
    })
    if not ok or type(contribution) ~= "table" then
        return 1, 0
    end
    return tonumber(contribution.regenScale) or 1, math.max(0, tonumber(contribution.extraDrain) or 0)
end

local function recordNmsResult(player, controlled, regenScale, extraDrain)
    local callback = nmsCallback("recordEnduranceResult")
    if callback then
        pcall(callback, player, {
            controlledEndurance = controlled,
            regenScale = regenScale,
            extraDrain = extraDrain,
        })
    end
end

local function scalesFor(options, loadFraction, heat, breathingInput, activityLabel, resting)
    local breathing = BreathingModel.calculate(options, {
        airflowResistance = breathingInput.airflowResistance,
        sealedRestriction = breathingInput.sealedRestriction,
        metabolicRate = breathingInput.metabolicRate,
        activityLabel = activityLabel,
    })
    return EnduranceModel.scales(options, {
        loadFraction = loadFraction,
        heat = heat,
        breathing = breathing.pressure,
        activityLabel = activityLabel,
        resting = resting,
    }), breathing
end

-- Presentation: what the current loadout costs at each pace, right now.
local function buildSnapshot(player, state, options, profile, thermal, activityLabel, postureLabel)
    local carrier = LoadModel.resolveCarrier(player, options)
    local loadFraction = LoadModel.loadFraction(options, profile.burdenKg, carrier)
    local heat = tonumber(thermal.heat) or 0
    local breathingInput = {
        airflowResistance = profile.airflowResistance,
        sealedRestriction = profile.sealedRestriction,
    }
    local walk = scalesFor(options, loadFraction, heat, breathingInput, "walk", false)
    local run = scalesFor(options, loadFraction, heat, breathingInput, "run", false)
    local sprint, sprintBreathing = scalesFor(options, loadFraction, heat, breathingInput, "sprint", false)
    local stand = scalesFor(options, loadFraction, heat, breathingInput, "idle", false)
    local rest = scalesFor(options, loadFraction, heat, breathingInput, "idle", true)
    return {
        activityLabel = activityLabel,
        postureLabel = postureLabel,
        burdenKg = profile.burdenKg,
        armKg = profile.armKg,
        rigidKg = profile.rigidKg,
        driverCount = profile.driverCount,
        bodyKg = carrier.bodyKg,
        strength = carrier.strength,
        loadFraction = loadFraction,
        heat = heat,
        thermalResistance = tonumber(thermal.resistance) or 0,
        hotPressure = tonumber(thermal.hotPressure) or 0,
        coldSuitability = tonumber(thermal.coldSuitability) or 0,
        airflowResistance = profile.airflowResistance,
        sealedRestriction = profile.sealedRestriction,
        breathingSeverity = sprintBreathing.severity,
        breathingEnabled = Utils.toBoolean(options.EnableBreathingModel),
        restRegenScale = rest.regenScale,
        standRegenScale = stand.regenScale,
        walkRegenScale = walk.physicalRegen * walk.thermalRegen,
        runDrainScale = run.drainScale,
        sprintDrainScale = sprint.drainScale,
        sleepPenaltyFraction = SleepModel.penaltyFraction(options, profile.rigidKg),
        updatedMinute = tonumber(Utils.getWorldAgeMinutes()) or 0,
    }
end

local function advanceThermal(player, state, options, dtMinutes)
    state.thermalModelState = type(state.thermalModelState) == "table" and state.thermalModelState or {}
    return ThermalModel.advance(ThermalModel.sample(player), state.thermalModelState, dtMinutes, options)
end

local function rebase(player, state)
    state.lastEnduranceObserved = Stats.getEndurance(player)
end

function Physiology.tick(player, state, options, profile, nowMinutes)
    local now = tonumber(nowMinutes) or 0
    local last = tonumber(state.lastTickMinute)
    state.lastTickMinute = now
    local elapsed = last and (now - last) or 0

    local sleep = SleepModel.step(player, state, options, profile)
    local postureLabel = Environment.getPostureLabel(player)
    local activityLabel = Environment.resolveActivity(player)

    if sleep.sleeping or last == nil or elapsed <= 0 or elapsed > (tonumber(options.MaxStepMinutes) or 30) then
        rebase(player, state)
        local thermal = advanceThermal(player, state, options, 0)
        state.uiRuntimeSnapshot = buildSnapshot(player, state, options, profile, thermal, activityLabel, postureLabel)
        return state.uiRuntimeSnapshot
    end

    local thermal = advanceThermal(player, state, options, elapsed)
    local snapshot = buildSnapshot(player, state, options, profile, thermal, activityLabel, postureLabel)
    local endurance = Stats.getEndurance(player)
    local previous = tonumber(state.lastEnduranceObserved)
    if endurance == nil then
        state.uiRuntimeSnapshot = snapshot
        return snapshot
    end

    local naturalDelta = previous and (endurance - previous) or 0
    local nmsRegenScale, nmsDrain = resolveNmsContribution(player, elapsed, naturalDelta, endurance, previous)
    local breathing = BreathingModel.calculate(options, {
        airflowResistance = profile.airflowResistance,
        sealedRestriction = profile.sealedRestriction,
        metabolicRate = Stats.getMetabolicRate(player),
        activityLabel = activityLabel,
    })
    local result = EnduranceModel.calculate(options, {
        previous = previous,
        current = endurance,
        loadFraction = snapshot.loadFraction,
        heat = snapshot.heat,
        breathing = breathing.pressure,
        activityLabel = activityLabel,
        resting = Environment.isResting(postureLabel),
        nmsRegenScale = nmsRegenScale,
        nmsDrain = nmsDrain,
    })
    local controlled = result.controlledEndurance
    if result.canApply then
        if math.abs(controlled - endurance) > 0.00001 then
            Stats.setEndurance(player, controlled)
        end
        recordNmsResult(player, controlled, result.nmsRegenScale, result.nmsDrainApplied)
    end
    state.lastEnduranceObserved = controlled

    snapshot.naturalDelta = result.naturalDelta
    snapshot.amsDelta = result.amsDelta
    snapshot.regenScale = result.regenScale
    snapshot.drainScale = result.drainScale
    snapshot.nmsRegenScale = result.nmsRegenScale
    snapshot.nmsDrain = result.nmsDrainApplied
    snapshot.dtMinutes = elapsed
    snapshot.metabolicRate = breathing.metabolicRate
    snapshot.breathingEffortRamp = breathing.effortRamp
    snapshot.breathingPressure = breathing.pressure
    state.uiRuntimeSnapshot = snapshot
    return snapshot
end

-- Read-only projection for UI refreshes between ticks.
function Physiology.project(player, state, options, profile)
    local thermalCopy = {}
    for key, value in pairs(type(state) == "table" and state.thermalModelState or {}) do
        thermalCopy[key] = value
    end
    local thermal = ThermalModel.advance(ThermalModel.sample(player), thermalCopy, 0, options)
    return buildSnapshot(
        player,
        state,
        options,
        profile,
        thermal,
        Environment.resolveActivity(player),
        Environment.getPostureLabel(player)
    )
end

-- MP presentation: gear-derived values from the local worn items (identical
-- to the server's), thermal state from the latest server snapshot.
function Physiology.projectWithServerThermal(player, options, profile, serverSnapshot)
    local server = type(serverSnapshot) == "table" and serverSnapshot or {}
    return buildSnapshot(
        player,
        nil,
        options,
        profile,
        {
            heat = server.heat,
            resistance = server.thermalResistance,
            hotPressure = server.hotPressure,
            coldSuitability = server.coldSuitability,
        },
        Environment.resolveActivity(player),
        Environment.getPostureLabel(player)
    )
end

function Physiology.getUiRuntimeSnapshot(state)
    if type(state) ~= "table" then
        return nil
    end
    if Utils.isMultiplayer() then
        return type(state.mpServerSnapshot) == "table" and state.mpServerSnapshot or nil
    end
    return type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or nil
end

function Physiology.sleepPenaltyContribution(player, options, profile)
    return {
        penaltyFraction = SleepModel.penaltyFraction(options, profile and profile.rigidKg),
        sleeping = Utils.toBoolean(Utils.safeMethod(player, "isAsleep")),
    }
end

function Physiology.buildCompatTraceSnapshot(state)
    local snapshot = type(state) == "table" and type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or {}
    return {
        activity_label = tostring(snapshot.activityLabel or ""),
        burden_kg = tonumber(snapshot.burdenKg) or 0,
        load_fraction = tonumber(snapshot.loadFraction) or 0,
        heat = tonumber(snapshot.heat) or 0,
        regen_scale = tonumber(snapshot.regenScale) or 1,
        drain_scale = tonumber(snapshot.drainScale) or 1,
        natural_delta = tonumber(snapshot.naturalDelta) or 0,
        ams_delta = tonumber(snapshot.amsDelta) or 0,
        nms_regen_scale = tonumber(snapshot.nmsRegenScale) or 1,
        nms_drain = tonumber(snapshot.nmsDrain) or 0,
        sleep_penalty_fraction = tonumber(snapshot.sleepPenaltyFraction) or 0,
    }
end

return Physiology
