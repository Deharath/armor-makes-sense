local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")
local root = os.getenv("AMS_ROOT") or "."

ArmorMakesSense = {}
BodyLocations = nil
ItemBodyLocation = nil
ResourceLocation = nil

local SlotCompat = dofile(root .. "/common/media/lua/shared/ArmorMakesSense_SlotCompat.lua")
Support.assertFalse(ArmorMakesSense._slotCompatLoaded, "missing slot APIs do not mark initialization complete")

local group = {
    setExclusive = function() end,
    setHideModel = function() end,
    moveLocationToIndex = function() end,
    indexOf = function() return 0 end,
    getOrCreateLocation = function() end,
}
BodyLocations = { getGroup = function() return group end }
ResourceLocation = { of = function(id) return id end }
ItemBodyLocation = setmetatable({
    register = function() end,
    get = function(id) return id end,
}, {
    __index = function(_, key) return key end,
})

Support.assertTrue(SlotCompat.initialize(), "slot initialization retries after APIs become available")
Support.assertTrue(ArmorMakesSense._slotCompatLoaded, "successful slot initialization marks completion")
Support.assertTrue(SlotCompat.initialize(), "completed slot initialization is idempotent")

print("ams slot compatibility lifecycle checks passed")
