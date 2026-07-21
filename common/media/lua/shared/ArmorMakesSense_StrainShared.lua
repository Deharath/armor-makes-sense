ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Strain = Core.Strain or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Strain = Core.Strain

-- -----------------------------------------------------------------------------
-- Muscle strain helpers
-- -----------------------------------------------------------------------------

function Strain.getVanillaMuscleStrainFactor()
    if SandboxOptions and SandboxOptions.instance and SandboxOptions.instance.muscleStrainFactor then
        local factor = tonumber(Utils.safeMethod(SandboxOptions.instance.muscleStrainFactor, "getValue"))
        if factor ~= nil then
            return factor
        end
    end
    return nil
end

function Strain.isMeleeStrainEligible(weapon)
    if not weapon then
        return false
    end
    local wtype = Utils.lower(Utils.safeMethod(weapon, "getType") or Utils.safeMethod(weapon, "getDisplayName") or "")
    if wtype == "bare hands" or wtype == "barehands" then
        return false
    end
    if not Utils.toBoolean(Utils.safeMethod(weapon, "isUseEndurance")) then
        return false
    end
    if Utils.toBoolean(Utils.safeMethod(weapon, "isRanged")) then
        return false
    end
    if Utils.toBoolean(Utils.safeMethod(weapon, "isAimedFirearm")) then
        return false
    end
    if Utils.toBoolean(Utils.safeMethod(weapon, "isBareHands")) then
        return false
    end
    return true
end

function Strain.computeArmorStrainExtra(options, profile)
    if not options or not options.EnableMuscleStrainModel or not profile then
        return 0
    end
    local maxExtra = Utils.clamp(tonumber(options.MuscleStrainMaxExtra) or 0.15, 0, 0.35)
    local startLoad = Utils.clamp(tonumber(options.MuscleStrainLoadStart) or 3.0, 0, 200)
    local fullLoad = Utils.clamp(tonumber(options.MuscleStrainLoadFull) or 22.0, 1, 200)
    if fullLoad <= startLoad then
        fullLoad = startLoad + 1.0
    end
    local load = Utils.clamp(tonumber(profile.swingChainLoad) or tonumber(profile.physicalLoad) or 0, 0, 600)
    if load <= startLoad then
        return 0
    end
    local t = Utils.clamp((load - startLoad) / (fullLoad - startLoad), 0, 1)
    return maxExtra * (t * math.sqrt(t))
end

function Strain.applyArmorStrainOverlay(player, weapon, options)
    if not options or not options.EnableMuscleStrainModel then
        return 0, 0
    end

    local vanillaStrainFactor = Strain.getVanillaMuscleStrainFactor()
    if vanillaStrainFactor ~= nil and vanillaStrainFactor <= 0 then
        return 0, vanillaStrainFactor
    end

    local useWeapon = weapon
    if not player or not Strain.isMeleeStrainEligible(useWeapon) then
        return 0, vanillaStrainFactor
    end

    local profile = LoadModel.computeWornProfile(player)
    local extra = Strain.computeArmorStrainExtra(options, profile)
    if extra <= 0 then
        return 0, vanillaStrainFactor
    end

    Utils.safeMethod(player, "addCombatMuscleStrain", useWeapon, 1, extra)

    return extra, vanillaStrainFactor
end

return Strain
