ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.BreathingClassifier = ArmorMakesSense.BreathingClassifier or {}

local BreathingClassifier = ArmorMakesSense.BreathingClassifier

local function lower(text)
    if text == nil then
        return ""
    end
    return string.lower(tostring(text))
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function contains(text, pattern)
    return string.find(lower(text), tostring(pattern), 1, true) ~= nil
end

local function endsWith(text, suffix)
    local t = tostring(text or "")
    local s = tostring(suffix or "")
    if s == "" then
        return true
    end
    if #s > #t then
        return false
    end
    return string.sub(t, #t - #s + 1) == s
end

local function normalizeTag(tagText)
    local tag = lower(tagText)
    local colon = string.find(tag, ":", 1, true)
    if colon ~= nil then
        return string.sub(tag, colon + 1)
    end
    return tag
end

local function collectTags(item, scriptItem)
    local out = {}

    local function addFrom(target)
        local tags = safeCall(target, "getTags")
        if not tags then
            return
        end
        local size = tonumber(safeCall(tags, "size")) or 0
        for i = 0, size - 1 do
            local tag = normalizeTag(safeCall(tags, "get", i))
            if tag ~= "" then
                out[tag] = true
            end
        end
    end

    addFrom(item)
    addFrom(scriptItem)
    return out
end

local function tagPresent(tags, name)
    return tags[tostring(name)] == true
end

local function bodyLocationClass(locationName)
    local loc = lower(locationName)
    if contains(loc, "maskfull") then
        return "maskfull"
    end
    if contains(loc, "maskeyes") then
        return "face_covering"
    end
    if contains(loc, "fullsuithead") then
        return "fullsuithead"
    end
    if contains(loc, "mask") then
        return "mask"
    end
    return ""
end

local function tokenizeIdentity(identity)
    local out = {}
    for token in string.gmatch(lower(identity), "[a-z0-9]+") do
        if token ~= "" then
            out[token] = true
        end
    end
    return out
end

local function hasExactOrSuffixToken(tokens, needle)
    if tokens[tostring(needle)] == true then
        return true
    end
    for token, present in pairs(tokens) do
        if present == true and endsWith(token, needle) then
            return true
        end
    end
    return false
end

local function respiratoryKeywordClass(identity)
    local text = lower(identity)
    if text == "" then
        return nil
    end
    local tokens = tokenizeIdentity(text)
    if hasExactOrSuffixToken(tokens, "gasmask") then
        return "sealed_mask"
    end
    if hasExactOrSuffixToken(tokens, "respirator") then
        return "respirator"
    end
    if hasExactOrSuffixToken(tokens, "weldingmask") then
        return "face_covering"
    end
    if tokens["hazmat"] == true or hasExactOrSuffixToken(tokens, "hazmatsuit") then
        return "sealed_suit"
    end
    if hasExactOrSuffixToken(tokens, "dustmask")
        or hasExactOrSuffixToken(tokens, "surgicalmask")
        or hasExactOrSuffixToken(tokens, "bandanamask")
    then
        return "face_covering"
    end
    return nil
end

local function classRank(class)
    if class == "face_covering" then
        return 1
    end
    if class == "respirator" then
        return 2
    end
    if class == "sealed_mask" then
        return 3
    end
    if class == "sealed_suit" then
        return 4
    end
    return 0
end

local function strongerClass(left, right)
    if classRank(right) > classRank(left) then
        return right
    end
    return left
end

function BreathingClassifier.computeSignals(item, scriptItem, wornLocation)
    scriptItem = scriptItem or safeCall(item, "getScriptItem")
    local locationName = lower(wornLocation or safeCall(item, "getBodyLocation") or safeCall(scriptItem, "getBodyLocation"))
    local itemType = lower(safeCall(item, "getType") or safeCall(scriptItem, "getType"))
    local fullType = lower(safeCall(item, "getFullType") or safeCall(scriptItem, "getFullType"))
    local identity = fullType ~= "" and fullType or itemType
    local tags = collectTags(item, scriptItem)

    local slotClass = bodyLocationClass(locationName)
    local hasFilter = not contains(identity, "nofilter")
    local class = "none"
    local tagClass = nil
    local keywordClass = respiratoryKeywordClass(identity)
    local hasDecorativeTag = tagPresent(tags, "ismemento")
        or tagPresent(tags, "cosmetic")
        or tagPresent(tags, "decorative")
    local slotFloorClass = "none"

    if tagPresent(tags, "hazmatsuit") or tagPresent(tags, "scba") then
        tagClass = "sealed_suit"
    elseif tagPresent(tags, "scbanotank") then
        tagClass = "sealed_mask"
    elseif tagPresent(tags, "gasmask") or tagPresent(tags, "gasmasknofilter") then
        tagClass = "sealed_mask"
    elseif tagPresent(tags, "respirator") or tagPresent(tags, "respiratornofilter") then
        tagClass = "respirator"
    elseif tagPresent(tags, "weldingmask") then
        tagClass = "face_covering"
    end

    if slotClass == "fullsuithead" then
        slotFloorClass = "sealed_suit"
    elseif slotClass == "maskfull" then
        slotFloorClass = "face_covering"
    elseif slotClass == "face_covering" or slotClass == "mask" then
        slotFloorClass = "face_covering"
    end

    class = slotFloorClass
    if tagClass ~= nil then
        class = tagClass
    elseif hasDecorativeTag then
        class = slotFloorClass
    else
        class = strongerClass(class, keywordClass)
    end

    local breathingLoad = 0
    local thermalLoad = 0
    if class == "face_covering" then
        breathingLoad = 0
        thermalLoad = 0
    elseif class == "respirator" then
        if hasFilter then
            breathingLoad = 3.30
            thermalLoad = 1.35
        else
            breathingLoad = 0.90
            thermalLoad = 0.45
        end
    elseif class == "sealed_mask" then
        if hasFilter then
            breathingLoad = 3.75
            thermalLoad = 1.35
        else
            breathingLoad = 1.35
            thermalLoad = 0.45
        end
    elseif class == "sealed_suit" then
        breathingLoad = 3.75
        thermalLoad = 1.35
    end

    return {
        class = class,
        hasFilter = hasFilter,
        breathingLoad = breathingLoad,
        thermalLoad = thermalLoad,
        reasons = {
            slotClass = slotClass,
            slotFloorClass = slotFloorClass,
            tagClass = tagClass,
            keywordClass = keywordClass,
            decorativeTag = hasDecorativeTag,
        },
    }
end

return BreathingClassifier
