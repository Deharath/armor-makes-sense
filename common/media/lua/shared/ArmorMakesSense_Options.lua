ArmorMakesSense = ArmorMakesSense or {}

local DEFAULTS = require "ArmorMakesSense_Config"
local Utils = require "ArmorMakesSense_UtilsShared"

local Options = ArmorMakesSense.Options or {}
ArmorMakesSense.Options = Options

function Options.get()
    local options = {}
    for key, value in pairs(DEFAULTS) do
        options[key] = value
    end

    local overrides = SandboxVars and SandboxVars.ArmorMakesSense or nil
    if not overrides then
        return options
    end

    for key, value in pairs(overrides) do
        local defaultValue = options[key]
        if type(defaultValue) == "boolean" then
            options[key] = Utils.toBoolean(value)
        elseif type(defaultValue) == "number" then
            options[key] = tonumber(value) or defaultValue
        elseif type(defaultValue) == "string" then
            options[key] = tostring(value)
        end
    end
    return options
end

return Options
