ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunner = Testing.BenchRunner or {}

local BenchRunner = Testing.BenchRunner
local C = {}

local BenchUtils = Testing.BenchUtils
local BenchCatalog = Testing.BenchCatalog
local BenchScenarios = Testing.BenchScenarios
local BenchRunnerRuntime = Testing.BenchRunnerRuntime
local BenchRunnerEnv = Testing.BenchRunnerEnv
local BenchRunnerSnapshot = Testing.BenchRunnerSnapshot
local BenchRunnerReport = Testing.BenchRunnerReport
local BenchRunnerNative = Testing.BenchRunnerNative
local BenchRunnerStep = Testing.BenchRunnerStep
local buildStepResult

-- -----------------------------------------------------------------------------
-- Module dependency checks
-- -----------------------------------------------------------------------------

local REQUIRED_MODULES = {
    BenchRunnerRuntime = BenchRunnerRuntime,
    BenchRunnerEnv = BenchRunnerEnv,
    BenchRunnerSnapshot = BenchRunnerSnapshot,
    BenchRunnerReport = BenchRunnerReport,
    BenchRunnerNative = BenchRunnerNative,
    BenchRunnerStep = BenchRunnerStep,
}
for name, mod in pairs(REQUIRED_MODULES) do
    if type(mod) ~= "table" then
        error("[ArmorMakesSense] missing testing/ArmorMakesSense_" .. name)
    end
end

local RUN_COUNTER = 0
local FITNESS_STIFFNESS_GROUPS = { "arms", "chest", "abs", "legs" }
local REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT = 0.02
local REAL_SLEEP_SAFETY_HOURS_DEFAULT = 16.0
local REAL_SLEEP_ENTRY_GRACE_SECONDS = 90.0

-- -----------------------------------------------------------------------------
-- Context propagation and shared utility imports
-- -----------------------------------------------------------------------------

local clamp = BenchUtils.clamp
local safeMethod = BenchUtils.safeMethod
local toBoolArg = BenchUtils.toBoolArg

local function ctx(name)
    return C[name]
end

local CONTEXT_MODULES = {
    BenchCatalog, BenchScenarios, BenchRunnerRuntime, BenchRunnerEnv,
    BenchRunnerSnapshot, BenchRunnerReport, BenchRunnerNative, BenchRunnerStep,
}

function BenchRunner.setContext(context)
    C = context or {}
    for _, mod in ipairs(CONTEXT_MODULES) do
        if mod and type(mod.setContext) == "function" then
            mod.setContext(C)
        end
    end
end

local function nowMinutes()
    return BenchUtils.nowMinutes(ctx)
end

local function nowMs()
    return type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
end

local function normalizeRestoreSpeed(value)
    local speed = tonumber(value) or 1.0
    return clamp(speed, 0.05, 40.0)
end

local function makeRunId()
    RUN_COUNTER = RUN_COUNTER + 1
    local minuteStamp = math.floor(nowMinutes() * 100)
    return string.format("%d-%03d", minuteStamp, RUN_COUNTER)
end

-- -----------------------------------------------------------------------------
-- Runtime module delegates
-- -----------------------------------------------------------------------------

local runtimeRunKey = BenchRunnerRuntime.runtimeRunKey
local getRuntimePending = BenchRunnerRuntime.getRuntimePending
local setRuntimePending = BenchRunnerRuntime.setRuntimePending
local getRuntimeBenchRunner = BenchRunnerRuntime.getRuntimeBenchRunner
local setRuntimeBenchRunner = BenchRunnerRuntime.setRuntimeBenchRunner
local getAnyActiveRuntimeBenchRunner = BenchRunnerRuntime.getAnyActiveRuntimeBenchRunner
local syncStateBenchRunnerHandle = BenchRunnerRuntime.syncStateBenchRunnerHandle
local unregisterNativeTickPump = BenchRunnerRuntime.unregisterNativeTickPump

-- -----------------------------------------------------------------------------
-- Snapshot stream delegates
-- -----------------------------------------------------------------------------

local benchSnapshotAppend = BenchRunnerSnapshot.benchSnapshotAppend
local streamAppend = BenchRunnerSnapshot.streamAppend

local function openStreamWriter(runner)
    return BenchRunnerSnapshot.openStreamWriter(runner)
end

local function streamActive(runner)
    return type(runner) == "table" and runner.streamWriterOpen == true and runner.streamWriterFailed ~= true and runner.streamWriter ~= nil
end

local function finalizeBenchLog(runner, reason)
    return BenchRunnerSnapshot.finalizeBenchLog(runner, reason, nowMinutes)
end

-- -----------------------------------------------------------------------------
-- Environment module delegates
-- -----------------------------------------------------------------------------

local readPlayerCoords = BenchRunnerEnv.readPlayerCoords
local getThermoregulator = BenchRunnerEnv.getThermoregulator
local clearNativeMovementState = BenchRunnerEnv.clearNativeMovementState

local setNativeTimeOfDay = BenchRunnerEnv.setNativeTimeOfDay

local readWeatherSpec = BenchRunnerEnv.readWeatherSpec
local applyWeatherOverrides = BenchRunnerEnv.applyWeatherOverrides
local refreshWeatherOverrides = BenchRunnerEnv.refreshWeatherOverrides
local clearExecWeatherOverride = BenchRunnerEnv.clearExecWeatherOverride

local collectMetrics = BenchRunnerEnv.collectMetrics

local metricOrNa = BenchUtils.metricOrNa

local sampleLog = BenchRunnerStep.sampleLog

local function snapshotHash(entries)
    if type(entries) ~= "table" then
        return "none"
    end
    local parts = {}
    for _, entry in ipairs(entries) do
        local fullType = tostring(entry.fullType or entry.type or "?")
        local loc = tostring(entry.location or entry.bodyLocation or "")
        parts[#parts + 1] = fullType .. "@" .. loc
    end
    table.sort(parts)
    return tostring(#parts) .. ":" .. table.concat(parts, "|")
end

local function snapshotWornHash(player)
    local snapshot = type(ctx("snapshotWornItems")) == "function" and ctx("snapshotWornItems")(player) or {}
    return snapshotHash(snapshot)
end

local setEnv = BenchRunnerEnv.setEnv
local restoreOutfit = BenchRunnerEnv.restoreOutfit
local equipSet = BenchRunnerEnv.equipSet

local summarizeStep = BenchRunnerStep.summarizeStep

-- -----------------------------------------------------------------------------
-- Scenario and threshold helpers
-- -----------------------------------------------------------------------------

local evaluateStepGates = BenchRunnerStep.evaluateStepGates

local logStepDone = BenchRunnerStep.logStepDone

local function resolvePinnedTimeOfDay(value)
    if value == false then
        return nil
    end
    return clamp(tonumber(value) or 10.0, 0.0, 23.99)
end

local function runActivity(player, state, exec, block)
    return BenchRunnerStep.runActivity(player, state, exec, block, {
        ctx = ctx,
        clamp = clamp,
        setEnv = setEnv,
        safeMethod = safeMethod,
        startNativeDriver = function(playerArg, execArg, blockArg)
            return BenchRunnerNative.startNativeDriver(playerArg, execArg, blockArg)
        end,
        realSleepFatigueWakeThresholdDefault = REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT,
        realSleepSafetyHoursDefault = REAL_SLEEP_SAFETY_HOURS_DEFAULT,
    })
end

local function isPendingComplete(player, state, pendingType, exec)
    return BenchRunnerStep.isPendingComplete(player, state, pendingType, exec, {
        clamp = clamp,
        nowMinutes = nowMinutes,
        ctx = ctx,
        toBoolArg = toBoolArg,
        safeMethod = safeMethod,
        realSleepFatigueWakeThresholdDefault = REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT,
        realSleepEntryGraceSeconds = REAL_SLEEP_ENTRY_GRACE_SECONDS,
        realSleepSafetyHoursDefault = REAL_SLEEP_SAFETY_HOURS_DEFAULT,
    })
end

local function maybeLogMidActivitySample(exec, player)
    return BenchRunnerStep.maybeLogMidActivitySample(exec, player, {
        clamp = clamp,
        nowMinutes = nowMinutes,
        collectMetrics = collectMetrics,
        sampleLog = sampleLog,
    })
end

local function resetPrepareStateCarryover(player, state)
    return BenchRunnerStep.resetPrepareStateCarryover(player, state, {
        ctx = ctx,
    })
end

local function resetStepMuscleStrainState(player, exec)
    return BenchRunnerStep.resetStepMuscleStrainState(player, {
        safeMethod = safeMethod,
        fitnessStiffnessGroups = FITNESS_STIFFNESS_GROUPS,
        skipFitnessResetValues = false,
    })
end

local function processStep(exec, player, state)
    return BenchRunnerStep.processStep(exec, player, state, {
        refreshWeatherOverrides = refreshWeatherOverrides,
        tickNativeDriver = function(playerArg, execArg)
            return BenchRunnerNative.tickNativeDriver(playerArg, execArg)
        end,
        finalizeNativeActivity = function(playerArg, execArg, driverArg, outcomeArg, reasonArg)
            return BenchRunnerNative.finalizeNativeActivity(playerArg, execArg, driverArg, outcomeArg, reasonArg)
        end,
        snapshotWornHash = snapshotWornHash,
        clearExecWeatherOverride = clearExecWeatherOverride,
        nowMinutes = nowMinutes,
        ctx = ctx,
        setNativeTimeOfDay = setNativeTimeOfDay,
        getThermoregulator = getThermoregulator,
        safeMethod = safeMethod,
        equipSet = equipSet,
        setEnv = setEnv,
        readWeatherSpec = readWeatherSpec,
        applyWeatherOverrides = applyWeatherOverrides,
        clamp = clamp,
        collectMetrics = collectMetrics,
        sampleLog = sampleLog,
        toBoolArg = toBoolArg,
        evaluateStepGates = evaluateStepGates,
        buildStepResult = buildStepResult,
        logStepDone = logStepDone,
        summarizeStep = summarizeStep,
        runActivity = runActivity,
        isPendingComplete = isPendingComplete,
        maybeLogMidActivitySample = maybeLogMidActivitySample,
        resetPrepareStateCarryover = resetPrepareStateCarryover,
    })
end

-- -----------------------------------------------------------------------------
-- Report assembly and run finalization
-- -----------------------------------------------------------------------------

buildStepResult = function(exec, summary)
    return BenchRunnerReport.buildStepResult(exec, summary)
end

local function appendStepResult(runner, stepResult)
    return BenchRunnerReport.appendStepResult(runner, stepResult)
end

local function buildBenchmarkReport(runner)
    return BenchRunnerReport.buildBenchmarkReport(runner, {
        benchScenarios = BenchScenarios,
        metricOrNa = metricOrNa,
    })
end

local function logBenchmarkReport(runner, report)
    return BenchRunnerReport.logBenchmarkReport(runner, report, {
        metricOrNa = metricOrNa,
        benchSnapshotAppend = benchSnapshotAppend,
        emitLine = function(runnerArg, line, markerType)
            if streamActive(runnerArg) then
                streamAppend(runnerArg, line, markerType)
                return
            end
            local log = ctx("log")
            if type(log) == "function" then
                log(line)
            end
            benchSnapshotAppend(runnerArg and runnerArg.snapshot or nil, line, markerType)
        end,
    })
end

local function finalizeRun(player, state, runner, reason)
    if not runner then
        return
    end
    if type(ctx("hideBenchCurtain")) == "function" then
        ctx("hideBenchCurtain")()
    end
    local runKey = runtimeRunKey(runner)
    unregisterNativeTickPump()
    pcall(BenchRunnerEnv.setIsoPlayerTestAIMode, false)
    local pendingExec = getRuntimePending(runKey)
    if pendingExec then
        clearExecWeatherOverride(pendingExec)
    end
    local pendingDriver = pendingExec and pendingExec.nativeDriver or nil
    setRuntimePending(runKey, nil)
    if type(ctx("clearBenchSpawnedWeapon")) == "function" then
        ctx("clearBenchSpawnedWeapon")(player)
    end
    clearNativeMovementState(player, pendingDriver)
    local doneReason = tostring(reason or "completed")

    if type(ctx("setCurrentGameSpeed")) == "function" then
        ctx("setCurrentGameSpeed")(normalizeRestoreSpeed(runner.restoreSpeed))
    end
    safeMethod(player, "forceAwake")
    setEnv(player, runner.envTemp or 37.0, runner.envWet or 0.0)
    local restoreSuccess = restoreOutfit(player, runner.baselineOutfit)
    if type(ctx("resetCharacterToEquilibrium")) == "function" then
        ctx("resetCharacterToEquilibrium")(player)
    end

    if doneReason == "completed" then
        runner.lastReport = buildBenchmarkReport(runner)
        logBenchmarkReport(runner, runner.lastReport)
    end

    local doneLine = string.format(
        "[AMS_BENCH_DONE] id=%s preset=%s steps=%d reason=%s restore_success=%s wall_sec=%.1f",
        tostring(runner.id),
        tostring(runner.preset),
        tonumber(runner.index) or 0,
        doneReason,
        tostring(restoreSuccess),
        math.max(0, nowMs() - (tonumber(runner.wallStartMs) or nowMs())) / 1000.0
    )
    if streamActive(runner) then
        streamAppend(runner, doneLine, "done")
    else
        benchSnapshotAppend(runner.snapshot, doneLine, "done")
    end
    local snapshotOk, snapshotPath, snapshotErr = finalizeBenchLog(runner, doneReason)
    runner.snapshotWriteOk = snapshotOk
    runner.snapshotPath = snapshotPath
    runner.snapshotWriteErr = snapshotErr
    local snapshot = type(runner.snapshot) == "table" and runner.snapshot or {}

    if type(ctx("log")) == "function" then
        ctx("log")(string.format(
            "[AMS_BENCH_SNAPSHOT] id=%s ok=%s path=%s lines=%d step_lines=%d report_lines=%d error=%s",
            tostring(runner.id),
            tostring(snapshotOk),
            tostring(snapshotPath or "na"),
            #(snapshot.lines or {}),
            tonumber(snapshot.stepCount) or 0,
            tonumber(snapshot.reportCount) or 0,
            tostring(snapshotErr or "none")
        ))
    end

    if type(ctx("log")) == "function" then
        ctx("log")(doneLine)
    end

    BenchRunner._state = {
        id = runner.id,
        preset = runner.preset,
        startedAt = runner.startedAt,
        endedAt = nowMinutes(),
        running = false,
        reason = doneReason,
        steps = tonumber(runner.index) or 0,
    }
    if state then
        state.benchRunner = nil
    end
    setRuntimeBenchRunner(runKey, nil)
end

function BenchRunner.run(presetId, opts)
    if not BenchCatalog or not BenchScenarios then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] dependencies unavailable")
        end
        return false
    end

    if type(ctx("isMultiplayer")) == "function" and ctx("isMultiplayer")() then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] benchmarks are singleplayer-only")
        end
        return false
    end

    local scenariosValid, scenarioError = BenchScenarios.validate()
    if not scenariosValid then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] " .. tostring(scenarioError))
        end
        return false
    end

    if not BenchCatalog.validate(BenchScenarios.exists) then
        return false
    end

    local player = type(ctx("getLocalPlayer")) == "function" and ctx("getLocalPlayer")() or nil
    if not player then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] no local player")
        end
        return false
    end

    local runOpts = type(opts) == "table" and opts or {}
    local plan, err = BenchCatalog.resolveRunPlan(presetId, runOpts)
    if not plan then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] " .. tostring(err))
        end
        return false
    end

    local state = type(ctx("ensureState")) == "function" and ctx("ensureState")(player) or {}

    local runId = makeRunId()
    setRuntimePending(runId, nil)
    setRuntimeBenchRunner(runId, nil)
    local repeats = math.max(1, math.floor(tonumber(plan.repeats) or 1))
    local benchLogVerbose = runOpts.benchVerbose == true
    local midSampleEnabled = runOpts.midActivitySamples == true
    local midSampleVerbose = runOpts.midActivityVerbose == true
    local midSampleEverySec = clamp(tonumber(runOpts.midActivityEverySec) or 5.0, 0.25, 120.0)
    local pinnedTimeOfDay = resolvePinnedTimeOfDay(runOpts.pinnedTimeOfDay)
    local nativeOptions = { nativeAttackCooldownSec = runOpts.nativeAttackCooldownSec }
    local benchLogMode = benchLogVerbose and "verbose" or "compact"
    local speedOriginal = tonumber(type(ctx("getCurrentGameSpeed")) == "function" and ctx("getCurrentGameSpeed")() or 1.0) or 1.0
    local baselineOutfit = type(ctx("snapshotWornItems")) == "function" and ctx("snapshotWornItems")(player) or {}
    local baselineHash = snapshotHash(baselineOutfit)

    local envSnapshot = {
        temp = tonumber(type(ctx("getBodyTemperature")) == "function" and ctx("getBodyTemperature")(player) or 37.0) or 37.0,
        wet = tonumber(type(ctx("getWetness")) == "function" and ctx("getWetness")(player) or 0.0) or 0.0,
    }

    BenchRunner._stopRequested = false
    BenchRunner._state = {
        id = runId,
        preset = plan.presetId,
        startedAt = nowMinutes(),
        running = true,
        reason = "active",
        steps = 0,
        logMode = benchLogMode,
    }

    if type(ctx("setCurrentGameSpeed")) == "function" then
        ctx("setCurrentGameSpeed")(plan.speed)
    end

    local benchStartLine = string.format(
        "[AMS_BENCH_START] id=%s preset=%s setsApplied=%d scenariosApplied=%d repeats=%d speedReq=%.2f speedOrig=%.2f envLocksAllowed=true version=%s label=%s log_mode=%s mid_sample_enabled=%s mid_sample_verbose=%s mid_sample_every_sec=%s baselineOutfitHash=%s",
        runId,
        tostring(plan.presetId),
        #plan.sets,
        #plan.scenarios,
        repeats,
        tonumber(plan.speed) or 0,
        speedOriginal,
        tostring(ctx("scriptVersion") or "0.0.0"),
        tostring(plan.label or ""),
        benchLogMode,
        tostring(midSampleEnabled),
        tostring(midSampleVerbose),
        metricOrNa(midSampleEverySec, 2),
        baselineHash
    )
    local log = ctx("log")
    if type(log) == "function" then
        log(benchStartLine)
    end

    local steps = {}
    for _, setDef in ipairs(plan.sets) do
        for _, scenarioId in ipairs(plan.scenarios) do
            for repeatIndex = 1, repeats do
                steps[#steps + 1] = {
                    setDef = setDef,
                    scenarioId = scenarioId,
                    repeatIndex = repeatIndex,
                    repeats = repeats,
                }
            end
        end
    end

    local setOrder = {}
    for _, setDef in ipairs(plan.sets) do
        setOrder[#setOrder + 1] = tostring(setDef.id)
    end

    local scenarioOrder = {}
    for _, scenarioId in ipairs(plan.scenarios) do
        scenarioOrder[#scenarioOrder + 1] = tostring(scenarioId)
    end
    local runStartX, runStartY, runStartZ = readPlayerCoords(player)

    local runner = {
        active = true,
        id = runId,
        preset = plan.presetId,
        label = tostring(plan.label or ""),
        startedAt = BenchRunner._state.startedAt,
        scriptVersion = tostring(ctx("scriptVersion") or "0.0.0"),
        scriptBuild = tostring(ctx("scriptBuild") or "na"),
        index = 0,
        steps = steps,
        total = #steps,
        repeats = repeats,
        setsApplied = #plan.sets,
        scenariosApplied = #plan.scenarios,
        restoreSpeed = speedOriginal,
        speedReq = tonumber(plan.speed) or 0,
        baselineOutfit = baselineOutfit,
        fixedRunAnchor = {
            x = tonumber(runStartX) or 0,
            y = tonumber(runStartY) or 0,
            z = tonumber(runStartZ) or 0,
        },
        envTemp = envSnapshot.temp,
        envWet = envSnapshot.wet,
        pinnedTimeOfDay = pinnedTimeOfDay,
        nativeOptions = nativeOptions,
        thresholds = plan.thresholds,
        setOrder = setOrder,
        scenarioOrder = scenarioOrder,
        logVerbose = benchLogVerbose,
        logMode = benchLogMode,
        midSampleEnabled = midSampleEnabled,
        midSampleVerbose = midSampleVerbose,
        midSampleEverySec = midSampleEverySec,
        snapshot = {
            lines = {},
            startCount = 0,
            stepStartCount = 0,
            sampleCount = 0,
            stepCount = 0,
            reportCount = 0,
            doneCount = 0,
        },
        snapshotWriteOk = nil,
        snapshotPath = nil,
        snapshotWriteErr = nil,
        streamWriter = nil,
        streamWriterPath = nil,
        streamWriterOpen = false,
        streamWriterFailed = false,
        streamWriterErr = nil,
        streamWarned = false,
        lastError = nil,
        lastGateFailed = "none",
        lastStepValidity = "none",
        lastExitReason = "none",
        stepResults = {},
        retryCounts = {},
        wallStartMs = nowMs(),
    }

    setRuntimeBenchRunner(runId, runner)
    syncStateBenchRunnerHandle(state, runner)
    local streamOk = false
    local streamPath = nil
    local streamErr = nil
    streamOk, streamPath, streamErr = openStreamWriter(runner)
    if streamOk then
        runner.streamWriterPath = streamPath
        streamAppend(runner, benchStartLine, "start")
    else
        benchSnapshotAppend(runner.snapshot, benchStartLine, "start")
        if not runner.streamWarned and type(ctx("log")) == "function" then
            runner.streamWarned = true
            ctx("log")(string.format(
                "[AMS_BENCH_STREAM_WARN] id=%s reason=%s mode=fallback_console",
                tostring(runner.id),
                tostring(streamErr or "stream_open_failed")
            ))
        end
    end

    if type(ctx("showBenchCurtain")) == "function" then
        ctx("showBenchCurtain")({
            status = BenchRunner.curtainStatus,
            onDisturb = BenchRunner.noteDisturbance,
            onStop = BenchRunner.stop,
        })
    end

    return true
end

function BenchRunner.tick(player, state)
    local runnerHandle = state and state.benchRunner or nil
    local runner = getRuntimeBenchRunner(runnerHandle)
    if not runner then
        local lastRunId = BenchRunner._state and BenchRunner._state.id or nil
        runner = getRuntimeBenchRunner(lastRunId)
    end
    if not runner or runner.active ~= true then
        if state and state.benchRunner then
            state.benchRunner = nil
        end
        return
    end
    syncStateBenchRunnerHandle(state, runner)

    local pendingExec = getRuntimePending(runner.id)
    local speedReq = tonumber(runner.speedReq)
    local pendingSpeedReq = tonumber(pendingExec and pendingExec.pendingSpeedReq)
    local activeSpeedReq = speedReq
    if pendingSpeedReq and pendingSpeedReq > 0 then
        activeSpeedReq = pendingSpeedReq
    end
    if activeSpeedReq and activeSpeedReq > 0 and type(ctx("setCurrentGameSpeed")) == "function" then
        ctx("setCurrentGameSpeed")(activeSpeedReq)
    end

    if BenchRunner._stopRequested then
        BenchRunner._stopRequested = false
        finalizeRun(player, state, runner, "stopped")
        return
    end

    local function updateStateActive()
        syncStateBenchRunnerHandle(state, runner)
        BenchRunner._state = {
            id = runner.id,
            preset = runner.preset,
            startedAt = runner.startedAt,
            running = true,
            reason = "active",
            steps = runner.index,
        }
    end

    local function processExec(exec)
        local ok, status, err = pcall(processStep, exec, player, state)
        if not ok then
            return "error", tostring(status)
        end
        if status == "pending" then
            return "pending", nil
        end
        if status == "done" then
            return "done", nil
        end
        return "error", tostring(err or "unknown")
    end

    if pendingExec then
        local status, err = processExec(pendingExec)
        if status == "pending" then
            updateStateActive()
            return
        end
        if status == "error" then
            runner.lastError = tostring(err or "unknown")
            if type(ctx("logError")) == "function" then
                ctx("logError")("[AMS_BENCH_ERROR] id=" .. tostring(runner.id) .. " step=" .. tostring(pendingExec.scenarioId) .. " msg=" .. tostring(err))
            end
            finalizeRun(player, state, runner, "partial")
            return
        end
        if pendingExec.retry then
            runner.retryCounts[pendingExec.index] = (tonumber(runner.retryCounts[pendingExec.index]) or 0) + 1
            setRuntimePending(runner.id, nil)
            updateStateActive()
            return
        end
        if pendingExec.stepResult then
            appendStepResult(runner, pendingExec.stepResult)
        end
        runner.index = pendingExec.index
        setRuntimePending(runner.id, nil)
        if runner.index >= (runner.total or 0) then
            finalizeRun(player, state, runner, "completed")
            return
        end
        updateStateActive()
        return
    end

    local nextIndex = (tonumber(runner.index) or 0) + 1
    local step = runner.steps and runner.steps[nextIndex]
    if not step then
        finalizeRun(player, state, runner, "completed")
        return
    end

    local scenario = BenchScenarios and BenchScenarios.get(step.scenarioId)
    if not scenario then
        runner.lastError = "unknown_scenario"
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] id=" .. tostring(runner.id) .. " set=" .. tostring(step.setDef and step.setDef.id) .. " scenario=" .. tostring(step.scenarioId) .. " msg=unknown scenario")
        end
        finalizeRun(player, state, runner, "partial")
        return
    end

    local log = ctx("log")
    local stepStartLine = string.format(
        "[AMS_BENCH_STEP_START] id=%s idx=%d/%d set=%s class=%s scenario=%s repeat_index=%d repeats=%d",
        runner.id,
        nextIndex,
        runner.total,
        tostring(step.setDef.id),
        tostring(step.setDef.class),
        tostring(step.scenarioId),
        tonumber(step.repeatIndex) or 1,
        tonumber(step.repeats) or tonumber(runner.repeats) or 1
    )
    if streamActive(runner) then
        streamAppend(runner, stepStartLine, "step_start")
    elseif type(log) == "function" then
        log(stepStartLine)
        benchSnapshotAppend(runner.snapshot, stepStartLine, "step_start")
    end

    local exec = {
        runId = tostring(runner.id),
        runner = runner,
        snapshot = runner.snapshot,
        setDef = step.setDef,
        scenarioId = step.scenarioId,
        scenario = scenario,
        index = nextIndex,
        total = runner.total,
        retryCount = tonumber(runner.retryCounts[nextIndex]) or 0,
        repeatIndex = tonumber(step.repeatIndex) or 1,
        repeats = tonumber(step.repeats) or tonumber(runner.repeats) or 1,
        blockIndex = 1,
        startMetrics = nil,
        endMetrics = nil,
        activityResult = {
            requested_swings = 0,
            achieved_swings = 0,
            requested_sec = 0,
            achieved_sec = 0,
            exit_reason = "completed",
        },
        pendingType = nil,
        softFail = false,
        pendingSpeedReq = nil,
        pendingStartedAt = nil,
        envSnapshot = {
            temp = runner.envTemp,
            wet = runner.envWet,
        },
        weatherOverride = nil,
        pinnedTimeOfDay = runner.pinnedTimeOfDay,
        nativeOptions = runner.nativeOptions,
        validityThresholds = runner.thresholds or {},
        benchLogVerbose = runner.logVerbose == true,
        midSampleEnabled = runner.midSampleEnabled == true,
        midSampleVerbose = runner.midSampleVerbose == true,
        midSampleEverySec = tonumber(runner.midSampleEverySec) or 5.0,
        midSampleTag = "mid",
        midSampleLastAt = nil,
        midSampleIndex = 0,
    }

    resetStepMuscleStrainState(player, exec)

    local status, err = processExec(exec)
    if status == "pending" then
        setRuntimePending(runner.id, exec)
        updateStateActive()
        return
    end
    if status == "error" then
        runner.lastError = tostring(err or "unknown")
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] id=" .. tostring(runner.id) .. " set=" .. tostring(step.setDef and step.setDef.id) .. " scenario=" .. tostring(step.scenarioId) .. " msg=" .. tostring(err))
        end
        finalizeRun(player, state, runner, "partial")
        return
    end

    if exec.stepResult then
        appendStepResult(runner, exec.stepResult)
    end

    runner.index = nextIndex
    if runner.index >= (runner.total or 0) then
        finalizeRun(player, state, runner, "completed")
        return
    end
    updateStateActive()
end

local function activeRunnerAndPending()
    local runner = getAnyActiveRuntimeBenchRunner()
    if not runner or runner.active ~= true then
        return nil, nil
    end
    return runner, getRuntimePending(runner.id)
end

-- Input only spoils a step once its measured window is open (ledger started).
function BenchRunner.noteDisturbance(reason)
    local _, pendingExec = activeRunnerAndPending()
    if pendingExec and pendingExec.ledger and not pendingExec.disturbed then
        pendingExec.disturbed = tostring(reason or "input")
    end
end

function BenchRunner.curtainStatus()
    local runner, pendingExec = activeRunnerAndPending()
    if not runner then
        return nil
    end
    return {
        preset = runner.preset,
        completed = tonumber(runner.index) or 0,
        total = tonumber(runner.total) or 0,
        setId = pendingExec and pendingExec.setDef and pendingExec.setDef.id or nil,
        scenarioId = pendingExec and pendingExec.scenarioId or nil,
        attempt = (tonumber(pendingExec and pendingExec.retryCount) or 0) + 1,
        disturbed = pendingExec and pendingExec.disturbed or nil,
    }
end

function BenchRunner.stop()
    BenchRunner._stopRequested = true
    local player = type(ctx("getLocalPlayer")) == "function" and ctx("getLocalPlayer")() or nil
    local state = player and type(ctx("ensureState")) == "function" and ctx("ensureState")(player) or nil
    local runner = getRuntimeBenchRunner(state and state.benchRunner or nil)
    if not runner then
        runner = getRuntimeBenchRunner(BenchRunner._state and BenchRunner._state.id or nil)
    end
    if not runner then
        runner = getAnyActiveRuntimeBenchRunner()
    end
    if runner and runner.active then
        finalizeRun(player, state, runner, "stopped")
        BenchRunner._stopRequested = false
    end
    local s = BenchRunner._state
    if type(ctx("log")) == "function" then
        ctx("log")(string.format("[AMS_BENCH_STOP] id=%s", tostring(s and s.id or "na")))
    end
    return true
end

return BenchRunner
