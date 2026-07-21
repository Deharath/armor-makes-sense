ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.SleepModel = ArmorMakesSense.SleepModel or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local SleepModel = ArmorMakesSense.SleepModel

local BED_MULTIPLIERS = {
    averageBedPillow = 1.05,
    goodBed = 1.10,
    goodBedPillow = 1.15,
    badBed = 0.90,
    badBedPillow = 0.95,
    floor = 0.60,
    floorPillow = 0.75,
}

function SleepModel.vanillaRecoveryRatePerHour(input)
    input = input or {}
    local fatigue = tonumber(input.fatigue)
    if fatigue == nil or fatigue <= 0 then
        return 0
    end
    local sleepMultiplier = input.insomniac and 0.5 or 1
    if input.nightOwl then
        sleepMultiplier = sleepMultiplier * 1.4
    end
    local traitMultiplier = input.needsLessSleep and 0.75 or (input.needsMoreSleep and 1.18 or 1)
    local bedMultiplier = BED_MULTIPLIERS[tostring(input.bedType or "")] or 1
    if fatigue <= 0.3 then
        return (0.3 / (7 * traitMultiplier)) * sleepMultiplier * bedMultiplier
    end
    return (0.7 / (5 * traitMultiplier)) * sleepMultiplier * bedMultiplier
end

function SleepModel.calculatePenalty(options, input)
    if type(options) ~= "table" then
        error("resolved options table required", 2)
    end
    input = input or {}
    local rate = tonumber(options.SleepRigidityFatigueRate)
    if rate == nil then
        error("missing resolved sleep option: SleepRigidityFatigueRate", 2)
    end
    local rigidityNorm = Utils.softNorm(tonumber(input.rigidityLoad) or 0, 80, 2)
    local fatigue = tonumber(input.fatigue)
    local vanillaRate = SleepModel.vanillaRecoveryRatePerHour(input)
    if rigidityNorm <= 0 or fatigue == nil or vanillaRate <= 0 then
        return { penaltyFraction = 0, vanillaRecoveryRatePerHour = vanillaRate, rigidityNorm = rigidityNorm }
    end
    local counteractRate = rigidityNorm * math.max(0, rate) * math.max(0.1, 1 - fatigue)
    return {
        penaltyFraction = Utils.clamp(counteractRate / vanillaRate, 0, 0.95),
        vanillaRecoveryRatePerHour = vanillaRate,
        rigidityNorm = rigidityNorm,
        counteractRatePerHour = counteractRate,
    }
end

function SleepModel.calculateAppliedPenalty(options, input)
    local result = SleepModel.calculatePenalty(options, input)
    local dtHours = math.max(0, tonumber(input and input.dtMinutes) or 0) / 60
    result.extraFatigue = result.vanillaRecoveryRatePerHour * dtHours * result.penaltyFraction
    return result
end

return SleepModel
