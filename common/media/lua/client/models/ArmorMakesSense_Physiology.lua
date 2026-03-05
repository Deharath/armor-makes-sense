ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Models = ArmorMakesSense.Models or {}

local Models = ArmorMakesSense.Models

local ok, sharedOrErr = pcall(require, "ArmorMakesSense_PhysiologyShared")
if ok and type(sharedOrErr) == "table" then
    Models.Physiology = sharedOrErr
else
    Models.Physiology = Models.Physiology or {}
    print("[ArmorMakesSense][WARN] failed to load shared Physiology: " .. tostring(sharedOrErr))
end

return Models.Physiology
