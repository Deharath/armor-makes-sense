ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.EnduranceModel = ArmorMakesSense.EnduranceModel or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local EnduranceModel = ArmorMakesSense.EnduranceModel

local function requiredNumber(options, key)
    local value = tonumber(options and options[key])
    if value == nil then
        error("missing resolved endurance option: " .. tostring(key), 3)
    end
    return value
end

local function calculateAmsRegenScale(options, input)
    if input.previous == nil or input.loadNorm <= 0 or input.naturalDelta <= 0 then
        return 1
    end
    local postureScale = input.isIdle and input.isSitting and 0.90 or 1.0
    local topoffScale = Utils.clamp(0.55 + ((1 - input.current) * 0.45), 0.55, 1)
    local regenActivityScale = 1
    if input.activityLabel == "walk" then
        regenActivityScale = input.current <= 0.58 and 0.70 or 0.40
    end
    local penalty = Utils.clamp(
        requiredNumber(options, "EnduranceRegenPenalty")
            * (0.45 + (0.35 * input.loadNorm))
            * postureScale
            * topoffScale
            * regenActivityScale
            * input.activityLoadScale,
        0,
        0.85
    )
    return 1 - penalty
end

local function activityDrainScale(input)
    if input.activityLabel == "walk" then
        local stressed = input.current <= 0.60 or input.enduranceMoodle >= 2
        if stressed and input.loadNorm >= 2.0 then
            return 0.06
        end
        return 0
    end
    if input.activityLabel == "idle" then
        return 0
    end
    if input.activityLabel == "run" then
        return 0.335
    end
    if input.activityLabel == "sprint" then
        return 0.58
    end
    return 0
end

function EnduranceModel.calculate(options, rawInput)
    if type(options) ~= "table" then
        error("resolved options table required", 2)
    end
    rawInput = rawInput or {}
    local input = {
        previous = tonumber(rawInput.previous),
        current = Utils.clamp(tonumber(rawInput.current) or 0, 0, 1),
        naturalDelta = tonumber(rawInput.naturalDelta) or 0,
        loadNorm = Utils.clamp(tonumber(rawInput.loadNorm) or 0, 0, 2.8),
        activityLoadScale = math.max(0, tonumber(rawInput.activityLoadScale) or 1),
        activityLabel = tostring(rawInput.activityLabel or "idle"),
        isIdle = tostring(rawInput.activityLabel or "idle") == "idle",
        isSitting = rawInput.isSitting == true,
        enduranceMoodle = tonumber(rawInput.enduranceMoodle) or -1,
        dtMinutes = math.max(0, tonumber(rawInput.dtMinutes) or 0),
        nmsRegenScale = Utils.clamp(tonumber(rawInput.nmsRegenScale) or 1, 0, 1),
        nmsDrain = math.max(0, tonumber(rawInput.nmsDrain) or 0),
    }
    local canApply = input.dtMinutes > 0
    local amsRegenScale = canApply and calculateAmsRegenScale(options, input) or 1
    local composedRegenScale = amsRegenScale * input.nmsRegenScale
    local controlled = input.current

    if canApply and input.previous ~= nil and input.naturalDelta > 0
        and (input.loadNorm > 0 or input.nmsRegenScale < 0.9999) then
        controlled = input.previous + (input.naturalDelta * composedRegenScale)
    end

    local amsDrain = 0
    local drainScale = activityDrainScale(input)
    if canApply and input.loadNorm > 0 and drainScale > 0 then
        local drainPerMinute = requiredNumber(options, "BaseEnduranceDrainPerMinute")
            * (1 + (1.6 * input.loadNorm))
            * drainScale
            * input.activityLoadScale
        amsDrain = drainPerMinute * input.dtMinutes
        controlled = controlled - amsDrain
    end
    if canApply then
        controlled = controlled - input.nmsDrain
    end

    if canApply and input.previous ~= nil and input.isIdle and input.naturalDelta > 0
        and input.nmsDrain <= 0 then
        controlled = math.max(input.previous, math.min(input.current, controlled))
    end
    controlled = Utils.clamp(controlled, 0, 1)

    return {
        canApply = canApply,
        controlledEndurance = controlled,
        enduranceDelta = controlled - input.current,
        amsRegenScale = amsRegenScale,
        nmsRegenScale = input.nmsRegenScale,
        composedRegenScale = composedRegenScale,
        amsDrainApplied = amsDrain,
        nmsDrainApplied = canApply and input.nmsDrain or 0,
        totalDrainApplied = amsDrain + (canApply and input.nmsDrain or 0),
        activityDrainScale = drainScale,
    }
end

return EnduranceModel
