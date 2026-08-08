local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_MPSnapshotBuilder"] = nil
local Builder = require "ArmorMakesSense_MPSnapshotBuilder"

local drivers = { { label = "Mask" } }
local snapshot = Builder.build({
    lastAppliedDtMinutes = 0.25,
    pendingCatchupMinutes = 0.5,
    lastSleepPenaltyFraction = 0.12,
    lastSleepWakeAdjustment = -0.04,
    uiRuntimeSnapshot = {
        loadNorm = 1.2,
        bodyHeatDelta = 0.31,
        hotDrive = 0.42,
        breathingContribution = 0.13,
        metabolicRate = 2.1,
        metabolicDemand = 2.2,
        metabolicNorm = 0.4,
        breathingEffortRamp = 0.5,
        breathingDynamicLoad = 0.6,
        breathingSealedLoad = 0.7,
        amsEnduranceRegenScale = 0.84,
        amsEnduranceDrainApplied = 0.003,
    },
}, {
    physicalLoad = 20,
    airflowResistance = 1.4,
    sealedRestriction = 0.2,
    rigidityLoad = 12,
    driverCount = 1,
}, drivers, "run", 42)

Support.assertEqual(snapshot.drivers, drivers, "snapshot preserves driver array")
Support.assertEqual(snapshot.activityLabel, "run", "snapshot activity label")
Support.assertClose(snapshot.metabolicRate, 2.1, 1e-9, "snapshot metabolic rate")
Support.assertClose(snapshot.metabolicDemand, 2.2, 1e-9, "snapshot metabolic demand")
Support.assertClose(snapshot.metabolicNorm, 0.4, 1e-9, "snapshot metabolic norm")
Support.assertClose(snapshot.breathingEffortRamp, 0.5, 1e-9, "snapshot breathing ramp")
Support.assertClose(snapshot.breathingDynamicLoad, 0.6, 1e-9, "snapshot dynamic breathing load")
Support.assertClose(snapshot.breathingSealedLoad, 0.7, 1e-9, "snapshot sealed breathing load")
Support.assertClose(snapshot.bodyHeatDelta, 0.31, 1e-9, "snapshot raw body heat delta")
Support.assertClose(snapshot.hotDrive, 0.42, 1e-9, "snapshot governed hot drive")
Support.assertClose(snapshot.amsEnduranceRegenScale, 0.84, 1e-9, "snapshot AMS recovery scale")
Support.assertClose(snapshot.amsEnduranceDrainApplied, 0.003, 1e-9, "snapshot AMS drain")
Support.assertClose(snapshot.sleepPenaltyFraction, 0.12, 1e-9, "snapshot sleep penalty")
Support.assertClose(snapshot.sleepWakeAdjustment, -0.04, 1e-9, "snapshot sleep wake adjustment")
Support.assertClose(snapshot.updatedMinute, 42, 1e-9, "snapshot current-minute fallback")

local defaults = Builder.build({}, {}, nil, nil, 7)
Support.assertClose(defaults.metabolicRate, 1.5, 1e-9, "snapshot metabolic default")
Support.assertClose(defaults.metabolicDemand, 1.5, 1e-9, "snapshot demand default")
Support.assertClose(defaults.updatedMinute, 7, 1e-9, "snapshot default updated minute")

print("ams MP snapshot builder checks passed")
