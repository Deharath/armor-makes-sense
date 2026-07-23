local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_MPRequestPolicy"] = nil
local Policy = require "ArmorMakesSense_MPRequestPolicy"

local state = {}
Support.assertTrue(Policy.acceptSnapshotRequest(state, 10, 2), "first request accepted")
Support.assertFalse(Policy.acceptSnapshotRequest(state, 11, 2), "request inside interval rejected")
Support.assertTrue(Policy.acceptSnapshotRequest(state, 12, 2), "request at interval accepted")
Support.assertTrue(Policy.acceptSnapshotRequest(state, 1, 2), "wall-clock rewind accepted")
Support.assertFalse(Policy.acceptSnapshotRequest(state, 1.5, 2), "rewound clock establishes new throttle point")
Support.assertFalse(Policy.acceptSnapshotRequest(nil, 10, 2), "missing player state rejected")

print("ams MP request policy checks passed")
