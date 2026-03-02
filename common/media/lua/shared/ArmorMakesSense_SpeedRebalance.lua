-- SpeedRebalance — Design Rationale
--
-- This module globally zeroes DiscomfortModifier on all wearable items and
-- overrides RunSpeedModifier / CombatSpeedModifier for known protective gear.
--
-- Why zero discomfort globally:
--   Vanilla discomfort is an abstract accumulating stat that penalizes wearing
--   any gear over time. AMS replaces it entirely with a physics-based load
--   model (endurance drain, thermal pressure, breathing restriction, muscle
--   strain, sleep recovery). Leaving vanilla discomfort active would double-
--   count the cost of armor and create confusing interactions where players
--   see both a "discomfort" moodle and AMS-driven endurance effects.
--   Zeroing it ensures AMS is the single source of truth for armor tradeoffs.
--
-- Why override speed modifiers per-item:
--   Vanilla speed penalties on crafted/found armor are often inconsistent —
--   elbow pads and greaves sometimes carry identical penalties despite very
--   different physical bulk. This table normalises values by body region:
--   leg armor penalises run speed, arm/shoulder armor penalises combat speed,
--   and light pads impose no penalty at all.

ArmorMakesSense = ArmorMakesSense or {}

-- Module load guard.
if ArmorMakesSense._speedRebalanceLoaded then
    return
end
ArmorMakesSense._speedRebalanceLoaded = true
pcall(require, "ArmorMakesSense_ArmorClassifier")
pcall(require, "ArmorMakesSense_SlotCompat")

local function log(msg)
    print('[ArmorMakesSense] ' .. tostring(msg))
end

-- Deliberate duplicate of ArmorMakesSense_Utils.safeMethod.
-- shared/ modules load before client/ modules, so this file cannot import Utils.
local function safeMethod(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function safeScriptString(item, methodName)
    local value = safeMethod(item, methodName)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function safeDoParam(item, param)
    if not item then
        return false
    end
    local fn = item.DoParam
    if type(fn) ~= "function" then
        return false
    end
    local ok, err = pcall(fn, item, param)
    if not ok then
        print("[ArmorMakesSense] DoParam failed: " .. tostring(err) .. " param=" .. tostring(param))
    end
    return ok
end

local function safeScriptNumber(item, methodName)
    local value = safeMethod(item, methodName)
    return tonumber(value)
end

ArmorMakesSense._originalDiscomfort = ArmorMakesSense._originalDiscomfort or {}

local function cacheOriginalDiscomfort(item)
    if not item then
        return
    end
    local fullType = safeScriptString(item, "getFullType")
    if fullType == "" then
        return
    end
    local origDiscomfort = safeScriptNumber(item, "getDiscomfortModifier") or 0
    if origDiscomfort > 0 then
        ArmorMakesSense._originalDiscomfort[fullType] = origDiscomfort
    end
end

-- Speed override data (authoritative values; do not reorder or retune here).
local overrides = {
    ["Base.AthleticCup"] = { run = 0.98, combat = 0.99 },
    ["Base.Chainmail_Hand_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Chainmail_SleeveFull_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Chainmail_SleeveFull_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Codpiece_Leather"] = { run = 0.98, combat = 0.99 },
    ["Base.Codpiece_Metal"] = { run = 0.97, combat = 0.99 },
    ["Base.Cuirass_BasicBone"] = { run = 0.98, combat = 0.99 },
    ["Base.Cuirass_Bone"] = { run = 0.98, combat = 0.99 },
    ["Base.Cuirass_CoatOfPlates"] = { run = 0.98, combat = 0.99 },
    ["Base.Cuirass_Magazine"] = { run = 0.98, combat = 0.99 },
    ["Base.Cuirass_Metal"] = { run = 0.97, combat = 0.99 },
    ["Base.Cuirass_MetalScrap"] = { run = 0.97, combat = 0.99 },
    ["Base.Cuirass_Tire"] = { run = 0.97, combat = 0.99 },
    ["Base.Cuirass_Wood"] = { run = 0.98, combat = 0.99 },
    ["Base.ElbowPad_Left"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Left_Leather"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Left_Military"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Left_Sport"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Left_TINT"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Left_Tactical"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Left_Workman"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right_Leather"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right_Military"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right_Sport"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right_TINT"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right_Tactical"] = { run = 1.00, combat = 1.00 },
    ["Base.ElbowPad_Right_Workman"] = { run = 1.00, combat = 1.00 },
    ["Base.Gaiter_Left"] = { run = 0.97, combat = 1.00 },
    ["Base.Gaiter_Right"] = { run = 0.97, combat = 1.00 },
    ["Base.Gloves_IceHockeyGloves"] = { run = 1.00, combat = 0.98 },
    ["Base.Gloves_IceHockeyGloves_Black"] = { run = 1.00, combat = 0.98 },
    ["Base.Gloves_IceHockeyGloves_Blue"] = { run = 1.00, combat = 0.98 },
    ["Base.Gloves_IceHockeyGloves_White"] = { run = 1.00, combat = 0.98 },
    ["Base.GreaveBodyArmour_Left"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Left_Army"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Left_Civ"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Left_Desert"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Left_Police"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Left_SWAT"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Right"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Right_Army"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Right_Civ"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Right_Desert"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Right_Police"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBodyArmour_Right_SWAT"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBone_Left"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveBone_Right"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveMagazine_Left"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveMagazine_Right"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveScrap_Left"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveScrap_Right"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveTire_Left"] = { run = 0.90, combat = 1.00 },
    ["Base.GreaveTire_Right"] = { run = 0.90, combat = 1.00 },
    ["Base.GreaveWood_Left"] = { run = 0.94, combat = 1.00 },
    ["Base.GreaveWood_Right"] = { run = 0.94, combat = 1.00 },
    ["Base.Greave_Left"] = { run = 0.97, combat = 1.00 },
    ["Base.Greave_Right"] = { run = 0.97, combat = 1.00 },
    ["Base.Hat_BaseballHelmet"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_BaseballHelmet_KY"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_BaseballHelmet_Rangers"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_BaseballHelmet_Z"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_CrashHelmetFULL"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_CrashHelmetFULL_Black"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_CrashHelmetFULL_Black_Spiked"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_CrashHelmetFULL_Spiked"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_CrashHelmet_Police"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_CrashHelmet_Stars"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_FootballHelmet"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_FootballHelmet_Blue"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_FootballHelmet_Red"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_FootballHelmet_White"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_MetalHelmet"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_MetalScrapHelmet"] = { run = 1.00, combat = 1.00 },
    ["Base.Hat_RiotHelmet"] = { run = 1.00, combat = 0.99 },
    ["Base.Hat_SPHhelmet"] = { run = 1.00, combat = 0.99 },
    ["Base.Jacket_Fireman"] = { run = 0.95, combat = 0.98 },
    ["Base.Kneepad_Left"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Left_Leather"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Left_Military"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Left_Sport"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Left_TINT"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Left_Tactical"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Left_Workman"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right_Leather"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right_Military"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right_Sport"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right_TINT"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right_Tactical"] = { run = 1.00, combat = 1.00 },
    ["Base.Kneepad_Right_Workman"] = { run = 1.00, combat = 1.00 },
    ["Base.SCBA"] = { run = 1.00, combat = 1.00 },
    ["Base.SCBA_notank"] = { run = 1.00, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_L"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_L_Baseball"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_L_IceHockey"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_L_Metal"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_L_Protective"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_R"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_R_Baseball"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_R_IceHockey"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_R_Metal"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuardSpike_R_Protective"] = { run = 0.90, combat = 1.00 },
    ["Base.ShinKneeGuard_L"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_L_Baseball"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_L_IceHockey"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_L_Metal"] = { run = 0.94, combat = 1.00 },
    ["Base.ShinKneeGuard_L_Protective"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_L_TINT"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_R"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_R_Baseball"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_R_IceHockey"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_R_Metal"] = { run = 0.94, combat = 1.00 },
    ["Base.ShinKneeGuard_R_Protective"] = { run = 0.97, combat = 1.00 },
    ["Base.ShinKneeGuard_R_TINT"] = { run = 0.97, combat = 1.00 },
    ["Base.Shoulderpad_ArticulatedSpike_L"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_ArticulatedSpike_R"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_Articulated_L_Metal"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Articulated_R_Metal"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Bone_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Bone_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Football_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Football_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Football_Spiked_R"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_MetalScrap_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_MetalScrap_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_MetalSpikeScrap_L"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_MetalSpikeScrap_R"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_MetalSpike_L"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_MetalSpike_R"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpad_Metal_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Metal_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Tire_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Tire_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Wood_L"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpad_Wood_R"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpads_Football"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpads_FootballOnTop"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpads_FootballOnTop_Spiked"] = { run = 1.00, combat = 0.98 },
    ["Base.Shoulderpads_IceHockey"] = { run = 1.00, combat = 0.99 },
    ["Base.Shoulderpads_IceHockeyOnTop"] = { run = 1.00, combat = 0.99 },
    ["Base.ThighBodyArmour_L"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_L_Army"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_L_Civ"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_L_Desert"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_L_Police"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_L_SWAT"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_R"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_R_Army"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_R_Civ"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_R_Desert"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_R_Police"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBodyArmour_R_SWAT"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBone_L"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighBone_R"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighMagazine_L"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighMagazine_R"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighMetalSpike_L"] = { run = 0.90, combat = 1.00 },
    ["Base.ThighMetalSpike_R"] = { run = 0.90, combat = 1.00 },
    ["Base.ThighMetal_L"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighMetal_R"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighProtective_L"] = { run = 0.97, combat = 1.00 },
    ["Base.ThighProtective_R"] = { run = 0.97, combat = 1.00 },
    ["Base.ThighScrapMetalSpike_L"] = { run = 0.90, combat = 1.00 },
    ["Base.ThighScrapMetalSpike_R"] = { run = 0.90, combat = 1.00 },
    ["Base.ThighScrapMetal_L"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighScrapMetal_R"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighTire_L"] = { run = 0.90, combat = 1.00 },
    ["Base.ThighTire_R"] = { run = 0.90, combat = 1.00 },
    ["Base.ThighWood_L"] = { run = 0.94, combat = 1.00 },
    ["Base.ThighWood_R"] = { run = 0.94, combat = 1.00 },
    ["Base.Thigh_ArticMetal_L"] = { run = 0.94, combat = 1.00 },
    ["Base.Thigh_ArticMetal_R"] = { run = 0.94, combat = 1.00 },
    ["Base.VambraceBone_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceBone_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceMagazine_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceMagazine_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceScrap_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceScrap_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceSpikeScrap_Left"] = { run = 1.00, combat = 0.98 },
    ["Base.VambraceSpikeScrap_Right"] = { run = 1.00, combat = 0.98 },
    ["Base.VambraceSpike_Left"] = { run = 1.00, combat = 0.98 },
    ["Base.VambraceSpike_Right"] = { run = 1.00, combat = 0.98 },
    ["Base.VambraceTire_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceTire_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceWood_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.VambraceWood_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Left_Army"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Left_Civ"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Left_Desert"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Left_Police"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Left_SWAT"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Right_Army"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Right_Civ"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Right_Desert"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Right_Police"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_BodyArmour_Right_SWAT"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_FullMetal_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_FullMetal_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_LeatherSpike_Left"] = { run = 1.00, combat = 0.98 },
    ["Base.Vambrace_LeatherSpike_Right"] = { run = 1.00, combat = 0.98 },
    ["Base.Vambrace_Leather_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_Left"] = { run = 1.00, combat = 0.99 },
    ["Base.Vambrace_Right"] = { run = 1.00, combat = 0.99 },
    ["Base.Vest_CatcherVest"] = { run = 0.98, combat = 0.99 },
    ["Base.Vest_CatcherVest_Blue"] = { run = 0.98, combat = 0.99 },
    ["Base.Vest_CatcherVest_Green"] = { run = 0.98, combat = 0.99 },
    ["Base.Vest_CatcherVest_Red"] = { run = 0.98, combat = 0.99 },

    -- Civilian scope expansion (formula_scope_expansion_spec_v1, Change 3)
    -- Military
    ["Base.Boilersuit_Flying"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyCamoDesert"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyCamoDesertNew"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyCamoGreen"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyCamoMilius"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyCamoTigerStripe"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyCamoUrban"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_ArmyOliveDrab"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_CoatArmy"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_NavyBlue"] = { run = 0.99, combat = 1.00 },
    ["Base.Shoes_ArmyBoots"] = { run = 0.99, combat = 1.00 },
    ["Base.Shoes_ArmyBootsDesert"] = { run = 0.99, combat = 1.00 },

    -- Police / SWAT
    ["Base.Boilersuit_SWAT"] = { run = 0.98, combat = 1.00 },
    ["Base.Jacket_Police"] = { run = 0.98, combat = 1.00 },
    ["Base.Jacket_Ranger"] = { run = 0.98, combat = 1.00 },
    ["Base.Jacket_Sheriff"] = { run = 0.98, combat = 1.00 },

    -- Boilersuits / Coveralls
    ["Base.Boilersuit"] = { run = 0.97, combat = 1.00 },
    ["Base.Boilersuit_BlueRed"] = { run = 0.97, combat = 1.00 },
    ["Base.Boilersuit_Prisoner"] = { run = 0.98, combat = 1.00 },
    ["Base.Boilersuit_PrisonerKhaki"] = { run = 0.98, combat = 1.00 },
    ["Base.Boilersuit_Yellow"] = { run = 0.97, combat = 1.00 },

    -- Sports gear
    ["Base.Shinpad_HockeyGoalie_L"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_L_Blue"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_L_Red"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_L_White"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_R"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_R_Blue"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_R_Red"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_HockeyGoalie_R_White"] = { run = 0.90, combat = 1.00 },
    ["Base.Shinpad_L"] = { run = 0.98, combat = 1.00 },
    ["Base.Shinpad_L_Blue"] = { run = 0.98, combat = 1.00 },
    ["Base.Shinpad_L_Rigid"] = { run = 0.97, combat = 1.00 },
    ["Base.Shinpad_L_White"] = { run = 0.98, combat = 1.00 },
    ["Base.Shinpad_R"] = { run = 0.98, combat = 1.00 },
    ["Base.Shinpad_R_Blue"] = { run = 0.98, combat = 1.00 },
    ["Base.Shinpad_R_Rigid"] = { run = 0.97, combat = 1.00 },
    ["Base.Shinpad_R_White"] = { run = 0.98, combat = 1.00 },

    -- Padded / winter
    ["Base.JacketLong_Santa"] = { run = 0.96, combat = 0.99 },
    ["Base.JacketLong_SantaGreen"] = { run = 0.96, combat = 0.99 },
    ["Base.JacketLong_SheepSkin"] = { run = 0.96, combat = 0.99 },
    ["Base.Jacket_Padded"] = { run = 0.96, combat = 0.99 },
    ["Base.Jacket_PaddedDOWN"] = { run = 0.96, combat = 0.99 },
    ["Base.Jacket_Padded_HuntingCamo"] = { run = 0.96, combat = 0.99 },
    ["Base.Jacket_Padded_HuntingCamoDOWN"] = { run = 0.96, combat = 0.99 },
    ["Base.Jacket_SheepSkin"] = { run = 0.96, combat = 0.99 },
    ["Base.Trousers_Padded"] = { run = 0.96, combat = 0.99 },
    ["Base.Trousers_Padded_HuntingCamo"] = { run = 0.96, combat = 0.99 },
    ["Base.Trousers_SheepSkin"] = { run = 0.96, combat = 0.99 },

    -- Ponchos
    ["Base.PonchoGarbageBag"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoGarbageBagDOWN"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoGreen"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoGreenDOWN"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoTarp"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoTarpDOWN"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoYellow"] = { run = 0.97, combat = 1.00 },
    ["Base.PonchoYellowDOWN"] = { run = 0.97, combat = 1.00 },

    -- Other jackets
    ["Base.Jacket_Chef"] = { run = 0.99, combat = 1.00 },
    ["Base.Jacket_HuntingCamo"] = { run = 0.99, combat = 1.00 },

    -- Fireman consistency amendment
    ["Base.Trousers_Fireman"] = { run = 0.95, combat = 0.98 },

    -- Missed armor symmetry
    ["Base.Chainmail_Hand_L"] = { run = 1.00, combat = 0.99 },
    ["Base.GreaveSpikeScrap_Left"] = { run = 0.90, combat = 1.00 },
    ["Base.GreaveSpikeScrap_Right"] = { run = 0.90, combat = 1.00 },
    ["Base.GreaveSpike_Left"] = { run = 0.90, combat = 1.00 },
    ["Base.GreaveSpike_Right"] = { run = 0.90, combat = 1.00 },
    ["Base.Shoulderpad_Football_Spiked_L"] = { run = 1.00, combat = 0.98 },
    ["Base.Vambrace_Leather_Left"] = { run = 1.00, combat = 0.99 },
}

-- Reslot map for AMS custom body locations.
local slotReslots = {
    {
        slot = "ams:shoulderpad_left",
        fullTypes = {
            "Base.Shoulderpad_ArticulatedSpike_L",
            "Base.Shoulderpad_Articulated_L_Metal",
            "Base.Shoulderpad_Bone_L",
            "Base.Shoulderpad_Football_L",
            "Base.Shoulderpad_Football_Spiked_L",
            "Base.Shoulderpad_MetalScrap_L",
            "Base.Shoulderpad_MetalSpikeScrap_L",
            "Base.Shoulderpad_MetalSpike_L",
            "Base.Shoulderpad_Metal_L",
            "Base.Shoulderpad_Tire_L",
            "Base.Shoulderpad_Wood_L",
        },
    },
    {
        slot = "ams:shoulderpad_right",
        fullTypes = {
            "Base.Shoulderpad_ArticulatedSpike_R",
            "Base.Shoulderpad_Articulated_R_Metal",
            "Base.Shoulderpad_Bone_R",
            "Base.Shoulderpad_Football_R",
            "Base.Shoulderpad_Football_Spiked_R",
            "Base.Shoulderpad_MetalScrap_R",
            "Base.Shoulderpad_MetalSpikeScrap_R",
            "Base.Shoulderpad_MetalSpike_R",
            "Base.Shoulderpad_Metal_R",
            "Base.Shoulderpad_Tire_R",
            "Base.Shoulderpad_Wood_R",
        },
    },
    {
        slot = "ams:sport_shoulderpad",
        fullTypes = {
            "Base.Shoulderpads_Football",
            "Base.Shoulderpads_IceHockey",
        },
    },
    {
        slot = "ams:sport_shoulderpad_on_top",
        fullTypes = {
            "Base.Shoulderpads_FootballOnTop",
            "Base.Shoulderpads_FootballOnTop_Spiked",
            "Base.Shoulderpads_IceHockeyOnTop",
        },
    },
    {
        slot = "ams:forearm_left",
        fullTypes = {
            "Base.VambraceBone_Left",
            "Base.VambraceMagazine_Left",
            "Base.VambraceScrap_Left",
            "Base.VambraceSpikeScrap_Left",
            "Base.VambraceSpike_Left",
            "Base.VambraceTire_Left",
            "Base.VambraceWood_Left",
            "Base.Vambrace_BodyArmour_Left",
            "Base.Vambrace_BodyArmour_Left_Army",
            "Base.Vambrace_BodyArmour_Left_Civ",
            "Base.Vambrace_BodyArmour_Left_Desert",
            "Base.Vambrace_BodyArmour_Left_Police",
            "Base.Vambrace_BodyArmour_Left_SWAT",
            "Base.Vambrace_FullMetal_Left",
            "Base.Vambrace_LeatherSpike_Left",
            "Base.Vambrace_Leather_Left",
            "Base.Vambrace_Left",
        },
    },
    {
        slot = "ams:forearm_right",
        fullTypes = {
            "Base.VambraceBone_Right",
            "Base.VambraceMagazine_Right",
            "Base.VambraceScrap_Right",
            "Base.VambraceSpikeScrap_Right",
            "Base.VambraceSpike_Right",
            "Base.VambraceTire_Right",
            "Base.VambraceWood_Right",
            "Base.Vambrace_BodyArmour_Right",
            "Base.Vambrace_BodyArmour_Right_Army",
            "Base.Vambrace_BodyArmour_Right_Civ",
            "Base.Vambrace_BodyArmour_Right_Desert",
            "Base.Vambrace_BodyArmour_Right_Police",
            "Base.Vambrace_BodyArmour_Right_SWAT",
            "Base.Vambrace_FullMetal_Right",
            "Base.Vambrace_LeatherSpike_Right",
            "Base.Vambrace_Leather_Right",
            "Base.Vambrace_Right",
        },
    },
    {
        slot = "ams:cuirass",
        fullTypes = {
            "Base.Cuirass_Bone",
            "Base.Cuirass_CoatOfPlates",
            "Base.Cuirass_Magazine",
            "Base.Cuirass_Metal",
            "Base.Cuirass_MetalScrap",
            "Base.Cuirass_Tire",
            "Base.Cuirass_Wood",
        },
    },
    {
        slot = "ams:torso_extra_vest_bullet",
        fullTypes = {
            "Base.Vest_BulletArmy",
            "Base.Vest_BulletCivilian",
            "Base.Vest_BulletDesert",
            "Base.Vest_BulletDesertNew",
            "Base.Vest_BulletOliveDrab",
            "Base.Vest_BulletPolice",
            "Base.Vest_BulletSWAT",
            "Base.Vest_CatcherVest",
            "Base.Vest_CatcherVest_Blue",
            "Base.Vest_CatcherVest_Green",
            "Base.Vest_CatcherVest_Red",
        },
    },
}

local function applySlotReslots(sm)
    local changed = 0
    local missing = 0
    for _, def in ipairs(slotReslots) do
        for _, fullType in ipairs(def.fullTypes) do
            local item = sm:getItem(fullType)
            if item then
                cacheOriginalDiscomfort(item)
                safeDoParam(item, "BodyLocation = " .. def.slot)
                safeDoParam(item, "DiscomfortModifier = 0.00")
                changed = changed + 1
            else
                missing = missing + 1
            end
        end
    end
    return changed, missing
end

local function applySpeedRebalance()
    local sm = ScriptManager and ScriptManager.instance
    if not sm then
        return
    end
    local changed = 0
    local missing = 0
    for fullType, values in pairs(overrides) do
        local item = sm:getItem(fullType)
        if item then
            cacheOriginalDiscomfort(item)
            if values.run then
                safeDoParam(item, string.format('RunSpeedModifier = %.2f', values.run))
            end
            if values.combat then
                safeDoParam(item, string.format('CombatSpeedModifier = %.2f', values.combat))
            end
            -- Remove vanilla discomfort accumulation source on known protective gear.
            safeDoParam(item, 'DiscomfortModifier = 0.00')
            changed = changed + 1
        else
            missing = missing + 1
        end
    end

    local slotReslotChanged, slotReslotMissing = applySlotReslots(sm)
    missing = missing + slotReslotMissing

    -- Global supersession: zero discomfort on all wearable script items.
    local discomfortZeroed = 0
    local ok, err = pcall(function()
        local all = sm:getAllItems()
        local n = tonumber(all and all:size()) or 0
        for i = 0, n - 1 do
            local it = all:get(i)
            if it then
                local bodyLoc = safeScriptString(it, "getBodyLocation")
                local canEquip = safeScriptString(it, "canBeEquipped")
                if bodyLoc ~= "" or canEquip ~= "" then
                    cacheOriginalDiscomfort(it)
                    safeDoParam(it, 'DiscomfortModifier = 0.00')
                    discomfortZeroed = discomfortZeroed + 1
                end
            end
        end
    end)
    if not ok then
        print("[ArmorMakesSense] SpeedRebalance global scan failed: " .. tostring(err))
    end

    log(string.format(
        'Speed rebalance applied to %d items (missing: %d). Discomfort zeroed on %d wearable items. Slot reslots applied=%d.',
        changed, missing, discomfortZeroed, slotReslotChanged
    ))
end

-- Lifecycle hooks.
if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(applySpeedRebalance)
end
if Events and Events.OnMainMenuEnter and type(Events.OnMainMenuEnter.Add) == "function" then
    Events.OnMainMenuEnter.Add(applySpeedRebalance)
end
if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(applySpeedRebalance)
end
