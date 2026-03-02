ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Utils = ArmorMakesSense.Utils or {}

local Utils = ArmorMakesSense.Utils

-- -----------------------------------------------------------------------------
-- Shared utility helpers
-- -----------------------------------------------------------------------------

local function invokeSafeMethod(target, methodName, onError, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        if type(onError) == "function" then
            onError(methodName, target, result)
        end
        return nil
    end
    return result
end

function Utils.clamp(value, minimum, maximum)
    local minV = tonumber(minimum) or 0
    local maxV = tonumber(maximum) or minV
    if minV > maxV then
        minV, maxV = maxV, minV
    end

    local v = tonumber(value)
    if v == nil or v ~= v then
        return minV
    end
    if v < minV then
        return minV
    end
    if v > maxV then
        return maxV
    end
    return v
end

function Utils.softNorm(value, pivot, maxNorm)
    local v = math.max(0, tonumber(value) or 0)
    local p = math.max(0.001, tonumber(pivot) or 1.0)
    local m = math.max(0.001, tonumber(maxNorm) or 1.0)
    local ratio = v / (v + p)
    return Utils.clamp(ratio * m, 0, m)
end

function Utils.toBoolean(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "string" then
        local lowered = string.lower(value)
        return lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "on"
    end
    if type(value) == "number" then
        return value ~= 0
    end
    return false
end

function Utils.lower(value)
    if not value then
        return ""
    end
    return string.lower(tostring(value))
end

function Utils.containsAny(text, patterns)
    if text == "" then
        return false
    end
    for _, pattern in ipairs(patterns) do
        if string.find(text, pattern, 1, true) then
            return true
        end
    end
    return false
end

function Utils.safeMethod(target, methodName, ...)
    return invokeSafeMethod(target, methodName, nil, ...)
end

function Utils.safeMethodWithOptions(target, methodName, options, ...)
    local onError = type(options) == "table" and options.onError or nil
    return invokeSafeMethod(target, methodName, onError, ...)
end

function Utils.safeMethodFromDeps(deps, target, methodName, ...)
    local depSafeMethod = deps and deps.safeMethod
    if type(depSafeMethod) == "function" then
        return depSafeMethod(target, methodName, ...)
    end
    local onError = deps and deps.onSafeMethodError
    return invokeSafeMethod(target, methodName, onError, ...)
end

return Utils
