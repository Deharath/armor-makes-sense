ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.LoadModel = Core.LoadModel or {}
local Utils = require "ArmorMakesSense_UtilsShared"
local Classifier = require "ArmorMakesSense_ArmorClassifier"
local BreathingClassifier = require "ArmorMakesSense_BreathingClassifier"

local LoadModel = Core.LoadModel

LoadModel.COST_DRIVER_THRESHOLD = 1.5

-- -----------------------------------------------------------------------------
-- Item-to-load transformation
-- -----------------------------------------------------------------------------

local function getItemOrScriptNumber(item, scriptItem, methodName, defaultValue)
    local value = tonumber(Utils.safeMethod(item, methodName))
    if value ~= nil then
        return value
    end
    value = tonumber(Utils.safeMethod(scriptItem, methodName))
    if value ~= nil then
        return value
    end
    return tonumber(defaultValue) or 0
end

local function getOriginalDiscomfort(item, scriptItem)
    local fullType = tostring(Utils.safeMethod(item, "getFullType") or Utils.safeMethod(scriptItem, "getFullType") or "")
    local discomfortCache = ArmorMakesSense and ArmorMakesSense._originalDiscomfort or nil
    local cached = discomfortCache and discomfortCache[fullType]
    if cached ~= nil then
        return tonumber(cached) or 0
    end
    return getItemOrScriptNumber(item, scriptItem, "getDiscomfortModifier")
end

local function getOriginalMovementModifier(item, scriptItem, cacheName, methodName)
    local fullType = tostring(Utils.safeMethod(item, "getFullType") or Utils.safeMethod(scriptItem, "getFullType") or "")
    local cache = ArmorMakesSense and ArmorMakesSense[cacheName] or nil
    local cached = cache and cache[fullType]
    if cached ~= nil then
        return tonumber(cached) or 1
    end
    return getItemOrScriptNumber(item, scriptItem, methodName, 1)
end

local function hasExactTag(item, scriptItem, expectedTag)
    local expected = Utils.lower(expectedTag)
    local function scan(target)
        local tags = Utils.safeMethod(target, "getTags")
        local count = tonumber(Utils.safeMethod(tags, "size")) or 0
        for i = 0, count - 1 do
            if Utils.lower(Utils.safeMethod(tags, "get", i)) == expected then
                return true
            end
        end
        return false
    end
    return scan(item) or scan(scriptItem)
end

local SWING_CHAIN_LOCATION_PATTERNS = {
    "shoulder", "forearm", "elbow", "hand", "arm",
}

local SWING_CHAIN_EXCLUSIONS = {
    "shoulderholster",
}

local SLEEP_CONTACT_HIGH = {
    "torso", "back", "cuirass", "chest", "boilersuit", "fullsuit",
    "jacket", "jersey", "sweater",
}

local SLEEP_CONTACT_MEDIUM = {
    "shoulder", "hip", "thigh", "leg", "belt",
}

local SLEEP_CONTACT_LOW = {
    "forearm", "hand", "elbow", "shin", "calf", "gaiter",
    "foot", "shoe", "sock", "wrist", "finger",
}

local SLEEP_CONTACT_ZERO = {
    "mask", "eye", "hat", "head", "ear", "scarf", "gorget", "neck",
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

local function isSwingChainLocation(locationName)
    local loc = tostring(locationName or "")
    if locationHasAnyPattern(loc, SWING_CHAIN_EXCLUSIONS) then
        return false
    end
    return locationHasAnyPattern(loc, SWING_CHAIN_LOCATION_PATTERNS)
end

local function getSleepContactWeight(locationName)
    local loc = tostring(locationName or "")
    if loc == "" then
        return 0.7
    end
    if locationHasAnyPattern(loc, SLEEP_CONTACT_ZERO) then
        return 0.0
    end
    if locationHasAnyPattern(loc, SLEEP_CONTACT_LOW) then
        return 0.15
    end
    if locationHasAnyPattern(loc, SLEEP_CONTACT_MEDIUM) then
        return 0.5
    end
    if locationHasAnyPattern(loc, SLEEP_CONTACT_HIGH) then
        return 1.0
    end
    return 0.7
end

function LoadModel.itemToBurdenSignal(item, wornLocation)
    local scriptItem = Utils.safeMethod(item, "getScriptItem")
    local forceInclude = hasExactTag(item, scriptItem, "AMSIncludeBurden")
    local forceExclude = hasExactTag(item, scriptItem, "AMSExcludeBurden")
    if forceExclude then
        return nil
    end
    local isCosmetic = Utils.toBoolean(Utils.safeMethod(item, "isCosmetic") or Utils.safeMethod(scriptItem, "isCosmetic"))
    if isCosmetic and not forceInclude then
        return nil
    end
    local isContainer = Utils.toBoolean(Utils.safeMethod(item, "IsInventoryContainer"))
    if isContainer and not forceInclude then
        return nil
    end
    local locationName = Utils.lower(wornLocation or Utils.safeMethod(item, "getBodyLocation") or Utils.safeMethod(scriptItem, "getBodyLocation"))
    local discomfort = getOriginalDiscomfort(item, scriptItem)
    local runSpeedMod = getOriginalMovementModifier(
        item,
        scriptItem,
        "_originalRunSpeedModifier",
        "getRunSpeedModifier"
    )
    local combatSpeedMod = getOriginalMovementModifier(
        item,
        scriptItem,
        "_originalCombatSpeedModifier",
        "getCombatSpeedModifier"
    )

    local equippedWeight = tonumber(Utils.safeMethod(item, "getEquippedWeight"))
    local actualWeight = tonumber(Utils.safeMethod(item, "getActualWeight"))
    local legacyWeight = tonumber(Utils.safeMethod(item, "getWeight"))
    local weight = equippedWeight or actualWeight or legacyWeight or 0
    local weightSource = "none"
    if equippedWeight ~= nil then
        weightSource = "equipped"
    elseif actualWeight ~= nil then
        weightSource = "actual"
    elseif legacyWeight ~= nil then
        weightSource = "legacy"
    end

    local classifierSignals = Classifier.computeArmorLikeSignals(item, scriptItem, wornLocation)
    local classifierEval = Classifier.evaluateArmorLikeSignals(classifierSignals)
    local hasProtectiveTag = classifierSignals.hasProtectiveTag == true
    local defenseScore = tonumber(classifierSignals.classifierDefenseScore) or 0
    local forceArmor = hasExactTag(item, scriptItem, "AMSArmor")
    local isArmor = forceArmor or classifierEval.isArmorLike == true
    local inclusionReason = forceInclude and "forced_include" or "wearable"
    local classificationReason = forceArmor and "forced_armor" or tostring(classifierEval.reason or "no_match")

    local runPenalty = math.max(0, 1 - runSpeedMod)
    local combatPenalty = math.max(0, 1 - combatSpeedMod)
    local isMaskSlot = string.find(locationName, "mask", 1, true) ~= nil
    local isShoesSlot = string.find(locationName, "shoe", 1, true) ~= nil
    local runPenaltyForLoad = isShoesSlot and 0 or runPenalty
    local weightScale = Utils.clamp(weight / 0.8, 0.15, 1.0)
    local weightContrib = math.max(0, weight - 0.30) * 8.0
    local physicalLoad = weightContrib
        + (math.max(discomfort, 0) * 12.0)
        + (runPenaltyForLoad * 42.0)
        + (combatPenalty * 24.0)
        + (defenseScore * 0.06 * weightScale)

    local respiratorySignals = BreathingClassifier.computeSignals(item, scriptItem, wornLocation)
    local airflowResistance = tonumber(respiratorySignals.airflowResistance) or 0
    local sealedRestriction = tonumber(respiratorySignals.sealedRestriction) or 0
    local respiratoryClass = tostring(respiratorySignals.class or "none")
    local respiratoryHasFilter = respiratorySignals.hasFilter == true
    local respiratoryReasons = respiratorySignals.reasons

    if not isArmor then
        local civilianRigidity = (weight * 5.0) + (math.max(discomfort, 0) * 12.0)
        if isMaskSlot then
            physicalLoad = 0
        end
        return {
            physicalLoad = Utils.clamp(physicalLoad, 0, 28),
            airflowResistance = Utils.clamp(airflowResistance, 0, 12),
            sealedRestriction = Utils.clamp(sealedRestriction, 0, 1),
            rigidityLoad = Utils.clamp(civilianRigidity, 0, 64),
            respiratoryClass = respiratoryClass,
            respiratoryHasFilter = respiratoryHasFilter,
            respiratoryReasons = respiratoryReasons,
            inclusionReason = inclusionReason,
            armorLike = isArmor,
            classificationReason = classificationReason,
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
    end

    if isMaskSlot then
        physicalLoad = 0
    end
    local rigidityLoad = (math.max(discomfort, 0) * 16.0)
        + (defenseScore * 0.60)
        + (weight * 3.5)

    return {
        physicalLoad = Utils.clamp(physicalLoad, 0, 28),
        airflowResistance = Utils.clamp(airflowResistance, 0, 8),
        sealedRestriction = Utils.clamp(sealedRestriction, 0, 1),
        rigidityLoad = Utils.clamp(rigidityLoad, 0, 64),
        respiratoryClass = respiratoryClass,
        respiratoryHasFilter = respiratoryHasFilter,
        respiratoryReasons = respiratoryReasons,
        inclusionReason = inclusionReason,
        armorLike = isArmor,
        classificationReason = classificationReason,
        discomfort = discomfort,
        weightUsed = tonumber(weight) or 0,
        weightSource = tostring(weightSource),
        equippedWeight = equippedWeight,
        actualWeight = actualWeight,
        legacyWeight = legacyWeight,
    }
end

local function emptyProfile()
    return {
        physicalLoad = 0,
        swingChainLoad = 0,
        airflowResistance = 0,
        sealedRestriction = 0,
        rigidityLoad = 0,
        driverCount = 0,
        weightUsedTotal = 0,
        equippedWeightTotal = 0,
        actualWeightTotal = 0,
        fallbackWeightTotal = 0,
        fallbackWeightCount = 0,
        sourceActualCount = 0,
        sourceFallbackCount = 0,
    }
end

local function getItemFullType(item)
    local fullType = tostring(Utils.safeMethod(item, "getFullType") or "")
    if fullType ~= "" then
        return fullType
    end

    local scriptItem = Utils.safeMethod(item, "getScriptItem")
    fullType = tostring(Utils.safeMethod(scriptItem, "getFullName") or "")
    if fullType ~= "" then
        return fullType
    end

    local moduleName = tostring(Utils.safeMethod(scriptItem, "getModuleName") or "")
    local typeName = tostring(Utils.safeMethod(scriptItem, "getName") or "")
    if moduleName ~= "" and typeName ~= "" then
        return moduleName .. "." .. typeName
    end

    return tostring(Utils.safeMethod(item, "getType") or "unknown")
end

local function getItemDisplayName(item, fullType)
    local displayName = tostring(Utils.safeMethod(item, "getDisplayName") or Utils.safeMethod(item, "getName") or "")
    if displayName ~= "" then
        return displayName
    end
    return tostring(fullType or "Unknown Item")
end

local function getItemSourceMod(item)
    local modId = tostring(Utils.safeMethod(item, "getModID") or "")
    if modId == "" then
        local scriptItem = Utils.safeMethod(item, "getScriptItem")
        modId = tostring(Utils.safeMethod(scriptItem, "getModID") or "")
    end
    if modId == "" then
        return nil
    end
    return modId
end

local function buildWornRow(item, locationName, signal)
    local fullType = getItemFullType(item)
    local respiratoryClass = tostring(signal and signal.respiratoryClass or "none")
    local respiratoryHasFilter = nil
    if signal and respiratoryClass ~= "none" then
        respiratoryHasFilter = signal.respiratoryHasFilter == true
    end
    return {
        bodyLocation = tostring(locationName or "unknown"),
        fullType = fullType,
        displayName = getItemDisplayName(item, fullType),
        sourceMod = getItemSourceMod(item),
        included = signal ~= nil,
        physical = tonumber(signal and signal.physicalLoad) or 0,
        airflow = tonumber(signal and signal.airflowResistance) or 0,
        sealedRestriction = tonumber(signal and signal.sealedRestriction) or 0,
        rigidity = tonumber(signal and signal.rigidityLoad) or 0,
        weightUsed = tonumber(signal and signal.weightUsed) or 0,
        weightSource = tostring(signal and signal.weightSource or "na"),
        discomfort = tonumber(signal and signal.discomfort) or 0,
        respiratoryClass = respiratoryClass,
        respiratoryHasFilter = respiratoryHasFilter,
        inclusionReason = tostring(signal and signal.inclusionReason or "excluded"),
        armorLike = signal and signal.armorLike == true or false,
        classificationReason = tostring(signal and signal.classificationReason or "excluded"),
    }
end

local function sortRowsByPhysical(rows)
    table.sort(rows, function(a, b)
        local left = tonumber(a and a.physical) or 0
        local right = tonumber(b and b.physical) or 0
        if left == right then
            return tostring(a and a.fullType or "") < tostring(b and b.fullType or "")
        end
        return left > right
    end)
end

function LoadModel.analyzeWornGear(player)
    local wornItems = Utils.safeMethod(player, "getWornItems")
    if not wornItems then
        return {
            profile = emptyProfile(),
            rows = {},
            costDrivers = {},
            equipmentSignature = "",
            wornCount = 0,
        }
    end

    local itemCount = Utils.safeMethod(wornItems, "size") or 0
    local physical = 0
    local swingChain = 0
    local airflow = 0
    local sealedRestriction = 0
    local rigidity = 0
    local driverCount = 0
    local weightUsedTotal = 0
    local equippedWeightTotal = 0
    local actualWeightTotal = 0
    local fallbackWeightTotal = 0
    local fallbackWeightCount = 0
    local sourceActualCount = 0
    local sourceFallbackCount = 0
    local rows = {}
    local costDrivers = {}
    local signatureParts = {}
    local wornCount = 0

    for i = 0, itemCount - 1 do
        local worn = Utils.safeMethod(wornItems, "get", i)
        local item = worn and Utils.safeMethod(worn, "getItem")
        if item then
            local locationName = tostring(
                Utils.safeMethod(worn, "getLocation")
                    or Utils.safeMethod(item, "getBodyLocation")
                    or "unknown"
            )
            local signal = LoadModel.itemToBurdenSignal(item, locationName)
            local row = buildWornRow(item, locationName, signal)
            rows[#rows + 1] = row
            wornCount = wornCount + 1
            signatureParts[#signatureParts + 1] = locationName .. "=" .. row.fullType
            if signal then
                physical = physical + signal.physicalLoad
                local lowerLoc = Utils.lower(locationName)
                if isSwingChainLocation(lowerLoc) then
                    local disc = tonumber(signal.discomfort) or 0
                    local discFactor = Utils.clamp(0.5 + disc * 5.0, 0.25, 3.0)
                    swingChain = swingChain + (tonumber(signal.physicalLoad) or 0) * discFactor
                end
                airflow = airflow + signal.airflowResistance
                sealedRestriction = math.max(sealedRestriction, tonumber(signal.sealedRestriction) or 0)
                local contactWeight = getSleepContactWeight(lowerLoc)
                rigidity = rigidity + (tonumber(signal.rigidityLoad) or 0) * contactWeight
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
                if (tonumber(signal.physicalLoad) or 0) >= LoadModel.COST_DRIVER_THRESHOLD then
                    driverCount = driverCount + 1
                    costDrivers[#costDrivers + 1] = {
                        label = row.displayName,
                        fullType = row.fullType,
                        physical = row.physical,
                    }
                end
            end
        end
    end

    physical = Utils.clamp(physical, 0, 600)
    swingChain = Utils.clamp(swingChain, 0, 600)
    airflow = Utils.clamp(airflow, 0, 30)
    sealedRestriction = Utils.clamp(sealedRestriction, 0, 1)
    rigidity = Utils.clamp(rigidity, 0, 600)

    local profile = {
        physicalLoad = physical,
        swingChainLoad = swingChain,
        airflowResistance = airflow,
        sealedRestriction = sealedRestriction,
        rigidityLoad = rigidity,
        driverCount = driverCount,
        weightUsedTotal = weightUsedTotal,
        equippedWeightTotal = equippedWeightTotal,
        actualWeightTotal = actualWeightTotal,
        fallbackWeightTotal = fallbackWeightTotal,
        fallbackWeightCount = fallbackWeightCount,
        sourceActualCount = sourceActualCount,
        sourceFallbackCount = sourceFallbackCount,
    }

    sortRowsByPhysical(rows)
    sortRowsByPhysical(costDrivers)
    table.sort(signatureParts)

    return {
        profile = profile,
        rows = rows,
        costDrivers = costDrivers,
        equipmentSignature = table.concat(signatureParts, ";"),
        wornCount = wornCount,
    }
end

function LoadModel.computeWornProfile(player)
    return LoadModel.analyzeWornGear(player).profile
end

return LoadModel
