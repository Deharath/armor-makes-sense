local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

local eventHandlers = {}
local function makeEvent(name)
    eventHandlers[name] = {}
    return {
        Add = function(handler)
            eventHandlers[name][#eventHandlers[name] + 1] = handler
        end,
        Remove = function(handler)
            for i = #eventHandlers[name], 1, -1 do
                if eventHandlers[name][i] == handler then
                    table.remove(eventHandlers[name], i)
                end
            end
        end,
    }
end

Events = {
    OnGameStart = makeEvent("OnGameStart"),
    EveryOneMinute = makeEvent("EveryOneMinute"),
    OnPlayerUpdate = makeEvent("OnPlayerUpdate"),
}

local player = {}
local playerState = {}
local Utils = {
    clamp = Support.clamp,
    softNorm = Support.softNorm,
    toBoolean = Support.toBoolean,
    lower = function(value)
        return string.lower(tostring(value or ""))
    end,
    safeMethod = Support.safeMethod,
}

ArmorMakesSense = {
    Utils = Utils,
    Classifier = {},
    MP = {
        SCRIPT_VERSION = "test",
        SCRIPT_BUILD = "test-build",
    },
    Core = {
        State = {
            ensureState = function()
                return playerState
            end,
            getOptions = function()
                return {}
            end,
        },
        Stats = {
            getEndurance = function() return 1 end,
            setEndurance = function() end,
            getFatigue = function() return 0 end,
            setFatigue = function() end,
            getThirst = function() return 0 end,
            setThirst = function() end,
            getWetness = function() return 0 end,
            setWetness = function() end,
            getBodyTemperature = function() return 37 end,
            setBodyTemperature = function() end,
            setDiscomfort = function() end,
        },
        LoadModel = {
            computeWornProfile = function() return {} end,
            itemToBurdenSignal = function() return nil end,
        },
        Strain = {
            getVanillaMuscleStrainFactor = function() return 1 end,
        },
    },
    Models = {
        Physiology = {
            getUiRuntimeSnapshot = function() return {} end,
        },
    },
}

getPlayer = function()
    return player
end
isClient = function()
    return false
end
isServer = function()
    return false
end
local sampledMultiplierCalls = 0
local gameTime = {
    getWorldAgeHours = function() return 1 end,
    getMultiplier = function()
        sampledMultiplierCalls = sampledMultiplierCalls + 1
        return 0.2
    end,
    getTrueMultiplier = function() return 5 end,
    setMultiplier = function() end,
}
getGameTime = function()
    return gameTime
end

local DevBootstrap = require "testing/ArmorMakesSense_00_DevBootstrap"
local capturedContext = nil
local benchRunner = ArmorMakesSense.Testing.BenchRunner
local originalSetContext = benchRunner.setContext
benchRunner.setContext = function(context)
    capturedContext = context
    return originalSetContext(context)
end
Support.assertEqual(#eventHandlers.OnGameStart, 1, "development startup registration")
Support.assertTrue(eventHandlers.OnGameStart[1](), "development bootstrap initialization")
Support.assertEqual(capturedContext.getCurrentGameSpeed(), 5, "configured game speed uses the vanilla true multiplier")
Support.assertEqual(sampledMultiplierCalls, 0, "per-tick multiplier is not mistaken for configured speed")
Support.assertTrue(type(_G.ams_bench_status) == "function", "development globals bound")
Support.assertTrue(type(_G.AMS_DevPanel) == "function", "development panel global bound")
Support.assertTrue(type(ArmorMakesSense.Testing.Reset) == "table", "development reset module loaded")
Support.assertTrue(type(ArmorMakesSense.Testing.DevPanel) == "table", "development panel module loaded")
Support.assertEqual(#eventHandlers.EveryOneMinute, 1, "development minute pump registration")
Support.assertEqual(#eventHandlers.OnPlayerUpdate, 1, "development frame pump registration")
eventHandlers.OnPlayerUpdate[1](player)
Support.assertTrue(type(playerState.testLock) == "table", "development test-lock state initialized")
Support.assertTrue(type(playerState.gearProfiles) == "table", "development gear-profile state initialized")
Support.assertEqual(_G.ams_ui_probe_suite, nil, "obsolete instant UI probe suite is not exported")

playerState.uiRuntimeSnapshot = {
    physicalLoad = 12,
    airflowResistance = 2,
    thermalResistance = 0.7,
    effectiveLoad = 18,
    loadNorm = 0.6,
    updatedMinute = 10,
}
Support.assertTrue(ArmorMakesSense.Testing.Commands.uiProbeCurrentGear(), "current gear probe reads production runtime")
playerState.uiRuntimeSnapshot = nil
Support.assertFalse(ArmorMakesSense.Testing.Commands.uiProbeCurrentGear(), "current gear probe rejects missing runtime telemetry")

local originalTick = benchRunner.tick
local originalStop = benchRunner.stop
local stopCalled = false
benchRunner.tick = function()
    error("injected benchmark tick failure")
end
benchRunner.stop = function()
    stopCalled = true
    return true
end
eventHandlers.OnPlayerUpdate[1](player)
Support.assertTrue(stopCalled, "benchmark tick failures enter the runner cleanup path")
benchRunner.tick = originalTick
benchRunner.stop = originalStop

dofile((os.getenv("AMS_ROOT") or ".") .. "/common/media/lua/client/testing/ArmorMakesSense_00_DevBootstrap.lua")
Support.assertEqual(#eventHandlers.OnGameStart, 1, "hot reload replaces the startup registration")
Support.assertTrue(eventHandlers.OnGameStart[1](), "hot-reloaded bootstrap initializes")
Support.assertEqual(#eventHandlers.EveryOneMinute, 1, "hot reload replaces the minute pump")
Support.assertEqual(#eventHandlers.OnPlayerUpdate, 1, "hot reload replaces the frame pump")

print("ams development bootstrap checks passed")
