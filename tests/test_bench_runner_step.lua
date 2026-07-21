local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    Testing = {
        BenchUtils = {
            clamp = Support.clamp,
            safeMethod = Support.safeMethod,
            toBoolArg = function(value) return value == true end,
            nowMinutes = function() return 0 end,
        },
    },
}
local Step = dofile(
    (os.getenv("AMS_ROOT") or ".")
        .. "/common/media/lua/client/testing/ArmorMakesSense_BenchRunnerStep.lua"
)

local scenario = {
    blocks = {
        { kind = "run_activity", mode = "native_combat_air" },
    },
}

local function combatActivity(swings)
    return {
        achieved_swings = swings,
        requested_swings = 24,
        achieved_sec = 350,
        requested_sec = 420,
        attack_attempts = 24,
        attack_success = 24,
        valid_sample_ratio = 0.95,
        set_integrity = "match",
        step_validity = "valid",
    }
end

local activity = combatActivity(24)
local summary = { armStiffnessDelta = 2.4, loadNormRuntime = 0.8 }
local result = Step.evaluateStepGates({ scenario = scenario, activityResult = activity }, summary)
Support.assertTrue(result.validity_gates_passed, "complete combat sample passes")
Support.assertClose(summary.stiffnessPerSwing, 0.1, 1e-9, "combat outcome is normalized per swing")

activity = combatActivity(23)
result = Step.evaluateStepGates({ scenario = scenario, activityResult = activity }, { loadNormRuntime = 0.8 })
Support.assertFalse(result.validity_gates_passed, "partial combat swing target is rejected")
Support.assertEqual(result.gate_failed, "achieved_swings", "combat completion gate")

activity = combatActivity(24)
result = Step.evaluateStepGates({ scenario = scenario, activityResult = activity }, {})
Support.assertFalse(result.validity_gates_passed, "missing production runtime telemetry is rejected")
Support.assertEqual(result.gate_failed, "runtime_snapshot", "runtime telemetry gate")

local movementScenario = {
    blocks = {
        { kind = "run_activity", mode = "native_treadmill_simple", activity = "run" },
    },
}
local movementActivity = {
    achieved_sec = 60,
    requested_sec = 60,
    valid_sample_ratio = 1,
    movement_uptime = 0.98,
    target_activity_pct = 0.92,
    set_integrity = "match",
    step_validity = "valid",
}
result = Step.evaluateStepGates({ scenario = movementScenario, activityResult = movementActivity }, { loadNormRuntime = 0 })
Support.assertTrue(result.validity_gates_passed, "movement sample at requested intensity passes")
movementActivity.clock_rewind_sec = 60
result = Step.evaluateStepGates({ scenario = movementScenario, activityResult = movementActivity }, { loadNormRuntime = 0 })
Support.assertFalse(result.validity_gates_passed, "movement sample after a clock rewind is rejected")
Support.assertEqual(result.gate_failed, "clock_continuity", "clock continuity gate")
movementActivity.clock_rewind_sec = 0
movementActivity.target_activity_pct = 0.70
result = Step.evaluateStepGates({ scenario = movementScenario, activityResult = movementActivity }, { loadNormRuntime = 0 })
Support.assertFalse(result.validity_gates_passed, "movement at the wrong intensity is rejected")
Support.assertEqual(result.gate_failed, "target_activity_uptime", "movement intensity gate")

local sleepScenario = {
    blocks = {
        { kind = "run_activity", mode = "real_sleep" },
    },
}
local recoveredSleep = {
    exit_reason = "sleep_recovered",
    set_integrity = "match",
    step_validity = "valid",
}
result = Step.evaluateStepGates({ scenario = sleepScenario, activityResult = recoveredSleep }, {})
Support.assertTrue(result.validity_gates_passed, "fatigue-threshold sleep completion passes")

local interruptedSleep = {
    exit_reason = "sleep_woke_external",
    set_integrity = "match",
    step_validity = "valid",
}
result = Step.evaluateStepGates({ scenario = sleepScenario, activityResult = interruptedSleep }, {})
Support.assertFalse(result.validity_gates_passed, "external sleep wake is rejected")
Support.assertEqual(result.gate_failed, "sleep_completion", "sleep completion gate")
Support.assertEqual(interruptedSleep.step_validity, "gate_rejected", "sleep rejection is retained in the artifact")

local unknown = Step.runActivity({}, {}, {}, { mode = "invented_mode", requested_sec = 10 }, {
    clamp = Support.clamp,
    setEnv = function() end,
    safeMethod = Support.safeMethod,
})
Support.assertTrue(unknown.hard_fail, "unknown activity mode fails closed")
Support.assertEqual(unknown.exit_reason, "native_hard_unknown_activity_mode", "unknown activity error")

local sleepRegistrations = 0
local sleepingEvent = {
    setPlayerFallAsleep = function(_, registeredPlayer, hours)
        Support.assertTrue(registeredPlayer ~= nil, "sleep registration player")
        Support.assertEqual(hours, 8, "sleep registration duration")
        sleepRegistrations = sleepRegistrations + 1
    end,
}
getSleepingEvent = function() return sleepingEvent end
getGameTime = function()
    return { getTimeOfDay = function() return 22 end }
end
local sleepPlayer = {
    setForceWakeUpTime = function(self, value) self.wakeHour = value end,
    setAsleepTime = function(self, value) self.asleepTime = value end,
    setAsleep = function(self, value) self.asleep = value end,
}
Step.setContext({
    ensureState = function() return {} end,
})
local sleepActivity = Step.runActivity(sleepPlayer, {}, {}, { mode = "real_sleep", hours = 8 }, {
    clamp = Support.clamp,
    setEnv = function() end,
    safeMethod = Support.safeMethod,
})
Support.assertEqual(sleepActivity.pending_type, "real_sleep", "real sleep starts")
Support.assertTrue(sleepPlayer.asleep, "real sleep sets vanilla asleep state")
Support.assertEqual(sleepRegistrations, 1, "real sleep registers with the vanilla sleeping event")

local carryState = {
    thermalModelState = { hotPressure = 1 },
    uiRuntimeSnapshot = { loadNorm = 1 },
    lastEnduranceObserved = 0.5,
    lastUpdateGameMinutes = 99,
    pendingCatchupMinutes = 4,
}
Step.resetPrepareStateCarryover({}, carryState, {
    ctx = function(name)
        if name == "getEndurance" then
            return function() return 0.9 end
        end
        if name == "getWorldAgeMinutes" then
            return function() return 20 end
        end
        return nil
    end,
})
Support.assertEqual(carryState.thermalModelState, nil, "thermal carryover cleared")
Support.assertEqual(carryState.uiRuntimeSnapshot, nil, "runtime telemetry carryover cleared")
Support.assertClose(carryState.lastEnduranceObserved, 0.9, 1e-9, "endurance observation rebased")
Support.assertClose(carryState.lastUpdateGameMinutes, 20, 1e-9, "runtime clock rebased after time pin")
Support.assertClose(carryState.pendingCatchupMinutes, 0, 1e-9, "runtime catchup cleared after time pin")

local now = 10
local waitExec = {
    pendingStartedAt = now,
    pendingWaitRequestedSec = 30,
}
Support.assertFalse(Step.isPendingComplete({}, {}, "wait_window", waitExec, {
    nowMinutes = function() return now + (29 / 60) end,
}), "recovery wait remains pending")
Support.assertTrue(Step.isPendingComplete({}, {}, "wait_window", waitExec, {
    nowMinutes = function() return now + (30 / 60) end,
}), "recovery wait completes on game time")

local alignedWaitExec = {
    pendingStartedAt = now,
    pendingWaitRequestedSec = 30,
    pendingWaitRuntimeAligned = true,
}
Support.assertFalse(Step.isPendingComplete({}, { uiRuntimeSnapshot = { updatedMinute = now + 0.49 } }, "wait_window", alignedWaitExec, {
    nowMinutes = function() return now + 0.6 end,
}), "runtime-aligned rest rejects a pre-target snapshot")
Support.assertTrue(Step.isPendingComplete({}, { uiRuntimeSnapshot = { updatedMinute = now + 0.5 } }, "wait_window", alignedWaitExec, {
    nowMinutes = function() return now + 0.6 end,
}), "runtime-aligned rest accepts the first post-target snapshot")

local runtimeExec = {
    pendingStartedAt = now,
    pendingWaitRequestedSec = 120,
}
Support.assertFalse(Step.isPendingComplete({}, {}, "runtime_tick", runtimeExec, {
    nowMinutes = function() return now end,
}), "runtime alignment waits for a fresh snapshot")
Support.assertTrue(Step.isPendingComplete({}, { uiRuntimeSnapshot = { updatedMinute = 11 } }, "runtime_tick", runtimeExec, {
    nowMinutes = function() return now + 0.1 end,
}), "runtime alignment accepts a fresh snapshot")

local logged = {}
Step.setContext({
    log = function(line)
        logged[#logged + 1] = line
    end,
})
local formatOk, formatError = pcall(function()
    Step.sampleLog("run", { id = "heavy", class = "armor" }, "scenario", "before", 1, {}, {}, {})
    Step.logStepDone("run", 1, 1, { id = "heavy", class = "armor" }, "scenario", 1, {}, {}, {})
end)
Support.assertTrue(formatOk, formatError or "benchmark log formatting accepts missing metrics")
Support.assertTrue(#logged >= 2, "benchmark sample and step logs emitted")
Support.assertTrue(string.find(logged[1], "airflow_resistance_runtime=na", 1, true) ~= nil, "sample log includes breathing airflow")
Support.assertTrue(string.find(logged[1], "sealed_restriction_runtime=na", 1, true) ~= nil, "sample log includes breathing seal")

local midNow = 20
local midExec = {
    runId = "mid-sample",
    index = 1,
    total = 1,
    repeatIndex = 1,
    blockIndex = 1,
    setDef = { id = "mask_gas", class = "mask" },
    scenarioId = "breathing_treadmill_run",
    scenario = {
        blocks = {
            {
                kind = "run_activity",
                mode = "native_treadmill_simple",
                mid_activity_samples = true,
                mid_activity_every_sec = 30,
                mid_activity_tag = "breathing_live",
            },
        },
    },
    activityResult = {},
    envSnapshot = {},
    midSampleEnabled = false,
    midSampleEverySec = 5,
}
local midCalls = 0
local midDeps = {
    nowMinutes = function() return midNow end,
    collectMetrics = function() return {} end,
    runActivity = function()
        return { pending_type = "native_driver", requested_sec = 60 }
    end,
    tickNativeDriver = function() return "pending", nil end,
    maybeLogMidActivitySample = function(exec)
        midCalls = midCalls + 1
        Support.assertTrue(exec.midSampleEnabled, "scenario enables mid samples")
        Support.assertEqual(exec.midSampleEverySec, 30, "scenario sets sample interval")
        Support.assertEqual(exec.midSampleTag, "breathing_live", "scenario sets sample tag")
    end,
    clearExecWeatherOverride = function() end,
}
local midStatus = Step.processStep(midExec, {}, {}, midDeps)
Support.assertEqual(midStatus, "pending", "native activity starts pending")
Support.assertTrue(midExec.midSampleEnabled, "block override replaces disabled run default")
midNow = midNow + 0.5
midStatus = Step.processStep(midExec, {}, {}, midDeps)
Support.assertEqual(midStatus, "pending", "native activity remains pending")
Support.assertEqual(midCalls, 1, "pending native activity invokes mid sampler")

local completeExec = {
    runId = "process-step",
    index = 1,
    total = 1,
    repeatIndex = 1,
    blockIndex = 1,
    setDef = { id = "naked", class = "baseline" },
    scenarioId = "sample_only",
    scenario = {
        blocks = {
            { kind = "sample_once", tag = "once" },
        },
    },
    activityResult = {
        exit_reason = "completed",
        step_validity = "valid",
    },
    envSnapshot = {},
}
local processStatus, processError = Step.processStep(completeExec, {}, {}, {
    collectMetrics = function() return {} end,
    sampleLog = function() end,
    summarizeStep = function() return {} end,
    snapshotWornHash = function() return "0:" end,
    evaluateStepGates = function() end,
    buildStepResult = function() return { ok = true } end,
    logStepDone = function() end,
    clearExecWeatherOverride = function() end,
})
Support.assertEqual(processStatus, "done", processError or "complete step execution")
Support.assertTrue(completeExec.stepResult.ok, "complete step builds a result")

print("ams benchmark combat gate checks passed")
