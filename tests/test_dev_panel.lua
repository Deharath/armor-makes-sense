local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    Testing = {},
}

local player = {}
local multiplayer = false
local state = {
    uiRuntimeSnapshot = {
        activityLabel = "run",
        loadNorm = 0.4,
        effectiveLoad = 2.5,
        updatedMinute = 100,
        enduranceAppliedDelta = -0.01,
    },
}

local DevPanel = require "testing/ArmorMakesSense_DevPanel"
DevPanel.setContext({
    getLocalPlayer = function() return player end,
    isMultiplayer = function() return multiplayer end,
    getRuntimeState = function() return state end,
    getOptions = function() return {} end,
    getUiRuntimeSnapshot = function()
        return multiplayer and state.mpServerSnapshot or state.uiRuntimeSnapshot
    end,
    analyzeWornGear = function()
        return {
            profile = {
                physicalLoad = 3.2,
                driverCount = 1,
            },
            costDrivers = {
                { label = "Vest", physical = 3.2 },
            },
        }
    end,
    getEndurance = function() return 0.75 end,
    getFatigue = function() return 0.20 end,
    getBodyTemperature = function() return 37.1 end,
    getWetness = function() return 5 end,
    getWorldAgeMinutes = function() return 105 end,
})

local luaTonumber = tonumber
_G.tonumber = function(...)
    Support.assertEqual(select("#", ...), 1, "developer panel numeric conversion arity")
    return luaTonumber((...))
end
local okSnapshot, snapshot = pcall(DevPanel.buildSnapshot)
_G.tonumber = luaTonumber
Support.assertTrue(okSnapshot, snapshot)
Support.assertEqual(snapshot.source, "SP LOCAL", "developer panel authority source")
Support.assertClose(snapshot.snapshotAgeMinutes, 5, 1e-9, "developer panel snapshot age")
Support.assertClose(snapshot.profile.physicalLoad, 3.2, 1e-9, "developer panel worn profile")
Support.assertClose(snapshot.endurance, 0.75, 1e-9, "developer panel player stat")
Support.assertEqual(snapshot.drivers[1].label, "Vest", "developer panel cost driver")

multiplayer = true
state.mpServerSnapshot = {
    activityLabel = "walk",
    physicalLoad = 4.5,
    thermalResistance = 0.7,
    driverCount = 1,
    updatedMinute = 104,
    drivers = {
        { label = "Server Vest", physical = 4.5 },
    },
}
snapshot = DevPanel.buildSnapshot()
Support.assertEqual(snapshot.source, "MP SERVER", "developer panel multiplayer authority")
Support.assertClose(snapshot.profile.physicalLoad, 4.5, 1e-9, "developer panel authoritative burden")
Support.assertClose(snapshot.localProfile.physicalLoad, 3.2, 1e-9, "developer panel local comparison")
Support.assertEqual(snapshot.drivers[1].label, "Server Vest", "developer panel authoritative driver")

print("ams development panel model checks passed")
