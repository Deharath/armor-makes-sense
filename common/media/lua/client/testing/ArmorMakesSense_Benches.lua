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

return Benches
