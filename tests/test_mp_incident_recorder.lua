local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_MPIncidentRecorder"] = nil
local Recorder = require "ArmorMakesSense_MPIncidentRecorder"
local Schema = require "ArmorMakesSense_MPIncidentSchema"

local mpState = {}
Recorder.clearSession(nil, mpState, 0)

local first = Recorder.recordSlice(nil, mpState, {
    worldMinute = 1,
    reason = "first",
    dtMinutes = Schema.THRESHOLDS.DT_MINUTES,
})
Support.assertEqual(first.seq, 1, "first incident sequence")

for i = 1, Schema.POST_TRIGGER_SLICES do
    Recorder.recordSlice(nil, mpState, {
        worldMinute = 1 + i,
        reason = "settle",
        dtMinutes = 0.1,
    })
end

local firstSeq, firstPayload = Recorder.buildSnapshotIncidentPayload(nil, mpState, 0)
Support.assertEqual(firstSeq, 1, "sealed first incident sequence")
Support.assertTrue(firstPayload.sealed, "first incident seals after post-trigger window")

local second = Recorder.recordSlice(nil, mpState, {
    worldMinute = 100,
    reason = "later",
    pendingCatchupMinutes = Schema.THRESHOLDS.PENDING_CATCHUP_MINUTES,
})
Support.assertEqual(second.seq, 2, "later incident replaces sealed capture")

local secondSeq, secondPayload = Recorder.buildSnapshotIncidentPayload(nil, mpState, firstSeq)
Support.assertEqual(secondSeq, 2, "replacement incident sequence")
Support.assertEqual(secondPayload.trigger, Schema.TRIGGERS.PENDING_CATCHUP, "replacement trigger")
Support.assertEqual(secondPayload.trigger_reason, "later", "replacement trigger reason")
Support.assertFalse(secondPayload.sealed, "replacement collects its own post-trigger window")

Recorder.recordSlice(nil, mpState, {
    worldMinute = 101,
    reason = "overlap",
    dtMinutes = Schema.THRESHOLDS.DT_MINUTES,
})
local activeSeq, activePayload = Recorder.buildSnapshotIncidentPayload(nil, mpState, 0)
Support.assertEqual(activeSeq, 2, "active capture is extended instead of replaced")
Support.assertEqual(activePayload.trigger, Schema.TRIGGERS.PENDING_CATCHUP, "active trigger remains stable")

print("ams MP incident recorder checks passed")
