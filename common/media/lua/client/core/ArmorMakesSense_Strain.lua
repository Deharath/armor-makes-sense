ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core

local ok, sharedOrErr = pcall(require, "ArmorMakesSense_StrainShared")
if ok and type(sharedOrErr) == "table" then
    Core.Strain = sharedOrErr
else
    Core.Strain = Core.Strain or {}
    print("[ArmorMakesSense][WARN] failed to load shared Strain: " .. tostring(sharedOrErr))
end

return Core.Strain
