ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.Weapons = Testing.Weapons or {}

local Weapons = Testing.Weapons
local Utils = ArmorMakesSense and ArmorMakesSense.Utils

-- -----------------------------------------------------------------------------
-- Safe-call and item helpers
-- -----------------------------------------------------------------------------

local function safeMethod(deps, target, methodName, ...)
    if Utils and type(Utils.safeMethodFromDeps) == "function" then
        return Utils.safeMethodFromDeps(deps, target, methodName, ...)
    end
    local fn = deps and deps.safeMethod
    if type(fn) == "function" then
        return fn(target, methodName, ...)
    end
    if not target then
        return nil
    end
    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, result = pcall(method, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function createWeaponItem(fullType)
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

local function isEligibleMeleeWeapon(item, deps)
    if not item then
        return false
    end
    if safeMethod(deps, item, "isBroken") == true then
        return false
    end
    local condition = tonumber(safeMethod(deps, item, "getCondition"))
    local conditionMax = tonumber(safeMethod(deps, item, "getConditionMax"))
    if condition ~= nil and conditionMax ~= nil and conditionMax > 0 and condition <= 0 then
        return false
    end
    if safeMethod(deps, item, "isRanged") then
        return false
    end
    if safeMethod(deps, item, "isAimedFirearm") then
        return false
    end
    if safeMethod(deps, item, "isBareHands") then
        return false
    end
    return safeMethod(deps, item, "isUseEndurance") == true
end

local BENCH_WEAPON_MODKEY = "AMSBenchSpawnedWeapon"
Weapons._spawnedByPlayer = Weapons._spawnedByPlayer or {}

-- -----------------------------------------------------------------------------
-- Bench-spawned weapon tracking and cleanup
-- -----------------------------------------------------------------------------

local function itemModData(item, deps)
    if not item then
        return nil
    end
    local data = safeMethod(deps, item, "getModData")
    return type(data) == "table" and data or nil
end

local function playerKey(player, deps)
    local num = tonumber(safeMethod(deps, player, "getPlayerNum"))
    if num ~= nil then
        return "p" .. tostring(num)
    end
    return tostring(player)
end

local function markBenchWeapon(item, player, deps)
    local data = itemModData(item, deps)
    if data then
        data[BENCH_WEAPON_MODKEY] = true
    end
    if player and item then
        Weapons._spawnedByPlayer[playerKey(player, deps)] = item
    end
end

local function clearIfHeld(player, item, deps)
    if not player or not item then
        return
    end
    if safeMethod(deps, player, "getPrimaryHandItem") == item then
        safeMethod(deps, player, "setPrimaryHandItem", nil)
    end
    if safeMethod(deps, player, "getSecondaryHandItem") == item then
        safeMethod(deps, player, "setSecondaryHandItem", nil)
    end
end

local function pushUniqueItem(list, seen, item)
    if not item then
        return
    end
    if seen[item] then
        return
    end
    seen[item] = true
    list[#list + 1] = item
end

local function removeBenchWeapons(player, inventory, deps)
    if not player or not inventory then
        return 0
    end

    local key = playerKey(player, deps)
    local trackedItem = Weapons._spawnedByPlayer[key]
    Weapons._spawnedByPlayer[key] = nil

    local toRemove = {}
    local seen = {}
    pushUniqueItem(toRemove, seen, trackedItem)

    local items = safeMethod(deps, inventory, "getItems")
    if items then
        local sizeNow = math.max(0, math.floor(tonumber(safeMethod(deps, items, "size")) or 0))
        for index = 0, sizeNow - 1 do
            local item = safeMethod(deps, items, "get", index)
            if item then
                local data = itemModData(item, deps)
                if data and data[BENCH_WEAPON_MODKEY] == true then
                    pushUniqueItem(toRemove, seen, item)
                end
            end
        end
    end

    local removed = 0
    for i = 1, #toRemove do
        local item = toRemove[i]
        clearIfHeld(player, item, deps)
        safeMethod(deps, inventory, "DoRemoveItem", item)
        removed = removed + 1
    end

    return removed
end

function Weapons.equipBestMeleeWeapon(player, candidates, deps)
    if not player then
        return nil
    end

    local list = type(candidates) == "table" and candidates or { "Base.BaseballBat", "Base.Crowbar", "Base.Machete", "Base.Sword" }

    local inventory = safeMethod(deps, player, "getInventory")
    if inventory then
        removeBenchWeapons(player, inventory, deps)
    end

    for i = 1, #list do
        local fullType = list[i]
        if type(fullType) == "string" and fullType ~= "" then
            local item = nil
            if inventory then
                item = safeMethod(deps, inventory, "AddItem", fullType)
            end
            if not item then
                item = createWeaponItem(fullType)
                if inventory and item then
                    safeMethod(deps, inventory, "AddItem", item)
                end
            end
            if isEligibleMeleeWeapon(item, deps) then
                markBenchWeapon(item, player, deps)
                local conditionMax = tonumber(safeMethod(deps, item, "getConditionMax"))
                if conditionMax ~= nil and conditionMax > 0 then
                    safeMethod(deps, item, "setCondition", conditionMax)
                end
                safeMethod(deps, player, "setPrimaryHandItem", item)
                safeMethod(deps, player, "setSecondaryHandItem", item)
                local active = safeMethod(deps, player, "getUseHandWeapon") or safeMethod(deps, player, "getPrimaryHandItem")
                if isEligibleMeleeWeapon(active, deps) then
                    return fullType
                end
            end
        end
    end

    return nil
end

function Weapons.clearBenchSpawnedWeapon(player, deps)
    if not player then
        return 0
    end
    local inventory = safeMethod(deps, player, "getInventory")
    if not inventory then
        return 0
    end
    return removeBenchWeapons(player, inventory, deps)
end

return Weapons
