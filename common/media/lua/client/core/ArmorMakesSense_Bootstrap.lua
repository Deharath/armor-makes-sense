ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Bootstrap = Core.Bootstrap or {}

local Bootstrap = Core.Bootstrap

-- -----------------------------------------------------------------------------
-- Bootstrap wiring
-- -----------------------------------------------------------------------------

function Bootstrap.bindApi(api, context)
    if not api or type(api) ~= "table" then
        return
    end
    if type(api.setContext) == "function" then
        api.setContext(context or {})
    end
    if type(api.bindGlobals) == "function" then
        api.bindGlobals()
    end
end

function Bootstrap.registerRuntimeEvents(mod, runtime)
    if not mod or not runtime or type(runtime.registerEvents) ~= "function" then
        return
    end
    runtime.registerEvents(mod)
end

return Bootstrap
