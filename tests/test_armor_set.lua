local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
require "ArmorMakesSense_Config"

local queue = {}
ISTimedActionQueue = {
    add = function(action) queue[#queue + 1] = action end,
    isPlayerDoingAction = function() return false end,
}
ISUnequipAction = { new = function(_, _, item) return { kind = "unequip", item = item } end }
ISWearClothing = { new = function(_, _, item) return { kind = "wear", item = item } end }
ISGrabItemAction = { new = function(_, _, worldItem) return { kind = "grab", item = worldItem:getItem() } end }
ISWorldObjectContextMenu = { grabItemTime = function() return 50 end }
ISInventoryTransferUtil = {
    newInventoryTransferAction = function(_, item) return { kind = "transfer", item = item } end,
}
ISInventoryPaneContextMenu = {
    dropItem = function(item) queue[#queue + 1] = { kind = "drop", item = item } end,
}
isClient = function() return false end

local ArmorSet = require "core/ArmorMakesSense_ArmorSet"

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, i) return values[i + 1] end,
        contains = function(_, x)
            for _, v in ipairs(values) do if v == x then return true end end
            return false
        end,
    }
end

local nextId = 100
local function armor(name, location, discomfort, weight)
    nextId = nextId + 1
    local item = Support.makeItem({
        fullType = "Base." .. name, type = name, displayName = name, bodyLocation = location,
        actualWeight = weight or 2, discomfort = discomfort,
    })
    local id = nextId
    function item:getID() return id end
    function item:isBroken() return false end
    return item
end

local helmet = armor("Helmet", "Hat", 0.1)
local vest = armor("Vest", "TorsoExtraVest", 0.2, 6)
local shirt = armor("Shirt", "Tshirt", 0, 0.2)
local greaves = armor("Greaves", "Calf_Left", 0.1)

local worn, bag, floor = { helmet, vest, shirt }, {}, {}
local inventory = {}
local player = { modData = {} }
function player:getModData() return self.modData end
function player:getInventory() return inventory end
function player:isAsleep() return false end
function player:getWornItems()
    local entries = {}
    for i, item in ipairs(worn) do
        entries[i] = { getItem = function() return item end, getLocation = function() return item:getBodyLocation() end }
    end
    local l = list(entries)
    l.contains = function(_, x)
        for _, item in ipairs(worn) do if item == x then return true end end
        return false
    end
    return l
end
function inventory:getAllEvalRecurse(fn)
    local out = {}
    for _, item in ipairs(worn) do if fn(item) then out[#out + 1] = item end end
    for _, item in ipairs(bag) do if fn(item) then out[#out + 1] = item end end
    return list(out)
end
local bagContainer = {}
local square = { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end }
function square:canReachTo() return true end
function square:getWorldObjects()
    local objects = {}
    for i, item in ipairs(floor) do objects[i] = { getItem = function() return item end } end
    return list(objects)
end
local farSquare = { getWorldObjects = function() return list({}) end }
function player:getCurrentSquare() return square end
getCell = function()
    return { getGridSquare = function(_, x, y) return (x == 10 and y == 10) and square or farSquare end }
end

local options = ArmorMakesSense.DEFAULTS

-- Only rigid gear counts, in worn order.
local status = ArmorSet.status(player, options)
Support.assertEqual(#status.worn, 2, "helmet and vest are armor, shirt is not")
Support.assertEqual(status.worn[1].item, helmet, "worn order kept")
Support.assertEqual(#status.ready, 0, "nothing saved yet")

-- Drop: outer layers first, set remembered.
Support.assertEqual(ArmorSet.takeOff(player, 0, true, options), 2, "two pieces dropped")
Support.assertEqual(queue[1].kind, "drop", "drop path")
Support.assertEqual(queue[1].item, vest, "outer layer first")
Support.assertEqual(queue[2].item, helmet, "inner layer last")
Support.assertEqual(#ArmorSet.saved(player), 2, "set saved")
Support.assertEqual(ArmorSet.saved(player)[1].fullType, "Base.Helmet", "saved in worn order")

-- The actions ran: vest on the floor, helmet in a bag.
worn, floor, bag = { shirt }, { vest }, { helmet }
queue = {}
status = ArmorSet.status(player, options)
Support.assertEqual(#status.worn, 0, "no armor worn")
Support.assertEqual(#status.ready, 2, "both pieces found nearby")
Support.assertEqual(#status.missing, 0, "nothing missing")

-- Wear: pick up, then wear, inner layer first.
function helmet:getContainer() return bagContainer end
function vest:getContainer() return nil end
Support.assertEqual(ArmorSet.putOn(player, options), 2, "two pieces queued")
Support.assertEqual(queue[1].kind, "transfer", "helmet moved out of the bag")
Support.assertEqual(queue[2].kind, "wear", "helmet worn")
Support.assertEqual(queue[2].item, helmet, "inner layer first")
Support.assertEqual(queue[3].kind, "grab", "vest grabbed from the floor")
Support.assertEqual(queue[4].item, vest, "vest worn")

-- A different helmet of the same type still counts when ids change on reload.
worn, floor, bag = { shirt, helmet }, {}, {}
queue = {}
local saved = ArmorSet.saved(player)
saved[1].id, saved[2].id = 1, 2
status = ArmorSet.status(player, options)
Support.assertEqual(status.wornSavedCount, 1, "helmet matched by type")
Support.assertEqual(#status.missing, 1, "vest is gone")
Support.assertEqual(status.missing[1].fullType, "Base.Vest", "missing named")
Support.assertEqual(#status.ready, 0, "nothing to put on")

-- Taking off again keeps saved pieces still lying nearby.
floor = { vest }
worn = { shirt, helmet, greaves }
ArmorSet.takeOff(player, 0, false, options)
Support.assertEqual(queue[1].kind, "unequip", "take off unequips")
saved = ArmorSet.saved(player)
Support.assertEqual(#saved, 3, "nearby vest kept in the set")
Support.assertEqual(saved[1].fullType, "Base.Vest", "nearby piece first")

-- Busy players queue nothing.
queue = {}
ISTimedActionQueue.isPlayerDoingAction = function() return true end
Support.assertEqual(ArmorSet.takeOff(player, 0, false, options), 0, "busy player takes nothing off")
Support.assertEqual(ArmorSet.putOn(player, options), 0, "busy player puts nothing on")
Support.assertEqual(#queue, 0, "no actions queued while busy")

print("ams armor set checks passed")
