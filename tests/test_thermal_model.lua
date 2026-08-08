local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local defaults = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_Config.lua")
local ThermalModel = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_ThermalModel.lua")

local hotSample = {
    coreTemp = 37.0,
    bodyHeatDelta = 0.77,
    coreRateOfChange = 0.0063,
    heatGeneration = 4.18,
    fluidsMultiplier = 1.28,
    externalAirTemp = 38,
    airAndWindTemp = 38,
    skinTemp = 36.2,
    perspiration = 0.364,
    vasodilation = 0.56,
    shivering = 0,
    insulation = 1.0,
    windResistance = 1.0,
}

local tenSecond = ThermalModel.advance(hotSample, {}, 10 / 60, defaults)
Support.assertTrue(tenSecond.hotPressure < 0.14, "ten-second spike stays below the former activation gate")
Support.assertClose(tenSecond.strainScale, 0, 1e-9, "ten-second spike stays inside the deadband")

local thirtySecond = ThermalModel.advance(hotSample, {}, 30 / 60, defaults)
Support.assertTrue(thirtySecond.strainScale < 0.10, "thirty-second spike remains a minor thermal effect")

local sustainedState = {}
local sustained = ThermalModel.advance(hotSample, sustainedState, 6, defaults)
Support.assertTrue(sustained.hotPressure > 0.95, "sustained heat charges pressure")
Support.assertTrue(sustained.strainScale > 0.99, "sustained heat reaches full scale")
Support.assertClose(sustained.contribution, defaults.ThermalContributionMax, 0.2, "full resistance reaches configured contribution")

local coolingSample = Support.copyTable(hotSample)
coolingSample.bodyHeatDelta = 0
coolingSample.coreRateOfChange = 0
coolingSample.heatGeneration = 1.1
coolingSample.fluidsMultiplier = 1
coolingSample.externalAirTemp = 20
coolingSample.airAndWindTemp = 20
coolingSample.skinTemp = 33.4
coolingSample.perspiration = 0
coolingSample.vasodilation = 0
local cooling = ThermalModel.advance(coolingSample, sustainedState, 2, defaults)
Support.assertTrue(cooling.hotPressure < sustained.hotPressure, "pressure decays after heat flow stops")
local recovered = ThermalModel.advance(coolingSample, sustainedState, 6, defaults)
Support.assertClose(recovered.strainScale, 0, 1e-9, "recovery returns pressure to the deadband")

local loadedHot = ThermalModel.advance({
    coreTemp = 38.15,
    bodyHeatDelta = 0,
    shivering = 0,
    insulation = 1.0,
    windResistance = 1.0,
}, {}, 0, defaults)
Support.assertClose(loadedHot.hotPressure, 0.5, 1e-9, "new state initializes from durable core heat")
Support.assertTrue(loadedHot.strainScale > 0, "loaded overheated character has immediate pressure")

local cold = ThermalModel.advance({
    coreTemp = 36.5,
    bodyHeatDelta = -0.2,
    shivering = 0,
    insulation = 1.0,
    windResistance = 1.0,
}, {}, 1, defaults)
Support.assertTrue(cold.coldNeed > 0.16, "cold physiology creates suitability context")
Support.assertClose(cold.coldSuitability, 1, 1e-9, "effective insulation is suitable in cold")
Support.assertClose(cold.contribution, 0, 1e-9, "cold suitability creates no AMS contribution")

local shivering = ThermalModel.advance({
    coreTemp = 36.5,
    bodyHeatDelta = -0.2,
    shivering = 0.20,
    insulation = 1.0,
    windResistance = 1.0,
}, {}, 1, defaults)
Support.assertClose(shivering.coldSuitability, 0, 1e-9, "active shivering rejects suitability")

local nodes = {
    {
        getSkinSurface = function() return 0.01 end,
        getInsulation = function() return 100 end,
        getWindresist = function() return 100 end,
        getInsulationUI = function() return 1 end,
        getWindresistUI = function() return 1 end,
        getSkinCelcius = function() return 40 end,
    },
    {
        getSkinSurface = function() return 0.99 end,
        getInsulation = function() return 100 end,
        getWindresist = function() return 100 end,
        getInsulationUI = function() return 0 end,
        getWindresistUI = function() return 0 end,
        getSkinCelcius = function() return 30 end,
    },
}
local thermoregulator = {
    getCoreTemperature = function() return 37 end,
    getBodyHeatDelta = function() return 0 end,
    getDbg_secTotal = function() return 0 end,
    getNodeSize = function() return #nodes end,
    getNode = function(_, index) return nodes[index + 1] end,
}
local player = {
    getBodyDamage = function()
        return {
            getThermoregulator = function() return thermoregulator end,
        }
    end,
}
local sampled = ThermalModel.sample(player)
Support.assertClose(sampled.insulation, 0.01, 1e-9, "insulation follows vanilla surface weighting")
Support.assertClose(sampled.windResistance, 0.01, 1e-9, "wind resistance follows vanilla surface weighting")
Support.assertClose(sampled.skinTemp, 30.1, 1e-9, "skin temperature follows vanilla surface weighting")

local lightSummerOutfit = ThermalModel.advance({
    coreTemp = 37.46,
    bodyHeatDelta = 0.55,
    coreRateOfChange = 0.001,
    heatGeneration = 2.2,
    fluidsMultiplier = 1.05,
    externalAirTemp = 29,
    airAndWindTemp = 29,
    skinTemp = 34.5,
    perspiration = 0.15,
    vasodilation = 0.20,
    shivering = 0,
    insulation = 0.30,
    windResistance = 0.296,
}, {}, 6, defaults)
Support.assertClose(lightSummerOutfit.resistance, 0.2988, 1e-9, "normalized light outfit keeps modest resistance")
Support.assertTrue(lightSummerOutfit.hotDrive < 0.30, "ordinary summer heat stays contextually bounded")
Support.assertTrue(lightSummerOutfit.contribution < 0.25, "ordinary summer clothing stays below visible thermal load")

local disabled = Support.copyTable(defaults)
disabled.EnableThermalModel = false
local disabledResult = ThermalModel.advance(hotSample, {}, 6, disabled)
Support.assertClose(disabledResult.contribution, 0, 1e-9, "disabled thermal model is neutral")
Support.assertClose(disabledResult.strainScale, 0, 1e-9, "disabled thermal scale is neutral")

local unavailable = ThermalModel.advance(nil, {}, 6, defaults)
Support.assertFalse(unavailable.available, "missing thermoregulator is reported")
Support.assertClose(unavailable.contribution, 0, 1e-9, "missing thermoregulator fails open")

print("ams thermal model characterization passed")
