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
local NORM_FLOOR = 0.05
local VALIDITY_DEFAULTS = {
    movement_uptime_min = 0.70,
    attack_success_ratio_min = 0.50,
    valid_sample_ratio_min = 0.85,
    completion_ratio_min = 0.50,
}

local REPORT_DEFAULTS = {
    stability_cv_warn = 0.15,
    separation_ratio_denominator_min = 0.005,
    separation_ratio_min = 1.2,
}

local FITNESS_STIFFNESS_GROUPS = { "arms", "chest", "abs", "legs" }
local REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT = 0.02
local REAL_SLEEP_SAFETY_HOURS_DEFAULT = 16.0
local REAL_SLEEP_ENTRY_GRACE_SECONDS = 90.0
local BENCH_WEAPON_CANDIDATES = {
    "Base.BaseballBat",
    "Base.Crowbar",
    "Base.Machete",
    "Base.Sword",
}

-- -----------------------------------------------------------------------------
-- Context propagation and shared utility imports
-- -----------------------------------------------------------------------------

local clamp = BenchUtils.clamp
local safeMethod = BenchUtils.safeMethod
local toBoolArg = BenchUtils.toBoolArg
local boolTag = BenchUtils.boolTag

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

local function normalizeRestoreSpeed(value)
    local speed = tonumber(value) or 1.0
    if speed < 1.0 then return 1.0 end
    return speed
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
local registerNativeTickPump = BenchRunnerRuntime.registerNativeTickPump
local unregisterNativeTickPump = BenchRunnerRuntime.unregisterNativeTickPump

local function setIsoPlayerTestAIMode(enabled)
    local classRef = type(rawget) == "function" and rawget(_G, "IsoPlayer") or (_G and _G.IsoPlayer)
    if classRef == nil then return false end
    local target = enabled == true
    local ok = pcall(function() classRef.isTestAIMode = target end)
    if not ok then return false end
    local readOk, value = pcall(function() return classRef.isTestAIMode end)
    if readOk and type(value) == "boolean" then return value == target end
    return true
end

-- -----------------------------------------------------------------------------
-- Snapshot stream delegates
-- -----------------------------------------------------------------------------

local benchSnapshotAppend = BenchRunnerSnapshot.benchSnapshotAppend
local openStreamWriter = BenchRunnerSnapshot.openStreamWriter
local streamLine = BenchRunnerSnapshot.streamLine
local streamAppend = BenchRunnerSnapshot.streamAppend
local closeStreamWriter = BenchRunnerSnapshot.closeStreamWriter

local function streamActive(runner)
    return type(runner) == "table" and runner.streamWriterOpen == true and runner.streamWriterFailed ~= true and runner.streamWriter ~= nil
end

local function writeBenchSnapshotFile(runner, reason)
    return BenchRunnerSnapshot.writeBenchSnapshotFile(runner, reason, nowMinutes, NORM_FLOOR)
end

-- -----------------------------------------------------------------------------
-- Environment module delegates
-- -----------------------------------------------------------------------------

local distance2D = BenchRunnerEnv.distance2D
local readPlayerCoords = BenchRunnerEnv.readPlayerCoords
local snapPlayerToCoords = BenchRunnerEnv.snapPlayerToCoords
local readClimateSnapshot = BenchRunnerEnv.readClimateSnapshot
local getThermoregulator = BenchRunnerEnv.getThermoregulator
local readThermoregulatorMetrics = BenchRunnerEnv.readThermoregulatorMetrics
local readClothingCondition = BenchRunnerEnv.readClothingCondition
local applyNativeActivityMode = BenchRunnerEnv.applyNativeActivityMode
local stabilizeNativeCombatStance = BenchRunnerEnv.stabilizeNativeCombatStance
local clearNativeMovementState = BenchRunnerEnv.clearNativeMovementState

-- -----------------------------------------------------------------------------
-- Native driver dependency bundle
-- -----------------------------------------------------------------------------

local metricOrNa
local setNativeTimeOfDay
local buildPatrolWaypoints
local logNativeProbe
local equipRequestedWeapon
local logWeaponSelection

local function nativeDeps()
    return {
        ctx = ctx,
        clamp = clamp,
        toBoolArg = toBoolArg,
        nowMinutes = nowMinutes,
        safeMethod = safeMethod,
        boolTag = boolTag,
        metricOrNa = metricOrNa,
        benchSnapshotAppend = benchSnapshotAppend,
        runtimeRunKey = runtimeRunKey,
        getRuntimeBenchRunner = getRuntimeBenchRunner,
        registerNativeTickPump = registerNativeTickPump,
        unregisterNativeTickPump = unregisterNativeTickPump,
        setIsoPlayerTestAIMode = setIsoPlayerTestAIMode,
        setNativeTimeOfDay = setNativeTimeOfDay,
        distance2D = distance2D,
        readPlayerCoords = readPlayerCoords,
        snapPlayerToCoords = snapPlayerToCoords,
        readClimateSnapshot = readClimateSnapshot,
        applyNativeActivityMode = applyNativeActivityMode,
        stabilizeNativeCombatStance = stabilizeNativeCombatStance,
        clearNativeMovementState = clearNativeMovementState,
        buildPatrolWaypoints = buildPatrolWaypoints,
        equipRequestedWeapon = equipRequestedWeapon,
        logWeaponSelection = logWeaponSelection,
        logNativeProbe = logNativeProbe,
    }
end

setNativeTimeOfDay = BenchRunnerEnv.setNativeTimeOfDay

local readWeatherSpec = BenchRunnerEnv.readWeatherSpec
local applyWeatherOverrides = BenchRunnerEnv.applyWeatherOverrides
local refreshWeatherOverrides = BenchRunnerEnv.refreshWeatherOverrides
local clearWeatherOverrides = BenchRunnerEnv.clearWeatherOverrides
local clearExecWeatherOverride = BenchRunnerEnv.clearExecWeatherOverride

buildPatrolWaypoints = BenchRunnerEnv.buildPatrolWaypoints

local normalizeLoad = BenchRunnerEnv.normalizeLoad
local collectMetrics = BenchRunnerEnv.collectMetrics

metricOrNa = BenchUtils.metricOrNa

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

local resolveScenarioGateProfile = BenchRunnerStep.resolveScenarioGateProfile

local function resolveThreshold(value, fallback, minValue)
    local parsed = tonumber(value)
    if parsed == nil then
        parsed = fallback
    end
    if minValue ~= nil and parsed < minValue then
        return minValue
    end
    return parsed
end

local evaluateStepGates = BenchRunnerStep.evaluateStepGates

local logStepDone = BenchRunnerStep.logStepDone

logNativeProbe = function(exec, driver, sample)
    local log = ctx("log")
    local line = string.format(
        "[AMS_NATIVE_PROBE] id=%s scenario=%s mode=%s elapsed_sec=%.2f x=%s y=%s moved=%s just_moved=%s is_npc=%s is_aiming=%s has_path=%s goal=%s moving_path=%s started=%s should_move=%s path_len=%s",
        tostring(exec and exec.runId or "na"),
        tostring(exec and exec.scenarioId or "na"),
        tostring(driver and driver.movementMode or "na"),
        tonumber(sample and sample.elapsedSec) or 0,
        metricOrNa(sample and sample.x, 3),
        metricOrNa(sample and sample.y, 3),
        metricOrNa(sample and sample.moved, 4),
        boolTag(sample and sample.justMoved),
        boolTag(sample and sample.isNPC),
        boolTag(sample and sample.isAiming),
        boolTag(sample and sample.hasPath),
        boolTag(sample and sample.goalLocation),
        boolTag(sample and sample.movingUsingPath),
        boolTag(sample and sample.startedMoving),
        boolTag(sample and sample.shouldBeMoving),
        metricOrNa(sample and sample.pathLength, 3)
    )
    local runner = exec and exec.runner or nil
    if streamActive(runner) then
        streamLine(runner, line)
    elseif type(log) == "function" then
        log(line)
    end
end

local function pickThresholdValue(thresholds, key, fallback, minValue)
    local value = nil
    if type(thresholds) == "table" and thresholds[key] ~= nil then
        value = thresholds[key]
    end
    return resolveThreshold(value, fallback, minValue)
end

local function resolveValidityThresholds(plan)
    local thresholds = type(plan and plan.thresholds) == "table" and plan.thresholds or {}
    return {
        movement_uptime_min = pickThresholdValue(thresholds, "movement_uptime_min", VALIDITY_DEFAULTS.movement_uptime_min, 0.0),
        attack_success_ratio_min = pickThresholdValue(thresholds, "attack_success_ratio_min", VALIDITY_DEFAULTS.attack_success_ratio_min, 0.0),
        valid_sample_ratio_min = pickThresholdValue(thresholds, "valid_sample_ratio_min", VALIDITY_DEFAULTS.valid_sample_ratio_min, 0.0),
        completion_ratio_min = pickThresholdValue(thresholds, "completion_ratio_min", VALIDITY_DEFAULTS.completion_ratio_min, 0.0),
    }
end

local function resolveReportThresholds(plan)
    local thresholds = type(plan and plan.thresholds) == "table" and plan.thresholds or {}
    return {
        stability_cv_warn = pickThresholdValue(thresholds, "stability_cv_warn", REPORT_DEFAULTS.stability_cv_warn, 0.0),
        separation_ratio_denominator_min = pickThresholdValue(thresholds, "separation_ratio_denominator_min", REPORT_DEFAULTS.separation_ratio_denominator_min, 0.000001),
        separation_ratio_min = pickThresholdValue(thresholds, "separation_ratio_min", REPORT_DEFAULTS.separation_ratio_min, 0.0),
    }
end

local function resolveBenchLogVerbose(opts)
    if type(opts) ~= "table" then
        return false
    end
    local modeRaw = opts.benchLogMode
    if modeRaw ~= nil then
        local mode = string.lower(tostring(modeRaw))
        if mode == "verbose" or mode == "full" then
            return true
        end
        if mode == "compact" or mode == "summary" then
            return false
        end
    end
    return toBoolArg(opts.benchVerbose)
end

local function resolveMidActivitySampling(opts)
    if type(opts) ~= "table" then
        return false, false, 5.0
    end

    local verboseRaw = opts.midActivityVerbose
    if verboseRaw == nil then
        verboseRaw = opts.mid_activity_verbose
    end
    local enabledRaw = opts.midActivitySamples
    if enabledRaw == nil then
        enabledRaw = opts.mid_activity_samples
    end
    if enabledRaw == nil then
        enabledRaw = opts.midSamples
    end
    if enabledRaw == nil and verboseRaw ~= nil then
        enabledRaw = verboseRaw
    end

    local everySec = tonumber(opts.midActivityEverySec)
        or tonumber(opts.mid_activity_every_sec)
        or tonumber(opts.midSampleEverySec)
        or tonumber(opts.mid_sample_every_sec)
        or tonumber(opts.midSampleSec)
        or 5.0

    local verboseEnabled = verboseRaw ~= nil and toBoolArg(verboseRaw) or false
    return toBoolArg(enabledRaw), verboseEnabled, clamp(everySec, 0.25, 120.0)
end

local function resolveCombatSpeedReq(opts)
    local raw = nil
    if type(opts) == "table" then
        raw = opts.combat_speed_req
        if raw == nil then
            raw = opts.combatSpeedReq
        end
    end
    local value = tonumber(raw)
    if not value or value <= 0 then
        return nil
    end
    return value
end

local function resolvePinnedTimeOfDay(opts)
    local raw = nil
    if type(opts) == "table" then
        raw = opts.pinnedTimeOfDay
        if raw == nil then
            raw = opts.pinned_time_of_day
        end
    end

    if raw == false then
        return nil
    end

    if type(raw) == "string" then
        local text = string.lower(tostring(raw))
        if text == "" or text == "false" or text == "off" or text == "none" or text == "nil" or text == "skip" then
            return nil
        end
    end

    local value = tonumber(raw)
    if value == nil then
        return 10.0
    end
    return clamp(value, 0.0, 23.99)
end

local function resolveNativeOptions(opts)
    if type(opts) ~= "table" then
        return {}
    end
    local out = {}
    if opts.nativeProbe ~= nil then
        out.nativeProbe = opts.nativeProbe
    elseif opts.native_probe ~= nil then
        out.nativeProbe = opts.native_probe
    end
    if opts.nativeProbeEverySec ~= nil then
        out.nativeProbeEverySec = opts.nativeProbeEverySec
    elseif opts.native_probe_every_sec ~= nil then
        out.nativeProbeEverySec = opts.native_probe_every_sec
    end
    if opts.nativeAttackCooldownSec ~= nil then
        out.nativeAttackCooldownSec = opts.nativeAttackCooldownSec
    elseif opts.native_attack_cooldown_sec ~= nil then
        out.nativeAttackCooldownSec = opts.native_attack_cooldown_sec
    elseif opts.nativeAttackEverySec ~= nil then
        out.nativeAttackEverySec = opts.nativeAttackEverySec
    end
    return out
end

local function resolveWeaponFlag(value)
    local raw = tostring(value or "")
    if raw == "" then
        return nil
    end
    local key = string.lower(raw)
    local aliases = {
        bat = "Base.BaseballBat",
        baseballbat = "Base.BaseballBat",
        crowbar = "Base.Crowbar",
        machete = "Base.Machete",
        machette = "Base.Machete",
        sword = "Base.Sword",
    }
    if aliases[key] then
        return aliases[key]
    end
    if string.find(raw, ".", 1, true) then
        return raw
    end
    return nil
end

equipRequestedWeapon = function(player, requestedWeapon)
    local equip = ctx("equipBestMeleeWeapon")
    if type(equip) ~= "function" then
        return nil, nil
    end
    local fullType = resolveWeaponFlag(requestedWeapon)
    if fullType then
        return equip(player, { fullType }), fullType
    end
    return equip(player, BENCH_WEAPON_CANDIDATES), nil
end

local function activeWeaponName(player)
    if not player then
        return "none"
    end
    local weapon = safeMethod(player, "getUseHandWeapon") or safeMethod(player, "getPrimaryHandItem")
    if not weapon then
        return "none"
    end
    local fullType = tostring(safeMethod(weapon, "getFullType") or safeMethod(weapon, "getType") or "")
    if fullType ~= "" then
        return fullType
    end
    return tostring(safeMethod(weapon, "getDisplayName") or "unknown")
end

logWeaponSelection = function(exec, mode, requestedWeapon, requestedResolved, equippedWeapon, player)
    local log = ctx("log")
    if type(log) ~= "function" then
        return
    end
    log(string.format(
        "[AMS_BENCH_WEAPON] id=%s set=%s scenario=%s mode=%s requested=%s requested_resolved=%s equipped=%s active=%s",
        tostring(exec and exec.runId or "na"),
        tostring(exec and exec.setDef and exec.setDef.id or "na"),
        tostring(exec and exec.scenarioId or "na"),
        tostring(mode or "na"),
        tostring(requestedWeapon or "auto"),
        tostring(requestedResolved or "auto"),
        tostring(equippedWeapon or "none"),
        tostring(activeWeaponName(player))
    ))
end

local function runActivity(player, state, exec, block)
    return BenchRunnerStep.runActivity(player, state, exec, block, {
        ctx = ctx,
        clamp = clamp,
        setEnv = setEnv,
        safeMethod = safeMethod,
        startNativeDriver = function(playerArg, execArg, blockArg)
            return BenchRunnerNative.startNativeDriver(playerArg, execArg, blockArg, nativeDeps())
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
        skipFitnessResetValues = type(exec and exec.statProfile) == "table",
    })
end

local function processStep(exec, player, state)
    return BenchRunnerStep.processStep(exec, player, state, {
        refreshWeatherOverrides = refreshWeatherOverrides,
        tickNativeDriver = function(playerArg, execArg)
            return BenchRunnerNative.tickNativeDriver(playerArg, execArg, nativeDeps())
        end,
        finalizeNativeActivity = function(playerArg, execArg, driverArg, outcomeArg, reasonArg)
            return BenchRunnerNative.finalizeNativeActivity(playerArg, execArg, driverArg, outcomeArg, reasonArg, nativeDeps())
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

local function hasAsyncScenarios(plan)
    if not BenchScenarios then
        return false
    end
    for _, scenarioId in ipairs(plan.scenarios or {}) do
        if BenchScenarios.isAsyncScenario and BenchScenarios.isAsyncScenario(scenarioId) then
            return true
        end
    end
    return false
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
        resolveThreshold = resolveThreshold,
        resolveScenarioGateProfile = resolveScenarioGateProfile,
        reportDefaults = REPORT_DEFAULTS,
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
    local runKey = runtimeRunKey(runner)
    unregisterNativeTickPump()
    pcall(setIsoPlayerTestAIMode, false)
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
        "[AMS_BENCH_DONE] id=%s preset=%s steps=%d reason=%s restore_success=%s",
        tostring(runner.id),
        tostring(runner.preset),
        tonumber(runner.index) or 0,
        doneReason,
        tostring(restoreSuccess)
    )
    if streamActive(runner) then
        streamAppend(runner, doneLine, "done")
    else
        benchSnapshotAppend(runner.snapshot, doneLine, "done")
    end
    closeStreamWriter(runner)

    local snapshotOk, snapshotPath, snapshotErr = writeBenchSnapshotFile(runner, doneReason)
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
        mode = tostring(runner.mode or "lab"),
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

    if not BenchCatalog.validate() then
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

    if tostring(plan.mode or "lab") == "lab" and hasAsyncScenarios(plan) then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] async scenarios require mode=sim")
        end
        return false
    end

    local state = type(ctx("ensureState")) == "function" and ctx("ensureState")(player) or {}

    local runId = makeRunId()
    setRuntimePending(runId, nil)
    setRuntimeBenchRunner(runId, nil)
    local repeats = math.max(1, math.floor(tonumber(plan.repeats) or 1))
    local validityThresholds = resolveValidityThresholds(plan)
    local reportThresholds = resolveReportThresholds(plan)
    local benchLogVerbose = resolveBenchLogVerbose(runOpts)
    local midSampleEnabled, midSampleVerbose, midSampleEverySec = resolveMidActivitySampling(runOpts)
    local combatSpeedReq = resolveCombatSpeedReq(runOpts)
    local pinnedTimeOfDay = resolvePinnedTimeOfDay(runOpts)
    local nativeOptions = resolveNativeOptions(runOpts)
    local statProfile = type(plan.statProfile) == "table" and plan.statProfile or nil
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
        mode = tostring(plan.mode or "lab"),
        logMode = benchLogMode,
    }

    if type(ctx("setCurrentGameSpeed")) == "function" then
        ctx("setCurrentGameSpeed")(plan.speed)
    end

    local benchStartLine = string.format(
        "[AMS_BENCH_START] id=%s preset=%s setsApplied=%d scenariosApplied=%d repeats=%d speedReq=%.2f speedOrig=%.2f envLocksAllowed=true version=%s label=%s log_mode=%s mid_sample_enabled=%s mid_sample_verbose=%s mid_sample_every_sec=%s norm_floor=%.2f baselineOutfitHash=%s",
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
        NORM_FLOOR,
        baselineHash
    )
    benchStartLine = benchStartLine .. string.format(
        " stat_strength=%s stat_fitness=%s stat_weapon_skill=%s stat_weapon_perk=%s",
        statProfile and tostring(statProfile.strength ~= nil and statProfile.strength or "na") or "na",
        statProfile and tostring(statProfile.fitness ~= nil and statProfile.fitness or "na") or "na",
        statProfile and tostring(statProfile.weaponSkill ~= nil and statProfile.weaponSkill or "na") or "na",
        statProfile and tostring(statProfile.weaponPerk or "all") or "na"
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
        mode = tostring(plan.mode or "lab"),
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
        normFloor = NORM_FLOOR,
        baselineOutfit = baselineOutfit,
        fixedRunAnchor = {
            x = tonumber(runStartX) or 0,
            y = tonumber(runStartY) or 0,
            z = tonumber(runStartZ) or 0,
        },
        envTemp = envSnapshot.temp,
        envWet = envSnapshot.wet,
        combatSpeedReq = combatSpeedReq,
        pinnedTimeOfDay = pinnedTimeOfDay,
        nativeOptions = nativeOptions,
        statProfile = statProfile,
        validityThresholds = validityThresholds,
        reportThresholds = reportThresholds,
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

    if tostring(plan.mode or "lab") == "lab" then
        while true do
            local activeRunner = getRuntimeBenchRunner(runId)
            if not activeRunner or activeRunner.active ~= true then
                break
            end
            BenchRunner.tick(player, state)
        end
        return true
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
            mode = tostring(runner.mode or "lab"),
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
        combatSpeedReq = tonumber(runner.combatSpeedReq) or nil,
        pinnedTimeOfDay = runner.pinnedTimeOfDay,
        nativeOptions = runner.nativeOptions,
        statProfile = runner.statProfile,
        validityThresholds = runner.validityThresholds or {},
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

function BenchRunner.status()
    local player = type(ctx("getLocalPlayer")) == "function" and ctx("getLocalPlayer")() or nil
    local state = player and type(ctx("ensureState")) == "function" and ctx("ensureState")(player) or nil
    local activeHandle = state and state.benchRunner or nil
    local activeRunner = getRuntimeBenchRunner(activeHandle)
    local s = BenchRunner._state
    if activeRunner then
        syncStateBenchRunnerHandle(state, activeRunner)
        s = {
            id = activeRunner.id,
            preset = activeRunner.preset,
            startedAt = activeRunner.startedAt,
            running = true,
            reason = "active",
            steps = activeRunner.index or 0,
            mode = tostring(activeRunner.mode or "lab"),
        }
    elseif activeHandle and activeHandle.active then
        state.benchRunner = nil
    end
    if not s then
        if type(ctx("log")) == "function" then
            ctx("log")("[AMS_BENCH_STATUS] inactive")
        end
        return false
    end
    if type(ctx("log")) == "function" then
        ctx("log")(string.format(
            "[AMS_BENCH_STATUS] id=%s preset=%s running=%s startedAt=%.2f endedAt=%s reason=%s steps=%d",
            tostring(s.id or ""),
            tostring(s.preset or ""),
            tostring(s.running),
            tonumber(s.startedAt) or 0,
            s.endedAt and string.format("%.2f", tonumber(s.endedAt) or 0) or "na",
            tostring(s.reason or "na") .. ":" .. tostring(s.mode or "lab"),
            tonumber(s.steps) or 0
        ))
    end
    return true
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

function BenchRunner.setList(presetId)
    if not BenchCatalog then
        return false
    end
    local ids = BenchCatalog.listSetIds(presetId)
    if type(ctx("log")) == "function" then
        ctx("log")(string.format("[AMS_BENCH_SET_LIST] preset=%s sets=%s", tostring(presetId or "holistic_v1"), table.concat(ids, ",")))
    end
    return true
end

function BenchRunner.scenarioList(presetId)
    if not BenchCatalog then
        return false
    end
    local ids = BenchCatalog.listScenarioIds(presetId)
    if type(ctx("log")) == "function" then
        ctx("log")(string.format("[AMS_BENCH_SCENARIO_LIST] preset=%s scenarios=%s", tostring(presetId or "holistic_v1"), table.concat(ids, ",")))
    end
    return true
end

function BenchRunner.wearSet(presetId, setId)
    if not BenchCatalog then
        return false
    end
    local player = type(ctx("getLocalPlayer")) == "function" and ctx("getLocalPlayer")() or nil
    if not player then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] no local player")
        end
        return false
    end

    local wanted = tostring(setId or "")
    if wanted == "" then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] wear set needs set id")
        end
        return false
    end

    local setDef = BenchCatalog.getSet(wanted)
    if not setDef then
        if type(ctx("logError")) == "function" then
            ctx("logError")("[AMS_BENCH_ERROR] unknown set '" .. wanted .. "'")
        end
        return false
    end

    local worn, missing = equipSet(player, setDef)
    if type(ctx("log")) == "function" then
        ctx("log")(string.format("[AMS_BENCH_SET] preset=%s set=%s class=%s worn=%d missing=%d", tostring(presetId or "holistic_v1"), wanted, tostring(setDef.class), worn, missing))
    end
    return true
end

return BenchRunner
