ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Logger = ArmorMakesSense.Logger or {}

local Logger = ArmorMakesSense.Logger
local emitted = {}

local function callBoolean(fn)
    if type(fn) ~= "function" then
        return false
    end
    local ok, value = pcall(fn)
    return ok and value == true
end

local function hasDevMod()
    if type(getActivatedMods) ~= "function" then
        return false
    end
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods or type(mods.contains) ~= "function" then
        return false
    end
    local containsOk, contains = pcall(mods.contains, mods, "ArmorMakesSenseDev")
    return containsOk and contains == true
end

function Logger.isVerbose()
    return callBoolean(rawget(_G, "isDebugEnabled")) or hasDevMod()
end

local function emit(level, message)
    local suffix = level and ("[" .. tostring(level) .. "]") or ""
    print("[ArmorMakesSense]" .. suffix .. " " .. tostring(message))
end

local function emitOnce(level, key, message)
    local resolvedKey = tostring(level or "INFO") .. ":" .. tostring(key or message)
    if emitted[resolvedKey] then
        return false
    end
    emitted[resolvedKey] = true
    emit(level, message)
    return true
end

function Logger.info(message)
    emit(nil, message)
end

function Logger.warn(message)
    emit("WARN", message)
end

function Logger.error(message)
    emit("ERROR", message)
end

function Logger.debug(message)
    if Logger.isVerbose() then
        emit("DEBUG", message)
    end
end

function Logger.infoOnce(key, message)
    return emitOnce(nil, key, message)
end

function Logger.warnOnce(key, message)
    return emitOnce("WARN", key, message)
end

function Logger.errorOnce(key, message)
    return emitOnce("ERROR", key, message)
end

function Logger.debugOnce(key, message)
    if not Logger.isVerbose() then
        return false
    end
    return emitOnce("DEBUG", key, message)
end

return Logger
