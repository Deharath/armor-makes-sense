ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Classifier = ArmorMakesSense.Classifier or {}

local Classifier = ArmorMakesSense.Classifier
local Utils = require "ArmorMakesSense_UtilsShared"

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

local lower = Utils.lower
local safeCall = Utils.safeMethod

local function containsAny(text, terms)
    return Utils.containsAny(lower(text), terms)
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
    -- Use stable script identifiers for keyword matching to avoid locale-dependent behavior.
    local itemName = lower(
        safeCall(item, "getFullType")
        or safeCall(item, "getType")
        or safeCall(item, "getName")
        or safeCall(item, "getFullName")
        or safeCall(scriptItem, "getFullType")
        or safeCall(scriptItem, "getType")
        or safeCall(scriptItem, "getName")
        or safeCall(scriptItem, "getFullName")
    )

    local scratch = getNumber(item, scriptItem, "getScratchDefense")
    local bite = getNumber(item, scriptItem, "getBiteDefense")
    local bullet = getNumber(item, scriptItem, "getBulletDefense")
    local neck = getNumber(item, scriptItem, "getNeckProtectionModifier")
    local discomfort = getNumber(item, scriptItem, "getDiscomfortModifier")
    local weight = tonumber(safeCall(item, "getActualWeight"))
        or tonumber(safeCall(item, "getWeight"))
        or tonumber(safeCall(scriptItem, "getActualWeight"))
        or tonumber(safeCall(scriptItem, "getWeight"))
        or 0

    local hasProtectiveTag = hasAnyProtectiveTag(item, scriptItem)
    local keywordMatch = containsAny(itemName, ARMOR_KEYWORDS)
    local locationMatch = containsAny(locationName, ARMOR_LOCATION_HINTS)

    local classifierDefenseScore = (scratch * 0.30) + (bite * 0.75) + (bullet * 1.25) + (neck * 0.45)
    local strongDefense = classifierDefenseScore >= 8.0 or bullet >= 1.0 or bite >= 4.0 or scratch >= 8.0
    local mediumDefense = classifierDefenseScore >= 3.0 or bite >= 1.5 or scratch >= 3.0

    return {
        hasProtectiveTag = hasProtectiveTag,
        keywordMatch = keywordMatch,
        locationMatch = locationMatch,
        strongDefense = strongDefense,
        mediumDefense = mediumDefense,
        discomfort = discomfort,
        classifierDefenseScore = classifierDefenseScore,
        weight = weight,
        itemName = itemName,
        locationName = locationName,
    }
end

function Classifier.evaluateArmorLikeSignals(signals)
    signals = signals or {}
    local strongDefense = signals.strongDefense == true
    local hasProtectiveTag = signals.hasProtectiveTag == true
    local keywordMatch = signals.keywordMatch == true
    local locationMatch = signals.locationMatch == true
    local mediumDefense = signals.mediumDefense == true
    local weight = tonumber(signals.weight) or 0
    local discomfort = tonumber(signals.discomfort) or 0

    local isArmorLike = false
    local reason = "no_match"

    -- Civilian floor: lightweight items with no armor indicators are never armor,
    -- even if they have decent defense stats (e.g. B42 jeans, leather gloves).
    -- Real armor is both protective AND heavy/encumbering.
    local hasSomeIndicator = hasProtectiveTag or keywordMatch or locationMatch
    if not hasSomeIndicator and weight < 1.5 and discomfort <= 0.05 then
        isArmorLike = false
        reason = "civilian_floor"
    elseif strongDefense then
        isArmorLike = true
        reason = "strong_defense"
    elseif hasProtectiveTag then
        isArmorLike = true
        reason = "protective_tag"
    elseif keywordMatch and (weight >= 1.2 or mediumDefense or discomfort > 0.15) then
        isArmorLike = true
        reason = "protective_identity"
    end

    return {
        isArmorLike = isArmorLike,
        reason = reason,
        hasProtectiveTag = hasProtectiveTag,
        discomfort = discomfort,
        classifierDefenseScore = signals.classifierDefenseScore,
        weight = weight,
        itemName = signals.itemName,
        locationName = signals.locationName,
        keywordMatch = keywordMatch,
        locationMatch = locationMatch,
        strongDefense = strongDefense,
        mediumDefense = mediumDefense,
    }
end

function Classifier.evaluateArmorLike(item, scriptItem, wornLocation)
    return Classifier.evaluateArmorLikeSignals(
        Classifier.computeArmorLikeSignals(item, scriptItem, wornLocation)
    )
end

return Classifier
