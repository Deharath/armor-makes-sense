local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
GameClient = nil
GameServer = nil
local defaults = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_Config.lua")
local Compat = require "ArmorMakesSense_Compat"
local Physiology = require "ArmorMakesSense_PhysiologyShared"

local nowMinutes = 500
getGameTime = function()
    return { getWorldAgeHours = function() return nowMinutes / 60 end }
end

local endurance = 0.8
local fatigue = 0.4
local player = { asleep = false, moving = false, running = false, sitting = false }
function player:isAsleep() return self.asleep end
function player:isPlayerMoving() return self.moving end
function player:isRunning() return self.running end
function player:isSitOnGround() return self.sitting end
function player:getNutrition() return { getWeight = function() return 80 end } end
function player:getStats()
    return {
        getEndurance = function() return endurance end,
        setEndurance = function(_, value) endurance = value end,
        getFatigue = function() return fatigue end,
        setFatigue = function(_, value) fatigue = value end,
    }
end

-- 23.5 kg burden on an 80 kg, strength-5 body: (23.5 - 3.5) / 80 = 0.25 load fraction.
local profile = { burdenKg = 23.5, armKg = 4, rigidKg = 8, driverCount = 3, airflowResistance = 0, sealedRestriction = 0 }
local state = {}

local snapshot = Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertClose(state.lastTickMinute, 500, 1e-9, "first tick records the minute")
Support.assertClose(state.lastEnduranceObserved, 0.8, 1e-9, "first tick rebases endurance")
Support.assertEqual(snapshot.amsDelta, nil, "rebase tick applies nothing")
Support.assertClose(snapshot.loadFraction, 0.25, 1e-9, "snapshot load fraction")
Support.assertClose(snapshot.walkRegenScale, 0.5, 1e-9, "snapshot walk recovery")
Support.assertClose(snapshot.runDrainScale, 1.25, 1e-9, "snapshot run drain")
Support.assertClose(snapshot.sprintDrainScale, 1.25, 1e-9, "sprint pays the same load share as running")
Support.assertClose(snapshot.standRegenScale, 0.9375, 1e-9, "standing recovery slows with load squared")
Support.assertClose(snapshot.restRegenScale, 1, 1e-9, "sitting recovers at the vanilla rate")
Support.assertClose(snapshot.sleepPenaltyFraction, 0.2, 1e-9, "snapshot sleep penalty preview")
Support.assertClose(snapshot.heat, 0, 1e-9, "missing thermoregulator is neutral heat")
Support.assertEqual(state.uiRuntimeSnapshot, snapshot, "snapshot stored for UI")
Support.assertEqual(Physiology.getUiRuntimeSnapshot(state), snapshot, "SP UI snapshot read")

-- Walking recovery is halved.
player.moving = true
nowMinutes = 501
endurance = 0.81
snapshot = Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertClose(endurance, 0.805, 1e-9, "walking tick scales vanilla recovery")
Support.assertClose(snapshot.naturalDelta, 0.01, 1e-9, "natural delta observed")
Support.assertClose(snapshot.amsDelta, -0.005, 1e-9, "AMS delta recorded")
Support.assertClose(snapshot.dtMinutes, 1, 1e-9, "tick step minutes")
Support.assertEqual(snapshot.activityLabel, "walk", "walk activity label")
Support.assertClose(state.lastEnduranceObserved, 0.805, 1e-9, "controlled value is the next baseline")

-- Same-minute tick and long gaps rebase instead of applying.
endurance = 0.9
snapshot = Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertEqual(snapshot.amsDelta, nil, "same-minute tick applies nothing")
Support.assertClose(endurance, 0.9, 1e-9, "same-minute tick leaves endurance")
Support.assertClose(state.lastEnduranceObserved, 0.9, 1e-9, "same-minute tick rebases")
nowMinutes = 501 + defaults.MaxStepMinutes + 1
endurance = 1.0
snapshot = Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertEqual(snapshot.amsDelta, nil, "gap beyond MaxStepMinutes rebases")
Support.assertClose(endurance, 1.0, 1e-9, "gap does not retroactively tax recovery")

-- Resting under load recovers at vanilla pace.
player.moving = false
player.sitting = true
endurance = 0.5
Physiology.tick(player, state, defaults, profile, nowMinutes)
nowMinutes = nowMinutes + 1
endurance = 0.52
Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertClose(endurance, 0.52, 1e-9, "resting recovery is untouched")
player.sitting = false

-- NMS contribution composes with AMS scaling.
local recorded
Compat:registerProvider("NutritionMakesSense", {
    callbacks = {
        computeEnduranceContribution = function(_, ctx)
            Support.assertClose(ctx.dtMinutes, 1, 1e-9, "NMS receives the step")
            return { regenScale = 0.5, extraDrain = 0.001 }
        end,
        recordEnduranceResult = function(_, result) recorded = result end,
    },
})
nowMinutes = nowMinutes + 1
endurance = 0.54
snapshot = Physiology.tick(player, state, defaults, profile, nowMinutes)
-- Standing: 0.02 recovery * 0.9375 load * 0.5 NMS, less 0.001 NMS drain.
Support.assertClose(endurance, 0.528375, 1e-9, "NMS regen scale and drain compose with standing load")
Support.assertClose(snapshot.nmsRegenScale, 0.5, 1e-9, "snapshot NMS regen scale")
Support.assertClose(snapshot.nmsDrain, 0.001, 1e-9, "snapshot NMS drain")
Support.assertClose(recorded.controlledEndurance, 0.528375, 1e-9, "NMS receives the controlled result")
Compat.providers.NutritionMakesSense = nil

-- Sleep: fatigue penalty applies, endurance pipeline pauses.
player.asleep = true
nowMinutes = nowMinutes + 1
Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertTrue(state.sleepWasAsleep, "sleep onset recorded")
nowMinutes = nowMinutes + 1
fatigue = 0.3
endurance = 0.6
snapshot = Physiology.tick(player, state, defaults, profile, nowMinutes)
Support.assertClose(fatigue, 0.32, 1e-9, "rigid armor slows sleep recovery")
Support.assertClose(state.lastSleepExtraFatigue, 0.02, 1e-9, "extra fatigue recorded")
Support.assertEqual(snapshot.amsDelta, nil, "endurance pipeline pauses asleep")
Support.assertClose(state.lastEnduranceObserved, 0.6, 1e-9, "asleep ticks keep endurance rebased")
player.asleep = false

-- Projection is read-only.
local before = state.lastTickMinute
local projected = Physiology.project(player, state, defaults, profile)
Support.assertClose(projected.loadFraction, 0.25, 1e-9, "projection load fraction")
Support.assertEqual(state.lastTickMinute, before, "projection does not advance time")

local mpView = Physiology.projectWithServerThermal(player, defaults, profile, {
    heat = 1, thermalResistance = 0.9, hotPressure = 0.8, coldSuitability = 0,
})
Support.assertClose(mpView.loadFraction, 0.25, 1e-9, "MP view derives load from local gear")
Support.assertClose(mpView.heat, 1, 1e-9, "MP view takes heat from the server")
Support.assertClose(mpView.restRegenScale, 0.5, 1e-9, "server heat shapes local recovery preview")
Support.assertClose(mpView.thermalResistance, 0.9, 1e-9, "MP view carries server thermal resistance")

local contribution = Physiology.sleepPenaltyContribution(player, defaults, profile)
Support.assertClose(contribution.penaltyFraction, 0.2, 1e-9, "CMS sleep penalty callback")
Support.assertFalse(contribution.sleeping, "CMS callback reports wake state")

local trace = Physiology.buildCompatTraceSnapshot(state)
Support.assertClose(trace.burden_kg, 23.5, 1e-9, "compat trace burden")
Support.assertClose(trace.load_fraction, 0.25, 1e-9, "compat trace load fraction")

print("ams physiology tick checks passed")
