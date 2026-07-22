ArmorMakesSense = ArmorMakesSense or {}

local Compat = require "ArmorMakesSense_Compat"
local Utils = require "ArmorMakesSense_UtilsShared"

local SleepOwnership = {}
local CMS_PROVIDER = "CaffeineMakesSense"

local function cmsHasCapability(capability)
    return type(Compat) == "table"
        and type(Compat.hasCapability) == "function"
        and Compat:hasCapability(CMS_PROVIDER, capability)
end

function SleepOwnership.cmsOwnsPlanner()
    return cmsHasCapability("sleep_planner_coordinator")
end

function SleepOwnership.cmsOwnsFatigue()
    return cmsHasCapability("fatigue_coordinator")
end

function SleepOwnership.cmsOwnsWakeAdjustment()
    return cmsHasCapability("sleep_wake_adjustment_coordinator")
end

function SleepOwnership.amsOwnsFatigue(options)
    return Utils.toBoolean(options and options.EnableSleepPenaltyModel)
        and not SleepOwnership.cmsOwnsFatigue()
end

ArmorMakesSense.SleepOwnership = SleepOwnership

return SleepOwnership
