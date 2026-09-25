ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Environment = Core.Environment or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Environment = Core.Environment

local function flag(player, methodName)
    return Utils.toBoolean(Utils.safeMethod(player, methodName))
end

-- Mirrors the posture split vanilla uses in IsoPlayer.updateEndurance.
function Environment.getPostureLabel(player)
    if flag(player, "isAsleep") then
        return "sleep"
    end
    if flag(player, "isSeatedInVehicle") then
        return "sit_vehicle"
    end
    if flag(player, "isSitOnGround") or flag(player, "isSittingOnFurniture") or flag(player, "isResting") then
        return "sit"
    end
    return "stand"
end

function Environment.isResting(postureLabel)
    return postureLabel == "sit" or postureLabel == "sit_vehicle"
end

function Environment.resolveActivity(player)
    if flag(player, "isAsleep") then
        return "sleep"
    end
    if flag(player, "isSprinting") then
        return "sprint"
    end
    if flag(player, "isRunning") then
        return "run"
    end
    if flag(player, "isPlayerMoving") or flag(player, "isMoving") then
        return "walk"
    end
    return "idle"
end

return Environment
