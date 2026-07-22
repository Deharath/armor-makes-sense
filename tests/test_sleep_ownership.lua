local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local capabilities = {}
local compat = {
    hasCapability = function(_, provider, capability)
        return provider == "CaffeineMakesSense" and capabilities[capability] == true
    end,
}

package.loaded["ArmorMakesSense_Compat"] = compat
package.loaded["ArmorMakesSense_SleepOwnership"] = nil
local SleepOwnership = require "ArmorMakesSense_SleepOwnership"

Support.assertFalse(SleepOwnership.cmsOwnsPlanner(), "CMS planner ownership defaults off")
Support.assertFalse(SleepOwnership.cmsOwnsFatigue(), "CMS fatigue ownership defaults off")
Support.assertFalse(SleepOwnership.cmsOwnsWakeAdjustment(), "CMS wake ownership defaults off")
Support.assertTrue(
    SleepOwnership.amsOwnsFatigue({ EnableSleepPenaltyModel = true }),
    "enabled standalone AMS owns fatigue"
)
Support.assertFalse(
    SleepOwnership.amsOwnsFatigue({ EnableSleepPenaltyModel = false }),
    "disabled AMS owns no fatigue"
)

capabilities.sleep_planner_coordinator = true
Support.assertTrue(SleepOwnership.cmsOwnsPlanner(), "planner capability delegates only planning")
Support.assertTrue(
    SleepOwnership.amsOwnsFatigue({ EnableSleepPenaltyModel = true }),
    "planner delegation does not surrender fatigue"
)

capabilities.sleep_wake_adjustment_coordinator = true
Support.assertTrue(SleepOwnership.cmsOwnsWakeAdjustment(), "wake capability delegates wake adjustment")
Support.assertTrue(
    SleepOwnership.amsOwnsFatigue({ EnableSleepPenaltyModel = true }),
    "wake delegation does not surrender continuous fatigue"
)

capabilities.fatigue_coordinator = true
Support.assertTrue(SleepOwnership.cmsOwnsFatigue(), "fatigue capability delegates fatigue")
Support.assertFalse(
    SleepOwnership.amsOwnsFatigue({ EnableSleepPenaltyModel = true }),
    "CMS fatigue coordinator owns fatigue when present"
)

print("ams sleep ownership checks passed")
