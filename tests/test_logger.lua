local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local originalPrint = print
local originalDebug = isDebugEnabled
local originalActivatedMods = getActivatedMods
local output = {}

print = function(message)
    output[#output + 1] = tostring(message)
end
isDebugEnabled = function() return false end
getActivatedMods = nil

package.loaded["ArmorMakesSense_Logger"] = nil
local Logger = require "ArmorMakesSense_Logger"
Logger.info("loaded")
Logger.warn("degraded")
Logger.error("failed")
Logger.debug("hidden")
Support.assertEqual(#output, 3, "release logger suppresses debug output")
Support.assertEqual(output[1], "[ArmorMakesSense] loaded", "release info format")
Support.assertEqual(output[2], "[ArmorMakesSense][WARN] degraded", "release warning format")
Support.assertEqual(output[3], "[ArmorMakesSense][ERROR] failed", "release error format")

Logger.warnOnce("same_warning", "once")
Logger.warnOnce("same_warning", "twice")
Support.assertEqual(#output, 4, "warning once is emitted once")

getActivatedMods = function()
    return {
        contains = function(_, modId) return modId == "ArmorMakesSenseDev" end,
    }
end
Logger.debug("visible")
Support.assertEqual(output[5], "[ArmorMakesSense][DEBUG] visible", "dev mod enables debug output")

print = originalPrint
isDebugEnabled = originalDebug
getActivatedMods = originalActivatedMods

print("ams logger policy checks passed")
