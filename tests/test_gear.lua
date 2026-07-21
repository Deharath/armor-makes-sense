local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    Utils = {
        safeMethodFromDeps = function(deps, target, methodName, ...)
            return deps.safeMethod(target, methodName, ...)
        end,
    },
    Testing = {},
}

local Gear = dofile(
    (os.getenv("AMS_ROOT") or ".")
        .. "/common/media/lua/client/testing/ArmorMakesSense_Gear.lua"
)
local item = {
    getFullType = function() return "Base.Jacket" end,
}
local location = { name = "Jacket" }
local worn = {
    getItem = function() return item end,
    getLocation = function() return location end,
}
local wornItems = {
    size = function() return 1 end,
    get = function() return worn end,
}
local player = {
    getWornItems = function() return wornItems end,
}
local snapshot = Gear.snapshotWornItems(player, { safeMethod = Support.safeMethod })
Support.assertEqual(#snapshot, 1, "worn snapshot count")
Support.assertEqual(snapshot[1].item, item, "worn snapshot preserves item identity")
Support.assertEqual(snapshot[1].locationObject, location, "worn snapshot preserves body-location identity")
Support.assertEqual(snapshot[1].fullType, "Base.Jacket", "worn snapshot keeps diagnostic item type")
Support.assertEqual(snapshot[1].location, tostring(location), "worn snapshot keeps diagnostic location text")

print("ams testing gear snapshot checks passed")
