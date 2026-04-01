ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Models = ArmorMakesSense.Models or {}

local Models = ArmorMakesSense.Models
Models.Physiology = Models.Physiology or {}

local Physiology = Models.Physiology
local C = {}

-- -----------------------------------------------------------------------------
-- Physiological load + recovery model
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

local function getCompat()
    local compatGetter = ctx("getCompat")
    if type(compatGetter) == "function" then
        return compatGetter()
    end
    if type(compatGetter) == "table" then
        return compatGetter
    end
    return nil
end

local function isCmsFatigueCompatActive()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("CaffeineMakesSense", "fatigue_coordinator")
end

local function clampValue(value, minimum, maximum)
    local clamp = ctx("clamp")
    if type(clamp) == "function" then
        return clamp(value, minimum, maximum)
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function smoothstep01(value)
    local x = clampValue(tonumber(value) or 0, 0, 1)
    return x * x * (3 - (2 * x))
end

local THERMAL_HOT_ON_THRESHOLD = 0.14
local THERMAL_HOT_OFF_THRESHOLD = 0.08
local THERMAL_COLD_ON_THRESHOLD = 0.12
local THERMAL_COLD_OFF_THRESHOLD = 0.06
local THERMAL_COLD_CONTEXT_MIN = 0.16
local THERMAL_COLD_CONTEXT_FULL = 0.60
local THERMAL_PRESSURE_DEADBAND = 0.18
local THERMAL_AMBIENT_COLD_TEMP = 22.0
local THERMAL_AMBIENT_HOT_TEMP = 38.0
local THERMAL_AMBIENT_FLOOR = 0.06
local THERMAL_CORE_ESCALATOR_WEIGHT = 0.35

local function thermalPressureToScale(pressure)
    local deadband = clampValue(THERMAL_PRESSURE_DEADBAND, 0, 0.95)
    local normalized = clampValue(
        ((tonumber(pressure) or 0) - deadband) / math.max(0.05, 1.0 - deadband),
        0,
        1.0
    )
    return smoothstep01(normalized)
end

local function resolveVentilationDemand(player, options, activityFactor, activityLabel)
    local idleFactor = clampValue(tonumber(options and options.ActivityIdle) or 0.35, 0.2, 1.8)
    local sprintFactor = clampValue(tonumber(options and options.ActivitySprint) or 1.35, 0.2, 1.8)
    local activitySpan = math.max(0.1, sprintFactor - idleFactor)
    local activityNorm = clampValue(((tonumber(activityFactor) or idleFactor) - idleFactor) / activitySpan, 0, 1.0)
    local demand = 0.20 + (0.70 * activityNorm)

    if activityLabel == "walk" then
        demand = math.min(demand, 0.48)
    elseif activityLabel == "combat" then
        demand = math.max(demand, 0.58)
    elseif activityLabel == "run" then
        demand = math.max(demand, 0.62)
    elseif activityLabel == "sprint" then
        demand = math.max(demand, 0.90)
    end

    local isAttackStarted = ctx("safeMethod") and ctx("safeMethod")(player, "isAttackStarted")
    if isAttackStarted == true then
        demand = math.max(demand, clampValue(tonumber(options and options.BreathingCombatDemandFloor) or 0.50, 0.2, 1.0))
    end

    return clampValue(demand, 0.15, 1.0)
end

local function normalizePositive(value, pivot, span, cap)
    local num = tonumber(value)
    if num == nil then
        return 0
    end
    if span == 0 then
        return 0
    end
    return clampValue((num - pivot) / span, 0, cap or 1.0)
end

local function normalizeNegative(value, pivot, span, cap)
    local num = tonumber(value)
    if num == nil then
        return 0
    end
    if span == 0 then
        return 0
    end
    return clampValue((pivot - num) / span, 0, cap or 1.0)
end

local function normalizeWetSample(value)
    local num = tonumber(value)
    if num == nil then
        return nil
    end
    if num > 1.0 then
        num = num / 100.0
    end
    return clampValue(num, 0, 1.0)
end

local function getOrCreateThermalState(state)
    if type(state) ~= "table" then
        return nil
    end
    if type(state.thermalModelState) ~= "table" then
        state.thermalModelState = {}
    end
    return state.thermalModelState
end

local function computeAsymmetricEma(stateBucket, key, target, riseAlpha, fallAlpha)
    local numTarget = tonumber(target) or 0
    if type(stateBucket) ~= "table" then
        return numTarget
    end

    local previous = tonumber(stateBucket[key])
    if previous == nil then
        stateBucket[key] = numTarget
        return numTarget
    end

    local alpha = (numTarget > previous) and (tonumber(riseAlpha) or 0.5) or (tonumber(fallAlpha) or 0.2)
    alpha = clampValue(alpha, 0.01, 1.0)
    local nextValue = previous + ((numTarget - previous) * alpha)
    stateBucket[key] = nextValue
    return nextValue
end

local function applySignalGate(stateBucket, key, value, onThreshold, offThreshold)
    local numValue = tonumber(value) or 0
    if type(stateBucket) ~= "table" then
        return numValue
    end

    local active = stateBucket[key] == true
    if active then
        if numValue <= (tonumber(offThreshold) or 0) then
            active = false
        end
    elseif numValue >= (tonumber(onThreshold) or 0) then
        active = true
    end

    stateBucket[key] = active
    if not active then
        return 0
    end
    return numValue
end

local collectThermoregulatorTelemetry

-- -----------------------------------------------------------------------------
-- Thermal pressure modeling
-- -----------------------------------------------------------------------------

local function sameMinute(a, b)
    return math.abs(a - b) < 0.05
end

local function resolveThermalPressureScale(player, state, heatFactor, wetFactor)
    local thermalState = getOrCreateThermalState(state)
    local nowMinutes = nil
    if type(ctx("getWorldAgeMinutes")) == "function" then
        nowMinutes = tonumber(ctx("getWorldAgeMinutes")())
    end
    if thermalState and nowMinutes ~= nil and thermalState.cachePayload and thermalState.cacheMinute ~= nil then
        if sameMinute(nowMinutes, thermalState.cacheMinute) then
            local cached = thermalState.cachePayload
            return cached.scale, cached.pressure, cached.hotStrain, cached.coldStrain, cached.bodyTemp, cached
        end
    end

    local telemetry = collectThermoregulatorTelemetry(player)
    local bodyTemp = telemetry and tonumber(telemetry.coreTemp) or nil
    if bodyTemp == nil then
        local getBodyTemperature = ctx("getBodyTemperature")
        if type(getBodyTemperature) == "function" then
            bodyTemp = tonumber(getBodyTemperature(player))
        end
    end

    local heatComponent = clampValue(((tonumber(heatFactor) or 1.0) - 1.00) / 0.15, 0, 1.6)
    local tempHotComponent = clampValue((tonumber(bodyTemp) and ((bodyTemp - 37.55) / 1.20) or 0), 0, 1.6)
    local tempColdComponent = clampValue((tonumber(bodyTemp) and ((36.90 - bodyTemp) / 1.20) or 0), 0, 1.6)

    local payload = {
        telemetry = telemetry,
        bodyTemp = bodyTemp,
        wetnessPenalty = clampValue(((tonumber(wetFactor) or 1.0) - 1.0) / 0.6, 0, 1.0),
    }

    if not telemetry then
        payload.hotStrain = math.max(heatComponent, tempHotComponent)
        payload.coldStrain = tempColdComponent
        payload.coldAppropriateness = 0
        payload.coldResidual = payload.coldStrain
        payload.pressure = clampValue(payload.hotStrain + payload.coldResidual, 0, 1.8)
        payload.scale = thermalPressureToScale(payload.pressure)
        local fallbackEnv = ((tonumber(heatFactor) or 1.0) * 0.70) + ((tonumber(wetFactor) or 1.0) * 0.30)
        payload.enduranceEnvFactor = clampValue(fallbackEnv, 0.70, 2.40)

        payload.heatGenerationNorm = 0
        payload.perspirationNorm = 0
        payload.shiveringNorm = 0
        payload.coldContext = payload.coldStrain
    else
        local skinHot = normalizePositive(telemetry.skinTemp, 33.40, 2.00, 1.8)
        local skinCold = normalizeNegative(telemetry.skinTemp, 32.20, 5.50, 1.8)
        local perspirationNorm = normalizePositive(telemetry.perspiration, 0.00, 0.26, 1.8)
        local shiveringNorm = normalizePositive(telemetry.shivering, 0.00, 0.20, 1.8)
        local vasodilationNorm = normalizePositive(telemetry.vasodilation, 0.00, 0.40, 1.5)
        local vasoconstrictionNorm = normalizePositive(telemetry.vasoconstriction, 0.00, 0.40, 1.5)
        local fluidsNorm = normalizePositive(telemetry.fluidsMultiplier, 1.00, 1.20, 1.6)
        local energyNorm = normalizePositive(telemetry.energyMultiplier, 1.00, 1.20, 1.6)
        local bodyHeatHot = normalizePositive(telemetry.bodyHeatDelta, 0.00, 0.55, 1.4)
        local bodyHeatCold = normalizeNegative(telemetry.bodyHeatDelta, 0.00, 0.65, 1.4)
        local coreTrendHot = normalizePositive(telemetry.coreRateOfChange, 0.00, 0.0045, 1.3)
        local coreTrendCold = normalizeNegative(telemetry.coreRateOfChange, 0.00, 0.0045, 1.3)
        local heatGenerationNorm = normalizePositive(telemetry.heatGeneration, 1.10, 2.20, 1.6)
        local coreHot = tempHotComponent
        local coreCold = tempColdComponent

        -- Peripheral effort = how hard the body is working to cool.
        -- Ambient context = whether the environment makes that effort armor-relevant.
        -- Core evidence = secondary escalator for genuinely rising body heat.
        local peripheralHot = clampValue(
            (skinHot * 0.22)
                + (perspirationNorm * 0.18)
                + (vasodilationNorm * 0.08)
                + (fluidsNorm * 0.06),
            0,
            1.4
        )
        local coreHotEvidence = clampValue(
            (bodyHeatHot * 0.32)
                + (coreHot * 0.30)
                + (coreTrendHot * 0.14)
                + (heatGenerationNorm * 0.12),
            0,
            1.4
        )
        local airTemp = math.max(
            tonumber(telemetry.externalAirTemp) or 20,
            tonumber(telemetry.airAndWindTemp) or 20
        )
        local ambientContext = clampValue(
            (airTemp - THERMAL_AMBIENT_COLD_TEMP) / math.max(1, THERMAL_AMBIENT_HOT_TEMP - THERMAL_AMBIENT_COLD_TEMP),
            0, 1.0
        )
        local modulatedPeripheral = peripheralHot * (THERMAL_AMBIENT_FLOOR + ((1 - THERMAL_AMBIENT_FLOOR) * ambientContext))
        local rawHot = clampValue(
            modulatedPeripheral + (coreHotEvidence * THERMAL_CORE_ESCALATOR_WEIGHT),
            0,
            1.8
        )
        local rawCold = clampValue(
            (skinCold * 0.27)
                + (shiveringNorm * 0.33)
                + (vasoconstrictionNorm * 0.10)
                + (energyNorm * 0.14)
                + (bodyHeatCold * 0.08)
                + (coreCold * 0.05)
                + (coreTrendCold * 0.03),
            0,
            1.8
        )

        local hotSmoothed = computeAsymmetricEma(thermalState, "hotEma", rawHot, 0.55, 0.38)
        local coldSmoothed = computeAsymmetricEma(thermalState, "coldEma", rawCold, 0.48, 0.32)
        local hotStrain = applySignalGate(
            thermalState,
            "hotActive",
            hotSmoothed,
            THERMAL_HOT_ON_THRESHOLD,
            THERMAL_HOT_OFF_THRESHOLD
        )
        local coldStrain = applySignalGate(
            thermalState,
            "coldActive",
            coldSmoothed,
            THERMAL_COLD_ON_THRESHOLD,
            THERMAL_COLD_OFF_THRESHOLD
        )

        local bodyWetness = normalizeWetSample(telemetry.bodyWetness)
        local clothingWetness = normalizeWetSample(telemetry.clothingWetness)
        local wetSamples = 0
        local wetTotal = 0
        if bodyWetness ~= nil then
            wetTotal = wetTotal + bodyWetness
            wetSamples = wetSamples + 1
        end
        if clothingWetness ~= nil then
            wetTotal = wetTotal + clothingWetness
            wetSamples = wetSamples + 1
        end
        local wetnessPenalty = payload.wetnessPenalty
        if wetSamples > 0 then
            wetnessPenalty = math.max(wetnessPenalty, wetTotal / wetSamples)
        end

        local insulationNorm = normalizePositive(telemetry.insulation, 0.10, 0.30, 1.6)
        local windResistanceNorm = normalizePositive(telemetry.windResistance, 0.08, 0.30, 1.6)
        local protectionEvidence = clampValue((insulationNorm * 0.62) + (windResistanceNorm * 0.38), 0, 1.6)

        local ambientCold = math.max(
            normalizeNegative(telemetry.externalAirTemp, 8.0, 18.0, 1.6),
            normalizeNegative(telemetry.airAndWindTemp, 8.0, 18.0, 1.6)
        )
        local shiverSuppression = 1.0 - clampValue(shiveringNorm / 1.10, 0, 1.0)
        local skinComfort = 1.0 - clampValue((32.0 - (tonumber(telemetry.skinTemp) or 33.0)) / 4.5, 0, 1.0)
        local severeSkinDrop = clampValue((30.0 - (tonumber(telemetry.skinTemp) or 33.0)) / 6.0, 0, 1.0)
        local outcomeEvidence = clampValue((shiverSuppression * 0.62) + (skinComfort * 0.38) - (severeSkinDrop * 0.28), 0, 1.2)
        local coldContext = clampValue(math.max(coldStrain, ambientCold, shiveringNorm * 0.80, coreCold * 0.60), 0, 1.6)

        local coldAppropriateness = 0
        if coldContext >= THERMAL_COLD_CONTEXT_MIN and protectionEvidence >= 0.10 then
            local contextScale = clampValue(coldContext / THERMAL_COLD_CONTEXT_FULL, 0.15, 1.0)
            coldAppropriateness = clampValue(
                ((protectionEvidence * 0.58) + (outcomeEvidence * 0.42))
                    * contextScale
                    * (1 - (wetnessPenalty * 0.80)),
                0,
                1.0
            )
            if shiveringNorm >= 1.00 and skinCold >= 0.80 then
                coldAppropriateness = coldAppropriateness * 0.40
            end
        end

        local coldResidualScale = 1 - coldAppropriateness
        local coldResidual = clampValue(coldStrain * coldResidualScale * coldResidualScale, 0, 1.8)
        local pressure = clampValue(hotStrain + coldResidual, 0, 1.8)
        local scale = thermalPressureToScale(pressure)
        local coldShiverLoad = clampValue((shiveringNorm * coldResidualScale * 0.70) + (coldResidual * 0.30), 0, 1.8)

        local thermalBurdenFactor = scale

        payload.hotStrain = hotStrain
        payload.coldStrain = coldStrain
        payload.coldAppropriateness = coldAppropriateness
        payload.coldResidual = coldResidual
        payload.pressure = pressure
        payload.scale = thermalBurdenFactor
        payload.enduranceEnvFactor = clampValue(
            1.0 + (thermalBurdenFactor * 1.05) + (coldShiverLoad * 0.45) + (wetnessPenalty * 0.20),
            0.70,
            2.40
        )

        payload.wetnessPenalty = wetnessPenalty
        payload.heatGenerationNorm = heatGenerationNorm
        payload.perspirationNorm = perspirationNorm
        payload.shiveringNorm = shiveringNorm
        payload.coldContext = coldContext
    end

    if thermalState and nowMinutes ~= nil then
        thermalState.cacheMinute = nowMinutes
        thermalState.cachePayload = payload
    end

    return payload.scale, payload.pressure, payload.hotStrain, payload.coldStrain, payload.bodyTemp, payload
end

collectThermoregulatorTelemetry = function(player)
    local safeMethod = ctx("safeMethod")
    if type(safeMethod) ~= "function" then
        return nil
    end

    local bodyDamage = safeMethod(player, "getBodyDamage")
    local thermoregulator = bodyDamage and safeMethod(bodyDamage, "getThermoregulator")
    if not thermoregulator then
        return nil
    end

    local telemetry = {
        coreTemp = tonumber(safeMethod(thermoregulator, "getCoreTemperature")),
        heatGeneration = tonumber(safeMethod(thermoregulator, "getHeatGeneration")),
        fluidsMultiplier = tonumber(safeMethod(thermoregulator, "getFluidsMultiplier")),
        energyMultiplier = tonumber(safeMethod(thermoregulator, "getEnergyMultiplier")),
        fatigueMultiplier = tonumber(safeMethod(thermoregulator, "getFatigueMultiplier")),
        bodyHeatDelta = tonumber(safeMethod(thermoregulator, "getBodyHeatDelta")),
        coreRateOfChange = tonumber(safeMethod(thermoregulator, "getCoreRateOfChange")),
        externalAirTemp = tonumber(safeMethod(thermoregulator, "getExternalAirTemperature")),
        airAndWindTemp = tonumber(safeMethod(thermoregulator, "getTemperatureAirAndWind")),
        dbgPrimaryTotal = tonumber(safeMethod(thermoregulator, "getDbg_primTotal")),
        dbgSecondaryTotal = tonumber(safeMethod(thermoregulator, "getDbg_secTotal")),
    }

    local nodeCount = tonumber(safeMethod(thermoregulator, "getNodeSize")) or 0
    nodeCount = math.max(0, math.floor(nodeCount))
    telemetry.nodeCount = nodeCount

    local totals = {}
    local counts = {}

    local function addValue(key, value)
        local num = tonumber(value)
        if num == nil then
            return
        end
        totals[key] = (totals[key] or 0) + num
        counts[key] = (counts[key] or 0) + 1
    end

    local function average(key)
        local count = counts[key] or 0
        if count <= 0 then
            return nil
        end
        return (totals[key] or 0) / count
    end

    for i = 0, nodeCount - 1 do
        local node = safeMethod(thermoregulator, "getNode", i)
        if node then
            addValue("skinTemp", safeMethod(node, "getSkinCelcius"))
            addValue("bodyResponse", safeMethod(node, "getBodyResponse"))
            addValue("primaryDelta", safeMethod(node, "getPrimaryDelta"))
            addValue("secondaryDelta", safeMethod(node, "getSecondaryDelta"))
            addValue("bodyWetness", safeMethod(node, "getBodyWetness"))
            addValue("clothingWetness", safeMethod(node, "getClothingWetness"))
            addValue("insulation", safeMethod(node, "getInsulation"))
            addValue("windResistance", safeMethod(node, "getWindresist"))
        end
    end

    telemetry.skinTemp = average("skinTemp")
    telemetry.bodyResponse = average("bodyResponse")
    telemetry.primaryDelta = average("primaryDelta")
    telemetry.secondaryDelta = average("secondaryDelta")
    telemetry.bodyWetness = average("bodyWetness")
    telemetry.clothingWetness = average("clothingWetness")
    telemetry.insulation = average("insulation")
    telemetry.windResistance = average("windResistance")

    if telemetry.dbgSecondaryTotal ~= nil then
        telemetry.perspiration = math.max(telemetry.dbgSecondaryTotal, 0)
        telemetry.shivering = math.max(-telemetry.dbgSecondaryTotal, 0)
    end
    if telemetry.dbgPrimaryTotal ~= nil then
        telemetry.bloodVessels = telemetry.dbgPrimaryTotal
        telemetry.vasodilation = math.max(telemetry.dbgPrimaryTotal, 0)
        telemetry.vasoconstriction = math.max(-telemetry.dbgPrimaryTotal, 0)
    end

    return telemetry
end

function Physiology.setContext(context)
    C = context or {}
end

function Physiology.getUiRuntimeSnapshot(player, state, options)
    local ensureState = ctx("ensureState")
    if type(ensureState) ~= "function" then
        return nil
    end
    local resolvedState = state or ensureState(player)
    if type(resolvedState) ~= "table" then
        return nil
    end
    local isMp = type(ctx("isMultiplayer")) == "function" and ctx("isMultiplayer")()
    if isMp and type(resolvedState.mpServerSnapshot) == "table" then
        local snapshot = resolvedState.mpServerSnapshot
        return {
            loadNorm = tonumber(snapshot.loadNorm) or 0,
            physicalLoad = tonumber(snapshot.physicalLoad) or 0,
            thermalLoad = tonumber(snapshot.thermalLoad) or 0,
            breathingLoad = tonumber(snapshot.breathingLoad) or 0,
            rigidityLoad = tonumber(snapshot.rigidityLoad) or 0,
            armorCount = tonumber(snapshot.armorCount) or 0,
            effectiveLoad = tonumber(snapshot.effectiveLoad) or 0,
            hotStrain = tonumber(snapshot.hotStrain) or 0,
            coldAppropriateness = tonumber(snapshot.coldAppropriateness) or 0,
            thermalPressureScale = tonumber(snapshot.thermalPressureScale) or 0,
            enduranceEnvFactor = tonumber(snapshot.enduranceEnvFactor) or 1,
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
        hotStrain = tonumber(snapshot.hotStrain) or 0,
        coldAppropriateness = tonumber(snapshot.coldAppropriateness) or 0,
        thermalPressureScale = tonumber(snapshot.thermalPressureScale) or 0,
        enduranceEnvFactor = tonumber(snapshot.enduranceEnvFactor) or 1,
        activityLabel = tostring(snapshot.activityLabel or "idle"),
        updatedMinute = tonumber(snapshot.updatedMinute) or 0,
    }
end

function Physiology.updateRecoveryTrace(state, options, nowMinutes, dtMinutes, profile, activityLabel, postureLabel, enduranceNow)
    local trace = state.recoveryTrace
    if not trace or enduranceNow == nil then
        return
    end

    local idleLike = (activityLabel == "idle")
    local recovered = enduranceNow >= 0.985
    local isSitting = string.find(postureLabel, "sit", 1, true) ~= nil

    if trace.active then
        trace.sampleMinutes = (trace.sampleMinutes or 0) + dtMinutes
        if isSitting then
            trace.sitMinutes = (trace.sitMinutes or 0) + dtMinutes
        else
            trace.standMinutes = (trace.standMinutes or 0) + dtMinutes
        end
        if enduranceNow > (trace.peakEndurance or 0) then
            trace.peakEndurance = enduranceNow
        end
        if enduranceNow < (trace.lowEndurance or 1) then
            trace.lowEndurance = enduranceNow
        end

        if recovered then
            trace.active = false
            return
        end

        if not idleLike then
            trace.active = false
            return
        end

        return
    end

    if idleLike and (not recovered) and postureLabel ~= "sleep" then
        trace.active = true
        trace.startMinute = nowMinutes
        trace.startEndurance = enduranceNow
        trace.peakEndurance = enduranceNow
        trace.lowEndurance = enduranceNow
        trace.startPhysicalLoad = tonumber(profile.physicalLoad) or 0
        trace.startArmorPieces = tonumber(profile.armorCount) or 0
        trace.postureStart = postureLabel
        trace.sitMinutes = 0
        trace.standMinutes = 0
        trace.sampleMinutes = 0
    end
end

local function playerHasTrait(player, traitName, traitEnum)
    local safeMethod = ctx("safeMethod")
    if type(safeMethod) ~= "function" or not player then
        return false
    end
    if traitEnum and _G.CharacterTrait and CharacterTrait[traitEnum] ~= nil then
        return safeMethod(player, "hasTrait", CharacterTrait[traitEnum]) == true
    end
    return safeMethod(player, "hasTrait", traitName) == true
end

local function getBedQualityMultiplier(player)
    local safeMethod = ctx("safeMethod")
    if type(safeMethod) ~= "function" then
        return 1.0
    end

    local bedType = tostring(safeMethod(player, "getBedType") or "")
    if bedType == "averageBedPillow" then
        return 1.05
    end
    if bedType == "goodBed" then
        return 1.10
    end
    if bedType == "goodBedPillow" then
        return 1.15
    end
    if bedType == "badBed" then
        return 0.90
    end
    if bedType == "badBedPillow" then
        return 0.95
    end
    if bedType == "floor" then
        return 0.60
    end
    if bedType == "floorPillow" then
        return 0.75
    end
    return 1.0
end

local function getVanillaSleepRecoveryRatePerHour(player, fatigue)
    local currentFatigue = tonumber(fatigue)
    if currentFatigue == nil or currentFatigue <= 0 then
        return 0
    end

    local sleepMul = 1.0
    if playerHasTrait(player, "Insomniac", "INSOMNIAC") then
        sleepMul = sleepMul * 0.5
    end
    if playerHasTrait(player, "NightOwl", "NIGHT_OWL") then
        sleepMul = sleepMul * 1.4
    end

    local traitMul = 1.0
    if playerHasTrait(player, "NeedsLessSleep", "NEEDS_LESS_SLEEP") then
        traitMul = 0.75
    elseif playerHasTrait(player, "NeedsMoreSleep", "NEEDS_MORE_SLEEP") then
        traitMul = 1.18
    end

    local bedQualityMultiplier = getBedQualityMultiplier(player)
    if currentFatigue <= 0.3 then
        return (0.3 / (7.0 * traitMul)) * sleepMul * bedQualityMultiplier
    end
    return (0.7 / (5.0 * traitMul)) * sleepMul * bedQualityMultiplier
end

local function getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
    local rigidityNorm = ctx("softNorm")(tonumber(snapshot and snapshot.rigidityLoad) or 0, 80.0, 2.0)
    if rigidityNorm <= 0 then
        return 0
    end

    local fatigue = tonumber(currentFatigue)
    if fatigue == nil then
        fatigue = ctx("getFatigue")(player)
    end
    if fatigue == nil then
        return 0
    end

    local baseRate = math.max(0, tonumber(options.SleepRigidityFatigueRate) or 0.003)
    local fatigueScale = math.max(0.1, 1.0 - fatigue)
    local counteractRatePerHour = rigidityNorm * baseRate * fatigueScale
    local vanillaRecoveryRatePerHour = getVanillaSleepRecoveryRatePerHour(player, fatigue)
    if vanillaRecoveryRatePerHour <= 0 then
        return 0
    end

    return clampValue(counteractRatePerHour / vanillaRecoveryRatePerHour, 0, 0.95)
end

function Physiology.applySleepTransition(player, state, options, dtMinutes, profile, heatFactor, wetFactor)
    if not options.EnableSleepPenaltyModel then
        state.sleepSnapshot = nil
        state.wasSleeping = false
        return
    end
    if isCmsFatigueCompatActive() then
        local sleeping = ctx("toBoolean")(ctx("safeMethod")(player, "isAsleep"))
        local wasSleeping = ctx("toBoolean")(state.wasSleeping)
        if sleeping and not state.sleepSnapshot then
            state.sleepSnapshot = {
                rigidityLoad = tonumber(profile.rigidityLoad) or 0,
            }
        end
        if (not sleeping) and wasSleeping and state.sleepSnapshot then
            state.sleepSnapshot = nil
        end
        state.wasSleeping = sleeping
        return 0
    end

    local result = Physiology.computeSleepPenaltyContribution(
        player,
        state,
        options,
        dtMinutes,
        profile,
        heatFactor,
        wetFactor,
        nil
    )

    local fatigue = ctx("getFatigue")(player)
    local penaltyFraction = clampValue(tonumber(result and result.penaltyFraction) or 0, 0, 0.95)
    local sampleMinutes = math.max(0, tonumber(dtMinutes) or 0)
    local extraFatigue = 0
    if fatigue ~= nil and penaltyFraction > 0 and sampleMinutes > 0 then
        local vanillaRecoveryRatePerHour = getVanillaSleepRecoveryRatePerHour(player, fatigue)
        local recoveredFatigue = vanillaRecoveryRatePerHour * (sampleMinutes / 60.0)
        extraFatigue = recoveredFatigue * penaltyFraction
    end
    if extraFatigue > 0 then
        if fatigue ~= nil then
            ctx("setFatigue")(player, math.min(0.85, fatigue + extraFatigue))
        end
    end
end

function Physiology.computeSleepPenaltyContribution(player, state, options, dtMinutes, profile, heatFactor, wetFactor, currentFatigue)
    if not options.EnableSleepPenaltyModel then
        state.sleepSnapshot = nil
        state.wasSleeping = false
        return {
            penaltyFraction = 0,
            sleeping = false,
        }
    end

    local sleeping = ctx("toBoolean")(ctx("safeMethod")(player, "isAsleep"))
    local wasSleeping = ctx("toBoolean")(state.wasSleeping)
    if sleeping and not wasSleeping then
        state.sleepSnapshot = {
            rigidityLoad = tonumber(profile.rigidityLoad) or 0,
        }
    end

    if sleeping then
        if not state.sleepSnapshot then
            state.sleepSnapshot = {
                rigidityLoad = tonumber(profile.rigidityLoad) or 0,
            }
        end
        local snapshot = state.sleepSnapshot
        if snapshot.rigidityLoad == nil then
            snapshot.rigidityLoad = tonumber(profile.rigidityLoad) or 0
        end
        local penaltyFraction = getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
        state.lastSleepPenaltyFraction = penaltyFraction
        state.wasSleeping = sleeping
        return {
            penaltyFraction = penaltyFraction,
            sleeping = true,
        }
    end

    if (not sleeping) and wasSleeping and state.sleepSnapshot then
        state.sleepSnapshot = nil
    end
    state.wasSleeping = sleeping
    state.lastSleepPenaltyFraction = 0

    return {
        penaltyFraction = 0,
        sleeping = sleeping,
    }
end

local function computeThermalContribution(player, state, options, wearabilityLoad, heatFactor, wetFactor)
    if not options.EnableThermalModel then
        return 0, 0, 0, 0, nil, nil, 0
    end
    local thermalPressureScale, thermalPressure, thermalHotStrain, thermalColdStrain, bodyTemp, thermalModel =
        resolveThermalPressureScale(player, state, heatFactor, wetFactor)
    local thermalContribution = wearabilityLoad * (tonumber(options.ThermalEnduranceWeight) or 0.35) * thermalPressureScale
    return thermalPressureScale, thermalPressure, thermalHotStrain, thermalColdStrain, bodyTemp, thermalModel, thermalContribution
end

local function applyBreathingRestrictionPenalty(player, options, profile, activityFactor, activityLabel, effectiveLoad)
    local effectiveBeforeBreathing = effectiveLoad
    local breathingContribution = 0
    local breathingLoad = tonumber(profile.breathingLoad) or 0
    if breathingLoad > 0 then
        local ventDemand = resolveVentilationDemand(player, options, activityFactor, activityLabel)
        local demandThreshold = clampValue(tonumber(options.BreathingDemandThreshold) or 0.52, 0.20, 0.92)
        local demandRamp = 0
        if ventDemand > demandThreshold then
            demandRamp = smoothstep01((ventDemand - demandThreshold) / math.max(0.05, 1.0 - demandThreshold))
        end

        local maskLoadStart = tonumber(options.BreathingPenaltyLoadStart) or 1.20
        local maskLoadSpan = math.max(0.1, tonumber(options.BreathingPenaltyLoadSpan) or 2.20)
        local maskNorm = clampValue((breathingLoad - maskLoadStart) / maskLoadSpan, 0, 1.0)

        local sealLoadStart = tonumber(options.BreathingSealLoadStart) or 3.45
        local sealLoadSpan = math.max(0.05, tonumber(options.BreathingSealLoadSpan) or 0.20)
        local sealedNorm = clampValue((breathingLoad - sealLoadStart) / sealLoadSpan, 0, 1.0)

        local reliefLoad = math.min(breathingLoad, math.max(0.1, tonumber(options.BreathingReliefMaxLoad) or 3.30))
        local staticRelief = reliefLoad * (tonumber(options.BreathingStaticReliefWeight) or 1.10) * maskNorm
        local dynamicLoad = breathingLoad
            * (tonumber(options.BreathingDynamicLoadWeight) or 1.80)
            * demandRamp
            * (0.35 + (0.65 * maskNorm))
        local sealedDynamicLoad = breathingLoad
            * (tonumber(options.BreathingSealedDynamicLoadWeight) or 1.35)
            * demandRamp
            * sealedNorm

        effectiveLoad = math.max(0, effectiveLoad - staticRelief + dynamicLoad + sealedDynamicLoad)
        breathingContribution = effectiveLoad - effectiveBeforeBreathing
    end

    return effectiveLoad, breathingContribution, breathingLoad
end

local function computeRegenControlledEndurance(previous, loadNorm, naturalDelta, endurance, isIdle, isSitting, isWalk, envFactor, options, activityLoadScale)
    local controlled = endurance
    local regenScale = 1.0

    if previous ~= nil and loadNorm > 0 and naturalDelta > 0 then
        local postureScale = 1.0
        if isIdle and isSitting then
            postureScale = 0.90
        elseif isIdle then
            postureScale = 1.00
        end
        local topoffScale = ctx("clamp")(0.55 + ((1.0 - endurance) * 0.45), 0.55, 1.0)
        local regenActivityScale = 1.0
        if isWalk then
            local walkStressed = envFactor >= 1.12 or endurance <= 0.58
            if walkStressed then
                regenActivityScale = 0.70
            else
                regenActivityScale = 0.40
            end
        end
        local regenPenalty = ctx("clamp")(
            (options.EnduranceRegenPenalty or 0.45) * (0.45 + (0.35 * loadNorm)) * envFactor * postureScale * topoffScale * regenActivityScale * activityLoadScale,
            0,
            0.85
        )
        regenScale = 1 - regenPenalty
        controlled = previous + (naturalDelta * regenScale)
    end

    return controlled, regenScale
end

local function computeEnduranceDrain(controlled, loadNorm, isIdle, activityLabel, envFactor, endurance, endMoodle, options, activityLoadScale, dtMinutes)
    local drainApplied = 0

    if loadNorm > 0 and (not isIdle) then
        local activityDrainScale = 0.45
        if activityLabel == "walk" then
            local stressed = envFactor >= 1.18 or endurance <= 0.60 or endMoodle >= 2
            if stressed and (loadNorm >= 2.0 or envFactor >= 1.18) then
                activityDrainScale = 0.06
            elseif envFactor >= 1.05 and loadNorm >= 2.4 and endurance <= 0.60 then
                activityDrainScale = 0.02
            else
                activityDrainScale = 0
            end
        elseif activityLabel == "combat" then
            activityDrainScale = 0.20
        elseif activityLabel == "run" then
            activityDrainScale = 0.335
        elseif activityLabel == "sprint" then
            activityDrainScale = 0.58
        end
        if activityDrainScale > 0 then
            local drainPerMinute = (options.BaseEnduranceDrainPerMinute or 0.0033) * (1 + (1.6 * loadNorm)) * activityDrainScale * envFactor * activityLoadScale
            drainApplied = drainPerMinute * dtMinutes
            controlled = controlled - drainApplied
        end
    end

    return controlled, drainApplied
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
    controlled = ctx("clamp")(controlled, 0, 1)
    if math.abs(controlled - endurance) > 0.0002 then
        ctx("setEndurance")(player, controlled)
    end
    return controlled
end

function Physiology.applyEnduranceModel(player, state, options, dtMinutes, profile, heatFactor, wetFactor, activityFactor, activityLabel, postureLabel)
    local endurance = ctx("getEndurance")(player)
    if endurance == nil then
        return nil
    end

    local massLoad = tonumber(profile.massLoad) or tonumber(profile.physicalLoad) or 0
    local wearabilityLoad = tonumber(profile.wearabilityLoad) or tonumber(profile.thermalLoad) or 0
    local thermalPressureScale, thermalPressure, thermalHotStrain, thermalColdStrain, bodyTemp, thermalModel =
        nil, nil, nil, nil, nil, nil
    local thermalContribution = 0
    thermalPressureScale, thermalPressure, thermalHotStrain, thermalColdStrain, bodyTemp, thermalModel, thermalContribution =
        computeThermalContribution(player, state, options, wearabilityLoad, heatFactor, wetFactor)
    local effectiveLoad = massLoad + thermalContribution
    local breathingContribution, breathingLoad = 0, 0
    effectiveLoad, breathingContribution, breathingLoad =
        applyBreathingRestrictionPenalty(player, options, profile, activityFactor, activityLabel, effectiveLoad)
    local loadMin = math.max(0, tonumber(options.ArmorLoadMin) or 5)
    local loadNorm = ctx("softNorm")(effectiveLoad - loadMin, 50.0, 2.5)
    loadNorm = ctx("clamp")(loadNorm, 0, 2.8)
    local envFactor = tonumber(thermalModel and thermalModel.enduranceEnvFactor)
        or ((heatFactor * 0.70) + (wetFactor * 0.30))
    local activityLoadScale = ctx("clamp")((0.55 + (0.45 * (tonumber(activityFactor) or 1.0))), 0.45, 1.85)
    local previous = state.lastEnduranceObserved
    local naturalDelta = 0
    if previous ~= nil then
        naturalDelta = endurance - previous
    end
    local isIdle = activityLabel == "idle"
    local isSitting = postureLabel and (string.find(postureLabel, "sit", 1, true) ~= nil)
    local isWalk = activityLabel == "walk"
    local nmsContribution = resolveNmsEnduranceContribution(player, dtMinutes, naturalDelta, endurance, previous)
    local nmsRegenScale = tonumber(nmsContribution and nmsContribution.regenScale) or 1.0
    local nmsDrain = math.max(0, tonumber(nmsContribution and nmsContribution.extraDrain) or 0)

    local _, amsRegenScale = computeRegenControlledEndurance(
        previous,
        loadNorm,
        naturalDelta,
        endurance,
        isIdle,
        isSitting,
        isWalk,
        envFactor,
        options,
        activityLoadScale
    )
    local regenScale = amsRegenScale * nmsRegenScale
    local controlled = endurance
    if previous ~= nil and naturalDelta > 0 and (loadNorm > 0 or nmsRegenScale < 0.9999) then
        controlled = previous + (naturalDelta * regenScale)
    end

    local endMoodle = -1
    local moodles = ctx("safeMethod")(player, "getMoodles")
    if moodles and MoodleType and MoodleType.ENDURANCE then
        endMoodle = tonumber(ctx("safeMethod")(moodles, "getMoodleLevel", MoodleType.ENDURANCE)) or -1
    end

    local amsDrainApplied = 0
    controlled, amsDrainApplied = computeEnduranceDrain(
        controlled,
        loadNorm,
        isIdle,
        activityLabel,
        envFactor,
        endurance,
        endMoodle,
        options,
        activityLoadScale,
        dtMinutes
    )
    if nmsDrain > 0 then
        controlled = controlled - nmsDrain
    end
    local drainApplied = amsDrainApplied + nmsDrain

    if previous ~= nil and isIdle and naturalDelta > 0 then
        if controlled < previous then
            controlled = previous
        end
        if controlled > endurance then
            controlled = endurance
        end
    end

    controlled = applyEnduranceCorrection(player, controlled, endurance)
    recordNmsEnduranceResult(player, controlled, nmsRegenScale, nmsDrain)

    local enduranceDelta = controlled - endurance
    state.lastEnduranceObserved = controlled
    local nowMinute = 0
    local getWorldAgeMinutes = ctx("getWorldAgeMinutes")
    if type(getWorldAgeMinutes) == "function" then
        nowMinute = tonumber(getWorldAgeMinutes()) or 0
    end
    local snapshotHotStrain = tonumber(thermalModel and thermalModel.hotStrain) or 0
    local snapshotColdAppropriateness = tonumber(thermalModel and thermalModel.coldAppropriateness) or 0
    local thermalUiState = snapshotHotStrain > 0.24 and "hot" or (snapshotColdAppropriateness > 0.45 and "cold" or "neutral")
    local prevThermalUiState = state.uiRuntimeSnapshot and state.uiRuntimeSnapshot.thermalUiState or nil
    state.uiRuntimeSnapshot = {
        loadNorm = loadNorm,
        effectiveLoad = effectiveLoad,
        massLoad = massLoad,
        thermalLoad = wearabilityLoad,
        breathingLoad = breathingLoad,
        thermalContribution = thermalContribution,
        breathingContribution = breathingContribution,
        muscleContribution = 0,
        recoveryContribution = 0,
        hotStrain = snapshotHotStrain,
        bodyTemp = tonumber(bodyTemp) or nil,
        coldAppropriateness = snapshotColdAppropriateness,
        thermalPressureScale = tonumber(thermalPressureScale) or 0,
        enduranceBeforeAms = endurance,
        enduranceAfterAms = controlled,
        enduranceNaturalDelta = naturalDelta,
        enduranceAppliedDelta = enduranceDelta,
        amsEnduranceRegenScale = amsRegenScale,
        nmsEnduranceRegenScale = nmsRegenScale,
        composedEnduranceRegenScale = regenScale,
        amsEnduranceDrainApplied = amsDrainApplied,
        nmsEnduranceDrainApplied = nmsDrain,
        enduranceEnvFactor = tonumber(envFactor) or 1,
        activityLabel = activityLabel,
        thermalUiState = thermalUiState,
        updatedMinute = nowMinute,
    }
    if prevThermalUiState ~= nil and thermalUiState ~= prevThermalUiState then
        local markUiDirty = ctx("markUiDirty")
        if type(markUiDirty) == "function" then
            markUiDirty()
        end
    end

    return enduranceDelta
end

function Physiology.buildCompatTraceSnapshot(state)
    local snapshot = type(state) == "table" and type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or {}
    return {
        activity_label = tostring(snapshot.activityLabel or ""),
        load_norm = tonumber(snapshot.loadNorm) or 0,
        effective_load = tonumber(snapshot.effectiveLoad) or 0,
        physical_load = tonumber(snapshot.massLoad) or 0,
        thermal_load = tonumber(snapshot.thermalLoad) or 0,
        breathing_load = tonumber(snapshot.breathingLoad) or 0,
        thermal_contribution = tonumber(snapshot.thermalContribution) or 0,
        breathing_contribution = tonumber(snapshot.breathingContribution) or 0,
        endurance_env_factor = tonumber(snapshot.enduranceEnvFactor) or 1,
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
    }
end

return Physiology
