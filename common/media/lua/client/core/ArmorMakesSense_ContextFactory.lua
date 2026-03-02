ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.ContextFactory = Core.ContextFactory or {}

local Factory = Core.ContextFactory

-- -----------------------------------------------------------------------------
-- Context assembly
-- -----------------------------------------------------------------------------

local function mergeInto(target, source)
    if type(source) ~= "table" then
        return
    end
    for key, value in pairs(source) do
        target[key] = value
    end
end

function Factory.build(coreA, coreB, coreCStatic)
    local context = {}
    mergeInto(context, coreA)
    mergeInto(context, coreB)
    mergeInto(context, coreCStatic)
    return context
end

return Factory
