ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Combat = Core.Combat or {}

local Combat = Core.Combat
local C = {}

-- -----------------------------------------------------------------------------
-- Combat event forwarding
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function Combat.setContext(context)
    C = context or {}
end

function Combat.onWeaponSwing(attacker, weapon)
    return
end

function Combat.onPlayerAttackFinished(attacker, weapon)
    if ctx("isRuntimeDisabled")() or ctx("isMultiplayer")() then
        return
    end
    if not attacker then
        return
    end
    local player = ctx("getLocalPlayer")()
    if not player or attacker ~= player then
        return
    end

    local options = ctx("getOptions")()
    if not options.EnableMuscleStrainModel then
        return
    end

    if not weapon then
        return
    end

    local equipped = ctx("safeMethod")(player, "getUseHandWeapon") or ctx("safeMethod")(player, "getPrimaryHandItem")
    if not equipped or weapon ~= equipped then
        return
    end

    ctx("applyArmorStrainOverlay")(player, weapon, nil, options)
end

return Combat
