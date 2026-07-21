local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    Testing = {
        BenchUtils = {
            clamp = Support.clamp,
            safeMethod = Support.safeMethod,
            toBoolArg = function(value) return value == true end,
        },
        BenchCatalog = {},
    },
}

local Env = dofile(
    (os.getenv("AMS_ROOT") or ".")
        .. "/common/media/lua/client/testing/ArmorMakesSense_BenchRunnerEnv.lua"
)

local liveCancelCount = 0
local staleCancelCount = 0
local resetCount = 0
local liveBehavior = {
    cancel = function() liveCancelCount = liveCancelCount + 1 end,
    reset = function() resetCount = resetCount + 1 end,
}
local staleBehavior = {
    cancel = function() staleCancelCount = staleCancelCount + 1 end,
}
local player = {
    x = 0,
    y = 0,
    z = 0,
    getPathFindBehavior2 = function() return liveBehavior end,
    setPath2 = function(self, value) self.path = value end,
    teleportTo = function(self, x, y, z)
        self.x = x
        self.y = y
        self.z = z
        self.teleportCount = (self.teleportCount or 0) + 1
    end,
    getX = function(self) return self.x end,
    getY = function(self) return self.y end,
    getZ = function(self) return self.z end,
}

Support.assertTrue(Env.snapPlayerToCoords(player, 10, 20, 0), "coordinate reset succeeds")
Support.assertEqual(player.teleportCount, 1, "coordinate reset uses the canonical vanilla teleport")
Support.assertEqual(liveCancelCount, 1, "coordinate reset cancels the live path behavior")
Support.assertEqual(resetCount, 0, "coordinate reset does not reactivate path state through reset")

Env.clearNativeMovementState(player, { behavior = staleBehavior })
Support.assertEqual(liveCancelCount, 2, "movement cleanup cancels the current player behavior")
Support.assertEqual(staleCancelCount, 1, "movement cleanup cancels a retained driver behavior")
Support.assertEqual(resetCount, 0, "movement cleanup follows vanilla cancellation semantics")

local forbiddenClimateLayerCalls = 0
local function makeClimateChannel(enabled, value)
    local channel = {
        enabled = enabled,
        value = value,
    }
    function channel:isEnableAdmin() return self.enabled end
    function channel:getAdminValue() return self.value end
    function channel:setEnableAdmin(nextEnabled) self.enabled = nextEnabled end
    function channel:setAdminValue(nextValue) self.value = nextValue end
    function channel:setEnableOverride() forbiddenClimateLayerCalls = forbiddenClimateLayerCalls + 1 end
    function channel:setOverride() forbiddenClimateLayerCalls = forbiddenClimateLayerCalls + 1 end
    function channel:setEnableModded() forbiddenClimateLayerCalls = forbiddenClimateLayerCalls + 1 end
    function channel:setModdedValue() forbiddenClimateLayerCalls = forbiddenClimateLayerCalls + 1 end
    return channel
end

local temperatureChannel = makeClimateChannel(true, 18)
local snowChannel = makeClimateChannel(false, true)
local climateUpdateCount = 0
local climate = {
    getClimateFloat = function(_, id)
        if id == 1 then return temperatureChannel end
        return nil
    end,
    getClimateBool = function(_, id)
        if id == 2 then return snowChannel end
        return nil
    end,
    forceDayInfoUpdate = function() climateUpdateCount = climateUpdateCount + 1 end,
    update = function() climateUpdateCount = climateUpdateCount + 1 end,
}
ClimateManager = {
    FLOAT_TEMPERATURE = 1,
    BOOL_IS_SNOW = 2,
}
getClimateManager = function() return climate end

local weatherToken, weatherError = Env.applyWeatherOverrides({
    profile = "test",
    temperature = 33,
    is_snow = false,
})
Support.assertEqual(weatherError, nil, "weather override applies")
Support.assertTrue(weatherToken ~= nil, "weather override returns a restoration token")
Support.assertEqual(temperatureChannel.value, 33, "temperature uses the admin override value")
Support.assertTrue(temperatureChannel.enabled, "temperature admin override enabled")
Support.assertFalse(snowChannel.value, "snow uses the admin override value")
Support.assertTrue(snowChannel.enabled, "snow admin override enabled")
Support.assertEqual(forbiddenClimateLayerCalls, 0, "weather override does not mutate unrelated climate layers")

Env.clearWeatherOverrides(weatherToken)
Support.assertEqual(temperatureChannel.value, 18, "temperature admin value restored")
Support.assertTrue(temperatureChannel.enabled, "pre-existing temperature override restored")
Support.assertTrue(snowChannel.value, "snow admin value restored")
Support.assertFalse(snowChannel.enabled, "pre-existing snow override state restored")
Support.assertEqual(forbiddenClimateLayerCalls, 0, "weather cleanup leaves unrelated climate layers untouched")
Support.assertTrue(climateUpdateCount >= 4, "climate refreshed after apply and restore")

local failedWeatherToken, failedWeatherError = Env.applyWeatherOverrides({
    profile = "partial_failure",
    temperature = 30,
    wind_intensity = 0.5,
})
Support.assertEqual(failedWeatherToken, nil, "partial weather application fails closed")
Support.assertTrue(string.find(failedWeatherError, "float_wind_intensity", 1, true) ~= nil, "partial weather failure identifies the missing channel")
Support.assertEqual(temperatureChannel.value, 18, "partial weather failure rolls back earlier channel writes")
Support.assertTrue(temperatureChannel.enabled, "partial weather failure restores earlier channel state")

local clothingEvents = 0
triggerEvent = function(name, eventPlayer)
    if name == "OnClothingUpdated" and eventPlayer then
        clothingEvents = clothingEvents + 1
    end
end
local shirt = {}
local trousers = {}
local shirtLocation = { name = "Shirt" }
local trousersLocation = { name = "Pants" }
local restoredWorn = {}
local wornList = {
    size = function() return #restoredWorn end,
    get = function(_, index) return restoredWorn[index + 1] end,
}
local outfitPlayer = {
    clearWornItems = function() restoredWorn = {} end,
    setWornItem = function(_, location, item)
        restoredWorn[#restoredWorn + 1] = {
            getLocation = function() return location end,
            getItem = function() return item end,
        }
    end,
    getWornItems = function() return wornList end,
}
local outfit = {
    { item = shirt, locationObject = shirtLocation, fullType = "Base.Shirt", location = tostring(shirtLocation) },
    { item = trousers, locationObject = trousersLocation, fullType = "Base.Trousers", location = tostring(trousersLocation) },
}
Support.assertTrue(Env.restoreOutfit(outfitPlayer, outfit), "exact outfit restoration succeeds")
Support.assertEqual(restoredWorn[1]:getItem(), shirt, "restoration preserves first item identity")
Support.assertEqual(restoredWorn[2]:getItem(), trousers, "restoration preserves second item identity")
Support.assertEqual(clothingEvents, 1, "restoration emits vanilla clothing update event")
Support.assertFalse(Env.restoreOutfit(outfitPlayer, {
    { fullType = "Base.Shirt", location = "Shirt" },
}), "metadata-only outfit is rejected instead of approximated")

print("ams benchmark environment cleanup checks passed")
