ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchUtils = Testing.BenchUtils or {}

local BenchUtils = Testing.BenchUtils
local CoreUtils = ArmorMakesSense.Utils

BenchUtils.clamp = CoreUtils.clamp
BenchUtils.safeMethod = CoreUtils.safeMethod

-- -----------------------------------------------------------------------------
-- Testing-specific helpers
-- -----------------------------------------------------------------------------

function BenchUtils.toBoolArg(value)
    if value == nil then return false end
    local kind = type(value)
    if kind == "boolean" then return value end
    if kind == "number" then return value ~= 0 end
    local text = string.lower(tostring(value))
    return text == "1" or text == "true" or text == "yes" or text == "on"
end

function BenchUtils.boolTag(value)
    if value == nil then return "na" end
    return value and "true" or "false"
end

function BenchUtils.metricOrNa(value, decimals)
    local num = tonumber(value)
    if num == nil then return "na" end
    if decimals and tonumber(decimals) then
        return string.format("%." .. tostring(math.max(0, math.floor(tonumber(decimals)))) .. "f", num)
    end
    return tostring(num)
end

function BenchUtils.resolveThreshold(value, fallback, minValue)
    local parsed = tonumber(value)
    if parsed == nil then
        parsed = fallback
    end
    if minValue ~= nil and parsed < minValue then
        return minValue
    end
    return parsed
end

function BenchUtils.nowMinutes(ctxRef)
    local fn = ctxRef and ctxRef("getWorldAgeMinutes")
    if type(fn) == "function" then
        return tonumber(fn()) or 0
    end
    return 0
end

return BenchUtils
