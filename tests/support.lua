local Support = {}

Support.ROOT = os.getenv("AMS_ROOT") or "."
Support.SHARED_LUA = Support.ROOT .. "/common/media/lua/shared"

package.path = table.concat({
    Support.SHARED_LUA .. "/?.lua",
    Support.ROOT .. "/common/media/lua/client/?.lua",
    Support.ROOT .. "/common/media/lua/server/?.lua",
    package.path,
}, ";")

local Utils = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_UtilsShared.lua")

function Support.assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s expected %s got %s", tostring(label), tostring(expected), tostring(actual)), 2)
    end
end

function Support.assertTrue(value, label)
    if not value then
        error(tostring(label) .. " expected truthy value", 2)
    end
end

function Support.assertFalse(value, label)
    if value then
        error(tostring(label) .. " expected falsey value", 2)
    end
end

function Support.assertClose(actual, expected, epsilon, label)
    local actualNumber = tonumber(actual)
    local expectedNumber = tonumber(expected)
    local difference = math.abs((actualNumber or 0) - (expectedNumber or 0))
    if actualNumber == nil or expectedNumber == nil or difference > (epsilon or 1e-6) then
        error(string.format(
            "%s expected %.9f got %.9f",
            tostring(label),
            expectedNumber or 0,
            actualNumber or 0
        ), 2)
    end
end

Support.clamp = Utils.clamp
Support.softNorm = Utils.softNorm
Support.toBoolean = Utils.toBoolean
Support.safeMethod = Utils.safeMethod
Support.containsAny = Utils.containsAny

local ITEM_METHODS = {
    fullType = "getFullType",
    type = "getType",
    name = "getName",
    fullName = "getFullName",
    displayName = "getDisplayName",
    modId = "getModID",
    moduleName = "getModuleName",
    bodyLocation = "getBodyLocation",
    displayCategory = "getDisplayCategory",
    bloodClothingType = "getBloodClothingType",
    scratchDefense = "getScratchDefense",
    biteDefense = "getBiteDefense",
    bulletDefense = "getBulletDefense",
    neckProtection = "getNeckProtectionModifier",
    discomfort = "getDiscomfortModifier",
    insulation = "getInsulation",
    windResistance = "getWindResistance",
    waterResistance = "getWaterResistance",
    runSpeedModifier = "getRunSpeedModifier",
    combatSpeedModifier = "getCombatSpeedModifier",
    equippedWeight = "getEquippedWeight",
    actualWeight = "getActualWeight",
    weight = "getWeight",
}

local function makeList(values)
    local list = {}
    function list:size()
        return #values
    end
    function list:get(index)
        return values[index + 1]
    end
    return list
end

function Support.makeItem(fields)
    local values = fields or {}
    local item = {}

    for fieldName, methodName in pairs(ITEM_METHODS) do
        item[methodName] = function()
            return values[fieldName]
        end
    end

    function item:getScriptItem()
        return values.scriptItem
    end
    function item:getTags()
        return makeList(values.tags or {})
    end
    function item:isCosmetic()
        return values.cosmetic == true
    end
    function item:IsInventoryContainer()
        return values.container == true
    end

    return item
end

function Support.makePlayer(wornEntries, fields)
    local player = fields or {}
    local worn = {}
    for i = 1, #(wornEntries or {}) do
        local entry = wornEntries[i]
        worn[i] = {
            getItem = function()
                return entry.item
            end,
            getLocation = function()
                return entry.location
            end,
        }
    end
    local wornList = makeList(worn)
    function player:getWornItems()
        return wornList
    end
    return player
end

function Support.copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

return Support
