ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.ContextBinder = Core.ContextBinder or {}

local Binder = Core.ContextBinder

-- -----------------------------------------------------------------------------
-- Context fan-out
-- -----------------------------------------------------------------------------

local function setContextIfSupported(target, context)
    if target and type(target.setContext) == "function" then
        target.setContext(context)
    end
end

function Binder.bindAll(context, modules)
    if not context or type(modules) ~= "table" then
        return
    end
    setContextIfSupported(modules.Commands, context)
    setContextIfSupported(modules.Benches, context)
    setContextIfSupported(modules.Physiology, context)
    setContextIfSupported(modules.Stats, context)
    setContextIfSupported(modules.Environment, context)
    setContextIfSupported(modules.LoadModel, context)
    setContextIfSupported(modules.UI, context)
    setContextIfSupported(modules.IncidentTrace, context)
    setContextIfSupported(modules.SupportReport, context)
    setContextIfSupported(modules.Combat, context)
    setContextIfSupported(modules.Strain, context)
    setContextIfSupported(modules.Runtime, context)
    setContextIfSupported(modules.BenchCatalog, context)
    setContextIfSupported(modules.BenchScenarios, context)
    setContextIfSupported(modules.BenchRunner, context)
end

return Binder
