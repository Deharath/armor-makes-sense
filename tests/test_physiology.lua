local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local defaults = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_Config.lua")
local Physiology = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_PhysiologyShared.lua")

GameClient = nil
GameServer = nil
MoodleType = nil

local nowMinutes = 500
local endurance = 0.8
local fatigue = 0.6
local metabolicRate = 1.5
local player = {
    asleep = false,
    bedType = "averageBed",
    attacking = false,
}
function player:isAsleep() return self.asleep end
function player:getBedType() return self.bedType end
function player:hasTrait() return false end
function player:isAttackStarted() return self.attacking end
function player:getStats()
    return {
        getEndurance = function() return endurance end,
        setEndurance = function(_, value) endurance = value end,
        getFatigue = function() return fatigue end,
        setFatigue = function(_, value) fatigue = value end,
    }
end
function player:getBodyDamage()
    return {
        getThermoregulator = function()
            return {
                getMetabolicRate = function() return metabolicRate end,
            }
        end,
    }
end

getGameTime = function()
    return {
        getWorldAgeHours = function()
            return nowMinutes / 60
        end,
    }
end

local sleepState = {}
local planner = Physiology.computeSleepPlannerPenalty(player, sleepState, defaults, { rigidityLoad = 80 }, fatigue)
Support.assertClose(planner.penaltyFraction, 0.012857142857, 1e-9, "average-bed sleep penalty")
Support.assertClose(sleepState.lastSleepPenaltyFraction, planner.penaltyFraction, 1e-12, "stored planner penalty")

local sleepDisabled = Support.copyTable(defaults)
sleepDisabled.EnableSleepPenaltyModel = false
planner = Physiology.computeSleepPlannerPenalty(player, {}, sleepDisabled, { rigidityLoad = 80 }, fatigue)
Support.assertClose(planner.penaltyFraction, 0, 1e-9, "disabled sleep penalty")

player.asleep = true
sleepState = { wasSleeping = false }
local sleepResult = Physiology.computeSleepPenaltyContribution(
    player,
    sleepState,
    defaults,
    1,
    { rigidityLoad = 80 },
    fatigue
)
Support.assertTrue(sleepResult.sleeping, "sleep transition state")
Support.assertClose(sleepResult.penaltyFraction, 0.012857142857, 1e-9, "sleep transition penalty")
Support.assertClose(sleepState.sleepSnapshot.rigidityLoad, 80, 1e-9, "sleep snapshot rigidity")

sleepResult = Physiology.computeSleepPenaltyContribution(
    player,
    sleepState,
    defaults,
    1,
    { rigidityLoad = 0 },
    fatigue
)
Support.assertClose(sleepResult.penaltyFraction, 0.012857142857, 1e-9, "sleep snapshot remains fixed")

player.asleep = false
Physiology.computeSleepPenaltyContribution(player, sleepState, defaults, 1, {}, fatigue)
Support.assertEqual(sleepState.sleepSnapshot, nil, "wake clears sleep snapshot")

fatigue = 0.90
player.asleep = true
Physiology.applySleepTransition(player, { wasSleeping = false }, defaults, 1, { rigidityLoad = 80 })
Support.assertClose(fatigue, 0.90, 1e-9, "sleep penalty never lowers high fatigue")
player.asleep = false
fatigue = 0.60

local enduranceOptions = Support.copyTable(defaults)
enduranceOptions.EnableThermalModel = false
local loadProfile = {
    physicalLoad = 30,
    airflowResistance = 0,
    sealedRestriction = 0,
}

endurance = 0.8
local thermalDisabledState = {}
Physiology.applyEnduranceModel(
    player,
    thermalDisabledState,
    enduranceOptions,
    0,
    loadProfile,
    defaults.ActivityIdle,
    "idle",
    "stand"
)
Support.assertClose(thermalDisabledState.uiRuntimeSnapshot.thermalContribution, 0, 1e-9, "disabled thermal model is neutral")

endurance = 0.8
local runState = {}
local runDelta = Physiology.applyEnduranceModel(
    player,
    runState,
    enduranceOptions,
    1,
    loadProfile,
    defaults.ActivityJog,
    "run",
    "stand"
)
Support.assertClose(runDelta, -0.0025795, 1e-9, "run endurance drain")
Support.assertClose(runState.uiRuntimeSnapshot.loadNorm, 0.833333333333, 1e-9, "run normalized load")

endurance = 0.6
local recoveryState = { lastEnduranceObserved = 0.5 }
local recoveryDelta = Physiology.applyEnduranceModel(
    player,
    recoveryState,
    enduranceOptions,
    1,
    loadProfile,
    defaults.ActivityIdle,
    "idle",
    "stand"
)
Support.assertClose(recoveryDelta, -0.017237353125, 1e-9, "idle recovery reduction")
Support.assertClose(recoveryState.uiRuntimeSnapshot.amsEnduranceRegenScale, 0.82762646875, 1e-9, "idle AMS regen scale")

local breathingProfile = {
    physicalLoad = 10,
    airflowResistance = 3.75,
    sealedRestriction = 1,
}
endurance = 0.8
local idleMaskState = {}
Physiology.applyEnduranceModel(
    player,
    idleMaskState,
    enduranceOptions,
    0,
    breathingProfile,
    defaults.ActivityIdle,
    "idle",
    "stand"
)
Support.assertClose(idleMaskState.uiRuntimeSnapshot.breathingContribution, 0, 1e-9, "idle mask cannot reduce armor burden")

local sprintMaskState = {}
Physiology.applyEnduranceModel(
    player,
    sprintMaskState,
    enduranceOptions,
    0,
    breathingProfile,
    defaults.ActivitySprint,
    "sprint",
    "stand"
)
Support.assertClose(sprintMaskState.uiRuntimeSnapshot.breathingContribution, 6.375, 1e-9, "sprint sealed-mask load")
Support.assertClose(sprintMaskState.uiRuntimeSnapshot.metabolicRate, 1.5, 1e-9, "runtime smoothed metabolic rate")
Support.assertClose(sprintMaskState.uiRuntimeSnapshot.metabolicDemand, 9.5, 1e-9, "runtime immediate metabolic demand")
Support.assertClose(sprintMaskState.uiRuntimeSnapshot.breathingEffortRamp, 1, 1e-9, "runtime breathing effort ramp")

local stackedRespiratorState = {}
Physiology.applyEnduranceModel(
    player,
    stackedRespiratorState,
    enduranceOptions,
    0,
    {
        physicalLoad = 10,
        airflowResistance = 6.6,
        sealedRestriction = 0,
    },
    defaults.ActivitySprint,
    "sprint",
    "stand"
)
Support.assertTrue(
    stackedRespiratorState.uiRuntimeSnapshot.breathingContribution
        < sprintMaskState.uiRuntimeSnapshot.breathingContribution,
    "stacked respirators do not inherit sealed-mask cost"
)
Support.assertClose(
    stackedRespiratorState.uiRuntimeSnapshot.sealedRestriction,
    0,
    1e-9,
    "runtime preserves explicit unsealed state"
)

print("ams physiology characterization passed")
