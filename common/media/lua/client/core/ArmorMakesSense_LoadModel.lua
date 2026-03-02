ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.LoadModel = Core.LoadModel or {}
local Classifier = ArmorMakesSense and ArmorMakesSense.Classifier

local LoadModel = Core.LoadModel
local C = {}

-- -----------------------------------------------------------------------------
-- Item-to-load transformation
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function LoadModel.setContext(context)
    C = context or {}
end

local function getItemOrScriptNumber(item, scriptItem, methodName)
    local value = tonumber(ctx("safeMethod")(item, methodName))
    if value ~= nil then
        return value
    end
    return tonumber(ctx("safeMethod")(scriptItem, methodName)) or 0
end

local function getOriginalDiscomfort(item, scriptItem)
    local fullType = tostring(ctx("safeMethod")(item, "getFullType") or ctx("safeMethod")(scriptItem, "getFullType") or "")
    local discomfortCache = ArmorMakesSense and ArmorMakesSense._originalDiscomfort or nil
    local cached = discomfortCache and discomfortCache[fullType]
    if cached ~= nil then
        return tonumber(cached) or 0
    end
    return getItemOrScriptNumber(item, scriptItem, "getDiscomfortModifier")
end

-- Minimal fallback for when Classifier module is unavailable.
-- Classifier.hasAnyProtectiveTag is the canonical source; this covers only the
-- DisplayCategory check so items aren't silently misclassified on load failure.
local function hasAnyProtectiveTagFallback(item, scriptItem)
    local displayCategory = ctx("lower")(ctx("safeMethod")(item, "getDisplayCategory") or ctx("safeMethod")(scriptItem, "getDisplayCategory"))
    return displayCategory == "protectivegear"
end

local UPPER_BODY_LOCATION_PATTERNS = {
    "torso", "chest", "back", "shoulder",
    "arm", "hand", "forearm", "elbow",
    "head", "neck", "face", "mask", "eye",
}

local LOWER_BODY_LOCATION_PATTERNS = {
    "leg", "knee", "shin", "foot", "shoe", "groin",
}

local SWING_CHAIN_LOCATION_PATTERNS = {
    "shoulder", "forearm", "elbow", "hand", "arm",
}

local SWING_CHAIN_EXCLUSIONS = {
    "shoulderholster",
}

local function locationHasAnyPattern(locationName, patterns)
    if locationName == "" then
        return false
    end
    for i = 1, #patterns do
        if string.find(locationName, patterns[i], 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function shouldCountAsUpperBodyLocation(locationName)
    local location = tostring(locationName or "")
    if locationHasAnyPattern(location, LOWER_BODY_LOCATION_PATTERNS) then
        return false
    end
    if locationHasAnyPattern(location, UPPER_BODY_LOCATION_PATTERNS) then
        return true
    end
    -- Conservative default: unknown body locations contribute.
    return true
end

local function isSwingChainLocation(locationName)
    local loc = tostring(locationName or "")
    if locationHasAnyPattern(loc, SWING_CHAIN_EXCLUSIONS) then
        return false
    end
    return locationHasAnyPattern(loc, SWING_CHAIN_LOCATION_PATTERNS)
end

function LoadModel.itemToArmorSignal(item, wornLocation)
    local scriptItem = ctx("safeMethod")(item, "getScriptItem")
    local isCosmetic = ctx("toBoolean")(ctx("safeMethod")(item, "isCosmetic") or ctx("safeMethod")(scriptItem, "isCosmetic"))
    if isCosmetic then
        return nil
    end
    local locationName = ctx("lower")(wornLocation or ctx("safeMethod")(item, "getBodyLocation") or ctx("safeMethod")(scriptItem, "getBodyLocation"))
    local itemName = ctx("lower")(ctx("safeMethod")(item, "getDisplayName") or ctx("safeMethod")(item, "getName") or ctx("safeMethod")(item, "getType"))

    local scratch = getItemOrScriptNumber(item, scriptItem, "getScratchDefense")
    local bite = getItemOrScriptNumber(item, scriptItem, "getBiteDefense")
    local bullet = getItemOrScriptNumber(item, scriptItem, "getBulletDefense")
    local neck = getItemOrScriptNumber(item, scriptItem, "getNeckProtectionModifier")
    local discomfort = getOriginalDiscomfort(item, scriptItem)
    local insulation = getItemOrScriptNumber(item, scriptItem, "getInsulation")
    local wind = getItemOrScriptNumber(item, scriptItem, "getWindResistance")
    local water = getItemOrScriptNumber(item, scriptItem, "getWaterResistance")
    local runSpeedMod = getItemOrScriptNumber(item, scriptItem, "getRunSpeedModifier")
    local combatSpeedMod = getItemOrScriptNumber(item, scriptItem, "getCombatSpeedModifier")

    local equippedWeight = tonumber(ctx("safeMethod")(item, "getEquippedWeight"))
    local actualWeight = tonumber(ctx("safeMethod")(item, "getActualWeight"))
    local legacyWeight = tonumber(ctx("safeMethod")(item, "getWeight"))
    local weight = equippedWeight or actualWeight or legacyWeight or 0
    local weightSource = "none"
    if equippedWeight ~= nil then
        weightSource = "equipped"
    elseif actualWeight ~= nil then
        weightSource = "actual"
    elseif legacyWeight ~= nil then
        weightSource = "legacy"
    end

    local classifierEval = nil
    local classifierSignals = nil
    local classifier = ctx("Classifier") or Classifier
    if classifier and type(classifier.computeArmorLikeSignals) == "function" then
        classifierSignals = classifier.computeArmorLikeSignals(item, scriptItem, wornLocation)
    end
    if classifier and type(classifier.evaluateArmorLike) == "function" then
        classifierEval = classifier.evaluateArmorLike(item, scriptItem, wornLocation)
    end

    local hasProtectiveTag = (classifierSignals and classifierSignals.hasProtectiveTag)
        or (classifierEval and classifierEval.hasProtectiveTag)
        or ((classifier and type(classifier.hasAnyProtectiveTag) == "function") and classifier.hasAnyProtectiveTag(item, scriptItem))
        or hasAnyProtectiveTagFallback(item, scriptItem)
    local hasBreathingTag = ctx("containsAny")(itemName, ctx("breathingKeywords")) or ctx("containsAny")(locationName, ctx("breathingLocationHints"))
    local keywordMatch = (classifierSignals and classifierSignals.keywordMatch) or ctx("containsAny")(itemName, ctx("armorKeywords"))
    local locationMatch = (classifierSignals and classifierSignals.locationMatch) or ctx("containsAny")(locationName, ctx("armorLocationHints"))

    local defenseScore = (classifierSignals and tonumber(classifierSignals.classifierDefenseScore))
        or ((scratch * 0.30) + (bite * 0.75) + (bullet * 0.35) + (neck * 0.45))
    local thermalScore = (classifierSignals and tonumber(classifierSignals.thermalScore))
        or ((insulation * 10.0) + (wind * 8.0))
    local isArmor = false
    local strongDefense = (classifierSignals and classifierSignals.strongDefense)
        or defenseScore >= 8.0 or bullet >= 1.0 or bite >= 4.0 or scratch >= 8.0
    local mediumDefense = (classifierSignals and classifierSignals.mediumDefense)
        or defenseScore >= 3.0 or bite >= 1.5 or scratch >= 3.0

    if classifierEval and classifierEval.isArmorLike ~= nil then
        isArmor = ctx("toBoolean")(classifierEval.isArmorLike)
    else
        local hasSomeIndicator = hasProtectiveTag or keywordMatch or locationMatch
        if not hasSomeIndicator and weight < 1.5 and discomfort <= 0.05 then
            isArmor = false
        elseif strongDefense then
            isArmor = true
        elseif hasProtectiveTag then
            isArmor = true
        elseif keywordMatch and (weight >= 1.2 or mediumDefense or discomfort > 0.15) then
            isArmor = true
        elseif locationMatch and strongDefense and weight >= 1.0 then
            isArmor = true
        end
    end

    local runPenalty = math.max(0, 1 - runSpeedMod)
    local combatPenalty = math.max(0, 1 - combatSpeedMod)
    local isMaskSlot = string.find(locationName, "mask", 1, true) ~= nil
    local isShoesSlot = string.find(locationName, "shoe", 1, true) ~= nil
    local runPenaltyForLoad = isShoesSlot and 0 or runPenalty
    local weightScale = ctx("clamp")(weight / 0.8, 0.15, 1.0)
    local weightContrib = math.max(0, weight - 0.30) * 8.0
    local physicalLoad = weightContrib
        + (math.max(discomfort, 0) * 12.0)
        + (runPenaltyForLoad * 42.0)
        + (combatPenalty * 24.0)
        + (defenseScore * 0.06 * weightScale)

    local wearabilityBase = (thermalScore * 0.72) + (math.max(discomfort, 0) * 1.10) + (defenseScore * 0.16)
    wearabilityBase = wearabilityBase + ((runPenaltyForLoad * 10.0) + (combatPenalty * 7.0))
    wearabilityBase = wearabilityBase + (math.max(water, 0) * 0.25)
    local thermalLoad = wearabilityBase
    local breathingLoad = 0

    if hasBreathingTag then
        breathingLoad = breathingLoad + 2.40
        thermalLoad = thermalLoad + 0.90
    end
    if string.find(locationName, "mask", 1, true) or string.find(itemName, "mask", 1, true) then
        breathingLoad = breathingLoad + 0.90
        thermalLoad = thermalLoad + 0.45
    end
    if string.find(locationName, "maskeyes", 1, true) or string.find(locationName, "maskfull", 1, true) then
        breathingLoad = breathingLoad + 0.45
    end
    if string.find(itemName, "helmet", 1, true) or string.find(locationName, "head", 1, true) then
        breathingLoad = breathingLoad + 0.30
    end

    if not isArmor then
        local civilianRigidity = (weight * 5.0) + (math.max(discomfort, 0) * 12.0)
        if isMaskSlot then
            physicalLoad = 0
            thermalLoad = 0
        end
        return {
            physicalLoad = ctx("clamp")(physicalLoad, 0, 28),
            thermalLoad = ctx("clamp")(thermalLoad, 0, 20),
            breathingLoad = ctx("clamp")(breathingLoad, 0, 12),
            rigidityLoad = ctx("clamp")(civilianRigidity, 0, 64),
            discomfort = discomfort,
            weightUsed = tonumber(weight) or 0,
            weightSource = tostring(weightSource),
            equippedWeight = equippedWeight,
            actualWeight = actualWeight,
            legacyWeight = legacyWeight,
        }
    end

    if hasProtectiveTag then
        physicalLoad = physicalLoad + 0.90
        thermalLoad = thermalLoad + 0.60
    end

    if isMaskSlot then
        physicalLoad = 0
        thermalLoad = 0
    end
    local rigidityLoad = (math.max(discomfort, 0) * 16.0)
        + (defenseScore * 0.60)
        + (weight * 3.5)

    return {
        physicalLoad = ctx("clamp")(physicalLoad, 0, 28),
        thermalLoad = ctx("clamp")(thermalLoad, 0, 20),
        breathingLoad = ctx("clamp")(breathingLoad, 0, 8),
        rigidityLoad = ctx("clamp")(rigidityLoad, 0, 64),
        discomfort = discomfort,
        weightUsed = tonumber(weight) or 0,
        weightSource = tostring(weightSource),
        equippedWeight = equippedWeight,
        actualWeight = actualWeight,
        legacyWeight = legacyWeight,
    }
end

function LoadModel.computeArmorProfile(player)
    local wornItems = ctx("safeMethod")(player, "getWornItems")
    if not wornItems then
        return {
            physicalLoad = 0,
            upperBodyLoad = 0,
            swingChainLoad = 0,
            thermalLoad = 0,
            breathingLoad = 0,
            rigidityLoad = 0,
            armorCount = 0,
            combinedLoad = 0,
        }
    end

    local itemCount = ctx("safeMethod")(wornItems, "size") or 0
    local physical = 0
    local upperBody = 0
    local swingChain = 0
    local thermal = 0
    local breathing = 0
    local rigidity = 0
    local armorCount = 0
    local weightUsedTotal = 0
    local equippedWeightTotal = 0
    local actualWeightTotal = 0
    local fallbackWeightTotal = 0
    local fallbackWeightCount = 0
    local sourceActualCount = 0
    local sourceFallbackCount = 0

    for i = 0, itemCount - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            local locationName = ctx("safeMethod")(worn, "getLocation")
            local signal = LoadModel.itemToArmorSignal(item, locationName)
            if signal then
                physical = physical + signal.physicalLoad
                local lowerLoc = ctx("lower")(locationName)
                if shouldCountAsUpperBodyLocation(lowerLoc) then
                    upperBody = upperBody + (tonumber(signal.physicalLoad) or 0)
                end
                if isSwingChainLocation(lowerLoc) then
                    local disc = tonumber(signal.discomfort) or 0
                    local discFactor = ctx("clamp")(0.5 + disc * 5.0, 0.25, 3.0)
                    swingChain = swingChain + (tonumber(signal.physicalLoad) or 0) * discFactor
                end
                thermal = thermal + signal.thermalLoad
                breathing = breathing + signal.breathingLoad
                rigidity = rigidity + (tonumber(signal.rigidityLoad) or 0)
                weightUsedTotal = weightUsedTotal + (tonumber(signal.weightUsed) or 0)
                equippedWeightTotal = equippedWeightTotal + (tonumber(signal.equippedWeight) or 0)
                actualWeightTotal = actualWeightTotal + (tonumber(signal.actualWeight) or 0)
                fallbackWeightTotal = fallbackWeightTotal + (tonumber(signal.legacyWeight) or 0)
                local source = tostring(signal.weightSource or "none")
                if source ~= "equipped" then
                    fallbackWeightCount = fallbackWeightCount + 1
                    if source == "actual" then
                        sourceActualCount = sourceActualCount + 1
                    elseif source == "legacy" then
                        sourceFallbackCount = sourceFallbackCount + 1
                    end
                end
                if (tonumber(signal.physicalLoad) or 0) >= 1.5 then
                    armorCount = armorCount + 1
                end
            end
        end
    end

    physical = ctx("clamp")(physical, 0, 600)
    upperBody = ctx("clamp")(upperBody, 0, 600)
    swingChain = ctx("clamp")(swingChain, 0, 600)
    thermal = ctx("clamp")(thermal, 0, 600)
    breathing = ctx("clamp")(breathing, 0, 30)
    rigidity = ctx("clamp")(rigidity, 0, 600)

    return {
        physicalLoad = physical,
        upperBodyLoad = upperBody,
        swingChainLoad = swingChain,
        massLoad = physical,
        thermalLoad = thermal,
        wearabilityLoad = thermal,
        breathingLoad = breathing,
        rigidityLoad = rigidity,
        armorCount = armorCount,
        weightUsedTotal = weightUsedTotal,
        equippedWeightTotal = equippedWeightTotal,
        actualWeightTotal = actualWeightTotal,
        fallbackWeightTotal = fallbackWeightTotal,
        fallbackWeightCount = fallbackWeightCount,
        sourceActualCount = sourceActualCount,
        sourceFallbackCount = sourceFallbackCount,
        combinedLoad = ctx("clamp")(physical + (thermal * 0.45) + (breathing * 0.90), 0, 320),
    }
end

return LoadModel
