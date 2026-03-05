ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core

local ok, sharedOrErr = pcall(require, "ArmorMakesSense_LoadModelShared")
if ok and type(sharedOrErr) == "table" then
    Core.LoadModel = sharedOrErr
else
    Core.LoadModel = Core.LoadModel or {}
    print("[ArmorMakesSense][WARN] failed to load shared LoadModel: " .. tostring(sharedOrErr))
end

return Core.LoadModel
