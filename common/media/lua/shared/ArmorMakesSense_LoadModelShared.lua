ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.LoadModel = Core.LoadModel or {}
local Utils = require "ArmorMakesSense_UtilsShared"
local DEFAULTS = require "ArmorMakesSense_Config"
local BreathingClassifier = require "ArmorMakesSense_BreathingClassifier"

local LoadModel = Core.LoadModel

LoadModel.COST_DRIVER_THRESHOLD_KG = 1.5

-- -----------------------------------------------------------------------------
-- Placement: cost per kg relative to mass carried on the trunk.
-- Ordered; the first matching body-location fragment wins.
-- -----------------------------------------------------------------------------

local PLACEMENT = {
    { "jacket", 1.0 }, { "sweater", 1.0 },
    { "fullsuit", 1.3 }, { "boilersuit", 1.3 }, { "torso1legs1", 1.3 },
    { "shoe", 2.0 }, { "sock", 2.0 }, { "ankle", 2.0 },
    { "calf", 2.0 }, { "knee", 2.0 }, { "shin", 2.0 }, { "gaiter", 2.0 },
    { "thigh", 1.5 }, { "pants", 1.4 }, { "legs", 1.4 },
    { "skirt", 1.3 }, { "shorts", 1.3 },
    { "hand", 1.6 }, { "finger", 1.6 }, { "wrist", 1.6 },
    { "forearm", 1.4 }, { "elbow", 1.4 }, { "shoulder", 1.2 }, { "arm", 1.3 },
    { "hat", 1.2 }, { "head", 1.2 }, { "mask", 1.2 }, { "eye", 1.2 }, { "ear", 1.2 },
    { "nose", 1.2 }, { "gorget", 1.2 }, { "neck", 1.2 }, { "scarf", 1.2 },
}

-- Vanilla leaves every shoe at the script default of 1.0 kg, so combat boots
-- and slippers would weigh the same. AMS authors realistic pair weights for
-- vanilla footwear; everything else, including modded shoes, uses its script
-- weight. Only the burden model reads these, inventory weight is untouched.
local AUTHORED_MASS_KG = {
    ["Base.Shoes_WorkBoots"] = 2.0,
    ["Base.Shoes_ArmyBoots"] = 1.8,
    ["Base.Shoes_Wellies"] = 1.8,
    ["Base.Shoes_ArmyBootsDesert"] = 1.6,
    ["Base.Shoes_BlackBoots"] = 1.6,
    ["Base.Shoes_CowboyBoots"] = 1.6,
    ["Base.Shoes_CowboyBoots_Black"] = 1.6,
    ["Base.Shoes_CowboyBoots_Brown"] = 1.6,
    ["Base.Shoes_CowboyBoots_Fancy"] = 1.6,
    ["Base.Shoes_CowboyBoots_SnakeSkin"] = 1.6,
    ["Base.Shoes_HikingBoots"] = 1.4,
    ["Base.Shoes_RidingBoots"] = 1.4,
    ["Base.Shoes_HideBoots"] = 1.3,
    ["Base.Shoes_Black"] = 0.9,
    ["Base.Shoes_Brown"] = 0.9,
    ["Base.Shoes_Fancy"] = 0.9,
    ["Base.Shoes_Bowling"] = 0.9,
    ["Base.Shoes_Random"] = 0.9,
    ["Base.Shoes_TireSandals"] = 0.9,
    ["Base.Shoes_BlueTrainers"] = 0.7,
    ["Base.Shoes_RedTrainers"] = 0.7,
    ["Base.Shoes_TrainerTINT"] = 0.7,
    ["Base.Shoes_Strapped"] = 0.6,
    ["Base.Shoes_CrudeLeatherFootwear"] = 0.6,
    ["Base.Shoes_Sandals"] = 0.5,
    ["Base.Shoes_Twine"] = 0.3,
    ["Base.Shoes_FlipFlop"] = 0.3,
    ["Base.Shoes_Slippers"] = 0.3,
}

local SWING_CHAIN = { "shoulder", "forearm", "elbow", "hand", "arm", "wrist", "finger" }
local SWING_CHAIN_EXCLUSIONS = { "shoulderholster" }

-- Share of a rigid piece that presses on the body when lying down. Rigid
-- means vanilla authored the item as uncomfortable (DiscomfortModifier > 0):
-- armor, helmets, pads, masks, crafted burlap and tarp. Leather and padded
-- clothing carry none.
local SLEEP_CONTACT = {
    { { "mask", "eye", "hat", "head", "ear", "scarf", "gorget", "neck" }, 0.0 },
    { { "forearm", "hand", "elbow", "shin", "calf", "knee", "gaiter", "foot", "shoe", "sock", "wrist", "finger" }, 0.4 },
    { { "shoulder", "hip", "thigh", "leg", "pants", "belt" }, 0.7 },
    { { "torso", "back", "cuirass", "chest", "boilersuit", "fullsuit", "jacket", "jersey", "sweater", "vest" }, 1.0 },
}

local function has(text, fragment)
    return string.find(text, fragment, 1, true) ~= nil
end

local function hasAny(text, fragments)
    for i = 1, #fragments do
        if has(text, fragments[i]) then
            return true
        end
    end
    return false
end

function LoadModel.placementFactor(locationName)
    local loc = Utils.lower(locationName)
    for i = 1, #PLACEMENT do
        if has(loc, PLACEMENT[i][1]) then
            return PLACEMENT[i][2]
        end
    end
    return 1.0
end

function LoadModel.isSwingChainLocation(locationName)
    local loc = Utils.lower(locationName)
    return loc ~= "" and not hasAny(loc, SWING_CHAIN_EXCLUSIONS) and hasAny(loc, SWING_CHAIN)
end

function LoadModel.sleepContactWeight(locationName)
    local loc = Utils.lower(locationName)
    if loc == "" then
        return 0.7
    end
    for i = 1, #SLEEP_CONTACT do
        if hasAny(loc, SLEEP_CONTACT[i][1]) then
            return SLEEP_CONTACT[i][2]
        end
    end
    return 0.7
end

-- -----------------------------------------------------------------------------
-- Item signal
-- -----------------------------------------------------------------------------

local function scriptNumber(item, scriptItem, methodName, defaultValue)
    local value = tonumber(Utils.safeMethod(item, methodName))
    if value == nil then
        value = tonumber(Utils.safeMethod(scriptItem, methodName))
    end
    if value == nil then
        return defaultValue
    end
    return value
end

local function getFullType(item, scriptItem)
    local fullType = tostring(Utils.safeMethod(item, "getFullType") or "")
    if fullType == "" then
        fullType = tostring(Utils.safeMethod(scriptItem, "getFullName") or "")
    end
    return fullType
end

local function originalDiscomfort(item, scriptItem, fullType)
    local cache = ArmorMakesSense._originalDiscomfort
    local cached = cache and cache[fullType]
    if cached ~= nil then
        return tonumber(cached) or 0
    end
    return scriptNumber(item, scriptItem, "getDiscomfortModifier", 0)
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

local function resolveOptions(options)
    return type(options) == "table" and options or DEFAULTS
end

-- Effective kg: mass beyond the per-item allowance, scaled by where it sits,
-- plus bulk from the item's vanilla stiffness (run and discomfort modifiers).
function LoadModel.burdenFromStats(options, weightKg, discomfort, runPenalty, locationName)
    local opts = resolveOptions(options)
    local massKg = math.max(0, (tonumber(weightKg) or 0) - (tonumber(opts.BurdenItemMassAllowanceKg) or 0.5))
    local placement = LoadModel.placementFactor(locationName)
    local bulkKg = (math.max(0, tonumber(runPenalty) or 0) * (tonumber(opts.BurdenBulkPerRunPenalty) or 6))
        + (math.max(0, tonumber(discomfort) or 0) * (tonumber(opts.BurdenBulkPerDiscomfort) or 4))
    return (massKg * placement) + bulkKg, massKg, placement, bulkKg
end

function LoadModel.computeItemSignal(item, wornLocation, options)
    local opts = resolveOptions(options)
    local scriptItem = Utils.safeMethod(item, "getScriptItem")
    local forceInclude = hasExactTag(item, scriptItem, "AMSIncludeBurden")
    if hasExactTag(item, scriptItem, "AMSExcludeBurden") then
        return nil
    end
    local isCosmetic = Utils.toBoolean(Utils.safeMethod(item, "isCosmetic") or Utils.safeMethod(scriptItem, "isCosmetic"))
    if isCosmetic and not forceInclude then
        return nil
    end
    if Utils.toBoolean(Utils.safeMethod(item, "IsInventoryContainer")) and not forceInclude then
        return nil
    end

    local fullType = getFullType(item, scriptItem)
    local locationName = Utils.lower(wornLocation or Utils.safeMethod(item, "getBodyLocation") or Utils.safeMethod(scriptItem, "getBodyLocation"))
    local weightKg = AUTHORED_MASS_KG[fullType] or math.max(0, scriptNumber(item, scriptItem, "getActualWeight", 0))
    local discomfort = math.max(0, originalDiscomfort(item, scriptItem, fullType))
    local runSpeedModifier = scriptNumber(item, scriptItem, "getRunSpeedModifier", 1)
    -- Footwear run modifiers describe soles and traction, not carried bulk.
    local runPenalty = has(locationName, "shoe") and 0 or math.max(0, 1 - runSpeedModifier)

    local burdenKg, massKg, placement, bulkKg = LoadModel.burdenFromStats(opts, weightKg, discomfort, runPenalty, locationName)

    local rigid = discomfort > 0 or hasExactTag(item, scriptItem, "AMSArmor")
    local rigidKg = rigid and (weightKg * LoadModel.sleepContactWeight(locationName)) or 0

    local respiratory = BreathingClassifier.computeSignals(item, scriptItem, wornLocation)
    local respiratoryClass = tostring(respiratory.class or "none")

    return {
        fullType = fullType,
        bodyLocation = locationName,
        weightKg = weightKg,
        massKg = massKg,
        placement = placement,
        bulkKg = bulkKg,
        burdenKg = burdenKg,
        swingChain = LoadModel.isSwingChainLocation(locationName),
        rigidKg = rigidKg,
        discomfort = discomfort,
        runPenalty = runPenalty,
        rigid = rigid,
        inclusionReason = forceInclude and "forced_include" or "wearable",
        airflowResistance = Utils.clamp(tonumber(respiratory.airflowResistance) or 0, 0, 8),
        sealedRestriction = Utils.clamp(tonumber(respiratory.sealedRestriction) or 0, 0, 1),
        respiratoryClass = respiratoryClass,
        respiratoryHasFilter = respiratoryClass ~= "none" and respiratory.hasFilter == true or nil,
    }
end

-- Item signals depend only on script data, so they are cached per type,
-- location and weight for the session. Options only change on sandbox load.
local signalCache = {}
local EXCLUDED = {}

function LoadModel.itemToBurdenSignal(item, wornLocation, options)
    local scriptItem = Utils.safeMethod(item, "getScriptItem")
    local key = getFullType(item, scriptItem)
        .. "|" .. Utils.lower(wornLocation or Utils.safeMethod(item, "getBodyLocation") or "")
        .. "|" .. tostring(tonumber(Utils.safeMethod(item, "getActualWeight")) or "")
    local cached = signalCache[key]
    if cached == nil then
        cached = LoadModel.computeItemSignal(item, wornLocation, options) or EXCLUDED
        signalCache[key] = cached
    end
    if cached == EXCLUDED then
        return nil
    end
    return cached
end

function LoadModel.clearSignalCache()
    signalCache = {}
end

-- -----------------------------------------------------------------------------
-- Worn profile
-- -----------------------------------------------------------------------------

local function emptyProfile()
    return {
        burdenKg = 0,
        massKg = 0,
        bulkKg = 0,
        armKg = 0,
        rigidKg = 0,
        airflowResistance = 0,
        sealedRestriction = 0,
        driverCount = 0,
    }
end

local function getItemDisplayName(item, fullType)
    local displayName = tostring(Utils.safeMethod(item, "getDisplayName") or Utils.safeMethod(item, "getName") or "")
    if displayName ~= "" then
        return displayName
    end
    return tostring(fullType ~= "" and fullType or "Unknown Item")
end

local function getItemSourceMod(item)
    local modId = tostring(Utils.safeMethod(item, "getModID") or "")
    if modId == "" then
        modId = tostring(Utils.safeMethod(Utils.safeMethod(item, "getScriptItem"), "getModID") or "")
    end
    return modId ~= "" and modId or nil
end

local function buildWornRow(item, locationName, signal)
    local fullType = signal and signal.fullType or getFullType(item, Utils.safeMethod(item, "getScriptItem"))
    return {
        item = item,
        bodyLocation = tostring(locationName or "unknown"),
        fullType = fullType,
        displayName = getItemDisplayName(item, fullType),
        sourceMod = getItemSourceMod(item),
        included = signal ~= nil,
        burdenKg = signal and signal.burdenKg or 0,
        massKg = signal and signal.massKg or 0,
        bulkKg = signal and signal.bulkKg or 0,
        placement = signal and signal.placement or 1,
        weightKg = signal and signal.weightKg or 0,
        rigidKg = signal and signal.rigidKg or 0,
        airflow = signal and signal.airflowResistance or 0,
        sealedRestriction = signal and signal.sealedRestriction or 0,
        discomfort = signal and signal.discomfort or 0,
        respiratoryClass = signal and signal.respiratoryClass or "none",
        respiratoryHasFilter = signal and signal.respiratoryHasFilter or nil,
        inclusionReason = signal and signal.inclusionReason or "excluded",
        rigid = signal and signal.rigid == true or false,
    }
end

local function sortByBurden(rows)
    table.sort(rows, function(a, b)
        local left = tonumber(a and a.burdenKg) or 0
        local right = tonumber(b and b.burdenKg) or 0
        if left == right then
            return tostring(a and a.fullType or "") < tostring(b and b.fullType or "")
        end
        return left > right
    end)
end

function LoadModel.analyzeWornGear(player, options)
    local profile = emptyProfile()
    local rows = {}
    local costDrivers = {}
    local signatureParts = {}
    local wornItems = Utils.safeMethod(player, "getWornItems")
    local itemCount = tonumber(wornItems and Utils.safeMethod(wornItems, "size")) or 0

    for i = 0, itemCount - 1 do
        local worn = Utils.safeMethod(wornItems, "get", i)
        local item = worn and Utils.safeMethod(worn, "getItem")
        if item then
            local locationName = tostring(
                Utils.safeMethod(worn, "getLocation")
                    or Utils.safeMethod(item, "getBodyLocation")
                    or "unknown"
            )
            local signal = LoadModel.itemToBurdenSignal(item, locationName, options)
            local row = buildWornRow(item, locationName, signal)
            rows[#rows + 1] = row
            signatureParts[#signatureParts + 1] = locationName .. "=" .. row.fullType
            if signal then
                profile.burdenKg = profile.burdenKg + signal.burdenKg
                profile.massKg = profile.massKg + signal.massKg
                profile.bulkKg = profile.bulkKg + signal.bulkKg
                profile.rigidKg = profile.rigidKg + signal.rigidKg
                profile.airflowResistance = profile.airflowResistance + signal.airflowResistance
                profile.sealedRestriction = math.max(profile.sealedRestriction, signal.sealedRestriction)
                if signal.swingChain then
                    profile.armKg = profile.armKg + signal.burdenKg
                end
                if signal.burdenKg >= LoadModel.COST_DRIVER_THRESHOLD_KG then
                    profile.driverCount = profile.driverCount + 1
                    costDrivers[#costDrivers + 1] = {
                        label = row.displayName,
                        fullType = row.fullType,
                        burdenKg = signal.burdenKg,
                    }
                end
            end
        end
    end

    profile.airflowResistance = Utils.clamp(profile.airflowResistance, 0, 12)
    sortByBurden(rows)
    sortByBurden(costDrivers)
    table.sort(signatureParts)

    return {
        profile = profile,
        rows = rows,
        costDrivers = costDrivers,
        equipmentSignature = table.concat(signatureParts, ";"),
        wornCount = #rows,
    }
end

function LoadModel.computeWornProfile(player, options)
    return LoadModel.analyzeWornGear(player, options).profile
end

-- -----------------------------------------------------------------------------
-- Carrier: burden relative to the body carrying it.
-- -----------------------------------------------------------------------------

function LoadModel.resolveCarrier(player, options)
    local opts = resolveOptions(options)
    local nutrition = Utils.safeMethod(player, "getNutrition")
    local bodyKg = tonumber(Utils.safeMethod(nutrition, "getWeight")) or 80
    local strength = 5
    if Perks and Perks.Strength then
        strength = tonumber(Utils.safeMethod(player, "getPerkLevel", Perks.Strength)) or 5
    end
    return {
        bodyKg = Utils.clamp(bodyKg, tonumber(opts.BodyMassMinKg) or 50, tonumber(opts.BodyMassMaxKg) or 90),
        strength = Utils.clamp(strength, 0, 10),
    }
end

function LoadModel.strengthFactor(options, strength)
    local opts = resolveOptions(options)
    return math.max(0.2, (tonumber(opts.StrengthFactorBase) or 1.3)
        - ((tonumber(opts.StrengthFactorPerLevel) or 0.06) * (tonumber(strength) or 5)))
end

function LoadModel.loadFraction(options, burdenKg, carrier)
    local opts = resolveOptions(options)
    local body = type(carrier) == "table" and carrier or { bodyKg = 80, strength = 5 }
    local excessKg = math.max(0, (tonumber(burdenKg) or 0) - (tonumber(opts.BurdenClothingAllowanceKg) or 3.5))
    local scale = math.max(0, tonumber(opts.PhysicalLoadScale) or 1)
    return (excessKg / math.max(1, tonumber(body.bodyKg) or 80))
        * LoadModel.strengthFactor(opts, body.strength)
        * scale
end

return LoadModel
