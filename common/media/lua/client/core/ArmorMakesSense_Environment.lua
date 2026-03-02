ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Environment = Core.Environment or {}

local Environment = Core.Environment
local C = {}

-- -----------------------------------------------------------------------------
-- Environment + activity sampling
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

local COMBAT_LATCH_ATTACK_SECONDS = 15.0
local COMBAT_LATCH_AIM_SECONDS = 6.0

function Environment.setContext(context)
    C = context or {}
end

local function readThermoregulator(player)
    local safeMethod = ctx("safeMethod")
    if type(safeMethod) ~= "function" then
        return nil
    end
    local bodyDamage = safeMethod(player, "getBodyDamage")
    return bodyDamage and safeMethod(bodyDamage, "getThermoregulator") or nil
end

local function readAverageSkinTemperature(thermoregulator)
    local safeMethod = ctx("safeMethod")
    if type(safeMethod) ~= "function" or not thermoregulator then
        return nil
    end

    local nodeCount = math.max(0, math.floor(tonumber(safeMethod(thermoregulator, "getNodeSize")) or 0))
    local total = 0
    local samples = 0
    for i = 0, nodeCount - 1 do
        local node = safeMethod(thermoregulator, "getNode", i)
        local skin = tonumber(node and safeMethod(node, "getSkinCelcius") or nil)
        if skin ~= nil then
            total = total + skin
            samples = samples + 1
        end
    end

    if samples > 0 then
        return total / samples
    end

    return tonumber(safeMethod(thermoregulator, "getSkinCelcius"))
end

local function resolveCoreHeatPressure(player)
    local temp = nil
    if type(ctx("getBodyTemperature")) == "function" then
        temp = tonumber(ctx("getBodyTemperature")(player))
    end
    if not temp then
        return 0
    end

    local bandScale = 0.0
    if temp <= 37.0 then
        bandScale = 0.0
    elseif temp < 37.5 then
        bandScale = ((temp - 37.0) / 0.5) * 0.25
    elseif temp < 39.0 then
        bandScale = 0.25 + (((temp - 37.5) / 1.5) * 0.75)
    else
        bandScale = 1.0 + (((temp - 39.0) / 2.0) * 0.60)
    end
    return ctx("clamp")(bandScale, 0.0, 1.6)
end

function Environment.getPostureLabel(player)
    if ctx("toBoolean")(ctx("safeMethod")(player, "isAsleep")) then
        return "sleep"
    end
    if ctx("toBoolean")(ctx("safeMethod")(player, "isSitOnGround")) then
        return "sit_ground"
    end
    if ctx("toBoolean")(ctx("safeMethod")(player, "isSeatedInVehicle")) then
        return "sit_vehicle"
    end
    return "stand"
end

function Environment.getHeatFactor(player, options)
    local heatStrength = ctx("clamp")(options.HeatAmplifierStrength or 0.25, 0, 1.0)
    local hotPressure = nil

    local thermoregulator = readThermoregulator(player)
    local safeMethod = ctx("safeMethod")
    if thermoregulator and type(safeMethod) == "function" then
        local skinTemp = readAverageSkinTemperature(thermoregulator)
        local secondary = tonumber(safeMethod(thermoregulator, "getDbg_secTotal"))
        local primary = tonumber(safeMethod(thermoregulator, "getDbg_primTotal"))
        local perspiration = math.max(0, secondary or 0)
        local vasodilation = math.max(0, primary or 0)
        local fluidsMultiplier = tonumber(safeMethod(thermoregulator, "getFluidsMultiplier"))
        local coreTemp = tonumber(safeMethod(thermoregulator, "getCoreTemperature"))

        local skinHot = ctx("clamp")(((tonumber(skinTemp) or 33.0) - 33.4) / 2.0, 0, 1.8)
        local perspirationNorm = ctx("clamp")(perspiration / 0.26, 0, 1.8)
        local vasodilationNorm = ctx("clamp")(vasodilation / 0.40, 0, 1.5)
        local fluidsNorm = ctx("clamp")(((tonumber(fluidsMultiplier) or 1.0) - 1.0) / 1.2, 0, 1.6)
        local coreHot = ctx("clamp")(((tonumber(coreTemp) or 37.0) - 37.0) / 0.8, 0, 1.6)

        hotPressure = ctx("clamp")(
            (skinHot * 0.45)
                + (perspirationNorm * 0.30)
                + (vasodilationNorm * 0.12)
                + (fluidsNorm * 0.08)
                + (coreHot * 0.05),
            0,
            1.6
        )
    end

    if hotPressure == nil then
        hotPressure = resolveCoreHeatPressure(player)
    end

    return 1.0 + (hotPressure * heatStrength)
end

function Environment.wetnessToFactor(wet, options)
    if not wet then
        return 1.0
    end
    local wetNorm = ctx("clamp")((tonumber(wet) or 0) / 100.0, 0, 1)
    return 1.0 + (wetNorm * ctx("clamp")(options.WetAmplifierStrength or 0.18, 0, 1.0))
end

function Environment.getWetFactor(player, options)
    local wet = nil
    if ctx("getWetness") then
        wet = ctx("getWetness")(player)
    end
    return Environment.wetnessToFactor(wet, options)
end

function Environment.getActivityFactor(player, options)
    local factor = options.ActivityIdle
    local moving = ctx("toBoolean")(ctx("safeMethod")(player, "isPlayerMoving"))
        or ctx("toBoolean")(ctx("safeMethod")(player, "isMoving"))
    local attackStarted = ctx("toBoolean")(ctx("safeMethod")(player, "isAttackStarted"))
    local isAiming = ctx("toBoolean")(ctx("safeMethod")(player, "isAiming"))
    if ctx("toBoolean")(ctx("safeMethod")(player, "isSprinting")) then
        factor = options.ActivitySprint
    elseif ctx("toBoolean")(ctx("safeMethod")(player, "isRunning")) then
        factor = options.ActivityJog
    elseif moving then
        factor = options.ActivityWalk
    elseif attackStarted or isAiming then
        factor = options.ActivityJog
    end
    return ctx("clamp")(tonumber(factor) or 1.0, 0.2, 1.8)
end

function Environment.getActivityLabel(player)
    local moving = ctx("toBoolean")(ctx("safeMethod")(player, "isPlayerMoving"))
        or ctx("toBoolean")(ctx("safeMethod")(player, "isMoving"))
    local isAiming = ctx("toBoolean")(ctx("safeMethod")(player, "isAiming"))
    local attackStarted = ctx("toBoolean")(ctx("safeMethod")(player, "isAttackStarted"))
    local nowMinutes = tonumber(type(ctx("getWorldAgeMinutes")) == "function" and ctx("getWorldAgeMinutes")() or 0) or 0
    local ensureState = ctx("ensureState")
    local state = type(ensureState) == "function" and ensureState(player) or nil
    local attackHoldMinutes = COMBAT_LATCH_ATTACK_SECONDS / 60.0
    local aimHoldMinutes = COMBAT_LATCH_AIM_SECONDS / 60.0

    if state and attackStarted then
        state.recentCombatUntilMinute = nowMinutes + attackHoldMinutes
    elseif state and isAiming then
        local current = tonumber(state.recentCombatUntilMinute) or 0
        local refreshed = nowMinutes + aimHoldMinutes
        if refreshed > current then
            state.recentCombatUntilMinute = refreshed
        end
    end

    if ctx("toBoolean")(ctx("safeMethod")(player, "isSprinting")) then
        if state then
            state.recentCombatUntilMinute = nil
        end
        return "sprint"
    end
    if ctx("toBoolean")(ctx("safeMethod")(player, "isRunning")) then
        if state then
            state.recentCombatUntilMinute = nil
        end
        return "run"
    end
    if moving then
        if state then
            state.recentCombatUntilMinute = nil
        end
        return "walk"
    end
    if state and tonumber(state.recentCombatUntilMinute) and nowMinutes <= tonumber(state.recentCombatUntilMinute) then
        return "combat"
    end
    return "idle"
end

return Environment
