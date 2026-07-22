ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local TestStats = ArmorMakesSense.Testing.TestStats or {}
ArmorMakesSense.Testing.TestStats = TestStats

local function shouldBlockWrite()
    return Utils.getExecutionRole() == "multiplayer_client"
end

local function getStats(player)
    return Utils.safeMethod(player, "getStats")
end

local function writeUnitStat(player, value, directMethod, characterStat)
    if shouldBlockWrite() then
        return false
    end
    local stats = getStats(player)
    if not stats then
        return false
    end
    local clamped = Utils.clamp(tonumber(value) or 0, 0, 1)
    if type(stats[directMethod]) == "function" then
        Utils.safeMethod(stats, directMethod, clamped)
        return true
    end
    if CharacterStat and characterStat and type(stats.set) == "function" then
        Utils.safeMethod(stats, "set", characterStat, clamped)
        return true
    end
    return false
end

function TestStats.setThirst(player, value)
    return writeUnitStat(player, value, "setThirst", CharacterStat and CharacterStat.THIRST)
end

function TestStats.setDiscomfort(player, value)
    if shouldBlockWrite() then
        return false
    end
    local stats = getStats(player)
    if not stats then
        return false
    end
    local clamped = Utils.clamp(tonumber(value) or 0, 0, 100)
    if type(stats.setDiscomfort) == "function" then
        Utils.safeMethod(stats, "setDiscomfort", clamped)
        return true
    end
    if CharacterStat and CharacterStat.DISCOMFORT and type(stats.set) == "function" then
        Utils.safeMethod(stats, "set", CharacterStat.DISCOMFORT, clamped)
        return true
    end
    return false
end

function TestStats.setWetness(player, value)
    if shouldBlockWrite() then
        return false
    end
    local clamped = Utils.clamp(tonumber(value) or 0, 0, 100)
    local stats = getStats(player)
    if stats and CharacterStat and CharacterStat.WETNESS then
        Utils.safeMethod(stats, "set", CharacterStat.WETNESS, clamped)
    end
    local body = Utils.safeMethod(player, "getBodyDamage")
    if body then
        Utils.safeMethod(body, "setWetness", clamped)
    end
    return stats ~= nil or body ~= nil
end

function TestStats.setBodyTemperature(player, value)
    if shouldBlockWrite() then
        return false
    end
    local clamped = Utils.clamp(tonumber(value) or 37.0, 34.0, 41.0)
    local stats = getStats(player)
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        Utils.safeMethod(stats, "set", CharacterStat.TEMPERATURE, clamped)
    end
    local body = Utils.safeMethod(player, "getBodyDamage")
    if body then
        Utils.safeMethod(body, "setTemperature", clamped)
    end
    return stats ~= nil or body ~= nil
end

return TestStats
