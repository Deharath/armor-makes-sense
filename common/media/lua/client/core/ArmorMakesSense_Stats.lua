ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Stats = Core.Stats or {}

local Stats = Core.Stats
local C = {}

-- -----------------------------------------------------------------------------
-- Character stat IO + equilibrium reset
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function Stats.setContext(context)
    C = context or {}
end

local function shouldBlockMpWrite()
    local isMultiplayer = type(ctx("isMultiplayer")) == "function" and ctx("isMultiplayer")()
    local isClientSide = type(ctx("isClientSide")) == "function" and ctx("isClientSide")()
    return isMultiplayer and isClientSide
end

function Stats.getEndurance(player)
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return nil
    end
    local value = tonumber(ctx("safeMethod")(stats, "getEndurance"))
    if value ~= nil then
        return value
    end
    if CharacterStat and CharacterStat.ENDURANCE then
        return tonumber(ctx("safeMethod")(stats, "get", CharacterStat.ENDURANCE))
    end
    ctx("logErrorOnce")("missing_stat_read_endurance", "Unable to read ENDURANCE stat (no direct or CharacterStat path).")
    return nil
end

function Stats.setEndurance(player, value)
    if shouldBlockMpWrite() then
        return
    end
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return
    end
    value = ctx("clamp")(value, 0, 1)
    if stats.setEndurance then
        ctx("safeMethod")(stats, "setEndurance", value)
        return
    end
    if CharacterStat and CharacterStat.ENDURANCE then
        ctx("safeMethod")(stats, "set", CharacterStat.ENDURANCE, value)
        return
    end
    ctx("logErrorOnce")("missing_stat_write_endurance", "Unable to write ENDURANCE stat (no direct or CharacterStat path).")
end

function Stats.getFatigue(player)
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return nil
    end
    local value = tonumber(ctx("safeMethod")(stats, "getFatigue"))
    if value ~= nil then
        return value
    end
    if CharacterStat and CharacterStat.FATIGUE then
        return tonumber(ctx("safeMethod")(stats, "get", CharacterStat.FATIGUE))
    end
    ctx("logErrorOnce")("missing_stat_read_fatigue", "Unable to read FATIGUE stat (no direct or CharacterStat path).")
    return nil
end

function Stats.setFatigue(player, value)
    if shouldBlockMpWrite() then
        return
    end
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return
    end
    value = ctx("clamp")(value, 0, 1)
    if stats.setFatigue then
        ctx("safeMethod")(stats, "setFatigue", value)
        return
    end
    if CharacterStat and CharacterStat.FATIGUE then
        ctx("safeMethod")(stats, "set", CharacterStat.FATIGUE, value)
        return
    end
    ctx("logErrorOnce")("missing_stat_write_fatigue", "Unable to write FATIGUE stat (no direct or CharacterStat path).")
end

function Stats.getThirst(player)
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return nil
    end
    local value = tonumber(ctx("safeMethod")(stats, "getThirst"))
    if value ~= nil then
        return value
    end
    if CharacterStat and CharacterStat.THIRST then
        return tonumber(ctx("safeMethod")(stats, "get", CharacterStat.THIRST))
    end
    ctx("logErrorOnce")("missing_stat_read_thirst", "Unable to read THIRST stat (no direct or CharacterStat path).")
    return nil
end

function Stats.setThirst(player, value)
    if shouldBlockMpWrite() then
        return
    end
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return
    end
    value = ctx("clamp")(value, 0, 1)
    if stats.setThirst then
        ctx("safeMethod")(stats, "setThirst", value)
        return
    end
    if CharacterStat and CharacterStat.THIRST then
        ctx("safeMethod")(stats, "set", CharacterStat.THIRST, value)
        return
    end
    ctx("logErrorOnce")("missing_stat_write_thirst", "Unable to write THIRST stat (no direct or CharacterStat path).")
end

function Stats.getDiscomfort(player)
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return nil
    end
    local value = tonumber(ctx("safeMethod")(stats, "getDiscomfort"))
    if value ~= nil then
        return value
    end
    if CharacterStat and CharacterStat.DISCOMFORT then
        return tonumber(ctx("safeMethod")(stats, "get", CharacterStat.DISCOMFORT))
    end
    return nil
end

function Stats.setWetness(player, value)
    if shouldBlockMpWrite() then
        return
    end
    value = ctx("clamp")(tonumber(value) or 0, 0, 100)
    local stats = ctx("safeMethod")(player, "getStats")
    if stats and CharacterStat and CharacterStat.WETNESS then
        ctx("safeMethod")(stats, "set", CharacterStat.WETNESS, value)
    end
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if body then
        ctx("safeMethod")(body, "setWetness", value)
    end
end

function Stats.getWetness(player)
    local stats = ctx("safeMethod")(player, "getStats")
    if stats and CharacterStat and CharacterStat.WETNESS then
        local wet = tonumber(ctx("safeMethod")(stats, "get", CharacterStat.WETNESS))
        if wet ~= nil then
            return wet
        end
    end
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if body then
        return tonumber(ctx("safeMethod")(body, "getWetness"))
    end
    return nil
end

function Stats.setDiscomfort(player, value)
    -- Discomfort suppression is an immediate client UX fix (fidget/moodle noise),
    -- so allow this write in MP while other gameplay-affecting stats remain blocked.
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        return
    end
    value = ctx("clamp")(value, 0, 100)
    if stats.setDiscomfort then
        ctx("safeMethod")(stats, "setDiscomfort", value)
        return
    end
    if CharacterStat and CharacterStat.DISCOMFORT then
        ctx("safeMethod")(stats, "set", CharacterStat.DISCOMFORT, value)
    end
end

function Stats.setBodyTemperature(player, value)
    if shouldBlockMpWrite() then
        return
    end
    value = ctx("clamp")(tonumber(value) or 37.0, 34.0, 41.0)
    local stats = ctx("safeMethod")(player, "getStats")
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        ctx("safeMethod")(stats, "set", CharacterStat.TEMPERATURE, value)
    end
    local bodyDamage = ctx("safeMethod")(player, "getBodyDamage")
    if bodyDamage then
        ctx("safeMethod")(bodyDamage, "setTemperature", value)
    end
end

function Stats.getBodyTemperature(player)
    local stats = ctx("safeMethod")(player, "getStats")
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        local temp = tonumber(ctx("safeMethod")(stats, "get", CharacterStat.TEMPERATURE))
        if temp ~= nil then
            return temp
        end
    end
    local bodyDamage = ctx("safeMethod")(player, "getBodyDamage")
    if bodyDamage then
        local temp = tonumber(ctx("safeMethod")(bodyDamage, "getTemperature"))
        if temp ~= nil then
            return temp
        end
    end
    return nil
end

function Stats.resetMuscleStrain(player)
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

local NUTRITION_BASELINES = {}

local function captureNutritionBaseline(player)
    local nutrition = ctx("safeMethod")(player, "getNutrition")
    if not nutrition then
        return nil
    end

    local baseline = {
        calories = tonumber(ctx("safeMethod")(nutrition, "getCalories")),
        carbohydrates = tonumber(ctx("safeMethod")(nutrition, "getCarbohydrates")),
        lipids = tonumber(ctx("safeMethod")(nutrition, "getLipids")),
        proteins = tonumber(ctx("safeMethod")(nutrition, "getProteins")),
        weight = tonumber(ctx("safeMethod")(nutrition, "getWeight")),
    }

    NUTRITION_BASELINES[player] = baseline
    return baseline
end

local function resetNutritionState(player)
    local nutrition = ctx("safeMethod")(player, "getNutrition")
    if not nutrition then
        return false
    end

    local baseline = NUTRITION_BASELINES[player] or captureNutritionBaseline(player)
    if not baseline then
        return false
    end

    if baseline.calories ~= nil then
        ctx("safeMethod")(nutrition, "setCalories", baseline.calories)
    end
    if baseline.carbohydrates ~= nil then
        ctx("safeMethod")(nutrition, "setCarbohydrates", baseline.carbohydrates)
    end
    if baseline.lipids ~= nil then
        ctx("safeMethod")(nutrition, "setLipids", baseline.lipids)
    end
    if baseline.proteins ~= nil then
        ctx("safeMethod")(nutrition, "setProteins", baseline.proteins)
    end
    if baseline.weight ~= nil then
        ctx("safeMethod")(nutrition, "setWeight", baseline.weight)
    end

    return true
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

function Stats.resetCharacterToEquilibrium(player)
    if shouldBlockMpWrite() then
        return 0
    end
    local stats = ctx("safeMethod")(player, "getStats")
    if stats then
        Stats.setEndurance(player, 1.0)
        Stats.setFatigue(player, 0.0)
        Stats.setThirst(player, 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.HUNGER, "setHunger", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.STRESS, "setStress", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.PANIC, "setPanic", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.BOREDOM, "setBoredom", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.UNHAPPINESS, "setUnhappyness", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.DRUNKENNESS, "setDrunkenness", 0.0)
        setStatIfPresent(stats, CharacterStat and CharacterStat.PAIN, "setPain", 0.0)
    end

    Stats.setWetness(player, 0.0)
    resetBodyDamageState(player)
    resetNutritionState(player)
    resetThermoregulatorState(player)
    Stats.setBodyTemperature(player, 37.0)
    Stats.setDiscomfort(player, 0.0)
    ctx("safeMethod")(player, "setRunning", false)
    ctx("safeMethod")(player, "setSprinting", false)
    NUTRITION_BASELINES[player] = nil

    local partsReset = Stats.resetMuscleStrain(player)
    return partsReset
end

return Stats
