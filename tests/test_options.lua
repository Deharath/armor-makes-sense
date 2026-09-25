local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

local Options = require "ArmorMakesSense_Options"
local Utils = require "ArmorMakesSense_UtilsShared"

SandboxVars = nil
local defaults = Options.get()
Support.assertEqual(defaults.EnableThermalModel, true, "default boolean option")
Support.assertClose(defaults.PhysicalLoadScale, 1.0, 1e-9, "default numeric option")
Support.assertEqual(defaults.EnableBreathingModel, true, "breathing toggle default")

SandboxVars = {
    ArmorMakesSense = {
        EnableThermalModel = "false",
        PhysicalLoadScale = "0.6",
        MaxStepMinutes = "invalid",
        UnknownOption = 99,
    },
}
local overridden = Options.get()
Support.assertEqual(overridden.EnableThermalModel, false, "boolean override")
Support.assertClose(overridden.PhysicalLoadScale, 0.6, 1e-9, "numeric override")
Support.assertEqual(overridden.MaxStepMinutes, defaults.MaxStepMinutes, "invalid numeric keeps default")
Support.assertEqual(overridden.UnknownOption, nil, "unknown option ignored")

overridden.PhysicalLoadScale = 99
Support.assertClose(Options.get().PhysicalLoadScale, 0.6, 1e-9, "option snapshots are independent")

getTimestampMs = function() return 12345 end
getTimestamp = function() return 99 end
Support.assertEqual(Utils.getWallClockSeconds(), 12, "millisecond clock precedence")

getTimestampMs = nil
Support.assertEqual(Utils.getWallClockSeconds(), 99, "second clock fallback")

getTimestamp = nil
getGameTime = function()
    return { getWorldAgeHours = function() return 2 end }
end
Support.assertEqual(Utils.getWallClockSeconds(), 7200, "world-time final fallback")

local unavailableMethodTarget = setmetatable({}, {
    __index = function()
        error("method lookup unavailable")
    end,
})
Support.assertEqual(Utils.safeMethod(unavailableMethodTarget, "missing"), nil, "safe method lookup failure")

print("ams shared options and clock checks passed")
