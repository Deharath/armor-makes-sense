ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.Gear = Testing.Gear or {}

local Gear = Testing.Gear
local Utils = ArmorMakesSense and ArmorMakesSense.Utils

-- -----------------------------------------------------------------------------
-- Dependency adapters
-- -----------------------------------------------------------------------------

local function dep(name, deps)
    return deps and deps[name]
end

local function safeMethod(deps, target, methodName, ...)
    if Utils and type(Utils.safeMethodFromDeps) == "function" then
        return Utils.safeMethodFromDeps(deps, target, methodName, ...)
    end
    local fn = dep("safeMethod", deps)
    if type(fn) == "function" then
        return fn(target, methodName, ...)
    end
    return nil
end

local function lower(deps, value)
    local fn = dep("lower", deps)
    if type(fn) == "function" then
        return fn(value)
    end
    return value and string.lower(tostring(value)) or ""
end

local function toBoolean(deps, value)
    local fn = dep("toBoolean", deps)
    if type(fn) == "function" then
        return fn(value)
    end
    return value == true
end

function Gear.snapshotWornItems(player, deps)
    local out = {}
    local wornItems = safeMethod(deps, player, "getWornItems")
    local count = tonumber(wornItems and safeMethod(deps, wornItems, "size")) or 0
    for i = 0, count - 1 do
        local worn = safeMethod(deps, wornItems, "get", i)
        local item = worn and safeMethod(deps, worn, "getItem")
        if item then
            out[#out + 1] = {
                fullType = tostring(safeMethod(deps, item, "getFullType") or safeMethod(deps, item, "getType") or ""),
                location = tostring(safeMethod(deps, worn, "getLocation") or ""),
            }
        end
    end
    return out
end

-- -----------------------------------------------------------------------------
-- Inventory and worn-item indexing
-- -----------------------------------------------------------------------------

function Gear.inventoryItemsByType(player, deps)
    local map = {}
    local inv = safeMethod(deps, player, "getInventory")
    local items = inv and safeMethod(deps, inv, "getItems")
    local count = tonumber(items and safeMethod(deps, items, "size")) or 0
    local wornItems = safeMethod(deps, player, "getWornItems")
    for i = 0, count - 1 do
        local item = safeMethod(deps, items, "get", i)
        if item and not toBoolean(deps, safeMethod(deps, wornItems, "contains", item)) then
            local fullType = tostring(safeMethod(deps, item, "getFullType") or safeMethod(deps, item, "getType") or "")
            if fullType ~= "" then
                map[fullType] = map[fullType] or {}
                map[fullType][#map[fullType] + 1] = item
            end
        end
    end
    return map
end

function Gear.wornItemsByType(player, deps)
    local map = {}
    local wornItems = safeMethod(deps, player, "getWornItems")
    local count = tonumber(wornItems and safeMethod(deps, wornItems, "size")) or 0
    for i = 0, count - 1 do
        local worn = safeMethod(deps, wornItems, "get", i)
        local item = worn and safeMethod(deps, worn, "getItem")
        if item then
            local fullType = tostring(safeMethod(deps, item, "getFullType") or safeMethod(deps, item, "getType") or "")
            if fullType ~= "" then
                map[fullType] = map[fullType] or {}
                map[fullType][#map[fullType] + 1] = item
            end
        end
    end
    return map
end

function Gear.resolveItemWearLocation(item, deps)
    if not item then
        return nil
    end
    local loc = safeMethod(deps, item, "getBodyLocation")
    if loc ~= nil then
        return loc
    end
    local scriptItem = safeMethod(deps, item, "getScriptItem")
    loc = scriptItem and safeMethod(deps, scriptItem, "getBodyLocation")
    if loc ~= nil then
        return loc
    end
    loc = safeMethod(deps, item, "canBeEquipped")
    return loc
end

function Gear.isWearableItem(item, wornLocation, deps)
    if not item then
        return false
    end
    local bodyLoc = tostring(wornLocation or safeMethod(deps, item, "getBodyLocation") or "")
    if bodyLoc ~= "" then
        return true
    end
    local canEquip = tostring(safeMethod(deps, item, "canBeEquipped") or "")
    if canEquip ~= "" then
        return true
    end
    local scriptItem = safeMethod(deps, item, "getScriptItem")
    local scriptBodyLoc = tostring(scriptItem and safeMethod(deps, scriptItem, "getBodyLocation") or "")
    return scriptBodyLoc ~= ""
end

function Gear.zeroLiveItemDiscomfortIfWearable(item, wornLocation, deps)
    if not item then
        return false
    end
    if not Gear.isWearableItem(item, wornLocation, deps) then
        return false
    end
    local current = tonumber(safeMethod(deps, item, "getDiscomfortModifier"))
    if current ~= nil and current > 0.0001 then
        safeMethod(deps, item, "setDiscomfortModifier", 0.0)
        return true
    end
    return false
end

function Gear.createItemByFullType(fullType)
    if not fullType or fullType == "" then
        return nil
    end
    if InventoryItemFactory and type(InventoryItemFactory.CreateItem) == "function" then
        local ok, item = pcall(InventoryItemFactory.CreateItem, fullType)
        if ok and item then
            return item
        end
    end
    if type(instanceItem) == "function" then
        local ok, item = pcall(instanceItem, fullType)
        if ok and item then
            return item
        end
    end
    return nil
end

function Gear.resolveSavedLocation(locationString)
    if not locationString or locationString == "" then
        return nil
    end
    if ItemBodyLocation and type(ItemBodyLocation.get) == "function" and ResourceLocation and type(ResourceLocation.of) == "function" then
        local okRL, rl = pcall(ResourceLocation.of, locationString)
        if okRL and rl then
            local okLoc, loc = pcall(ItemBodyLocation.get, rl)
            if okLoc and loc then
                return loc
            end
        end
    end
    return nil
end

function Gear.getBaselineWearEntries()
    return {
        { fullType = "Base.Tshirt_DefaultTEXTURE_TINT", location = "" },
        { fullType = "Base.Trousers_DefaultTEXTURE_TINT", location = "" },
        { fullType = "Base.Socks_Ankle", location = "" },
        { fullType = "Base.Shoes_TrainerTINT", location = "" },
    }
end

local function restoreVirtualItemCondition(item, deps)
    local conditionMax = tonumber(safeMethod(deps, item, "getConditionMax"))
    if conditionMax and conditionMax > 0 then
        safeMethod(deps, item, "setCondition", conditionMax)
    end
end

function Gear.wearProfile(player, profileEntries, mode, deps)
    if not profileEntries then
        return 0, 0, 0
    end
    local baselineEntries = Gear.getBaselineWearEntries()
    local entries = {}
    for _, entry in ipairs(baselineEntries) do
        entries[#entries + 1] = entry
    end
    for _, entry in ipairs(profileEntries) do
        entries[#entries + 1] = entry
    end
    local wearMode = lower(deps, mode or "inventory")
    local useInventory = wearMode ~= "virtual"
    local allowSpawn = wearMode == "spawn" or wearMode == "virtual"
    local invByType = useInventory and Gear.inventoryItemsByType(player, deps) or {}
    local wornByType = Gear.wornItemsByType(player, deps)
    local plan = {}
    local worn = 0
    local missing = 0
    local spawned = 0
    for _, entry in ipairs(entries) do
        local ft = tostring(entry.fullType or "")
        local bucket = invByType[ft]
        local item = bucket and table.remove(bucket, 1) or nil
        if not item then
            local wornBucket = wornByType[ft]
            item = wornBucket and table.remove(wornBucket, 1) or nil
        end
        local created = false
        if not item and allowSpawn then
            item = Gear.createItemByFullType(ft)
            if item then
                spawned = spawned + 1
                created = true
            end
        end
        if item then
            if wearMode == "virtual" then
                restoreVirtualItemCondition(item, deps)
            end
            local loc = Gear.resolveItemWearLocation(item, deps) or Gear.resolveSavedLocation(entry.location)
            if loc ~= nil then
                plan[#plan + 1] = {
                    item = item,
                    loc = loc,
                    created = created,
                }
            else
                missing = missing + 1
            end
        else
            missing = missing + 1
        end
    end

    local byLocation = {}
    local dedupPlan = {}
    for _, step in ipairs(plan) do
        local key = tostring(step.loc)
        local existing = byLocation[key]
        if existing then
            dedupPlan[existing] = step
        else
            dedupPlan[#dedupPlan + 1] = step
            byLocation[key] = #dedupPlan
        end
    end
    plan = dedupPlan

    if #plan == 0 then
        return 0, missing, spawned
    end
    safeMethod(deps, player, "clearWornItems")
    for _, step in ipairs(plan) do
        safeMethod(deps, player, "setWornItem", step.loc, step.item)
        Gear.zeroLiveItemDiscomfortIfWearable(step.item, step.loc, deps)
        worn = worn + 1
    end
    return worn, missing, spawned
end

local BUILTIN_GEAR_PROFILES = {
    light = {
        { fullType = "Base.Vest_BulletCivilian", location = "" },
    },
    heavy = {
        { fullType = "Base.Hat_MetalHelmet", location = "" },
        { fullType = "Base.Cuirass_CoatOfPlates", location = "" },
        { fullType = "Base.Gorget_Metal", location = "" },
        { fullType = "Base.Codpiece_Metal", location = "" },
        { fullType = "Base.Shoulderpad_Articulated_L_Metal", location = "" },
        { fullType = "Base.Shoulderpad_Articulated_R_Metal", location = "" },
        { fullType = "Base.Gloves_MetalArmour", location = "" },
        { fullType = "Base.Vambrace_FullMetal_Left", location = "" },
        { fullType = "Base.Vambrace_FullMetal_Right", location = "" },
        { fullType = "Base.Thigh_ArticMetal_L", location = "" },
        { fullType = "Base.Thigh_ArticMetal_R", location = "" },
        { fullType = "Base.ShinKneeGuard_L_Metal", location = "" },
        { fullType = "Base.ShinKneeGuard_R_Metal", location = "" },
        { fullType = "Base.Belt2", location = "" },
        { fullType = "Base.Tshirt_PoloTINT", location = "" },
        { fullType = "Base.Trousers_DefaultTEXTURE_TINT", location = "" },
        { fullType = "Base.Socks_Long", location = "" },
        { fullType = "Base.Shoes_ArmyBoots", location = "" },
    },
    metal_basic = {
        { fullType = "Base.Hat_MetalHelmet", location = "" },
        { fullType = "Base.Cuirass_Metal", location = "" },
        { fullType = "Base.Gorget_Metal", location = "" },
        { fullType = "Base.Codpiece_Metal", location = "" },
        { fullType = "Base.Gloves_MetalArmour", location = "" },
        { fullType = "Base.Shoulderpad_Metal_L", location = "" },
        { fullType = "Base.Shoulderpad_Metal_R", location = "" },
        { fullType = "Base.Vambrace_Left", location = "" },
        { fullType = "Base.Vambrace_Right", location = "" },
        { fullType = "Base.ThighMetal_L", location = "" },
        { fullType = "Base.ThighMetal_R", location = "" },
        { fullType = "Base.Greave_Left", location = "" },
        { fullType = "Base.Greave_Right", location = "" },
    },
    bulletproof_armor = {
        { fullType = "Base.Hat_RiotHelmet", location = "" },
        { fullType = "Base.Vest_BulletPolice", location = "" },
        { fullType = "Base.Vambrace_BodyArmour_Left_Police", location = "" },
        { fullType = "Base.Vambrace_BodyArmour_Right_Police", location = "" },
        { fullType = "Base.ThighBodyArmour_L_Police", location = "" },
        { fullType = "Base.ThighBodyArmour_R_Police", location = "" },
        { fullType = "Base.GreaveBodyArmour_Left_Police", location = "" },
        { fullType = "Base.GreaveBodyArmour_Right_Police", location = "" },
    },
    tire_armor = {
        { fullType = "Base.Cuirass_Tire", location = "" },
        { fullType = "Base.Shoulderpad_Tire_L", location = "" },
        { fullType = "Base.Shoulderpad_Tire_R", location = "" },
        { fullType = "Base.VambraceTire_Left", location = "" },
        { fullType = "Base.VambraceTire_Right", location = "" },
        { fullType = "Base.ThighTire_L", location = "" },
        { fullType = "Base.ThighTire_R", location = "" },
        { fullType = "Base.GreaveTire_Left", location = "" },
        { fullType = "Base.GreaveTire_Right", location = "" },
    },
    wood_armor = {
        { fullType = "Base.Hat_HockeyMask_Wood", location = "" },
        { fullType = "Base.Cuirass_Wood", location = "" },
        { fullType = "Base.Shoulderpad_Wood_L", location = "" },
        { fullType = "Base.Shoulderpad_Wood_R", location = "" },
        { fullType = "Base.VambraceWood_Left", location = "" },
        { fullType = "Base.VambraceWood_Right", location = "" },
        { fullType = "Base.ThighWood_L", location = "" },
        { fullType = "Base.ThighWood_R", location = "" },
        { fullType = "Base.GreaveWood_Left", location = "" },
        { fullType = "Base.GreaveWood_Right", location = "" },
    },
    military_surplus = {
        { fullType = "Base.Hat_Army", location = "" },
        { fullType = "Base.Vest_BulletArmy", location = "" },
        { fullType = "Base.Jacket_ArmyCamoGreen", location = "" },
        { fullType = "Base.Trousers_CamoGreen", location = "" },
        { fullType = "Base.Shoes_ArmyBoots", location = "" },
        { fullType = "Base.Tshirt_DefaultTEXTURE_TINT", location = "" },
        { fullType = "Base.Socks_Ankle", location = "" },
    },
    military_full = {
        { fullType = "Base.Hat_Army", location = "" },
        { fullType = "Base.Vest_BulletArmy", location = "" },
        { fullType = "Base.Jacket_ArmyCamoGreen", location = "" },
        { fullType = "Base.Trousers_CamoGreen", location = "" },
        { fullType = "Base.Shoes_ArmyBoots", location = "" },
        { fullType = "Base.Vambrace_BodyArmour_Left_Army", location = "" },
        { fullType = "Base.Vambrace_BodyArmour_Right_Army", location = "" },
        { fullType = "Base.ThighBodyArmour_L_Army", location = "" },
        { fullType = "Base.ThighBodyArmour_R_Army", location = "" },
        { fullType = "Base.GreaveBodyArmour_Left_Army", location = "" },
        { fullType = "Base.GreaveBodyArmour_Right_Army", location = "" },
        { fullType = "Base.Tshirt_DefaultTEXTURE_TINT", location = "" },
        { fullType = "Base.Socks_Ankle", location = "" },
    },
    early_scrap = {
        { fullType = "Base.Hat_MetalScrapHelmet", location = "" },
        { fullType = "Base.Cuirass_MetalScrap", location = "" },
        { fullType = "Base.Shoulderpad_MetalScrap_L", location = "" },
        { fullType = "Base.Shoulderpad_MetalScrap_R", location = "" },
        { fullType = "Base.VambraceScrap_Left", location = "" },
        { fullType = "Base.VambraceScrap_Right", location = "" },
        { fullType = "Base.ThighScrapMetal_L", location = "" },
        { fullType = "Base.ThighScrapMetal_R", location = "" },
        { fullType = "Base.GreaveScrap_Left", location = "" },
        { fullType = "Base.GreaveScrap_Right", location = "" },
    },
}

local function cloneProfileEntries(entries)
    local out = {}
    for i = 1, #entries do
        local e = entries[i]
        out[#out + 1] = {
            fullType = tostring(e.fullType or ""),
            location = tostring(e.location or ""),
        }
    end
    return out
end

function Gear.listBuiltInProfileNames()
    local out = {}
    for name in pairs(BUILTIN_GEAR_PROFILES) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

function Gear.getBuiltInGearProfile(profileName, deps)
    local name = lower(deps, profileName or "")
    local profile = BUILTIN_GEAR_PROFILES[name]
    if profile then
        return cloneProfileEntries(profile)
    end
    return nil
end

return Gear
