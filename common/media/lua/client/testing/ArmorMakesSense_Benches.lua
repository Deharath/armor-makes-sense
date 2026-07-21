ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.Benches = Testing.Benches or {}

local Benches = Testing.Benches
local C = {}

-- -----------------------------------------------------------------------------
-- Context wiring and bench helpers
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function Benches.setContext(context)
    C = context or {}
end

function Benches.getVanillaMuscleStrainFactor()
    local resolver = ctx("getVanillaMuscleStrainFactor")
    if type(resolver) ~= "function" then
        return nil
    end
    return resolver()
end

function Benches.getArmStiffnessSnapshot(player)
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if not body then
        return nil
    end
    local function partStiff(partType)
        if not partType then
            return 0
        end
        local part = ctx("safeMethod")(body, "getBodyPart", partType)
        return tonumber(part and ctx("safeMethod")(part, "getStiffness")) or 0
    end
    local hR = partStiff(BodyPartType and BodyPartType.Hand_R)
    local fR = partStiff(BodyPartType and BodyPartType.ForeArm_R)
    local uR = partStiff(BodyPartType and BodyPartType.UpperArm_R)
    local hL = partStiff(BodyPartType and BodyPartType.Hand_L)
    local fL = partStiff(BodyPartType and BodyPartType.ForeArm_L)
    local uL = partStiff(BodyPartType and BodyPartType.UpperArm_L)
    local avg = (hR + fR + uR + hL + fL + uL) / 6.0
    return {
        avg = avg,
        right = hR + fR + uR,
        left = hL + fL + uL,
    }
end

function Benches.getPerkLevelSafe(player, perk)
    if not player or not perk then
        return -1
    end
    return tonumber(ctx("safeMethod")(player, "getPerkLevel", perk)) or -1
end

function Benches.getStaticCombatSnapshot(player)
    local strength = Benches.getPerkLevelSafe(player, PerkFactory and PerkFactory.Perks and PerkFactory.Perks.Strength)
    local fitness = Benches.getPerkLevelSafe(player, PerkFactory and PerkFactory.Perks and PerkFactory.Perks.Fitness)
    local weapon = ctx("safeMethod")(player, "getUseHandWeapon") or ctx("safeMethod")(player, "getPrimaryHandItem")
    local weaponName = tostring(ctx("safeMethod")(weapon, "getDisplayName") or ctx("safeMethod")(weapon, "getType") or "none")
    local weaponSkill = tonumber(weapon and ctx("safeMethod")(weapon, "getWeaponSkill", player)) or -1
    return {
        strength = strength,
        fitness = fitness,
        weaponName = weaponName,
        weaponSkill = weaponSkill,
    }
end

function Benches.fitnessProbe()
    local player = ctx("getLocalPlayer") and ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("fitness probe failed: no local player")
        return false
    end
    local fitness = ctx("safeMethod")(player, "getFitness")
    if not fitness then
        ctx("logError")("fitness probe failed: fitness object unavailable")
        return false
    end

    local groups = {"arms", "chest", "abs", "legs"}
    local bits = {}
    for i = 1, #groups do
        local g = groups[i]
        local timer = tonumber(ctx("safeMethod")(fitness, "getCurrentExeStiffnessTimer", g)) or 0
        local inc = tonumber(ctx("safeMethod")(fitness, "getCurrentExeStiffnessInc", g)) or 0
        bits[#bits + 1] = string.format("%s(timer=%d,inc=%.2f)", g, timer, inc)
    end

    local arm = Benches.getArmStiffnessSnapshot(player)
    local armAvg = tonumber(arm and arm.avg) or 0
    local armL = tonumber(arm and arm.left) or 0
    local armR = tonumber(arm and arm.right) or 0
    local heavyLoad = -1
    local moodles = ctx("safeMethod")(player, "getMoodles")
    if moodles and MoodleType and MoodleType.HEAVY_LOAD then
        heavyLoad = tonumber(ctx("safeMethod")(moodles, "getMoodleLevel", MoodleType.HEAVY_LOAD)) or -1
    end
    local factor = Benches.getVanillaMuscleStrainFactor()

    ctx("log")(string.format(
        "[FITNESS_PROBE] %s arm(avg=%.2f,l=%.2f,r=%.2f) heavyLoad=%d vanillaFactor=%s",
        table.concat(bits, " "),
        armAvg,
        armL,
        armR,
        heavyLoad,
        tostring(factor)
    ))
    return true
end

return Benches
