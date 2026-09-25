-- SpeedRebalance: script-level wearable changes applied at boot.
--
-- Discomfort is zeroed on every wearable. Vanilla discomfort is an
-- accumulating equipment cost; AMS reads each item's original discomfort
-- as bulk in the burden model instead, so leaving it live would double-count.
--
-- CombatSpeedModifier follows one rule. Only gear on the swing chain
-- (shoulders, arms, hands) slows swings, by 1% per effective kg up to 5%.
-- Everything else swings at full speed. RunSpeedModifier is left alone:
-- vanilla does not read it for movement.

ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.SpeedRebalance = ArmorMakesSense.SpeedRebalance or {}
local SpeedRebalance = ArmorMakesSense.SpeedRebalance
require "ArmorMakesSense_SlotCompat"
local Config = require "ArmorMakesSense_Config"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Logger = require "ArmorMakesSense_Logger"
local Utils = require "ArmorMakesSense_UtilsShared"

SpeedRebalance.COMBAT_PENALTY_PER_KG = 0.01
SpeedRebalance.COMBAT_PENALTY_MAX = 0.05

local safeMethod = Utils.safeMethod

local function safeScriptString(item, methodName)
    local value = safeMethod(item, methodName)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function safeDoParam(item, param)
    if not item or type(item.DoParam) ~= "function" then
        return false
    end
    local ok, err = pcall(item.DoParam, item, param)
    if not ok then
        Logger.error("DoParam failed: " .. tostring(err) .. " param=" .. tostring(param))
    end
    return ok
end

local function safeClearScriptTooltip(item)
    if not item or type(item.DoParam) ~= "function" then
        return false
    end
    local ok, err = pcall(item.DoParam, item, "Tooltip", "")
    if not ok then
        Logger.warn("clearing script tooltip failed: " .. tostring(err))
    end
    return ok
end

-- Keyed by script full name; the burden model reads it after discomfort is zeroed.
ArmorMakesSense._originalDiscomfort = ArmorMakesSense._originalDiscomfort or {}

local function originalDiscomfort(item, fullName)
    local cache = ArmorMakesSense._originalDiscomfort
    if cache[fullName] == nil then
        cache[fullName] = math.max(0, tonumber(safeMethod(item, "getDiscomfortModifier")) or 0)
    end
    return cache[fullName]
end

function SpeedRebalance.combatSpeedModifier(locationName, burdenKg)
    if not LoadModel.isSwingChainLocation(locationName) then
        return 1.0
    end
    local penalty = math.min(
        SpeedRebalance.COMBAT_PENALTY_MAX,
        SpeedRebalance.COMBAT_PENALTY_PER_KG * math.max(0, tonumber(burdenKg) or 0)
    )
    return 1.0 - penalty
end

-- Reslot map for AMS custom body locations.
local slotReslots = {
    {
        slot = "ams:shoulderpad_left",
        fullTypes = {
            "Base.Shoulderpad_ArticulatedSpike_L",
            "Base.Shoulderpad_Articulated_L_Metal",
            "Base.Shoulderpad_Bone_L",
            "Base.Shoulderpad_Football_L",
            "Base.Shoulderpad_Football_Spiked_L",
            "Base.Shoulderpad_MetalScrap_L",
            "Base.Shoulderpad_MetalSpikeScrap_L",
            "Base.Shoulderpad_MetalSpike_L",
            "Base.Shoulderpad_Metal_L",
            "Base.Shoulderpad_Tire_L",
            "Base.Shoulderpad_Wood_L",
        },
    },
    {
        slot = "ams:shoulderpad_right",
        fullTypes = {
            "Base.Shoulderpad_ArticulatedSpike_R",
            "Base.Shoulderpad_Articulated_R_Metal",
            "Base.Shoulderpad_Bone_R",
            "Base.Shoulderpad_Football_R",
            "Base.Shoulderpad_Football_Spiked_R",
            "Base.Shoulderpad_MetalScrap_R",
            "Base.Shoulderpad_MetalSpikeScrap_R",
            "Base.Shoulderpad_MetalSpike_R",
            "Base.Shoulderpad_Metal_R",
            "Base.Shoulderpad_Tire_R",
            "Base.Shoulderpad_Wood_R",
        },
    },
    {
        slot = "ams:sport_shoulderpad",
        fullTypes = {
            "Base.Shoulderpads_Football",
            "Base.Shoulderpads_IceHockey",
        },
    },
    {
        slot = "ams:sport_shoulderpad_on_top",
        fullTypes = {
            "Base.Shoulderpads_FootballOnTop",
            "Base.Shoulderpads_FootballOnTop_Spiked",
            "Base.Shoulderpads_IceHockeyOnTop",
        },
    },
    {
        slot = "ams:forearm_left",
        fullTypes = {
            "Base.VambraceBone_Left",
            "Base.VambraceMagazine_Left",
            "Base.VambraceScrap_Left",
            "Base.VambraceSpikeScrap_Left",
            "Base.VambraceSpike_Left",
            "Base.VambraceTire_Left",
            "Base.VambraceWood_Left",
            "Base.Vambrace_BodyArmour_Left",
            "Base.Vambrace_BodyArmour_Left_Army",
            "Base.Vambrace_BodyArmour_Left_Civ",
            "Base.Vambrace_BodyArmour_Left_Desert",
            "Base.Vambrace_BodyArmour_Left_Police",
            "Base.Vambrace_BodyArmour_Left_SWAT",
            "Base.Vambrace_FullMetal_Left",
            "Base.Vambrace_LeatherSpike_Left",
            "Base.Vambrace_Leather_Left",
            "Base.Vambrace_Left",
        },
    },
    {
        slot = "ams:forearm_right",
        fullTypes = {
            "Base.VambraceBone_Right",
            "Base.VambraceMagazine_Right",
            "Base.VambraceScrap_Right",
            "Base.VambraceSpikeScrap_Right",
            "Base.VambraceSpike_Right",
            "Base.VambraceTire_Right",
            "Base.VambraceWood_Right",
            "Base.Vambrace_BodyArmour_Right",
            "Base.Vambrace_BodyArmour_Right_Army",
            "Base.Vambrace_BodyArmour_Right_Civ",
            "Base.Vambrace_BodyArmour_Right_Desert",
            "Base.Vambrace_BodyArmour_Right_Police",
            "Base.Vambrace_BodyArmour_Right_SWAT",
            "Base.Vambrace_FullMetal_Right",
            "Base.Vambrace_LeatherSpike_Right",
            "Base.Vambrace_Leather_Right",
            "Base.Vambrace_Right",
        },
    },
    {
        slot = "ams:cuirass",
        fullTypes = {
            "Base.Cuirass_BasicBone",
            "Base.Cuirass_Bone",
            "Base.Cuirass_CoatOfPlates",
            "Base.Cuirass_Magazine",
            "Base.Cuirass_Metal",
            "Base.Cuirass_MetalScrap",
            "Base.Cuirass_Tire",
            "Base.Cuirass_Wood",
        },
    },
    {
        slot = "ams:torso_extra_vest_bullet",
        fullTypes = {
            "Base.Vest_BulletArmy",
            "Base.Vest_BulletCivilian",
            "Base.Vest_BulletDesert",
            "Base.Vest_BulletDesertNew",
            "Base.Vest_BulletOliveDrab",
            "Base.Vest_BulletPolice",
            "Base.Vest_BulletSWAT",
            "Base.Vest_CatcherVest",
            "Base.Vest_CatcherVest_Blue",
            "Base.Vest_CatcherVest_Green",
            "Base.Vest_CatcherVest_Red",
        },
    },
}

local function applySlotReslots(sm)
    local changed = 0
    local missing = 0
    for _, def in ipairs(slotReslots) do
        local isShoulderpadSlot = (
            def.slot == "ams:shoulderpad_left"
            or def.slot == "ams:shoulderpad_right"
            or def.slot == "ams:sport_shoulderpad"
            or def.slot == "ams:sport_shoulderpad_on_top"
        )
        for _, fullType in ipairs(def.fullTypes) do
            local item = sm:getItem(fullType)
            if item then
                local itemChanged = safeDoParam(item, "BodyLocation = " .. def.slot)
                -- Vanilla shoulderpads carry Tooltip_item_NoBackpack. After AMS slot
                -- compatibility changes this becomes misleading, so clear it.
                if isShoulderpadSlot then
                    itemChanged = safeClearScriptTooltip(item) or itemChanged
                end
                if itemChanged then
                    changed = changed + 1
                end
            else
                missing = missing + 1
            end
        end
    end
    return changed, missing
end

local function applyWearableRules(sm)
    local wearables = 0
    local swingChain = 0
    local all = sm:getAllItems()
    local n = tonumber(all and all:size()) or 0
    for i = 0, n - 1 do
        local item = all:get(i)
        local location = item and Utils.lower(safeScriptString(item, "getBodyLocation")) or ""
        local fullName = item and safeScriptString(item, "getFullName") or ""
        if location ~= "" and fullName ~= "" then
            wearables = wearables + 1
            local discomfort = originalDiscomfort(item, fullName)
            local burdenKg = 0
            if not Utils.toBoolean(safeMethod(item, "isCosmetic")) then
                burdenKg = LoadModel.burdenFromStats(
                    Config,
                    tonumber(safeMethod(item, "getActualWeight")) or 0,
                    discomfort,
                    0,
                    location
                )
            end
            local combat = SpeedRebalance.combatSpeedModifier(location, burdenKg)
            if combat < 1.0 then
                swingChain = swingChain + 1
            end
            safeDoParam(item, string.format("CombatSpeedModifier = %.2f", combat))
            safeDoParam(item, "DiscomfortModifier = 0.00")
        end
    end
    return wearables, swingChain
end

local function applySpeedRebalance()
    local sm = ScriptManager and ScriptManager.instance
    if not sm then
        return
    end
    local reslotted, missing = applySlotReslots(sm)
    local ok, wearables, swingChain = pcall(applyWearableRules, sm)
    if not ok then
        Logger.error("SpeedRebalance wearable scan failed: " .. tostring(wearables))
        return
    end
    LoadModel.clearSignalCache()
    Logger.debug(string.format(
        "SpeedRebalance: wearables=%d swing_chain_penalized=%d reslotted=%d missing=%d",
        wearables, swingChain, reslotted, missing
    ))
end

SpeedRebalance.apply = applySpeedRebalance

function SpeedRebalance.registerEvents()
    for eventName, handler in pairs(SpeedRebalance._eventHandlers or {}) do
        local event = Events and Events[eventName] or nil
        if event and type(event.Remove) == "function" then
            pcall(event.Remove, handler)
        end
    end

    local handlers = {}
    local registeredCount = 0
    local eventNames = { "OnGameBoot", "OnMainMenuEnter", "OnGameStart" }
    for i = 1, #eventNames do
        local eventName = eventNames[i]
        local event = Events and Events[eventName] or nil
        if event and type(event.Add) == "function" then
            event.Add(applySpeedRebalance)
            handlers[eventName] = applySpeedRebalance
            registeredCount = registeredCount + 1
        end
    end
    SpeedRebalance._eventHandlers = handlers
    ArmorMakesSense._speedRebalanceLoaded = registeredCount > 0
    return ArmorMakesSense._speedRebalanceLoaded
end

SpeedRebalance.registerEvents()

return SpeedRebalance
