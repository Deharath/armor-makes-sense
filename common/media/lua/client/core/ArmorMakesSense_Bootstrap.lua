ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Bootstrap = Core.Bootstrap or {}

local Bootstrap = Core.Bootstrap

-- -----------------------------------------------------------------------------
-- Client runtime selection
-- -----------------------------------------------------------------------------

local function readGlobalBool(name)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn)
    if not ok then
        return nil
    end
    return value == true
end

function Bootstrap.resolveClientRole()
    local multiplayer = readGlobalBool("isClient")
    if multiplayer == nil then
        return nil
    end
    if multiplayer then
        return "multiplayer"
    end
    return "singleplayer"
end

function Bootstrap.registerClientRuntime(mod, singleplayerRuntime, multiplayerRuntime)
    if not mod then
        return false, "missing_mod"
    end
    if mod._activeClientRuntimeRole then
        return true, mod._activeClientRuntimeRole
    end

    local role = Bootstrap.resolveClientRole()
    if not role then
        return false, "unknown_role"
    end
    local runtime = role == "multiplayer" and multiplayerRuntime or singleplayerRuntime
    if not runtime or type(runtime.registerEvents) ~= "function" then
        return false, role
    end

    local registered = runtime.registerEvents(mod)
    if registered == false then
        return false, role
    end
    mod._activeClientRuntimeRole = role
    return true, role
end

return Bootstrap
