ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

-- Take off or drop the stiff gear you wear and put exactly that set back on
-- later. Armor is what AMS treats as rigid: the gear that costs sleep. All
-- changes go through vanilla timed actions, so MP stays server-validated.
local ArmorSet = ArmorMakesSense.Core.ArmorSet or {}
ArmorMakesSense.Core.ArmorSet = ArmorSet

local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Utils = require "ArmorMakesSense_UtilsShared"

ArmorSet.MODDATA_KEY = "AMSArmorSet"

local safe = Utils.safeMethod

local function itemId(item)
    return tonumber(safe(item, "getID"))
end

local function fullTypeOf(item)
    return tostring(safe(item, "getFullType") or "")
end

local function labelOf(item)
    return tostring(safe(item, "getDisplayName") or safe(item, "getName") or fullTypeOf(item))
end

-- Worn armor in worn order (inner layers first).
function ArmorSet.wornArmor(player, options)
    local out = {}
    local worn = safe(player, "getWornItems")
    local count = tonumber(worn and safe(worn, "size")) or 0
    for i = 0, count - 1 do
        local entry = safe(worn, "get", i)
        local item = entry and safe(entry, "getItem")
        if item then
            local location = safe(entry, "getLocation") or safe(item, "getBodyLocation")
            local signal = LoadModel.itemToBurdenSignal(item, location and tostring(location) or nil, options)
            if signal and signal.rigid then
                out[#out + 1] = { item = item, id = itemId(item), fullType = fullTypeOf(item), label = labelOf(item) }
            end
        end
    end
    return out
end

function ArmorSet.saved(player)
    local modData = safe(player, "getModData")
    local list = type(modData) == "table" and modData[ArmorSet.MODDATA_KEY] or nil
    return type(list) == "table" and list or {}
end

function ArmorSet.save(player, pieces)
    local modData = safe(player, "getModData")
    if type(modData) ~= "table" then
        return
    end
    local list = {}
    for i, piece in ipairs(pieces) do
        list[i] = { id = piece.id, fullType = piece.fullType, label = piece.label }
    end
    modData[ArmorSet.MODDATA_KEY] = list
end

-- Matches saved pieces to candidate items: first by item id, then by type
-- (ids may not survive a reload). Each candidate is claimed once.
local function match(saved, candidates)
    local matched, unmatched = {}, {}
    local claimed = {}
    local byId = {}
    for _, c in ipairs(candidates) do
        if c.id then
            byId[c.id] = c
        end
    end
    for i, piece in ipairs(saved) do
        local c = piece.id and byId[piece.id] or nil
        if c then
            claimed[c] = true
            matched[i] = c
        end
    end
    for i, piece in ipairs(saved) do
        if not matched[i] then
            for _, c in ipairs(candidates) do
                if not claimed[c] and c.fullType == piece.fullType then
                    claimed[c] = true
                    matched[i] = c
                    break
                end
            end
        end
        if not matched[i] then
            unmatched[#unmatched + 1] = i
        end
    end
    return matched, unmatched
end

local function wornCandidates(player)
    local out = {}
    local worn = safe(player, "getWornItems")
    local count = tonumber(worn and safe(worn, "size")) or 0
    for i = 0, count - 1 do
        local entry = safe(worn, "get", i)
        local item = entry and safe(entry, "getItem")
        if item then
            out[#out + 1] = { item = item, id = itemId(item), fullType = fullTypeOf(item) }
        end
    end
    return out
end

local function wantedTypes(pieces)
    local types = {}
    for _, piece in ipairs(pieces) do
        types[piece.fullType] = true
    end
    return types
end

local function isWorn(player, item)
    local worn = safe(player, "getWornItems")
    return worn ~= nil and safe(worn, "contains", item) == true
end

local function inventoryCandidates(player, types, out)
    local inventory = safe(player, "getInventory")
    if not inventory then
        return
    end
    local found = safe(inventory, "getAllEvalRecurse", function(item)
        return types[fullTypeOf(item)] == true
    end)
    local count = tonumber(found and safe(found, "size")) or 0
    for i = 0, count - 1 do
        local item = safe(found, "get", i)
        if item and not isWorn(player, item) and not safe(item, "isBroken") then
            out[#out + 1] = { item = item, id = itemId(item), fullType = fullTypeOf(item) }
        end
    end
end

-- Floor items the player can reach without walking: own square and the
-- eight around it, not through walls.
local function floorCandidates(player, types, out)
    local square = safe(player, "getCurrentSquare") or safe(player, "getSquare")
    local cell = type(getCell) == "function" and getCell() or nil
    if not square or not cell then
        return
    end
    local x, y, z = safe(square, "getX"), safe(square, "getY"), safe(square, "getZ")
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = safe(cell, "getGridSquare", x + dx, y + dy, z)
            local reachable = sq == square or (sq and safe(square, "canReachTo", sq) == true)
            local objects = reachable and safe(sq, "getWorldObjects") or nil
            local count = tonumber(objects and safe(objects, "size")) or 0
            for i = 0, count - 1 do
                local worldItem = safe(objects, "get", i)
                local item = worldItem and safe(worldItem, "getItem")
                if item and types[fullTypeOf(item)] and not safe(item, "isBroken") then
                    out[#out + 1] = { item = item, id = itemId(item), fullType = fullTypeOf(item), worldItem = worldItem }
                end
            end
        end
    end
end

-- Saved pieces not on the body, split into the ones found nearby and the
-- ones that are gone.
function ArmorSet.status(player, options)
    local worn = ArmorSet.wornArmor(player, options)
    local saved = ArmorSet.saved(player)
    local _, offIndexes = match(saved, wornCandidates(player))
    local off = {}
    for _, i in ipairs(offIndexes) do
        off[#off + 1] = saved[i]
    end
    local candidates = {}
    if #off > 0 then
        local types = wantedTypes(off)
        inventoryCandidates(player, types, candidates)
        floorCandidates(player, types, candidates)
    end
    local found, missingIndexes = match(off, candidates)
    local ready, missing = {}, {}
    for i, piece in ipairs(off) do
        if found[i] then
            ready[#ready + 1] = { piece = piece, source = found[i] }
        end
    end
    for _, i in ipairs(missingIndexes) do
        missing[#missing + 1] = off[i]
    end
    return {
        worn = worn,
        ready = ready,
        missing = missing,
        wornSavedCount = #saved - #off,
    }
end

local function busy(player)
    if Utils.toBoolean(safe(player, "isAsleep")) then
        return true
    end
    return ISTimedActionQueue and type(ISTimedActionQueue.isPlayerDoingAction) == "function"
        and ISTimedActionQueue.isPlayerDoingAction(player) == true
end
ArmorSet.isBusy = busy

-- Outer layers come off first. Dropping uses vanilla's drop path, which
-- also handles vehicles. Saved pieces still lying nearby stay in the set, so
-- taking off again after a partial re-wear forgets nothing.
function ArmorSet.takeOff(player, playerNum, drop, options)
    local status = ArmorSet.status(player, options)
    local worn = status.worn
    if #worn == 0 or busy(player) then
        return 0
    end
    local keep = {}
    for _, entry in ipairs(status.ready) do
        keep[#keep + 1] = entry.piece
    end
    for _, piece in ipairs(worn) do
        keep[#keep + 1] = piece
    end
    ArmorSet.save(player, keep)
    for i = #worn, 1, -1 do
        local item = worn[i].item
        if drop then
            ISInventoryPaneContextMenu.dropItem(item, playerNum)
        else
            ISTimedActionQueue.add(ISUnequipAction:new(player, item, 50))
        end
    end
    return #worn
end

local function queuePickUp(player, source)
    local inventory = player:getInventory()
    if source.worldItem then
        if type(isClient) == "function" and isClient() then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(
                player, source.item, source.item:getContainer(), inventory))
        else
            local time = ISWorldObjectContextMenu.grabItemTime(player, source.worldItem)
            ISTimedActionQueue.add(ISGrabItemAction:new(player, source.worldItem, time))
        end
    elseif source.item:getContainer() ~= inventory then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(
            player, source.item, source.item:getContainer(), inventory))
    end
end

-- Inner layers go on first, so the saved order is restored.
function ArmorSet.putOn(player, options)
    if busy(player) then
        return 0
    end
    local status = ArmorSet.status(player, options)
    for _, entry in ipairs(status.ready) do
        queuePickUp(player, entry.source)
        ISTimedActionQueue.add(ISWearClothing:new(player, entry.source.item))
    end
    return #status.ready
end

return ArmorSet
