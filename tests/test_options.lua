local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

local Options = require "ArmorMakesSense_Options"
local Utils = require "ArmorMakesSense_UtilsShared"

SandboxVars = nil
local defaults = Options.get()
Support.assertEqual(defaults.EnableThermalModel, true, "default boolean option")
Support.assertClose(defaults.ActivityIdle, 0.35, 1e-9, "default numeric option")

SandboxVars = {
    ArmorMakesSense = {
        EnableThermalModel = "false",
        ActivityIdle = "0.6",
        DtMaxMinutes = "invalid",
        UnknownOption = 99,
    },
}
local overridden = Options.get()
Support.assertEqual(overridden.EnableThermalModel, false, "boolean override")
Support.assertClose(overridden.ActivityIdle, 0.6, 1e-9, "numeric override")
Support.assertEqual(overridden.DtMaxMinutes, defaults.DtMaxMinutes, "invalid numeric keeps default")
Support.assertEqual(overridden.UnknownOption, nil, "unknown option ignored")

overridden.ActivityIdle = 99
Support.assertClose(Options.get().ActivityIdle, 0.6, 1e-9, "option snapshots are independent")

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
