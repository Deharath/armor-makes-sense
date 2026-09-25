ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.BreathingModel = ArmorMakesSense.BreathingModel or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local BreathingModel = ArmorMakesSense.BreathingModel
local METABOLIC_REST = 1.5
local METABOLIC_WALK = 3.1
local METABOLIC_RUN = 6.9
local METABOLIC_MAX = 9.5
-- Airflow resistance of a filtered, sealed gas mask (BreathingClassifier).
local FULL_RESTRICTION = 3.75

local function smoothstep01(value)
    local t = Utils.clamp(tonumber(value) or 0, 0, 1)
    return t * t * (3 - (2 * t))
end

local function movementDemand(activityLabel)
    if activityLabel == "sprint" then
        return METABOLIC_MAX
    end
    if activityLabel == "run" then
        return METABOLIC_RUN
    end
    if activityLabel == "walk" then
        return METABOLIC_WALK
    end
    return METABOLIC_REST
end

-- Restriction severity of the worn respiratory gear, 0..1.
function BreathingModel.severity(airflowResistance, sealedRestriction)
    local airflow = math.max(0, tonumber(airflowResistance) or 0)
    local sealed = Utils.clamp(tonumber(sealedRestriction) or 0, 0, 1)
    return Utils.clamp(airflow / FULL_RESTRICTION, 0, 1) * (0.75 + (0.25 * sealed))
end

function BreathingModel.calculate(options, input)
    if type(options) ~= "table" then
        error("resolved options table required", 2)
    end
    input = input or {}
    local severity = BreathingModel.severity(input.airflowResistance, input.sealedRestriction)
    local metabolicRate = math.max(0, tonumber(input.metabolicRate) or METABOLIC_REST)
    local demand = math.max(metabolicRate, movementDemand(tostring(input.activityLabel or "idle")))
    local effortNorm = Utils.clamp((demand - METABOLIC_REST) / (METABOLIC_MAX - METABOLIC_REST), 0, 1)
    local onset = Utils.clamp(tonumber(options.BreathingEffortOnset) or 0.2, 0, 0.95)
    local effortRamp = 0
    if effortNorm > onset then
        effortRamp = smoothstep01((effortNorm - onset) / math.max(0.05, 1 - onset))
    end
    local enabled = Utils.toBoolean(options.EnableBreathingModel)
    return {
        severity = severity,
        effortRamp = effortRamp,
        pressure = enabled and (severity * effortRamp) or 0,
        metabolicRate = metabolicRate,
    }
end

return BreathingModel
