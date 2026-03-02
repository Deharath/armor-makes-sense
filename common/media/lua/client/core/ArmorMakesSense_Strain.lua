ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Strain = Core.Strain or {}

local Strain = Core.Strain
local C = {}

-- -----------------------------------------------------------------------------
-- Muscle strain helpers
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function Strain.setContext(context)
    C = context or {}
end

function Strain.getVanillaMuscleStrainFactor()
    if SandboxOptions and SandboxOptions.instance and SandboxOptions.instance.muscleStrainFactor then
        local factor = tonumber(ctx("safeMethod")(SandboxOptions.instance.muscleStrainFactor, "getValue"))
        if factor ~= nil then
            return factor
        end
    end
    return nil
end

function Strain.isMeleeStrainEligible(player, weapon, requireActiveAttack)
    if not player or not weapon then
        return false
    end
    local wtype = ctx("lower")(ctx("safeMethod")(weapon, "getType") or ctx("safeMethod")(weapon, "getDisplayName") or "")
    if wtype == "bare hands" or wtype == "barehands" then
        return false
    end
    if not ctx("toBoolean")(ctx("safeMethod")(weapon, "isUseEndurance")) then
        return false
    end
    if ctx("toBoolean")(ctx("safeMethod")(weapon, "isRanged")) then
        return false
    end
    if ctx("toBoolean")(ctx("safeMethod")(weapon, "isAimedFirearm")) then
        return false
    end
    if ctx("toBoolean")(ctx("safeMethod")(weapon, "isBareHands")) then
        return false
    end
    if requireActiveAttack ~= false and not ctx("toBoolean")(ctx("safeMethod")(player, "isActuallyAttackingWithMeleeWeapon")) then
        return false
    end
    return true
end

function Strain.computeArmorStrainExtra(options, profile)
    if not options or not options.EnableMuscleStrainModel or not profile then
        return 0
    end
    local maxExtra = ctx("clamp")(tonumber(options.MuscleStrainMaxExtra) or 0.15, 0, 0.35)
    local startLoad = ctx("clamp")(tonumber(options.MuscleStrainLoadStart) or 3.0, 0, 200)
    local fullLoad = ctx("clamp")(tonumber(options.MuscleStrainLoadFull) or 22.0, 1, 200)
    if fullLoad <= startLoad then
        fullLoad = startLoad + 1.0
    end
    local load = ctx("clamp")(tonumber(profile.swingChainLoad) or tonumber(profile.upperBodyLoad) or tonumber(profile.physicalLoad) or 0, 0, 600)
    if load <= startLoad then
        return 0
    end
    local t = ctx("clamp")((load - startLoad) / (fullLoad - startLoad), 0, 1)
    return maxExtra * (t * math.sqrt(t))
end

function Strain.applyArmorStrainOverlay(player, weapon, hitCount, options)
    if not options or not options.EnableMuscleStrainModel then
        return 0, 0
    end

    local vanillaStrainFactor = Strain.getVanillaMuscleStrainFactor()
    if vanillaStrainFactor ~= nil and vanillaStrainFactor <= 0 then
        return 0, vanillaStrainFactor
    end

    local useWeapon = weapon
    if not Strain.isMeleeStrainEligible(player, useWeapon) then
        return 0, vanillaStrainFactor
    end

    local profile = ctx("computeArmorProfile")(player)
    local extra = Strain.computeArmorStrainExtra(options, profile)
    if extra <= 0 then
        return 0, vanillaStrainFactor
    end

    local hc = tonumber(hitCount) or tonumber(ctx("safeMethod")(player, "getLastHitCount")) or 1
    if hc < 1 then
        hc = 1
    end
    ctx("safeMethod")(player, "addCombatMuscleStrain", useWeapon, hc, extra)

    return extra, vanillaStrainFactor
end

return Strain
