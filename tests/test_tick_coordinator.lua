local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense.Core = ArmorMakesSense.Core or {}
ArmorMakesSense.Core.Tick = nil
local Tick = dofile((os.getenv("AMS_ROOT") or ".") .. "/common/media/lua/client/core/ArmorMakesSense_Tick.lua")
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local Stats = require "ArmorMakesSense_StatsShared"
local UI = require "core/ArmorMakesSense_UI"
local Utils = require "ArmorMakesSense_UtilsShared"

local player = {}
local state = {
    lastUpdateGameMinutes = 10,
    pendingCatchupMinutes = 0,
    lastEnduranceObserved = 0.8,
}
local calls = {}
local uiUpdates = 0
local optionReads = 0

ClientRuntime.ensureState = function(receivedPlayer)
    Support.assertEqual(receivedPlayer, player, "tick player state lookup")
    return state
end
ClientRuntime.runPlayerStartupChecks = function() return true end
ClientRuntime.log = function() end
Options.get = function()
    optionReads = optionReads + 1
    return { DtMaxMinutes = 3, DtCatchupMaxSlices = 10 }
end
UI.update = function()
    uiUpdates = uiUpdates + 1
end
Utils.getWorldAgeMinutes = function() return 11 end
Stats.getEndurance = function() return 0.8 end
LoadModel.computeWornProfile = function()
    return { physicalLoad = 10, driverCount = 2 }
end
Environment.resolveActivity = function() return { label = "run", factor = 1.0 } end
Environment.getPostureLabel = function() return "stand" end
Physiology.applySleepTransition = function(_, _, _, dtMinutes)
    calls[#calls + 1] = "sleep:" .. tostring(dtMinutes)
end
Physiology.applyEnduranceModel = function(_, _, _, dtMinutes)
    calls[#calls + 1] = "endurance:" .. tostring(dtMinutes)
end
local result = Tick.tickPlayer(player)
Support.assertEqual(result.committedSlices, 1, "tick delegates one slice")
Support.assertClose(result.committedMinutes, 1, 1e-9, "tick committed elapsed minute")
Support.assertClose(state.pendingCatchupMinutes, 0, 1e-9, "tick drains pending time")
Support.assertEqual(uiUpdates, 2, "tick preserves UI refresh points")
Support.assertEqual(
    table.concat(calls, "|"),
    "sleep:1|endurance:1",
    "tick shared advance call order"
)

calls = {}
Utils.getWorldAgeMinutes = function() return 12 end
Environment.resolveActivity = function() return { label = "idle", factor = 0.35 } end
Environment.getPostureLabel = function() return "sleep" end

local sleepResult = Tick.tickPlayer(player)
Support.assertEqual(sleepResult.committedSlices, 1, "sleep tick delegates one slice")
Support.assertClose(sleepResult.committedMinutes, 1, 1e-9, "sleep tick committed elapsed minute")
Support.assertEqual(table.concat(calls, "|"), "sleep:1", "sleep tick pauses endurance pipeline")

local uiUpdatesBeforeIdleFrame = uiUpdates
local optionReadsBeforeIdleFrame = optionReads
Tick.tickPlayer(player)
Support.assertEqual(uiUpdates, uiUpdatesBeforeIdleFrame, "zero-elapsed sleep frame skips UI work")
Support.assertEqual(optionReads, optionReadsBeforeIdleFrame, "zero-elapsed sleep frame skips option allocation")

print("ams singleplayer tick coordinator checks passed")
