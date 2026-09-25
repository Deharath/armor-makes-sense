local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local Environment = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_EnvironmentShared.lua")
local Strain = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_StrainShared.lua")
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local defaults = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_Config.lua")

local player = {
    asleep = false,
    sitting = false,
    seatedVehicle = false,
    sprinting = false,
    running = false,
    moving = false,
    attacking = false,
}
function player:isAsleep() return self.asleep end
function player:isSitOnGround() return self.sitting end
function player:isSeatedInVehicle() return self.seatedVehicle end
function player:isSprinting() return self.sprinting end
function player:isRunning() return self.running end
function player:isPlayerMoving() return self.moving end
function player:isMoving() return self.moving end
function player:isAttackStarted() return self.attacking end

Support.assertEqual(Environment.getPostureLabel(player), "stand", "standing posture")
Support.assertFalse(Environment.isResting("stand"), "standing is not resting")
player.sitting = true
Support.assertEqual(Environment.getPostureLabel(player), "sit", "sitting posture")
Support.assertTrue(Environment.isResting("sit"), "sitting is resting")
player.sitting = false
player.seatedVehicle = true
Support.assertEqual(Environment.getPostureLabel(player), "sit_vehicle", "vehicle posture")
Support.assertTrue(Environment.isResting("sit_vehicle"), "vehicle seat is resting")
player.seatedVehicle = false
player.asleep = true
Support.assertEqual(Environment.getPostureLabel(player), "sleep", "sleep posture")
Support.assertFalse(Environment.isResting("sleep"), "sleep is handled by the sleep model")
player.asleep = false

Support.assertEqual(Environment.resolveActivity(player), "idle", "idle activity")
player.attacking = true
Support.assertEqual(Environment.resolveActivity(player), "idle", "attacking does not invent an activity band")
player.attacking = false
player.asleep = true
Support.assertEqual(Environment.resolveActivity(player), "sleep", "sleep activity")
player.asleep = false
player.moving = true
Support.assertEqual(Environment.resolveActivity(player), "walk", "walk activity")
player.running = true
Support.assertEqual(Environment.resolveActivity(player), "run", "run activity")
player.sprinting = true
Support.assertEqual(Environment.resolveActivity(player), "sprint", "sprint activity")

Support.assertClose(Strain.computeArmorStrainExtra(defaults, { armKg = 1 }), 0, 1e-9, "strain start threshold")
Support.assertClose(Strain.computeArmorStrainExtra(defaults, { armKg = 4.5 }), 0.053033008589, 1e-9, "strain midpoint")
Support.assertClose(Strain.computeArmorStrainExtra(defaults, { armKg = 8 }), 0.15, 1e-9, "strain full threshold")

local meleeWeapon = {
    getType = function() return "Axe" end,
    isUseEndurance = function() return true end,
    isRanged = function() return false end,
    isAimedFirearm = function() return false end,
    isBareHands = function() return false end,
}
Support.assertTrue(Strain.isMeleeStrainEligible(meleeWeapon), "melee strain eligibility")
meleeWeapon.isRanged = function() return true end
Support.assertFalse(Strain.isMeleeStrainEligible(meleeWeapon), "ranged strain exclusion")

meleeWeapon.isRanged = function() return false end
player.attacking = false
local appliedStrain = {}
function player:addCombatMuscleStrain(_, hitCount, extra)
    appliedStrain[#appliedStrain + 1] = { hitCount = hitCount, extra = extra }
end

local computeWornProfile = LoadModel.computeWornProfile
LoadModel.computeWornProfile = function()
    return { armKg = 8 }
end

SandboxOptions = {
    instance = {
        muscleStrainFactor = {
            getValue = function() return 0 end,
        },
    },
}
local disabledExtra, disabledVanillaFactor = Strain.applyArmorStrainOverlay(
    player,
    meleeWeapon,
    defaults
)
Support.assertClose(disabledExtra, 0, 1e-9, "disabled vanilla strain blocks overlay")
Support.assertClose(disabledVanillaFactor, 0, 1e-9, "disabled vanilla strain factor")
Support.assertEqual(#appliedStrain, 0, "disabled vanilla strain write count")

SandboxOptions.instance.muscleStrainFactor.getValue = function() return 1 end
local serverExtra, serverVanillaFactor = Strain.applyArmorStrainOverlay(
    player,
    meleeWeapon,
    defaults
)
Support.assertClose(serverExtra, 0.15, 1e-9, "event-authoritative strain overlay")
Support.assertClose(serverVanillaFactor, 1, 1e-9, "enabled vanilla strain factor")
Support.assertEqual(#appliedStrain, 1, "event-authoritative strain write count")
Support.assertEqual(appliedStrain[1].hitCount, 1, "one overlay application per swing")
Support.assertClose(appliedStrain[1].extra, 0.15, 1e-9, "event-authoritative strain amount")

LoadModel.computeWornProfile = function()
    error("cached swing profile should avoid a worn-gear rescan")
end
local cachedExtra = Strain.applyArmorStrainOverlay(
    player,
    meleeWeapon,
    defaults,
    { armKg = 4.5 }
)
Support.assertClose(cachedExtra, 0.053033008589, 1e-9, "cached swing profile amount")
Support.assertEqual(#appliedStrain, 2, "cached swing profile write count")

LoadModel.computeWornProfile = computeWornProfile
SandboxOptions = nil

print("ams environment and strain characterization passed")
