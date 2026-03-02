ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.ContextRefs = Core.ContextRefs or {}

local Refs = Core.ContextRefs
local C = {}

-- -----------------------------------------------------------------------------
-- Delegating references into context-bound modules
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

local function delegate(moduleName, methodName, default)
    return function(...)
        local mod = ctx(moduleName)
        if not mod or type(mod[methodName]) ~= "function" then
            return default
        end
        return mod[methodName](...)
    end
end

function Refs.setContext(context)
    C = context or {}
end

function Refs.computeArmorProfile(player)
    -- Kept explicit: default must allocate a fresh table on every fallback.
    local loadModel = ctx("LoadModel")
    if not loadModel or type(loadModel.computeArmorProfile) ~= "function" then
        return {
            physicalLoad = 0,
            thermalLoad = 0,
            breathingLoad = 0,
            armorCount = 0,
            combinedLoad = 0,
        }
    end
    return loadModel.computeArmorProfile(player)
end

Refs.getHeatFactor = delegate("Environment", "getHeatFactor", 1.0)

Refs.wetnessToFactor = delegate("Environment", "wetnessToFactor", 1.0)

Refs.getWetFactor = delegate("Environment", "getWetFactor", 1.0)

function Refs.getActivityFactor(player, options)
    -- Kept explicit: fallback computes a clamped option-derived value.
    local env = ctx("Environment")
    if not env or type(env.getActivityFactor) ~= "function" then
        return ctx("clamp")(tonumber(options and options.ActivityIdle) or 1.0, 0.2, 1.8)
    end
    return env.getActivityFactor(player, options)
end

Refs.getActivityLabel = delegate("Environment", "getActivityLabel", "idle")

Refs.getPostureLabel = delegate("Environment", "getPostureLabel", "stand")

Refs.getBodyTemperature = delegate("Stats", "getBodyTemperature", nil)

Refs.setBodyTemperature = delegate("Stats", "setBodyTemperature", nil)

Refs.getEndurance = delegate("Stats", "getEndurance", nil)

Refs.setEndurance = delegate("Stats", "setEndurance", nil)

Refs.getFatigue = delegate("Stats", "getFatigue", nil)

Refs.setFatigue = delegate("Stats", "setFatigue", nil)

Refs.getThirst = delegate("Stats", "getThirst", nil)

Refs.setThirst = delegate("Stats", "setThirst", nil)

Refs.getDiscomfort = delegate("Stats", "getDiscomfort", nil)

Refs.setDiscomfort = delegate("Stats", "setDiscomfort", nil)

Refs.getWetness = delegate("Stats", "getWetness", nil)

Refs.setWetness = delegate("Stats", "setWetness", nil)

Refs.resetMuscleStrain = delegate("Stats", "resetMuscleStrain", 0)

Refs.resetCharacterToEquilibrium = delegate("Stats", "resetCharacterToEquilibrium", 0)

Refs.updateRecoveryTrace = delegate("Physiology", "updateRecoveryTrace", nil)

return Refs
