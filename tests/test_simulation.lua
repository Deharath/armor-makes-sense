local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = nil
package.loaded["ArmorMakesSense_Simulation"] = nil
local Simulation = require "ArmorMakesSense_Simulation"

local timingState = {
    lastUpdateGameMinutes = 10,
    pendingCatchupMinutes = 0.25,
}
local elapsed, pending = Simulation.accumulateElapsed(timingState, 12)
Support.assertClose(elapsed, 2, 1e-9, "elapsed accumulation")
Support.assertClose(pending, 2.25, 1e-9, "pending accumulation")

local capped, pendingBeforeCap = Simulation.capActiveCatchup(timingState, true, 0.72)
Support.assertTrue(capped, "active catch-up capped")
Support.assertClose(pendingBeforeCap, 2.25, 1e-9, "pre-cap pending reported")
Support.assertClose(timingState.pendingCatchupMinutes, 1, 1e-9, "active catch-up cap")
Support.assertClose(timingState.lastEnduranceObserved, 0.72, 1e-9, "active baseline anchored")

local function runAdvance(includeEndurance)
    local state = { pendingCatchupMinutes = 5 }
    local calls = {}
    local result = Simulation.advance({
        player = "player",
        state = state,
        options = {
            DtMaxMinutes = 2,
            DtCatchupMaxSlices = 10,
        },
        nowMinutes = 20,
        profile = { physicalLoad = 12 },
        activityFactor = 1.0,
        activityLabel = "run",
        postureLabel = "stand",
        applySleepTransition = function(_, _, _, dtMinutes)
            calls[#calls + 1] = "sleep:" .. tostring(dtMinutes)
        end,
        applyEnduranceModel = includeEndurance and function(_, _, _, dtMinutes)
            calls[#calls + 1] = "endurance:" .. tostring(dtMinutes)
            return -dtMinutes
        end or nil,
        afterSlice = function(slice)
            calls[#calls + 1] = string.format("after:%.1f:%.1f", slice.dtMinutes, slice.nowMinutes)
        end,
    })
    return state, result, table.concat(calls, "|")
end

local spState, spResult, spCalls = runAdvance(true)
local serverState, serverResult, serverCalls = runAdvance(true)
Support.assertEqual(spCalls, serverCalls, "SP and server slice order parity")
Support.assertClose(spState.pendingCatchupMinutes, serverState.pendingCatchupMinutes, 1e-9, "SP and server pending parity")
Support.assertClose(spResult.committedMinutes, serverResult.committedMinutes, 1e-9, "SP and server committed parity")
Support.assertEqual(spResult.committedSlices, 3, "committed slice count")
Support.assertClose(spResult.committedMinutes, 5, 1e-9, "committed minutes")
Support.assertClose(spResult.discardedMinutes, 0, 1e-9, "successful advance discards no time")
Support.assertClose(spResult.pendingMinutes, 0, 1e-9, "pending drained")

local _, sleepResult, sleepCalls = runAdvance(false)
Support.assertFalse(string.find(sleepCalls, "endurance", 1, true), "sleep-only path skips endurance")
Support.assertEqual(sleepResult.committedSlices, 3, "sleep-only slice count")

local limitedState = { pendingCatchupMinutes = 5 }
local limited = Simulation.advance({
    state = limitedState,
    options = { DtMaxMinutes = 2, DtCatchupMaxSlices = 2 },
    applySleepTransition = function() end,
})
Support.assertEqual(limited.committedSlices, 2, "max slice limit")
Support.assertClose(limited.pendingMinutes, 1, 1e-9, "max slice remainder")

local failureState = { pendingCatchupMinutes = 2 }
local failure = Simulation.advance({
    state = failureState,
    options = { DtMaxMinutes = 1 },
    applySleepTransition = function()
        error("sleep failure")
    end,
})
Support.assertEqual(failure.failurePhase, "sleep", "failure phase")
Support.assertEqual(failure.attemptedSlices, 1, "failed slice attempted")
Support.assertEqual(failure.committedSlices, 0, "failed slice not committed")
Support.assertClose(failure.committedMinutes, 0, 1e-9, "failed slice committed time")
Support.assertClose(failure.discardedMinutes, 1, 1e-9, "failed slice explicitly discarded")
Support.assertClose(failure.pendingMinutes, 1, 1e-9, "failed slice removed from pending")

local abortState = { pendingCatchupMinutes = 4 }
local aborted = Simulation.advance({
    state = abortState,
    options = { DtMaxMinutes = 1 },
    applySleepTransition = function() end,
    afterSlice = function()
        return { abort = true, clearPending = true }
    end,
})
Support.assertTrue(aborted.aborted, "abort directive honored")
Support.assertEqual(aborted.committedSlices, 1, "abort stops after committed slice")
Support.assertClose(aborted.pendingMinutes, 0, 1e-9, "abort clears pending")

print("ams shared simulation checks passed")
