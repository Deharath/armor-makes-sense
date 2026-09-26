ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.EnduranceModel = ArmorMakesSense.EnduranceModel or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local EnduranceModel = ArmorMakesSense.EnduranceModel

-- AMS never invents its own endurance curve. It observes vanilla's change
-- since the previous tick and scales it: recovery is slowed, drain is
-- amplified. Sitting stays free of physical cost; only heat touches it.
--
-- Drain is amplified by one load-proportional factor whatever the pace:
-- vanilla already drains faster paces harder, and the extra metabolic cost
-- of a carried load is close to a fixed share of the movement cost
-- (Pandolf). This keeps drain independent of the activity sampled at the
-- tick, which can differ from what the player did during the minute.
--
-- The load share grows with the square of the load too, so single pieces
-- stay cheap and full kits cost disproportionately more (limb loads and a
-- rigid torso compound, as in Pandolf's load term and armour studies).
-- A minute with melee attacks and no running pays only CombatDrainShare of
-- it: a chest plate barely changes the cost of a standing swing, and arm
-- gear already costs through strain and swing speed.

local function requiredNumber(options, key)
    local value = tonumber(options and options[key])
    if value == nil then
        error("missing resolved endurance option: " .. tostring(key), 3)
    end
    return value
end

function EnduranceModel.scales(options, input)
    if type(options) ~= "table" then
        error("resolved options table required", 2)
    end
    input = input or {}
    local loadFraction = math.max(0, tonumber(input.loadFraction) or 0)
    local heat = Utils.clamp(tonumber(input.heat) or 0, 0, 1)
    local breathing = Utils.clamp(tonumber(input.breathing) or 0, 0, 1)
    local activityLabel = tostring(input.activityLabel or "idle")
    local resting = input.resting == true
    local fighting = input.fighting == true and activityLabel ~= "run" and activityLabel ~= "sprint"

    local physicalRegen = 1
    if activityLabel == "walk" and not resting then
        physicalRegen = math.max(
            requiredNumber(options, "WalkRegenFloor"),
            1 - (requiredNumber(options, "WalkRegenLoadWeight") * loadFraction)
        )
    elseif not resting then
        physicalRegen = math.max(0, 1 - (requiredNumber(options, "StandRegenLoadWeight") * loadFraction * loadFraction))
    end
    local thermalRegen = 1 - (requiredNumber(options, "ThermalRegenPenaltyMax") * heat)
    local physicalDrain = (requiredNumber(options, "DrainLoadWeight") * loadFraction)
        + (requiredNumber(options, "DrainLoadCurveWeight") * loadFraction * loadFraction)
    if fighting then
        physicalDrain = physicalDrain * requiredNumber(options, "CombatDrainShare")
    end
    local thermalDrain = requiredNumber(options, "ThermalDrainWeight") * heat
    local breathingDrain = requiredNumber(options, "BreathingDrainWeight") * breathing

    return {
        regenScale = math.max(0, physicalRegen) * thermalRegen,
        walkDrainFraction = math.max(0, -physicalRegen),
        drainScale = 1 + physicalDrain + thermalDrain + breathingDrain,
        physicalRegen = physicalRegen,
        thermalRegen = thermalRegen,
        physicalDrain = physicalDrain,
        thermalDrain = thermalDrain,
        breathingDrain = breathingDrain,
        fighting = fighting,
    }
end

function EnduranceModel.calculate(options, rawInput)
    rawInput = rawInput or {}
    local scales = EnduranceModel.scales(options, rawInput)
    local current = Utils.clamp(tonumber(rawInput.current) or 0, 0, 1)
    local previous = tonumber(rawInput.previous)
    local nmsRegenScale = Utils.clamp(tonumber(rawInput.nmsRegenScale) or 1, 0, 1)
    local nmsDrain = math.max(0, tonumber(rawInput.nmsDrain) or 0)
    local result = {
        canApply = previous ~= nil,
        controlledEndurance = current,
        naturalDelta = 0,
        amsDelta = 0,
        regenScale = scales.regenScale,
        composedRegenScale = scales.regenScale * nmsRegenScale,
        drainScale = scales.drainScale,
        nmsRegenScale = nmsRegenScale,
        nmsDrainApplied = 0,
        scales = scales,
    }
    if previous == nil then
        return result
    end

    local naturalDelta = current - previous
    local controlled = current
    if naturalDelta > 0 then
        controlled = previous
            + (naturalDelta * scales.regenScale * nmsRegenScale)
            - (naturalDelta * scales.walkDrainFraction)
    elseif naturalDelta < 0 then
        controlled = previous + (naturalDelta * scales.drainScale)
    end
    controlled = Utils.clamp(controlled - nmsDrain, 0, 1)

    result.naturalDelta = naturalDelta
    result.controlledEndurance = controlled
    result.amsDelta = controlled - current
    result.nmsDrainApplied = nmsDrain
    return result
end

return EnduranceModel
