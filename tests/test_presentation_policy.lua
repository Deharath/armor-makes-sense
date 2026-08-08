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

Support.assertClose(Policy.recoveryPenaltyPercent(0.82, 0.01), 18, 1e-9, "active recovery penalty")
Support.assertClose(Policy.recoveryPenaltyPercent(0.82, 0), 0, 1e-9, "inactive recovery has no displayed penalty")
Support.assertClose(Policy.drainPercentPerMinute(0.002, 0.5), 0.4, 1e-9, "drain normalized per minute")
Support.assertClose(Policy.drainPercentPerMinute(0.002, 0), 0, 1e-9, "zero-duration drain is not displayed")
Support.assertClose(Policy.sleepPenaltyPercent(0.125, true), 12.5, 1e-9, "enabled sleep penalty")
Support.assertClose(Policy.sleepPenaltyPercent(0.125, false), 0, 1e-9, "disabled sleep penalty is hidden")
Support.assertClose(Policy.snapshotAgeMinutes(10.5, 10), 0.5, 1e-9, "snapshot age")

Support.assertFalse(Policy.hasThermalPressure(0.2499), "sub-threshold retained heat stays hidden")
Support.assertTrue(Policy.hasThermalPressure(0.25), "meaningful retained heat becomes visible")
Support.assertFalse(Policy.hasBreathingPressure(0), "inactive breathing pressure stays hidden")
Support.assertTrue(Policy.hasBreathingPressure(0.01), "active breathing pressure becomes visible")
Support.assertFalse(Policy.hasSleepPressure(0.15, false), "disabled sleep pressure stays hidden")
Support.assertFalse(Policy.hasSleepPressure(0, true), "inactive sleep pressure stays hidden")
Support.assertTrue(Policy.hasSleepPressure(0.15, true), "active sleep pressure becomes visible")

Support.assertFalse(Policy.hasSleepRestriction(9.99), "sub-threshold sleep restriction")
Support.assertTrue(Policy.hasSleepRestriction(10), "sleep restriction boundary")

print("ams presentation policy checks passed")
