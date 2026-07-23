local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_PresentationPolicy"] = nil
local Policy = require "ArmorMakesSense_PresentationPolicy"

Support.assertEqual(Policy.burdenTier(0), "negligible", "empty burden tier")
Support.assertEqual(Policy.burdenTier(6.99), "negligible", "negligible upper edge")
Support.assertEqual(Policy.burdenTier(7), "light", "light boundary")
Support.assertEqual(Policy.burdenTier(20), "moderate", "moderate boundary")
Support.assertEqual(Policy.burdenTier(45), "heavy", "heavy boundary")
Support.assertEqual(Policy.burdenTier(75), "extreme", "extreme boundary")

Support.assertEqual(Policy.breathingTier(0.79, 0), nil, "sub-threshold breathing")
Support.assertEqual(Policy.breathingTier(0.80, 0), "mild", "mild breathing boundary")
Support.assertEqual(Policy.breathingTier(2.00, 0), "restricted", "restricted breathing boundary")
Support.assertEqual(Policy.breathingTier(0.80, 0.1), "heavy", "sealed breathing tier")

Support.assertFalse(Policy.hasSleepRestriction(9.99), "sub-threshold sleep restriction")
Support.assertTrue(Policy.hasSleepRestriction(10), "sleep restriction boundary")

print("ams presentation policy checks passed")
