ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core

local ok, sharedOrErr = pcall(require, "ArmorMakesSense_EnvironmentShared")
if ok and type(sharedOrErr) == "table" then
    Core.Environment = sharedOrErr
else
    Core.Environment = Core.Environment or {}
    print("[ArmorMakesSense][WARN] failed to load shared Environment: " .. tostring(sharedOrErr))
end

return Core.Environment
