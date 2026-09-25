ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.SleepModel = ArmorMakesSense.SleepModel or {}

local Compat = require "ArmorMakesSense_Compat"
local Stats = require "ArmorMakesSense_StatsShared"
local Utils = require "ArmorMakesSense_UtilsShared"
local SleepModel = ArmorMakesSense.SleepModel

-- Rigid armor slows fatigue recovery while asleep. AMS observes vanilla's
-- recovery between authoritative ticks and gives back a share of it; sleep
-- planning, wake time and bed choice stay entirely vanilla.

function SleepModel.penaltyFraction(options, rigidKg)
    if not Utils.toBoolean(options and options.EnableSleepPenaltyModel) then
        return 0
    end
    local rigid = math.max(0, tonumber(rigidKg) or 0)
    if rigid <= 0 then
        return 0
    end
    local maxPenalty = Utils.clamp(tonumber(options.SleepPenaltyMax) or 0.5, 0, 0.95)
    return math.min(maxPenalty, rigid * math.max(0, tonumber(options.SleepPenaltyPerRigidKg) or 0.025))
end

-- When CMS coordinates fatigue it charges the AMS fraction itself through
-- the computeSleepPenaltyContribution callback.
function SleepModel.cmsOwnsFatigue()
    return type(Compat) == "table"
        and type(Compat.hasCapability) == "function"
        and Compat:hasCapability("CaffeineMakesSense", "fatigue_coordinator") == true
end

function SleepModel.step(player, state, options, profile)
    local asleep = Utils.toBoolean(Utils.safeMethod(player, "isAsleep"))
    local fatigue = Stats.getFatigue(player)
    local fraction = asleep and SleepModel.penaltyFraction(options, profile and profile.rigidKg) or 0
    local extraFatigue = 0
    local previous = tonumber(state.lastFatigueObserved)

    if asleep and state.sleepWasAsleep == true and fatigue ~= nil and previous ~= nil
        and fraction > 0 and not SleepModel.cmsOwnsFatigue() then
        local recovered = previous - fatigue
        if recovered > 0 then
            extraFatigue = recovered * fraction
            fatigue = Utils.clamp(fatigue + extraFatigue, 0, 1)
            Stats.setFatigue(player, fatigue)
        end
    end

    state.lastFatigueObserved = fatigue
    state.sleepWasAsleep = asleep
    state.sleepPenaltyFraction = fraction
    state.lastSleepExtraFatigue = extraFatigue
    return {
        sleeping = asleep,
        penaltyFraction = fraction,
        extraFatigue = extraFatigue,
    }
end

return SleepModel
