ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Classifier = ArmorMakesSense.Classifier or {}

local Classifier = ArmorMakesSense.Classifier

-- Text cues for armor-like classification.
local ARMOR_KEYWORDS = {
    "armor", "armour", "vest", "plate", "kevlar", "ballistic", "riot", "tactical", "hazmat",
    "helmet", "mask", "respirator", "gas", "welding", "pads", "gauntlet", "greave", "mail"
}

local ARMOR_LOCATION_HINTS = {
    "torso", "vest", "bullet", "helmet", "mask", "neck", "forearm", "shin"
}

local PROTECTIVE_TAG_HINTS = {
    "gasmask", "respirator", "gasmasknofilter", "respiratornofilter",
    "hazmatsuit", "weldingmask", "bulletproof", "helmet", "armour", "armor", "protectivegear"
}

local function lower(text)
    if text == nil then
        return ""
    end
    return string.lower(tostring(text))
end

local function containsAny(text, terms)
    local t = lower(text)
    for i = 1, #terms do
        if string.find(t, terms[i], 1, true) then
            return true
        end
    end
    return false
end

-- Deliberate duplicate of ArmorMakesSense_Utils.safeMethod.
-- shared/ modules load before client/ modules, so this file cannot import Utils.
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

local function getNumber(item, scriptItem, methodName)
    local value = tonumber(safeCall(item, methodName))
    if value ~= nil then
        return value
    end
    return tonumber(safeCall(scriptItem, methodName)) or 0
end

local function hasAnyProtectiveTag(item, scriptItem)
    local function hasTagByScan(target)
        if not target then
            return false
        end
        local tags = safeCall(target, "getTags")
        if not tags then
            return false
        end
        local size = tonumber(safeCall(tags, "size")) or 0
        for i = 0, size - 1 do
            local tagText = lower(safeCall(tags, "get", i))
            if tagText ~= "" and containsAny(tagText, PROTECTIVE_TAG_HINTS) then
                return true
            end
        end
        return false
    end

    if hasTagByScan(item) or hasTagByScan(scriptItem) then
        return true
    end

    local displayCategory = lower(safeCall(item, "getDisplayCategory") or safeCall(scriptItem, "getDisplayCategory"))
    if displayCategory == "protectivegear" then
        return true
    end

    local bloodLocation = lower(safeCall(item, "getBloodClothingType") or safeCall(scriptItem, "getBloodClothingType"))
    if bloodLocation ~= "" and containsAny(bloodLocation, {"helmet", "mask"}) then
        return true
    end
    return false
end

function Classifier.computeArmorLikeSignals(item, scriptItem, wornLocation)
    scriptItem = scriptItem or safeCall(item, "getScriptItem")
    local locationName = lower(wornLocation or safeCall(item, "getBodyLocation") or safeCall(scriptItem, "getBodyLocation"))
    local itemName = lower(
        safeCall(item, "getDisplayName")
        or safeCall(item, "getName")
        or safeCall(item, "getType")
        or safeCall(item, "getFullType")
        or safeCall(item, "getFullName")
        or safeCall(scriptItem, "getDisplayName")
        or safeCall(scriptItem, "getName")
        or safeCall(scriptItem, "getType")
        or safeCall(scriptItem, "getFullType")
        or safeCall(scriptItem, "getFullName")
    )

    local scratch = getNumber(item, scriptItem, "getScratchDefense")
    local bite = getNumber(item, scriptItem, "getBiteDefense")
    local bullet = getNumber(item, scriptItem, "getBulletDefense")
    local neck = getNumber(item, scriptItem, "getNeckProtectionModifier")
    local discomfort = getNumber(item, scriptItem, "getDiscomfortModifier")
    local insulation = getNumber(item, scriptItem, "getInsulation")
    local wind = getNumber(item, scriptItem, "getWindResistance")
    local weight = tonumber(safeCall(item, "getActualWeight"))
        or tonumber(safeCall(item, "getWeight"))
        or tonumber(safeCall(scriptItem, "getActualWeight"))
        or tonumber(safeCall(scriptItem, "getWeight"))
        or 0

    local hasProtectiveTag = hasAnyProtectiveTag(item, scriptItem)
    local keywordMatch = containsAny(itemName, ARMOR_KEYWORDS)
    local locationMatch = containsAny(locationName, ARMOR_LOCATION_HINTS)

    local classifierDefenseScore = (scratch * 0.30) + (bite * 0.75) + (bullet * 1.25) + (neck * 0.45)
    local thermalScore = (insulation * 10.0) + (wind * 8.0)
    local confidence = classifierDefenseScore + (thermalScore * 0.18) + (math.max(discomfort, 0) * 0.55) + (weight * 0.40)
    if hasProtectiveTag then
        confidence = confidence + 4.0
    end
    if keywordMatch then
        confidence = confidence + 1.4
    end
    if locationMatch then
        confidence = confidence + 0.8
    end

    local strongDefense = classifierDefenseScore >= 8.0 or bullet >= 1.0 or bite >= 4.0 or scratch >= 8.0
    local mediumDefense = classifierDefenseScore >= 3.0 or bite >= 1.5 or scratch >= 3.0

    return {
        hasProtectiveTag = hasProtectiveTag,
        keywordMatch = keywordMatch,
        locationMatch = locationMatch,
        strongDefense = strongDefense,
        mediumDefense = mediumDefense,
        confidence = confidence,
        discomfort = discomfort,
        classifierDefenseScore = classifierDefenseScore,
        thermalScore = thermalScore,
        weight = weight,
        itemName = itemName,
        locationName = locationName,
    }
end

function Classifier.evaluateArmorLike(item, scriptItem, wornLocation)
    local signals = Classifier.computeArmorLikeSignals(item, scriptItem, wornLocation) or {}
    local strongDefense = signals.strongDefense == true
    local hasProtectiveTag = signals.hasProtectiveTag == true
    local keywordMatch = signals.keywordMatch == true
    local locationMatch = signals.locationMatch == true
    local mediumDefense = signals.mediumDefense == true
    local weight = tonumber(signals.weight) or 0
    local discomfort = tonumber(signals.discomfort) or 0

    local isArmorLike = false

    -- Civilian floor: lightweight items with no armor indicators are never armor,
    -- even if they have decent defense stats (e.g. B42 jeans, leather gloves).
    -- Real armor is both protective AND heavy/encumbering.
    local hasSomeIndicator = hasProtectiveTag or keywordMatch or locationMatch
    if not hasSomeIndicator and weight < 1.5 and discomfort <= 0.05 then
        isArmorLike = false
    elseif strongDefense then
        isArmorLike = true
    elseif hasProtectiveTag then
        isArmorLike = true
    elseif keywordMatch and (weight >= 1.2 or mediumDefense or discomfort > 0.15) then
        isArmorLike = true
    elseif locationMatch and strongDefense and weight >= 1.0 then
        isArmorLike = true
    end

    return {
        isArmorLike = isArmorLike,
        hasProtectiveTag = hasProtectiveTag,
        confidence = signals.confidence,
        discomfort = discomfort,
        classifierDefenseScore = signals.classifierDefenseScore,
        thermalScore = signals.thermalScore,
        weight = weight,
        itemName = signals.itemName,
        locationName = signals.locationName,
        keywordMatch = keywordMatch,
        locationMatch = locationMatch,
        strongDefense = strongDefense,
        mediumDefense = mediumDefense,
    }
end

Classifier.ARMOR_KEYWORDS = ARMOR_KEYWORDS
Classifier.ARMOR_LOCATION_HINTS = ARMOR_LOCATION_HINTS
Classifier.PROTECTIVE_TAG_HINTS = PROTECTIVE_TAG_HINTS
Classifier.hasAnyProtectiveTag = hasAnyProtectiveTag

return Classifier


