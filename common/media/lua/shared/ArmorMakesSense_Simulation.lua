ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Simulation = ArmorMakesSense.Simulation or {}

local Simulation = ArmorMakesSense.Simulation

Simulation.ACTIVE_CATCHUP_MAX_MINUTES = 1.0
Simulation.ACTIVE_CATCHUP_RESET_THRESHOLD_MINUTES = 1.10

local function clamp(value, minimum, maximum)
    local numeric = tonumber(value) or 0
    if numeric < minimum then
        return minimum
    end
    if numeric > maximum then
        return maximum
    end
    return numeric
end

function Simulation.accumulateElapsed(state, nowMinutes)
    local now = tonumber(nowMinutes) or 0
    local last = tonumber(state and state.lastUpdateGameMinutes) or now
    local elapsed = math.max(0, now - last)
    local pending = math.max(0, tonumber(state and state.pendingCatchupMinutes) or 0) + elapsed

    state.lastUpdateGameMinutes = now
    state.pendingCatchupMinutes = pending
    return elapsed, pending
end

function Simulation.capActiveCatchup(state, active, currentEndurance)
    local pending = math.max(0, tonumber(state and state.pendingCatchupMinutes) or 0)
    if active ~= true or pending <= Simulation.ACTIVE_CATCHUP_RESET_THRESHOLD_MINUTES then
        return false, pending
    end

    state.pendingCatchupMinutes = Simulation.ACTIVE_CATCHUP_MAX_MINUTES
    state.lastEnduranceObserved = tonumber(currentEndurance)
    return true, pending
end

local function fail(result, phase, failure)
    result.failurePhase = phase
    result.failure = failure
    return result
end

function Simulation.advance(args)
    local state = args and args.state
    local options = args and args.options or {}
    local result = {
        attemptedMinutes = 0,
        committedMinutes = 0,
        discardedMinutes = 0,
        attemptedSlices = 0,
        committedSlices = 0,
        lastDtMinutes = 0,
        pendingMinutes = math.max(0, tonumber(state and state.pendingCatchupMinutes) or 0),
        aborted = false,
    }
    if type(state) ~= "table" then
        return fail(result, "state", "state unavailable")
    end
    if type(args.applySleepTransition) ~= "function" then
        return fail(result, "sleep", "sleep model unavailable")
    end

    local dtCap = math.max(0.01, tonumber(options.DtMaxMinutes) or 3)
    local maxSlices = math.max(1, math.floor(tonumber(options.DtCatchupMaxSlices) or 240))
    local pending = result.pendingMinutes
    local sliceNowMinutes = (tonumber(args.nowMinutes) or 0) - pending

    while pending > 0 and result.attemptedSlices < maxSlices do
        local dtMinutes = clamp(pending, 0, dtCap)
        if dtMinutes <= 0 then
            break
        end

        local pendingAfterSlice = math.max(0, pending - dtMinutes)
        result.attemptedMinutes = result.attemptedMinutes + dtMinutes
        result.attemptedSlices = result.attemptedSlices + 1

        local okSleep, sleepResult = pcall(
            args.applySleepTransition,
            args.player,
            state,
            options,
            dtMinutes,
            args.profile
        )
        if not okSleep then
            pending = pendingAfterSlice
            state.pendingCatchupMinutes = pending
            result.discardedMinutes = result.discardedMinutes + dtMinutes
            result.pendingMinutes = pending
            return fail(result, "sleep", sleepResult)
        end

        local enduranceResult = nil
        if type(args.applyEnduranceModel) == "function" then
            local okEndurance, appliedOrFailure = pcall(
                args.applyEnduranceModel,
                args.player,
                state,
                options,
                dtMinutes,
                args.profile,
                args.activityFactor,
                args.activityLabel,
                args.postureLabel
            )
            if not okEndurance then
                pending = pendingAfterSlice
                state.pendingCatchupMinutes = pending
                result.discardedMinutes = result.discardedMinutes + dtMinutes
                result.pendingMinutes = pending
                return fail(result, "endurance", appliedOrFailure)
            end
            enduranceResult = appliedOrFailure
        end

        if type(args.afterSlice) == "function" then
            local okAfter, directiveOrFailure = pcall(args.afterSlice, {
                dtMinutes = dtMinutes,
                nowMinutes = sliceNowMinutes + dtMinutes,
                enduranceResult = enduranceResult,
                pendingMinutes = pendingAfterSlice,
                slice = result.attemptedSlices,
            })
            if not okAfter then
                pending = pendingAfterSlice
                state.pendingCatchupMinutes = pending
                result.discardedMinutes = result.discardedMinutes + dtMinutes
                result.pendingMinutes = pending
                return fail(result, "after_slice", directiveOrFailure)
            end
            pending = pendingAfterSlice
            state.pendingCatchupMinutes = pending
            state.lastAppliedDtMinutes = dtMinutes
            result.committedMinutes = result.committedMinutes + dtMinutes
            result.committedSlices = result.committedSlices + 1
            result.lastDtMinutes = dtMinutes
            sliceNowMinutes = sliceNowMinutes + dtMinutes
            if type(directiveOrFailure) == "table" and directiveOrFailure.abort == true then
                result.aborted = true
                if directiveOrFailure.clearPending == true then
                    pending = 0
                    state.pendingCatchupMinutes = 0
                end
                break
            end
        else
            pending = pendingAfterSlice
            state.pendingCatchupMinutes = pending
            state.lastAppliedDtMinutes = dtMinutes
            result.committedMinutes = result.committedMinutes + dtMinutes
            result.committedSlices = result.committedSlices + 1
            result.lastDtMinutes = dtMinutes
            sliceNowMinutes = sliceNowMinutes + dtMinutes
        end
    end

    state.pendingCatchupMinutes = math.max(0, pending)
    result.pendingMinutes = state.pendingCatchupMinutes
    return result
end

return Simulation
