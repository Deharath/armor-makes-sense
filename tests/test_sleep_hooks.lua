local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    MP = { NET_MODULE = "ArmorMakesSenseRuntime", SLEEP_BED_TYPE_COMMAND = "sleep_bed_type" },
}
local plannerPenalty = 0.25
local compat = {
    getCallback = function(_, provider, callback)
        if provider == "ArmorMakesSense" and callback == "estimateSleepPlannerPenalty" then
            return function() return { penaltyFraction = plannerPenalty } end
        end
        return nil
    end,
    computePlannerExtraHours = function(baseHours) return baseHours end,
    combinePenaltyFractions = function(penalties) return penalties[1] or 0 end,
    hasCapability = function() return false end,
}
ArmorMakesSense.Compat = compat

package.loaded["ArmorMakesSense_MPCompat"] = true
package.loaded["ArmorMakesSense_Compat"] = compat
package.loaded["ArmorMakesSense_SleepOwnership"] = nil
package.loaded["ISUI/ISSleepDialog"] = true
package.loaded["ISUI/ISWorldObjectContextMenu"] = true

local asleep = false
local wakeHour = 8
local wakeWrites = 0
local originalCalls = 0
local sleepingEventHours = nil
local sleepingEventCalls = 0
local vanillaSleepHours = 2
local player = {
    isAsleep = function() return asleep end,
    getForceWakeUpTime = function() return wakeHour end,
    setForceWakeUpTime = function(_, value)
        wakeHour = value
        wakeWrites = wakeWrites + 1
    end,
    getBedType = function() return "averageBed" end,
}

ISSleepDialog = nil
ISWorldObjectContextMenu = {
    onSleepWalkToComplete = function()
        originalCalls = originalCalls + 1
        asleep = true
        player:setForceWakeUpTime((6 + vanillaSleepHours) % 24)
        if not (isClient() and getServerOptions():getBoolean("SleepAllowed")) then
            getSleepingEvent():setPlayerFallAsleep(player, vanillaSleepHours)
        end
    end,
}
getSpecificPlayer = function() return player end
GameTime = { getInstance = function() return { getTimeOfDay = function() return 6 end } end }
getSleepingEvent = function()
    return {
        setPlayerFallAsleep = function(_, _, hours)
            sleepingEventHours = hours
            sleepingEventCalls = sleepingEventCalls + 1
        end,
    }
end
isClient = function() return false end
getServerOptions = function()
    return { getBoolean = function() return false end }
end

package.loaded["ArmorMakesSense_SleepHooks"] = nil
local SleepHooks = require "ArmorMakesSense_SleepHooks"
Support.assertEqual(SleepHooks.wrapSleepPlanning(), nil, "partial sleep hook installation remains retryable")
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")

Support.assertEqual(originalCalls, 1, "vanilla sleep workflow called exactly once")
Support.assertClose(wakeHour, 10, 1e-9, "AMS adjusts only vanilla wake duration")
Support.assertEqual(wakeWrites, 2, "penalty extends vanilla wake time once")
Support.assertClose(sleepingEventHours, 2, 1e-9, "vanilla sleeping event keeps its original duration")
Support.assertEqual(sleepingEventCalls, 1, "AMS never reinitializes vanilla sleeping-event data")

plannerPenalty = 0
asleep = false
wakeHour = 8
wakeWrites = 0
sleepingEventHours = nil
sleepingEventCalls = 0
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")
Support.assertClose(wakeHour, 8, 1e-9, "disabled penalty preserves vanilla wake time")
Support.assertEqual(wakeWrites, 1, "disabled penalty performs no second wake-time write")
Support.assertClose(sleepingEventHours, 2, 1e-9, "disabled penalty preserves vanilla sleeping event")
Support.assertEqual(sleepingEventCalls, 1, "disabled penalty never reinitializes sleep")

plannerPenalty = 0.25
asleep = false
wakeHour = 8
wakeWrites = 0
sleepingEventHours = nil
sleepingEventCalls = 0
isClient = function() return true end
getServerOptions = function()
    return { getBoolean = function(_, option) return option == "SleepAllowed" end }
end
local sentSleepCommand = nil
sendClientCommand = function(commandPlayer, module, command, args)
    sentSleepCommand = { player = commandPlayer, module = module, command = command, args = args }
end
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")
Support.assertClose(wakeHour, 10, 1e-9, "MP sleep duration still adjusts")
Support.assertEqual(sleepingEventHours, nil, "MP server sleep flow skips local sleeping-event setup")
Support.assertEqual(sleepingEventCalls, 0, "AMS does not create a client sleeping event in MP")
Support.assertEqual(sentSleepCommand.command, "sleep_bed_type", "MP sends narrow sleep context command")
Support.assertEqual(sentSleepCommand.player, player, "MP addresses sleep context to the sleeping player")
Support.assertEqual(sentSleepCommand.args.bed_type, "averageBed", "MP sends bed type")
local sleepArgCount = 0
for _ in pairs(sentSleepCommand.args) do
    sleepArgCount = sleepArgCount + 1
end
Support.assertEqual(sleepArgCount, 1, "MP sleep context contains no unused metadata")

plannerPenalty = 0
asleep = false
wakeWrites = 0
sentSleepCommand = nil
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")
Support.assertEqual(sentSleepCommand, nil, "disabled MP sleep model sends no AMS bed context")
Support.assertEqual(wakeWrites, 1, "disabled MP sleep model leaves vanilla wake planning untouched")

plannerPenalty = 0.25
isClient = function() return false end
vanillaSleepHours = 15
asleep = false
wakeWrites = 0
sleepingEventHours = nil
sleepingEventCalls = 0
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")
Support.assertClose(wakeHour, 22, 1e-9, "adjusted duration respects vanilla sixteen-hour wake ceiling")
Support.assertClose(sleepingEventHours, 15, 1e-9, "wake ceiling does not reinitialize the sleeping event")

plannerPenalty = 0.25
isClient = function() return true end
vanillaSleepHours = 0
asleep = false
wakeHour = 8
wakeWrites = 0
sentSleepCommand = nil
ISWorldObjectContextMenu.onSleepWalkToComplete(0, "bed")
Support.assertClose(wakeHour, 12, 1e-9, "zero-hour vanilla schedule is repaired before sleep can instantly end")
Support.assertEqual(wakeWrites, 2, "invalid vanilla schedule receives one corrective wake-time write")

plannerPenalty = 0.25
isClient = function() return true end
sentSleepCommand = nil
local dialogOptionCount = 0
getText = function(_, hours) return tostring(hours or "") end
ISSleepDialog = {
    initialise = function(self)
        self.spinBox = {
            selected = 2,
            addOption = function()
                dialogOptionCount = dialogOptionCount + 1
            end,
        }
    end,
    onClick = function(self, button)
        if button.internal == "YES" then
            asleep = true
        end
    end,
}

Support.assertTrue(SleepHooks.wrapSleepPlanning(), "dialog hook installs when vanilla class becomes available")
local dialog = { player = player }
ISSleepDialog.initialise(dialog)
Support.assertEqual(dialog.spinBox.selected, 4, "dialog planner extends selected sleep duration")
Support.assertEqual(dialogOptionCount, 2, "dialog planner adds extended hour choices")
ISSleepDialog.onClick(dialog, { internal = "YES" })
Support.assertEqual(sentSleepCommand.command, "sleep_bed_type", "dialog sleep sends bed context")
Support.assertEqual(sentSleepCommand.player, player, "dialog sleep addresses the correct player")
Support.assertEqual(sentSleepCommand.args.bed_type, "averageBed", "dialog sleep sends bed type")

print("ams narrow sleep hook checks passed")
