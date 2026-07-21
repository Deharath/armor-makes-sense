local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")
local root = os.getenv("AMS_ROOT") or "."

ArmorMakesSense = {}
local options = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_Config.lua")
local BreathingModel = require "ArmorMakesSense_BreathingModel"
local EnduranceModel = require "ArmorMakesSense_EnduranceModel"
local SleepModel = require "ArmorMakesSense_SleepModel"
local sleepContract = dofile(root .. "/tests/fixtures/vanilla_sleep_contract.lua")

local breathing = BreathingModel.calculate(options, {
    airflowResistance = 3.75,
    sealedRestriction = 1,
    metabolicRate = 1.5,
    activityLabel = "sprint",
})
Support.assertClose(breathing.contribution, 6.375, 1e-9, "pure breathing result")
Support.assertClose(breathing.metabolicNorm, 1, 1e-9, "pure breathing effort")
Support.assertClose(breathing.effortRamp, 1, 1e-9, "pure breathing effort ramp")
Support.assertClose(breathing.metabolicRate, 1.5, 1e-9, "pure breathing smoothed rate")
Support.assertClose(breathing.metabolicDemand, 9.5, 1e-9, "pure breathing movement demand")

local restingBreathing = BreathingModel.calculate(options, {
    airflowResistance = 3.75,
    sealedRestriction = 1,
    metabolicRate = 1.5,
    activityLabel = "idle",
})
Support.assertClose(restingBreathing.contribution, 0, 1e-9, "resting mask has no burden contribution")
Support.assertClose(restingBreathing.metabolicNorm, 0, 1e-9, "resting metabolic effort")

local workingBreathing = BreathingModel.calculate(options, {
    airflowResistance = 3.75,
    sealedRestriction = 1,
    metabolicRate = 3.9,
    activityLabel = "idle",
})
Support.assertClose(workingBreathing.metabolicNorm, 0.3, 1e-9, "medium-work metabolic effort")
Support.assertClose(workingBreathing.contribution, 0.27392578125, 1e-9, "medium-work sealed-mask load")

local briskWalkBreathing = BreathingModel.calculate(options, {
    airflowResistance = 3.75,
    sealedRestriction = 1,
    metabolicRate = 1.5,
    activityLabel = "walk",
})
Support.assertClose(briskWalkBreathing.contribution, 0, 1e-9, "brisk walking remains below breathing onset")

local unfilteredRespirator = BreathingModel.calculate(options, {
    airflowResistance = 0.9,
    sealedRestriction = 0,
    metabolicRate = 1.5,
    activityLabel = "run",
})
local filteredRespirator = BreathingModel.calculate(options, {
    airflowResistance = 3.3,
    sealedRestriction = 0,
    metabolicRate = 1.5,
    activityLabel = "run",
})
Support.assertTrue(
    filteredRespirator.contribution > unfilteredRespirator.contribution,
    "higher airflow resistance remains more costly at every active effort"
)
Support.assertClose(
    BreathingModel.calculate(options, {
        airflowResistance = 3.75,
        sealedRestriction = 1,
        metabolicRate = 1.5,
        activityLabel = "run",
    }).contribution,
    4.073478698730469,
    1e-9,
    "running gas-mask load remains a modest immediate burden"
)

local endurance = EnduranceModel.calculate(options, {
    previous = 0.8,
    current = 0.8,
    naturalDelta = 0,
    loadNorm = 0.833333333333,
    activityLoadScale = 1,
    activityLabel = "run",
    dtMinutes = 1,
})
Support.assertClose(endurance.amsDrainApplied, 0.0025795, 1e-9, "pure endurance drain")
Support.assertClose(endurance.enduranceDelta, -0.0025795, 1e-9, "pure endurance result")

local vanillaRate = SleepModel.vanillaRecoveryRatePerHour({ fatigue = 0.6, bedType = "averageBed" })
Support.assertClose(
    vanillaRate,
    sleepContract.highFatigueRecovery / sleepContract.highFatigueHours,
    1e-9,
    "versioned vanilla sleep recovery contract"
)
local goodBedRate = SleepModel.vanillaRecoveryRatePerHour({ fatigue = 0.6, bedType = "goodBed" })
Support.assertClose(goodBedRate, vanillaRate * 1.10, 1e-9, "sleep model consumes explicit bed type")

local okMissing = pcall(BreathingModel.calculate, {}, { airflowResistance = 1 })
Support.assertFalse(okMissing, "calculation modules reject unresolved options")

print("ams pure calculation model checks passed")
