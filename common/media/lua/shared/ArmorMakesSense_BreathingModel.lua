ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.BreathingModel = ArmorMakesSense.BreathingModel or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local BreathingModel = ArmorMakesSense.BreathingModel
local METABOLIC_REST = 1.5
local METABOLIC_WALK = 3.1
local METABOLIC_RUN = 6.9
local METABOLIC_MAX = 9.5

local function requiredNumber(options, key)
    local value = tonumber(options and options[key])
    if value == nil then
        error("missing resolved breathing option: " .. tostring(key), 3)
    end
    return value
end

local function smoothstep01(value)
    local t = Utils.clamp(tonumber(value) or 0, 0, 1)
    return t * t * (3 - (2 * t))
end

local function resolveEffort(input)
    local metabolicRate = math.max(0, tonumber(input.metabolicRate) or METABOLIC_REST)
    local activityLabel = tostring(input.activityLabel or "idle")
    local movementDemand = METABOLIC_REST
    if activityLabel == "sprint" then
        movementDemand = METABOLIC_MAX
    elseif activityLabel == "run" then
        movementDemand = METABOLIC_RUN
    elseif activityLabel == "walk" then
        movementDemand = METABOLIC_WALK
    end
    local metabolicDemand = math.max(metabolicRate, movementDemand)
    local metabolicNorm = Utils.clamp(
        (metabolicDemand - METABOLIC_REST) / (METABOLIC_MAX - METABOLIC_REST),
        0,
        1
    )
    return metabolicNorm, metabolicDemand, metabolicRate
end

function BreathingModel.calculate(options, input)
    if type(options) ~= "table" then
        error("resolved options table required", 2)
    end
    input = input or {}
    local airflowResistance = math.max(0, tonumber(input.airflowResistance) or 0)
    local sealedRestriction = Utils.clamp(tonumber(input.sealedRestriction) or 0, 0, 1)
    local metabolicNorm, metabolicDemand, metabolicRate = resolveEffort(input)
    if airflowResistance <= 0 then
        return {
            contribution = 0,
            airflowResistance = 0,
            sealedRestriction = sealedRestriction,
            metabolicRate = metabolicRate,
            metabolicDemand = metabolicDemand,
            metabolicNorm = metabolicNorm,
            effortRamp = 0,
            dynamicLoad = 0,
            sealedDynamicLoad = 0,
        }
    end

    local effortOnset = Utils.clamp(requiredNumber(options, "BreathingEffortOnset"), 0, 0.95)
    local effortRamp = 0
    if metabolicNorm > effortOnset then
        effortRamp = smoothstep01((metabolicNorm - effortOnset) / math.max(0.05, 1 - effortOnset))
    end

    local dynamicLoad = airflowResistance
        * requiredNumber(options, "BreathingDynamicLoadWeight")
        * effortRamp
    local sealedDynamicLoad = airflowResistance
        * requiredNumber(options, "BreathingSealedDynamicLoadWeight")
        * effortRamp
        * sealedRestriction

    return {
        contribution = dynamicLoad + sealedDynamicLoad,
        airflowResistance = airflowResistance,
        sealedRestriction = sealedRestriction,
        metabolicRate = metabolicRate,
        metabolicDemand = metabolicDemand,
        metabolicNorm = metabolicNorm,
        effortRamp = effortRamp,
        dynamicLoad = dynamicLoad,
        sealedDynamicLoad = sealedDynamicLoad,
    }
end

return BreathingModel
