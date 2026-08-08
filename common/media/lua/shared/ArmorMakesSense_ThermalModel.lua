ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.ThermalModel = ArmorMakesSense.ThermalModel or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local ThermalModel = ArmorMakesSense.ThermalModel

local HOT_PRESSURE_DEADBAND = 0.18
local HOT_RISE_ALPHA = 0.55
local HOT_FALL_ALPHA = 0.38
local COLD_CONTEXT_MIN = 0.16
local AMBIENT_COLD_C = 22.0
local AMBIENT_HOT_C = 38.0
local AMBIENT_PERIPHERAL_FLOOR = 0.06
local CORE_ESCALATOR_WEIGHT = 0.35

local function normalizePositive(value, pivot, span, cap)
    local numeric = tonumber(value)
    if numeric == nil or span <= 0 then
        return 0
    end
    return Utils.clamp((numeric - pivot) / span, 0, tonumber(cap) or 1)
end

local function normalizeNegative(value, pivot, span, cap)
    local numeric = tonumber(value)
    if numeric == nil or span <= 0 then
        return 0
    end
    return Utils.clamp((pivot - numeric) / span, 0, tonumber(cap) or 1)
end

local function smoothstep01(value)
    local x = Utils.clamp(tonumber(value) or 0, 0, 1)
    return x * x * (3 - (2 * x))
end

local function pressureToScale(pressure)
    local normalized = Utils.clamp(
        ((tonumber(pressure) or 0) - HOT_PRESSURE_DEADBAND) / (1 - HOT_PRESSURE_DEADBAND),
        0,
        1
    )
    return smoothstep01(normalized)
end

local function advanceEma(previous, target, elapsedMinutes)
    local prior = tonumber(previous) or 0
    local nextTarget = Utils.clamp(tonumber(target) or 0, 0, 1)
    local elapsed = math.max(0, tonumber(elapsedMinutes) or 0)
    if elapsed <= 0 then
        return prior
    end
    local baseAlpha = nextTarget > prior and HOT_RISE_ALPHA or HOT_FALL_ALPHA
    local alpha = 1 - math.pow(1 - baseAlpha, elapsed)
    return prior + ((nextTarget - prior) * alpha)
end

local function neutralResult(available, bodyTemp)
    return {
        available = available == true,
        bodyTemp = tonumber(bodyTemp),
        bodyHeatDelta = 0,
        resistance = 0,
        hotDrive = 0,
        hotPressure = 0,
        strainScale = 0,
        coldNeed = 0,
        coldSuitability = 0,
        contribution = 0,
    }
end

function ThermalModel.sample(player)
    local bodyDamage = Utils.safeMethod(player, "getBodyDamage")
    local thermoregulator = bodyDamage and Utils.safeMethod(bodyDamage, "getThermoregulator")
    if not thermoregulator then
        return nil
    end

    local totals = {
        insulation = 0,
        windResistance = 0,
        skinTemp = 0,
    }
    local weights = {
        insulation = 0,
        windResistance = 0,
        skinTemp = 0,
    }

    local function add(key, value, weight)
        local numeric = tonumber(value)
        if numeric == nil then
            return
        end
        local sampleWeight = tonumber(weight) or 1
        if sampleWeight <= 0 then
            return
        end
        totals[key] = totals[key] + (numeric * sampleWeight)
        weights[key] = weights[key] + sampleWeight
    end

    local nodeCount = math.max(0, math.floor(tonumber(Utils.safeMethod(thermoregulator, "getNodeSize")) or 0))
    for index = 0, nodeCount - 1 do
        local node = Utils.safeMethod(thermoregulator, "getNode", index)
        if node then
            local surface = tonumber(Utils.safeMethod(node, "getSkinSurface"))
            add("insulation", Utils.safeMethod(node, "getInsulationUI"), surface)
            add("windResistance", Utils.safeMethod(node, "getWindresistUI"), surface)
            add("skinTemp", Utils.safeMethod(node, "getSkinCelcius"), surface)
        end
    end

    local function average(key)
        if weights[key] <= 0 then
            return 0
        end
        return totals[key] / weights[key]
    end

    local primaryTotal = tonumber(Utils.safeMethod(thermoregulator, "getDbg_primTotal")) or 0
    local secondaryTotal = tonumber(Utils.safeMethod(thermoregulator, "getDbg_secTotal")) or 0
    return {
        coreTemp = tonumber(Utils.safeMethod(thermoregulator, "getCoreTemperature")),
        bodyHeatDelta = tonumber(Utils.safeMethod(thermoregulator, "getBodyHeatDelta")),
        coreRateOfChange = tonumber(Utils.safeMethod(thermoregulator, "getCoreRateOfChange")),
        heatGeneration = tonumber(Utils.safeMethod(thermoregulator, "getHeatGeneration")),
        fluidsMultiplier = tonumber(Utils.safeMethod(thermoregulator, "getFluidsMultiplier")),
        externalAirTemp = tonumber(Utils.safeMethod(thermoregulator, "getExternalAirTemperature")),
        airAndWindTemp = tonumber(Utils.safeMethod(thermoregulator, "getTemperatureAirAndWind")),
        skinTemp = average("skinTemp"),
        perspiration = math.max(secondaryTotal, 0),
        vasodilation = math.max(primaryTotal, 0),
        shivering = math.max(-secondaryTotal, 0),
        insulation = average("insulation"),
        windResistance = average("windResistance"),
        nodeCount = nodeCount,
    }
end

function ThermalModel.advance(sample, state, elapsedMinutes, options)
    if not (options and options.EnableThermalModel) then
        return neutralResult(sample ~= nil, sample and sample.coreTemp)
    end
    if type(sample) ~= "table" then
        return neutralResult(false, nil)
    end

    local insulation = Utils.clamp(tonumber(sample.insulation) or 0, 0, 1)
    local windResistance = Utils.clamp(tonumber(sample.windResistance) or 0, 0, 1)
    local resistance = Utils.clamp((insulation * 0.70) + (windResistance * 0.30), 0, 1)

    -- Vanilla body heat is not, by itself, evidence that equipment is imposing
    -- an exertion cost. Peripheral cooling effort is contextualized by ambient
    -- temperature, while core/body-heat evidence only escalates the signal.
    -- This retains the simple aggregate resistance model without letting one
    -- saturated thermoregulator field turn ordinary summer clothing into armor.
    local skinHot = normalizePositive(sample.skinTemp, 33.40, 2.00, 1.8)
    local perspiration = normalizePositive(sample.perspiration, 0, 0.26, 1.8)
    local vasodilation = normalizePositive(sample.vasodilation, 0, 0.40, 1.5)
    local fluids = normalizePositive(sample.fluidsMultiplier, 1.00, 1.20, 1.6)
    local bodyHeat = normalizePositive(sample.bodyHeatDelta, 0, 0.55, 1.4)
    local coreHeat = normalizePositive(sample.coreTemp, 37.55, 1.20, 1.6)
    local coreTrend = normalizePositive(sample.coreRateOfChange, 0, 0.0045, 1.3)
    local heatGeneration = normalizePositive(sample.heatGeneration, 1.10, 2.20, 1.6)

    local peripheralHeat = Utils.clamp(
        (skinHot * 0.22)
            + (perspiration * 0.18)
            + (vasodilation * 0.08)
            + (fluids * 0.06),
        0,
        1.4
    )
    local coreEvidence = Utils.clamp(
        (bodyHeat * 0.32)
            + (coreHeat * 0.30)
            + (coreTrend * 0.14)
            + (heatGeneration * 0.12),
        0,
        1.4
    )
    local externalAir = tonumber(sample.externalAirTemp)
    local airAndWind = tonumber(sample.airAndWindTemp)
    local ambientAir = math.max(externalAir or 20, airAndWind or 20)
    local ambientContext = Utils.clamp(
        (ambientAir - AMBIENT_COLD_C) / math.max(1, AMBIENT_HOT_C - AMBIENT_COLD_C),
        0,
        1
    )
    local contextualPeripheral = peripheralHeat
        * (AMBIENT_PERIPHERAL_FLOOR + ((1 - AMBIENT_PERIPHERAL_FLOOR) * ambientContext))
    local hotDrive = Utils.clamp(
        contextualPeripheral + (coreEvidence * CORE_ESCALATOR_WEIGHT),
        0,
        1
    )

    local modelState = type(state) == "table" and state or nil
    local previous = modelState and tonumber(modelState.hotPressure) or nil
    if previous == nil then
        previous = Utils.clamp(coreHeat, 0, 1)
    end
    local hotPressure = advanceEma(previous, hotDrive, elapsedMinutes)
    if modelState then
        modelState.hotPressure = hotPressure
    end

    local shivering = normalizePositive(sample.shivering, 0, 0.20)
    local coldNeed = math.max(
        normalizeNegative(sample.bodyHeatDelta, 0, 0.65),
        normalizeNegative(sample.coreTemp, 36.90, 1.20),
        shivering
    )
    local coldSuitability = 0
    if coldNeed >= COLD_CONTEXT_MIN then
        coldSuitability = Utils.clamp(resistance * (1 - shivering), 0, 1)
    end

    local strainScale = pressureToScale(hotPressure)
    local contributionMax = math.max(0, tonumber(options.ThermalContributionMax) or 14)
    return {
        available = true,
        bodyTemp = tonumber(sample.coreTemp),
        bodyHeatDelta = tonumber(sample.bodyHeatDelta) or 0,
        resistance = resistance,
        hotDrive = hotDrive,
        hotPressure = hotPressure,
        strainScale = strainScale,
        coldNeed = coldNeed,
        coldSuitability = coldSuitability,
        contribution = resistance * strainScale * contributionMax,
    }
end

return ThermalModel
