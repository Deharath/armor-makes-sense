ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchUtils = Testing.BenchUtils or {}

local BenchUtils = Testing.BenchUtils
local CoreUtils = ArmorMakesSense and ArmorMakesSense.Utils

-- -----------------------------------------------------------------------------
-- Core utility delegates (prefer CoreUtils, inline fallback)
-- -----------------------------------------------------------------------------

function BenchUtils.clamp(value, minimum, maximum)
    if CoreUtils and type(CoreUtils.clamp) == "function" then
        return CoreUtils.clamp(value, minimum, maximum)
    end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function BenchUtils.safeMethod(target, methodName, ...)
    if CoreUtils and type(CoreUtils.safeMethod) == "function" then
        return CoreUtils.safeMethod(target, methodName, ...)
    end
    if not target then return nil end
    local method = target[methodName]
    if type(method) ~= "function" then return nil end
    local ok, result = pcall(method, target, ...)
    if not ok then return nil end
    return result
end

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

function BenchUtils.nowMinutes(ctxRef)
    local fn = ctxRef and ctxRef("getWorldAgeMinutes")
    if type(fn) == "function" then
        return tonumber(fn()) or 0
    end
    return 0
end

return BenchUtils
