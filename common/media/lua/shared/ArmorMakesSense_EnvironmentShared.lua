ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Environment = Core.Environment or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Environment = Core.Environment

-- -----------------------------------------------------------------------------
-- Environment + activity sampling
-- -----------------------------------------------------------------------------

function Environment.getPostureLabel(player)
    if Utils.toBoolean(Utils.safeMethod(player, "isAsleep")) then
        return "sleep"
    end
    if Utils.toBoolean(Utils.safeMethod(player, "isSitOnGround")) then
        return "sit_ground"
    end
    if Utils.toBoolean(Utils.safeMethod(player, "isSeatedInVehicle")) then
        return "sit_vehicle"
    end
    return "stand"
end

local function activityFactorForLabel(options, label)
    if label == "sleep" then
        return 0
    end
    if label == "sprint" then
        return Utils.clamp(tonumber(options.ActivitySprint) or 1.35, 0.2, 1.8)
    end
    if label == "run" then
        return Utils.clamp(tonumber(options.ActivityJog) or 1.0, 0.2, 1.8)
    end
    if label == "walk" then
        return Utils.clamp(tonumber(options.ActivityWalk) or 0.75, 0.2, 1.8)
    end
    return Utils.clamp(tonumber(options.ActivityIdle) or 0.35, 0.2, 1.8)
end

function Environment.resolveActivity(player, options)
    local moving = Utils.toBoolean(Utils.safeMethod(player, "isPlayerMoving"))
        or Utils.toBoolean(Utils.safeMethod(player, "isMoving"))

    local label = "idle"
    if Utils.toBoolean(Utils.safeMethod(player, "isAsleep")) then
        label = "sleep"
    elseif Utils.toBoolean(Utils.safeMethod(player, "isSprinting")) then
        label = "sprint"
    elseif Utils.toBoolean(Utils.safeMethod(player, "isRunning")) then
        label = "run"
    elseif moving then
        label = "walk"
    end

    return {
        label = label,
        factor = activityFactorForLabel(options or {}, label),
    }
end

return Environment
