local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    MP = { NET_MODULE = "ArmorMakesSenseRuntime", SLEEP_BED_TYPE_COMMAND = "sleep_bed_type" },
}
local compat = {
    getCallback = function(_, provider, callback)
        if provider == "ArmorMakesSense" and callback == "estimateSleepPlannerPenalty" then
            return function() return { penaltyFraction = 0.25 } end
        end
        return nil
    end,
    computePlannerExtraHours = function(baseHours) return baseHours end,
    combinePenaltyFractions = function(penalties) return penalties[1] or 0 end,
    hasCapability = function() return false end,
}
ArmorMakesSense.Compat = compat

package.loaded["ArmorMakesSense_MPCompat"] = true
package.loaded["ISUI/ISSleepDialog"] = true
package.loaded["ISUI/ISWorldObjectContextMenu"] = true

local asleep = false
local wakeHour = 8
local originalCalls = 0
local sleepingEventHours = nil
local player = {
    isAsleep = function() return asleep end,
    getForceWakeUpTime = function() return wakeHour end,
    setForceWakeUpTime = function(_, value) wakeHour = value end,
    getBedType = function() return "averageBed" end,
}

ISSleepDialog = nil
ISWorldObjectContextMenu = {
    onSleepWalkToComplete = function()
        originalCalls = originalCalls + 1
        asleep = true
    end,
}
getSpecificPlayer = function() return player end
GameTime = { getInstance = function() return { getTimeOfDay = function() return 6 end } end }
getSleepingEvent = function()
    return {
        setPlayerFallAsleep = function(_, _, hours) sleepingEventHours = hours end,
    }
end
isClient = function() return false end
getServerOptions = function()
    return { getBoolean = function() return false end }
end

package.loaded["ArmorMakesSense_SleepHooks"] = nil
local SleepHooks = require "ArmorMakesSense_SleepHooks"
Support.assertTrue(SleepHooks.wrapSleepPlanning(), "sleep hook installation")
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")

Support.assertEqual(originalCalls, 1, "vanilla sleep workflow called exactly once")
Support.assertClose(wakeHour, 10, 1e-9, "AMS adjusts only vanilla wake duration")
Support.assertClose(sleepingEventHours, 4, 1e-9, "sleeping event receives adjusted duration")

asleep = false
wakeHour = 8
sleepingEventHours = nil
isClient = function() return true end
getServerOptions = function()
    return { getBoolean = function(_, option) return option == "SleepAllowed" end }
end
local sentSleepCommand = nil
sendClientCommand = function(module, command, args)
    sentSleepCommand = { module = module, command = command, args = args }
end
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")
Support.assertClose(wakeHour, 10, 1e-9, "MP sleep duration still adjusts")
Support.assertEqual(sleepingEventHours, nil, "MP server sleep flow skips local sleeping-event setup")
Support.assertEqual(sentSleepCommand.command, "sleep_bed_type", "MP sends narrow sleep context command")
Support.assertEqual(sentSleepCommand.args.bed_type, "averageBed", "MP sends bed type")
local sleepArgCount = 0
for _ in pairs(sentSleepCommand.args) do
    sleepArgCount = sleepArgCount + 1
end
Support.assertEqual(sleepArgCount, 1, "MP sleep context contains no unused metadata")

print("ams narrow sleep hook checks passed")
