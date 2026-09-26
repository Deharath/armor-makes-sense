local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
GameClient = nil
GameServer = nil
local options = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_Config.lua")
local Compat = require "ArmorMakesSense_Compat"
local BreathingModel = require "ArmorMakesSense_BreathingModel"
local EnduranceModel = require "ArmorMakesSense_EnduranceModel"
local SleepModel = require "ArmorMakesSense_SleepModel"

local function breathe(airflow, sealed, rate, activity, opts)
    return BreathingModel.calculate(opts or options, {
        airflowResistance = airflow,
        sealedRestriction = sealed,
        metabolicRate = rate,
        activityLabel = activity,
    })
end

-- Breathing: severity is the gear, effort ramp is the pace.
local sprintMask = breathe(3.75, 1, 1.5, "sprint")
Support.assertClose(sprintMask.severity, 1, 1e-9, "sealed gas mask is full severity")
Support.assertClose(sprintMask.effortRamp, 1, 1e-9, "sprint is full breathing effort")
Support.assertClose(sprintMask.pressure, 1, 1e-9, "sprinting in a sealed mask is full pressure")
Support.assertClose(breathe(3.75, 1, 1.5, "idle").pressure, 0, 1e-9, "resting mask costs nothing")
Support.assertClose(breathe(3.75, 1, 1.5, "walk").pressure, 0, 1e-9, "walking sits at the breathing onset")
Support.assertClose(breathe(3.75, 1, 3.9, "idle").pressure, 0.04296875, 1e-9, "metabolic work above walking ramps pressure")
Support.assertClose(breathe(3.75, 1, 1.5, "run").pressure, 0.63897705078125, 1e-9, "running in a sealed mask")
Support.assertClose(breathe(3.3, 0, 1.5, "run").severity, 0.66, 1e-9, "filtered respirator severity")
Support.assertClose(breathe(0.9, 0, 1.5, "run").severity, 0.18, 1e-9, "unfiltered respirator severity")
Support.assertTrue(breathe(3.3, 0, 1.5, "run").pressure > breathe(0.9, 0, 1.5, "run").pressure, "filters cost more at equal effort")

local breathingOff = Support.copyTable(options)
breathingOff.EnableBreathingModel = false
local disabled = breathe(3.75, 1, 1.5, "sprint", breathingOff)
Support.assertClose(disabled.pressure, 0, 1e-9, "disabled breathing applies no pressure")
Support.assertClose(disabled.severity, 1, 1e-9, "disabled breathing still reports gear severity")
Support.assertFalse(pcall(BreathingModel.calculate, nil, {}), "breathing rejects missing options")

-- Endurance scales.
local function scales(input)
    return EnduranceModel.scales(options, input)
end
local walk = scales({ loadFraction = 0.25, activityLabel = "walk" })
Support.assertClose(walk.regenScale, 0.5, 1e-9, "loaded walking halves recovery")
Support.assertClose(walk.walkDrainFraction, 0, 1e-9, "moderate walking load does not drain")
Support.assertClose(walk.drainScale, 1.25, 1e-9, "walking drain amplification")
local heavyWalk = scales({ loadFraction = 0.75, activityLabel = "walk" })
Support.assertClose(heavyWalk.regenScale, 0, 1e-9, "heavy walking stops recovery")
Support.assertClose(heavyWalk.walkDrainFraction, 0.5, 1e-9, "walk floor turns recovery into drain")
Support.assertClose(scales({ loadFraction = 0.5, activityLabel = "run" }).drainScale, 1.5, 1e-9, "load drain weight")
Support.assertClose(scales({ loadFraction = 0.5, activityLabel = "sprint" }).drainScale, 1.5, 1e-9, "drain does not depend on the sampled pace")
local rest = scales({ loadFraction = 0.75, activityLabel = "idle", resting = true })
Support.assertClose(rest.regenScale, 1, 1e-9, "sitting under load recovers at vanilla pace")
Support.assertClose(rest.drainScale, 1.75, 1e-9, "sitting does not exempt a minute's drain")
local stand = scales({ loadFraction = 0.5, activityLabel = "idle" })
Support.assertClose(stand.regenScale, 0.75, 1e-9, "standing recovery slows with load squared")
Support.assertClose(stand.walkDrainFraction, 0, 1e-9, "standing never turns recovery into drain")
local crushing = scales({ loadFraction = 1.5, activityLabel = "idle" })
Support.assertClose(crushing.regenScale, 0, 1e-9, "standing recovery floors at zero")
Support.assertClose(crushing.walkDrainFraction, 0, 1e-9, "standing never drains, however heavy")
local hot = scales({ loadFraction = 0, heat = 1, activityLabel = "idle", resting = true })
Support.assertClose(hot.regenScale, 0.5, 1e-9, "full heat halves recovery even at rest")
Support.assertClose(hot.drainScale, 1.25, 1e-9, "full heat drain weight")
Support.assertClose(scales({ breathing = 1, activityLabel = "sprint" }).drainScale, 1.35, 1e-9, "full breathing drain weight")
Support.assertFalse(pcall(EnduranceModel.scales, {}, {}), "endurance rejects unresolved options")

-- Endurance calculate: scale vanilla's observed delta.
local function calc(input)
    return EnduranceModel.calculate(options, input)
end
local first = calc({ previous = nil, current = 0.7, loadFraction = 1, activityLabel = "run" })
Support.assertFalse(first.canApply, "no previous observation cannot apply")
Support.assertClose(first.controlledEndurance, 0.7, 1e-9, "first observation keeps vanilla value")

local recovery = calc({ previous = 0.8, current = 0.81, loadFraction = 0.25, activityLabel = "walk" })
Support.assertClose(recovery.controlledEndurance, 0.805, 1e-9, "walking recovery is scaled")
Support.assertClose(recovery.amsDelta, -0.005, 1e-9, "AMS delta reports the withheld recovery")
local heavyRecovery = calc({ previous = 0.8, current = 0.81, loadFraction = 0.75, activityLabel = "walk" })
Support.assertClose(heavyRecovery.controlledEndurance, 0.795, 1e-9, "heavy walking turns recovery into drain")
local drain = calc({ previous = 0.8, current = 0.79, loadFraction = 0.5, activityLabel = "run" })
Support.assertClose(drain.controlledEndurance, 0.785, 1e-9, "running drain is amplified")
Support.assertClose(calc({ previous = 0.8, current = 0.8, loadFraction = 1, activityLabel = "run" }).amsDelta, 0, 1e-9, "no vanilla change, no AMS change")

local nms = calc({ previous = 0.8, current = 0.81, activityLabel = "idle", nmsRegenScale = 0.5, nmsDrain = 0.02 })
Support.assertClose(nms.controlledEndurance, 0.785, 1e-9, "NMS regen scale and drain compose")
Support.assertClose(nms.composedRegenScale, 0.5, 1e-9, "composed regen scale")
Support.assertClose(nms.nmsDrainApplied, 0.02, 1e-9, "NMS drain applied")
Support.assertClose(calc({ previous = 0.01, current = 0.0, loadFraction = 2, activityLabel = "sprint" }).controlledEndurance, 0, 1e-9, "endurance clamps at zero")

-- Sleep penalty: rigid kilograms only.
Support.assertClose(SleepModel.penaltyFraction(options, 0), 0, 1e-9, "no rigid armor, no sleep penalty")
Support.assertClose(SleepModel.penaltyFraction(options, 8), 0.2, 1e-9, "sleep penalty per rigid kg")
Support.assertClose(SleepModel.penaltyFraction(options, 40), 0.5, 1e-9, "sleep penalty cap")
local sleepOff = Support.copyTable(options)
sleepOff.EnableSleepPenaltyModel = false
Support.assertClose(SleepModel.penaltyFraction(sleepOff, 40), 0, 1e-9, "disabled sleep penalty")

local fatigue = 0.6
local sleeper = { asleep = true }
function sleeper:isAsleep() return self.asleep end
function sleeper:getStats()
    return {
        getFatigue = function() return fatigue end,
        setFatigue = function(_, value) fatigue = value end,
    }
end
local profile = { rigidKg = 8 }
local sleepState = {}
local step = SleepModel.step(sleeper, sleepState, options, profile)
Support.assertClose(step.extraFatigue, 0, 1e-9, "sleep onset only records a baseline")
Support.assertTrue(sleepState.sleepWasAsleep, "sleep onset recorded")
fatigue = 0.5
step = SleepModel.step(sleeper, sleepState, options, profile)
Support.assertClose(step.extraFatigue, 0.02, 1e-9, "rigid armor gives back a share of recovery")
Support.assertClose(fatigue, 0.52, 1e-9, "fatigue write applies the penalty")
Support.assertClose(sleepState.lastFatigueObserved, 0.52, 1e-9, "penalized fatigue becomes the next baseline")
fatigue = 0.55
step = SleepModel.step(sleeper, sleepState, options, profile)
Support.assertClose(step.extraFatigue, 0, 1e-9, "rising fatigue is never penalized")

Compat:registerProvider("CaffeineMakesSense", { capabilities = { fatigue_coordinator = true } })
Support.assertTrue(SleepModel.cmsOwnsFatigue(), "CMS fatigue coordinator detected")
fatigue = 0.45
step = SleepModel.step(sleeper, sleepState, options, profile)
Support.assertClose(step.extraFatigue, 0, 1e-9, "CMS-owned fatigue is not written by AMS")
Support.assertClose(step.penaltyFraction, 0.2, 1e-9, "CMS still reads the AMS penalty fraction")
Support.assertClose(fatigue, 0.45, 1e-9, "fatigue untouched under CMS")
Compat.providers.CaffeineMakesSense = nil

sleeper.asleep = false
step = SleepModel.step(sleeper, sleepState, options, profile)
Support.assertFalse(step.sleeping, "wake transition")
Support.assertClose(step.penaltyFraction, 0, 1e-9, "awake players carry no live sleep penalty")

print("ams pure calculation model checks passed")
