ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = ArmorMakesSense.Core.Stats or {}
ArmorMakesSense.Core.Stats = Stats

local warned = {}

local function logErrorOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    print("[ArmorMakesSense][ERROR] " .. tostring(message))
end

local function shouldBlockWrite()
    return Utils.getExecutionRole() == "multiplayer_client"
end

local function getStats(player)
    return Utils.safeMethod(player, "getStats")
end

local function readStat(player, directMethod, characterStat, warningKey)
    local stats = getStats(player)
    if not stats then
        return nil
    end
    local value = tonumber(Utils.safeMethod(stats, directMethod))
    if value ~= nil then
        return value
    end
    if CharacterStat and characterStat then
        return tonumber(Utils.safeMethod(stats, "get", characterStat))
    end
    if warningKey then
        logErrorOnce(warningKey, "Unable to read " .. tostring(warningKey) .. " stat.")
    end
    return nil
end

local function writeStat(player, value, directMethod, characterStat, warningKey)
    if shouldBlockWrite() then
        return
    end
    local stats = getStats(player)
    if not stats then
        return
    end
    value = Utils.clamp(value, 0, 1)
    if type(stats[directMethod]) == "function" then
        Utils.safeMethod(stats, directMethod, value)
        return
    end
    if CharacterStat and characterStat then
        Utils.safeMethod(stats, "set", characterStat, value)
        return
    end
    if warningKey then
        logErrorOnce(warningKey, "Unable to write " .. tostring(warningKey) .. " stat.")
    end
end

function Stats.getEndurance(player)
    return readStat(player, "getEndurance", CharacterStat and CharacterStat.ENDURANCE, "ENDURANCE")
end

function Stats.setEndurance(player, value)
    writeStat(player, value, "setEndurance", CharacterStat and CharacterStat.ENDURANCE, "ENDURANCE")
end

function Stats.getFatigue(player)
    return readStat(player, "getFatigue", CharacterStat and CharacterStat.FATIGUE, "FATIGUE")
end

function Stats.setFatigue(player, value)
    writeStat(player, value, "setFatigue", CharacterStat and CharacterStat.FATIGUE, "FATIGUE")
end

function Stats.getThirst(player)
    return readStat(player, "getThirst", CharacterStat and CharacterStat.THIRST, "THIRST")
end

function Stats.getDiscomfort(player)
    return readStat(player, "getDiscomfort", CharacterStat and CharacterStat.DISCOMFORT)
end

function Stats.getWetness(player)
    local stats = getStats(player)
    if stats and CharacterStat and CharacterStat.WETNESS then
        local wet = tonumber(Utils.safeMethod(stats, "get", CharacterStat.WETNESS))
        if wet ~= nil then
            return wet
        end
    end
    local body = Utils.safeMethod(player, "getBodyDamage")
    return body and tonumber(Utils.safeMethod(body, "getWetness")) or nil
end

function Stats.getBodyTemperature(player)
    local stats = getStats(player)
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        local temp = tonumber(Utils.safeMethod(stats, "get", CharacterStat.TEMPERATURE))
        if temp ~= nil then
            return temp
        end
    end
    local bodyDamage = Utils.safeMethod(player, "getBodyDamage")
    return bodyDamage and tonumber(Utils.safeMethod(bodyDamage, "getTemperature")) or nil
end

function Stats.getMetabolicRate(player)
    local bodyDamage = Utils.safeMethod(player, "getBodyDamage")
    local thermoregulator = bodyDamage and Utils.safeMethod(bodyDamage, "getThermoregulator")
    return thermoregulator and tonumber(Utils.safeMethod(thermoregulator, "getMetabolicRate")) or nil
end

return Stats
