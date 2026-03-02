ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.WearDebug = Core.WearDebug or {}

local WearDebug = Core.WearDebug
local C = {}

-- -----------------------------------------------------------------------------
-- Worn-item telemetry helpers
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function WearDebug.setContext(context)
    C = context or {}
end

function WearDebug.getWornItemCounts(player)
    local counts = {}
    local wornItems = ctx("safeMethod")(player, "getWornItems")
    if not wornItems then
        return counts
    end

    local itemCount = ctx("safeMethod")(wornItems, "size") or 0
    for i = 0, itemCount - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            local fullType = tostring(ctx("safeMethod")(item, "getFullType") or ctx("safeMethod")(item, "getType") or "unknown")
            counts[fullType] = (counts[fullType] or 0) + 1
        end
    end
    return counts
end

function WearDebug.logWearChanges(player, state, options, nowMinutes)
    state.lastWornCounts = WearDebug.getWornItemCounts(player)
end

return WearDebug
