local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_PresentationPolicy"] = nil
local Policy = require "ArmorMakesSense_PresentationPolicy"

Support.assertEqual(Policy.PIP_COUNT, 4, "four-pip strips")
for _, bands in ipairs({ Policy.LOAD_BANDS, Policy.ITEM_BANDS_KG, Policy.HEAT_BANDS, Policy.BREATHING_BANDS, Policy.SLEEP_BANDS }) do
    Support.assertEqual(#bands, Policy.PIP_COUNT, "band table matches pip count")
    for i = 2, #bands do
        Support.assertTrue(bands[i] > bands[i - 1], "bands ascend")
    end
end

Support.assertEqual(Policy.loadPips(0), 0, "no load, no pips")
Support.assertEqual(Policy.loadPips(0.0199), 0, "below the first load band")
Support.assertEqual(Policy.loadPips(0.02), 1, "first load band")
Support.assertEqual(Policy.loadPips(0.13), 3, "third load band")
Support.assertEqual(Policy.loadPips(5), 4, "load pips saturate")
Support.assertEqual(Policy.itemPips(0.99), 0, "sub-kilogram items stay unlit")
Support.assertEqual(Policy.itemPips(6), 4, "heavy item")
Support.assertEqual(Policy.heatPips(0.2), 2, "heat pips")
Support.assertEqual(Policy.breathingPips(1), 4, "sealed mask breathing pips")
Support.assertEqual(Policy.sleepPips(0.2), 3, "sleep pips")
Support.assertEqual(Policy.pips(nil, Policy.LOAD_BANDS), 0, "nil value is zero pips")
Support.assertEqual(Policy.ITEM_TOOLTIP_MIN_KG, Policy.ITEM_BANDS_KG[1], "tooltip threshold is the first item band")

Support.assertEqual(Policy.tier(0), "negligible", "zero-pip tier")
Support.assertEqual(Policy.tier(2), "moderate", "two-pip tier")
Support.assertEqual(Policy.tier(4), "extreme", "four-pip tier")
Support.assertEqual(Policy.tier(nil), "negligible", "nil tier")

Support.assertEqual(Policy.percentChange(1), 0, "vanilla scale")
Support.assertEqual(Policy.percentChange(0.5), -50, "halved recovery")
Support.assertEqual(Policy.percentChange(1.375), 38, "amplified drain rounds")
Support.assertEqual(Policy.percentChange(-0.5), -150, "walk floor below zero")

-- Continuous fill: partial cells between bands, floor matches pips.
local bands = { 1, 2, 4, 8 }
Support.assertClose(Policy.fill(0, bands), 0, 1e-9, "empty fill")
Support.assertClose(Policy.fill(0.5, bands), 0.5, 1e-9, "half of the first cell")
Support.assertClose(Policy.fill(3, bands), 2.5, 1e-9, "half of the third cell")
Support.assertClose(Policy.fill(20, bands), 4, 1e-9, "fill caps at the band count")
for _, v in ipairs({ 0, 0.99, 1, 1.5, 2, 3.9, 4, 7.9, 8, 12 }) do
    Support.assertEqual(math.floor(Policy.fill(v, bands)), Policy.pips(v, bands), "floor(fill) equals pips at " .. v)
end
Support.assertEqual(Policy.armPips(1.4), 0, "light arm gear is free")
Support.assertEqual(Policy.armPips(5), 3, "heavy arm gear")

print("ams presentation policy checks passed")
