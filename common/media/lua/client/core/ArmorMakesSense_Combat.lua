ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Options = require "ArmorMakesSense_Options"
local Strain = require "ArmorMakesSense_StrainShared"

local Core = ArmorMakesSense.Core
Core.Combat = Core.Combat or {}

local Combat = Core.Combat

function Combat.onPlayerAttackFinished(attacker, weapon)
    if ClientRuntime.isDisabled() or not attacker then
        return
    end
    local player = ClientRuntime.getLocalPlayer()
    if not player or attacker ~= player then
        return
    end

    local options = Options.get()
    if not options.EnableMuscleStrainModel or not weapon then
        return
    end

    Strain.applyArmorStrainOverlay(player, weapon, options)
end

return Combat
