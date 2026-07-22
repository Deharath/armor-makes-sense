ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.Reset = Testing.Reset or {}

local Reset = Testing.Reset
local Stats = ArmorMakesSense.Core.Stats
local TestStats = ArmorMakesSense.Testing.TestStats
local C = {}

local function ctx(name)
    return C[name]
end

function Reset.setContext(context)
    C = context or {}
end

local function shouldBlockMpWrite()
    return ctx("isMultiplayer")() and ctx("isClientSide")()
end

function Reset.resetMuscleStrain(player)
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if not body then
        return 0
    end
    local parts = ctx("safeMethod")(body, "getBodyParts")
    local n = tonumber(parts and ctx("safeMethod")(parts, "size")) or 0
    local changed = 0
    for i = 0, n - 1 do
        local part = ctx("safeMethod")(parts, "get", i)
        if part then
            ctx("safeMethod")(part, "setStiffness", 0.0)
            ctx("safeMethod")(part, "setAdditionalPain", 0.0)
            changed = changed + 1
        end
    end
    return changed
end

local function setStatIfPresent(stats, charStat, directMethod, value)
    local wrote = false
    if directMethod and ctx("hasFunction")(stats, directMethod) then
        ctx("safeMethod")(stats, directMethod, value)
        wrote = true
    end
    if charStat and ctx("hasFunction")(stats, "set") then
        ctx("safeMethod")(stats, "set", charStat, value)
        wrote = true
    end
    return wrote
end

local function resetBodyDamageState(player)
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if not body then
        return 0
    end

    ctx("safeMethod")(body, "RestoreToFullHealth")
    ctx("safeMethod")(body, "setOverallBodyHealth", 100.0)
    ctx("safeMethod")(body, "setInfectionTime", 0.0)
    ctx("safeMethod")(body, "setInfectionGrowthRate", 0.0)
    ctx("safeMethod")(body, "setInfectionMortalityDuration", 0.0)
    ctx("safeMethod")(body, "setIsFakeInfected", false)
    ctx("safeMethod")(body, "setReduceFakeInfection", false)
    ctx("safeMethod")(body, "setHealthFromFoodTimer", 0.0)

    local parts = ctx("safeMethod")(body, "getBodyParts")
    local n = tonumber(parts and ctx("safeMethod")(parts, "size")) or 0
    local changed = 0
    for i = 0, n - 1 do
        local part = ctx("safeMethod")(parts, "get", i)
        if part then
            ctx("safeMethod")(part, "setBleeding", false)
            ctx("safeMethod")(part, "setBleedingTime", 0.0)
            ctx("safeMethod")(part, "setCut", false)
            ctx("safeMethod")(part, "setCutTime", 0.0)
            ctx("safeMethod")(part, "setScratched", false, false)
            ctx("safeMethod")(part, "setScratchTime", 0.0)
            ctx("safeMethod")(part, "setDeepWounded", false)
            ctx("safeMethod")(part, "setDeepWoundTime", 0.0)
            ctx("safeMethod")(part, "SetBitten", false)
            ctx("safeMethod")(part, "setBiteTime", 0.0)
            ctx("safeMethod")(part, "setInfectedWound", false)
            ctx("safeMethod")(part, "setWoundInfectionLevel", 0.0)
            ctx("safeMethod")(part, "setHaveGlass", false)
            ctx("safeMethod")(part, "setHaveBullet", false, 0)
            ctx("safeMethod")(part, "setFractureTime", 0.0)
            ctx("safeMethod")(part, "setSplint", false, 0.0)
            ctx("safeMethod")(part, "setSplintFactor", 0.0)
            ctx("safeMethod")(part, "setStitched", false)
            ctx("safeMethod")(part, "setStitchTime", 0.0)
            ctx("safeMethod")(part, "setBandaged", false, 0.0)
            ctx("safeMethod")(part, "setBandageLife", 0.0)
            ctx("safeMethod")(part, "setNeedBurnWash", false)
            ctx("safeMethod")(part, "setLastTimeBurnWash", 0.0)
            changed = changed + 1
        end
    end

    return changed
end

local function resetThermoregulatorState(player)
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if not body then
        return false
    end

    local thermoregulator = ctx("safeMethod")(body, "getThermoregulator")
    if thermoregulator then
        ctx("safeMethod")(thermoregulator, "reset")
    end

    ctx("safeMethod")(body, "setColdDamageStage", 0.0)
    return thermoregulator ~= nil
end

function Reset.resetCharacterToEquilibrium(player)
    if shouldBlockMpWrite() then
        return 0
    end
    local stats = ctx("safeMethod")(player, "getStats")
    if stats then
        Stats.setEndurance(player, 1.0)
        Stats.setFatigue(player, 0.0)
        TestStats.setThirst(player, 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.HUNGER, "setHunger", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.STRESS, "setStress", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.PANIC, "setPanic", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.BOREDOM, "setBoredom", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.UNHAPPINESS, "setUnhappyness", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.DRUNKENNESS, "setDrunkenness", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.PAIN, "setPain", 0.0)
    end

    TestStats.setWetness(player, 0.0)
    resetBodyDamageState(player)
    resetThermoregulatorState(player)
    TestStats.setBodyTemperature(player, 37.0)
    TestStats.setDiscomfort(player, 0.0)
    ctx("safeMethod")(player, "setRunning", false)
    ctx("safeMethod")(player, "setSprinting", false)
    return Reset.resetMuscleStrain(player)
end

return Reset
