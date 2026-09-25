ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunnerStep = Testing.BenchRunnerStep or {}

local BenchRunnerStep = Testing.BenchRunnerStep
local BenchUtils = Testing.BenchUtils
local C = {}
local BenchRunnerSnapshot = Testing.BenchRunnerSnapshot
local BenchRunnerEnv = Testing.BenchRunnerEnv

local VALIDITY_DEFAULTS = {
    movement_uptime_min = 0.70,
    target_activity_uptime_min = 0.85,
    attack_success_ratio_min = 0.50,
    valid_sample_ratio_min = 0.85,
    completion_ratio_min = 0.50,
}

-- -----------------------------------------------------------------------------
-- Context and shared helper adapters
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function BenchRunnerStep.setContext(context)
    C = context or {}
end

local function depOr(deps, key, fallback)
    return (deps and deps[key]) or fallback
end

local function nowMs()
    return type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
end

local function streamActive(runner)
    return type(runner) == "table" and runner.streamWriterOpen == true and runner.streamWriterFailed ~= true and runner.streamWriter ~= nil
end

local function benchSnapshotAppend(snapshot, line, markerType)
    if BenchRunnerSnapshot and type(BenchRunnerSnapshot.benchSnapshotAppend) == "function" then
        return BenchRunnerSnapshot.benchSnapshotAppend(snapshot, line, markerType)
    end
end

local function streamLine(runner, line)
    if BenchRunnerSnapshot and type(BenchRunnerSnapshot.streamLine) == "function" then
        return BenchRunnerSnapshot.streamLine(runner, line)
    end
    return false
end

local function streamAppend(runner, line, markerType)
    if BenchRunnerSnapshot and type(BenchRunnerSnapshot.streamAppend) == "function" then
        return BenchRunnerSnapshot.streamAppend(runner, line, markerType)
    end
    benchSnapshotAppend(runner and runner.snapshot or nil, line, markerType)
    return streamLine(runner, line)
end

local boolTag = BenchUtils.boolTag
local metricOrNa = BenchUtils.metricOrNa

local function isVerboseBenchLog(exec)
    return exec and exec.benchLogVerbose == true
end

local function isSnapshotSampleTag(tag)
    local value = string.lower(tostring(tag or ""))
    return string.sub(value, 1, 6) == "before" or string.sub(value, 1, 5) == "after"
end

local function textSignature(value)
    local text = tostring(value or "")
    local hash = 0
    local mod = 2147483647
    for i = 1, #text do
        hash = ((hash * 131) + string.byte(text, i)) % mod
    end
    return string.format("%d:%d", #text, hash)
end

local function asMetricValue(value)
    if value == nil then
        return nil
    end
    return tonumber(value) or nil
end

local function updateSetIntegrity(activity, expectedHash, actualHash)
    if type(activity) ~= "table" then
        return
    end
    activity.set_expected = expectedHash
    activity.set_actual = actualHash
    activity.set_integrity = (actualHash == expectedHash) and "match" or "mismatch"
    if activity.set_integrity == "mismatch" and tostring(activity.exit_reason or "completed") == "completed" then
        activity.exit_reason = "set_mismatch"
    end
end

-- -----------------------------------------------------------------------------
-- Sample logging
-- -----------------------------------------------------------------------------

function BenchRunnerStep.sampleLog(runId, setDef, scenarioId, tag, sampleIndex, metrics, activity, exec, forceVerbose)
    local log = ctx("log")
    local runner = exec and exec.runner or nil
    local useStream = streamActive(runner)
    if not useStream and type(log) ~= "function" then
        return
    end
    local driver = activity and activity.driver or "na"
    local envSource = activity and activity.env_source or "na"
    local activitySource = activity and activity.activity_source or "na"
    local verbose = forceVerbose == true or isVerboseBenchLog(exec)
    local diagSuffix = " " .. BenchRunnerEnv.formatRuntimeMetrics(metrics.runtime, metricOrNa)
    local line
    if not verbose then
        line = string.format(
            "[AMS_BENCH_SAMPLE] id=%s set=%s class=%s scenario=%s tag=%s sample=%d t=%.2f end=%s thirst=%s fatigue=%s temp=%s skinTemp=%s strainTotal=%s strainPeak=%s armStiffness=%s strainRightArm=%s strainLeftArm=%s strainTorso=%s strainRightLeg=%s strainHandR=%s strainForeArmR=%s strainUpperArmR=%s strainHandL=%s strainForeArmL=%s strainUpperArmL=%s ambientAirTemp=%s externalAirTemp=%s airAndWindTemp=%s thermalChevronUp=%s energyMultiplier=%s fatigueMultiplier=%s setPoint=%s timeOfDay=%s gameHour=%s windSpeed=%s windIntensity=%s clothingCondAvg=%s clothingCondMin=%s clothingCondItems=%d drivers=%d load_fraction=%s driver=%s env_source=%s activity_source=%s",
            runId,
            tostring(setDef.id),
            tostring(setDef.class),
            tostring(scenarioId),
            tostring(tag or "sample"),
            tonumber(sampleIndex) or 1,
            tonumber(metrics.t) or 0,
            metricOrNa(metrics.endurance, 6),
            metricOrNa(metrics.thirst, 6),
            metricOrNa(metrics.fatigue, 6),
            metricOrNa(metrics.temp, 4),
            metricOrNa(metrics.skinTemp, 4),
            metricOrNa(metrics.strainTotal, 4),
            metricOrNa(metrics.strainPeak, 4),
            metricOrNa(metrics.armStiffness, 4),
            metricOrNa(metrics.strainRightArm, 4),
            metricOrNa(metrics.strainLeftArm, 4),
            metricOrNa(metrics.strainTorso, 4),
            metricOrNa(metrics.strainRightLeg, 4),
            metricOrNa(metrics.strainHandR, 4),
            metricOrNa(metrics.strainForeArmR, 4),
            metricOrNa(metrics.strainUpperArmR, 4),
            metricOrNa(metrics.strainHandL, 4),
            metricOrNa(metrics.strainForeArmL, 4),
            metricOrNa(metrics.strainUpperArmL, 4),
            metricOrNa(metrics.ambientAirTemp, 3),
            metricOrNa(metrics.externalAirTemp, 3),
            metricOrNa(metrics.airAndWindTemp, 3),
            boolTag(metrics.thermalChevronUp),
            metricOrNa(metrics.energyMultiplier, 4),
            metricOrNa(metrics.fatigueMultiplier, 4),
            metricOrNa(metrics.setPoint, 3),
            metricOrNa(metrics.timeOfDay, 3),
            metricOrNa(metrics.gameHour, 3),
            metricOrNa(metrics.windSpeed, 3),
            metricOrNa(metrics.windIntensity, 4),
            metricOrNa(metrics.clothingCondAvg, 4),
            metricOrNa(metrics.clothingCondMin, 4),
            tonumber(metrics.clothingCondItems) or 0,
            tonumber(metrics.driverCount) or 0,
            metricOrNa(metrics.loadFraction, 5),
            tostring(driver),
            tostring(envSource),
            tostring(activitySource)
        )
        line = line .. diagSuffix
    else
        line = string.format(
            "[AMS_BENCH_SAMPLE] id=%s set=%s class=%s scenario=%s tag=%s sample=%d t=%.2f end=%s thirst=%s fatigue=%s temp=%s skinTemp=%s strainTotal=%s strainPeak=%s armStiffness=%s strainRightArm=%s strainLeftArm=%s strainTorso=%s strainRightLeg=%s strainHandR=%s strainForeArmR=%s strainUpperArmR=%s strainHandL=%s strainForeArmL=%s strainUpperArmL=%s strainTorsoUpper=%s strainTorsoLower=%s strainUpperLegR=%s strainLowerLegR=%s strainFootR=%s strainNeck=%s wet=%s clothingCondAvg=%s clothingCondMin=%s clothingCondItems=%d drivers=%d load_fraction=%s x=%s y=%s z=%s outdoors=%s in_vehicle=%s climbing=%s ambient=%s ambientAirTemp=%s externalAirTemp=%s airAndWindTemp=%s thermalChevronUp=%s energyMultiplier=%s fatigueMultiplier=%s setPoint=%s timeOfDay=%s gameHour=%s airTemp=%s airWindTemp=%s wind=%s windSpeed=%s windIntensity=%s cloud=%s rain=%s raining=%s driver=%s env_source=%s activity_source=%s",
            runId,
            tostring(setDef.id),
            tostring(setDef.class),
            tostring(scenarioId),
            tostring(tag or "sample"),
            tonumber(sampleIndex) or 1,
            tonumber(metrics.t) or 0,
            metricOrNa(metrics.endurance, 6),
            metricOrNa(metrics.thirst, 6),
            metricOrNa(metrics.fatigue, 6),
            metricOrNa(metrics.temp, 4),
            metricOrNa(metrics.skinTemp, 4),
            metricOrNa(metrics.strainTotal, 4),
            metricOrNa(metrics.strainPeak, 4),
            metricOrNa(metrics.armStiffness, 4),
            metricOrNa(metrics.strainRightArm, 4),
            metricOrNa(metrics.strainLeftArm, 4),
            metricOrNa(metrics.strainTorso, 4),
            metricOrNa(metrics.strainRightLeg, 4),
            metricOrNa(metrics.strainHandR, 4),
            metricOrNa(metrics.strainForeArmR, 4),
            metricOrNa(metrics.strainUpperArmR, 4),
            metricOrNa(metrics.strainHandL, 4),
            metricOrNa(metrics.strainForeArmL, 4),
            metricOrNa(metrics.strainUpperArmL, 4),
            metricOrNa(metrics.strainTorsoUpper, 4),
            metricOrNa(metrics.strainTorsoLower, 4),
            metricOrNa(metrics.strainUpperLegR, 4),
            metricOrNa(metrics.strainLowerLegR, 4),
            metricOrNa(metrics.strainFootR, 4),
            metricOrNa(metrics.strainNeck, 4),
            metricOrNa(metrics.wetness, 4),
            metricOrNa(metrics.clothingCondAvg, 4),
            metricOrNa(metrics.clothingCondMin, 4),
            tonumber(metrics.clothingCondItems) or 0,
            tonumber(metrics.driverCount) or 0,
            metricOrNa(metrics.loadFraction, 5),
            metricOrNa(metrics.x, 3),
            metricOrNa(metrics.y, 3),
            metricOrNa(metrics.z, 1),
            boolTag(metrics.outdoors),
            boolTag(metrics.inVehicle),
            boolTag(metrics.climbing),
            metricOrNa(metrics.ambient, 4),
            metricOrNa(metrics.ambientAirTemp, 3),
            metricOrNa(metrics.externalAirTemp, 3),
            metricOrNa(metrics.airAndWindTemp, 3),
            boolTag(metrics.thermalChevronUp),
            metricOrNa(metrics.energyMultiplier, 4),
            metricOrNa(metrics.fatigueMultiplier, 4),
            metricOrNa(metrics.setPoint, 3),
            metricOrNa(metrics.timeOfDay, 3),
            metricOrNa(metrics.gameHour, 3),
            metricOrNa(metrics.airTemp, 3),
            metricOrNa(metrics.airWindTemp, 3),
            metricOrNa(metrics.wind, 4),
            metricOrNa(metrics.windSpeed, 3),
            metricOrNa(metrics.windIntensity, 4),
            metricOrNa(metrics.cloud, 4),
            metricOrNa(metrics.rainIntensity, 4),
            boolTag(metrics.raining),
            tostring(driver),
            tostring(envSource),
            tostring(activitySource)
        )
        line = line .. diagSuffix
    end

    if isSnapshotSampleTag(tag) then
        if useStream then
            streamAppend(runner, line, "sample")
        else
            log(line)
            benchSnapshotAppend(exec and exec.snapshot or nil, line, "sample")
        end
    else
        if useStream then
            streamLine(runner, line)
        else
            log(line)
        end
    end
end

-- -----------------------------------------------------------------------------
-- Step summary and validity gates
-- -----------------------------------------------------------------------------

function BenchRunnerStep.summarizeStep(startMetrics, endMetrics)
    local startEnd = asMetricValue(startMetrics and startMetrics.endurance)
    local endEnd = asMetricValue(endMetrics and endMetrics.endurance)
    local startThirst = asMetricValue(startMetrics and startMetrics.thirst)
    local endThirst = asMetricValue(endMetrics and endMetrics.thirst)
    local startFatigue = asMetricValue(startMetrics and startMetrics.fatigue)
    local endFatigue = asMetricValue(endMetrics and endMetrics.fatigue)
    local startTemp = asMetricValue(startMetrics and startMetrics.temp)
    local endTemp = asMetricValue(endMetrics and endMetrics.temp)
    local startStrain = asMetricValue(startMetrics and startMetrics.strainTotal)
    local endStrain = asMetricValue(endMetrics and endMetrics.strainTotal)
    local startArmStiffness = asMetricValue(startMetrics and startMetrics.armStiffness)
    local endArmStiffness = asMetricValue(endMetrics and endMetrics.armStiffness)

    local endDelta = (endEnd ~= nil and startEnd ~= nil) and (endEnd - startEnd) or nil
    local thirstDelta = (endThirst ~= nil and startThirst ~= nil) and (endThirst - startThirst) or nil
    local fatigueDelta = (endFatigue ~= nil and startFatigue ~= nil) and (endFatigue - startFatigue) or nil
    local tempDelta = (endTemp ~= nil and startTemp ~= nil) and (endTemp - startTemp) or nil
    local strainDelta = (endStrain ~= nil and startStrain ~= nil) and (endStrain - startStrain) or nil
    local armStiffnessDelta = (endArmStiffness ~= nil and startArmStiffness ~= nil) and (endArmStiffness - startArmStiffness) or nil

    local loadFraction = asMetricValue(endMetrics and endMetrics.loadFraction)

    return {
        endDelta = endDelta,
        thirstDelta = thirstDelta,
        fatigueDelta = fatigueDelta,
        tempDelta = tempDelta,
        strainDelta = strainDelta,
        armStiffnessStart = startArmStiffness,
        armStiffnessEnd = endArmStiffness,
        armStiffnessDelta = armStiffnessDelta,
        swingsPerMinute = nil,
        loadFraction = loadFraction,
        runtime = type(endMetrics and endMetrics.runtime) == "table" and endMetrics.runtime or nil,
    }
end

local function calculateSwingsPerMinute(activity)
    local swings = math.max(0, tonumber(activity and activity.achieved_swings) or 0)
    local sec = math.max(0, tonumber(activity and activity.achieved_sec) or 0)
    if swings <= 0 or sec <= 0 then
        return nil
    end
    return swings / (sec / 60.0)
end

local function normalizeSetIntegrityTag(value)
    local tag = string.lower(tostring(value or "na"))
    if tag == "ok" or tag == "match" then
        return "match"
    end
    if tag == "mismatch" then
        return "mismatch"
    end
    return "na"
end

function BenchRunnerStep.resolveScenarioGateProfile(scenario)
    local profile = {
        hasNative = false,
        movement = false,
        combat = false,
        realSleep = false,
        movementUptimeMin = tonumber(scenario and scenario.movement_uptime_min),
        targetActivityUptimeMin = tonumber(scenario and scenario.target_activity_uptime_min),
    }
    for _, block in ipairs((scenario and scenario.blocks) or {}) do
        if tostring(block.kind or "") == "run_activity" then
            local mode = tostring(block.mode or "")
            if string.sub(mode, 1, 7) == "native_" then
                profile.hasNative = true
            end
            if mode == "native_treadmill_simple" then
                profile.movement = true
                local blockMovementUptimeMin = tonumber(block.movement_uptime_min)
                if blockMovementUptimeMin ~= nil then
                    if profile.movementUptimeMin == nil then
                        profile.movementUptimeMin = blockMovementUptimeMin
                    else
                        profile.movementUptimeMin = math.min(profile.movementUptimeMin, blockMovementUptimeMin)
                    end
                end
                local blockTargetActivityUptimeMin = tonumber(block.target_activity_uptime_min)
                if blockTargetActivityUptimeMin ~= nil then
                    profile.targetActivityUptimeMin = blockTargetActivityUptimeMin
                end
            end
            if mode == "native_combat_air" then
                profile.combat = true
            end
            if mode == "real_sleep" then
                profile.realSleep = true
            end
        end
    end
    return profile
end

local resolveThreshold = BenchUtils.resolveThreshold

function BenchRunnerStep.evaluateStepGates(exec, summary)
    local activity = exec and exec.activityResult or {}
    local profile = BenchRunnerStep.resolveScenarioGateProfile(exec and exec.scenario)
    local thresholds = exec and exec.validityThresholds or {}

    local movementUptimeMin = resolveThreshold(thresholds.movement_uptime_min, VALIDITY_DEFAULTS.movement_uptime_min, 0.0)
    local targetActivityUptimeMin = resolveThreshold(thresholds.target_activity_uptime_min, VALIDITY_DEFAULTS.target_activity_uptime_min, 0.0)
    local attackSuccessRatioMin = resolveThreshold(thresholds.attack_success_ratio_min, VALIDITY_DEFAULTS.attack_success_ratio_min, 0.0)
    local validSampleRatioMin = resolveThreshold(thresholds.valid_sample_ratio_min, VALIDITY_DEFAULTS.valid_sample_ratio_min, 0.0)
    local completionRatioMin = resolveThreshold(thresholds.completion_ratio_min, VALIDITY_DEFAULTS.completion_ratio_min, 0.0)

    local result = {
        validity_gates_passed = true,
        gate_rejected = false,
        gate_failed = "none",
    }

    local function reject(gateName)
        result.validity_gates_passed = false
        result.gate_rejected = true
        result.gate_failed = tostring(gateName or "unknown")
    end

    summary.swingsPerMinute = calculateSwingsPerMinute(activity)
    activity.swings_per_minute = summary.swingsPerMinute

    if activity.input_disturbed then
        reject("input_disturbed")
    end

    local clockRewindSec = tonumber(activity.clock_rewind_sec)
    if clockRewindSec ~= nil and clockRewindSec > 0.1 then
        reject("clock_continuity")
    end

    local achievedSwings = tonumber(activity.achieved_swings) or 0
    if summary.armStrainGain ~= nil and achievedSwings > 0 then
        summary.stiffnessPerSwing = summary.armStrainGain / achievedSwings
    end

    activity.set_integrity = normalizeSetIntegrityTag(activity.set_integrity)
    if activity.set_integrity ~= "na" and activity.set_integrity ~= "match" then
        reject("set_integrity")
    end

    if result.validity_gates_passed and profile.hasNative then
        local validSampleRatio = tonumber(activity.valid_sample_ratio)
        if validSampleRatio == nil or validSampleRatio < validSampleRatioMin then
            reject("valid_sample_ratio")
        end
    end

    if result.validity_gates_passed and profile.movement then
        local movementUptime = tonumber(activity.movement_uptime)
        local movementGateMin = resolveThreshold(profile.movementUptimeMin, movementUptimeMin, 0.0)
        if movementUptime == nil or movementUptime < movementGateMin then
            reject("movement_uptime")
        end
    end

    if result.validity_gates_passed and profile.movement then
        local targetActivityUptime = tonumber(activity.target_activity_pct)
        local activityGateMin = resolveThreshold(profile.targetActivityUptimeMin, targetActivityUptimeMin, 0.0)
        if targetActivityUptime == nil or targetActivityUptime < activityGateMin then
            reject("target_activity_uptime")
        end
    end

    if profile.combat then
        local attackAttempts = math.max(0, tonumber(activity.attack_attempts) or 0)
        local attackSuccess = math.max(0, tonumber(activity.attack_success) or 0)
        local ratio = attackAttempts > 0 and (attackSuccess / attackAttempts) or 0
        activity.attack_success_ratio = ratio
        if result.validity_gates_passed and ratio < attackSuccessRatioMin then
            reject("attack_success_ratio")
        end
    else
        activity.attack_success_ratio = nil
    end

    if result.validity_gates_passed and not profile.realSleep then
        if tonumber(summary and summary.loadFraction) == nil then
            reject("runtime_snapshot")
        end
    end

    if result.validity_gates_passed and not profile.realSleep then
        local requestedSec = math.max(0, tonumber(activity.requested_sec) or 0)
        local achievedSec = math.max(0, tonumber(activity.achieved_sec) or 0)
        if requestedSec > 0 and achievedSec < (requestedSec * completionRatioMin) then
            reject("achieved_sec")
        end
    end
    if result.validity_gates_passed and profile.realSleep then
        local exitReason = tostring(activity.exit_reason or "completed")
        if exitReason ~= "sleep_recovered" then
            reject("sleep_completion")
        end
    end

    if result.validity_gates_passed then
        local requestedSwings = math.max(0, tonumber(activity.requested_swings) or 0)
        local swingCompletionRatio = profile.combat and 1.0 or completionRatioMin
        if requestedSwings > 0 and achievedSwings < (requestedSwings * swingCompletionRatio) then
            reject("achieved_swings")
        end
    end

    activity.validity_gates_passed = result.validity_gates_passed
    activity.gate_rejected = result.gate_rejected
    activity.gate_failed = result.gate_failed
    if result.gate_rejected and tostring(activity.step_validity or "valid") == "valid" then
        activity.step_validity = "gate_rejected"
    end

    return result
end

-- -----------------------------------------------------------------------------
-- Final step logging
-- -----------------------------------------------------------------------------

function BenchRunnerStep.logStepDone(runId, index, total, setDef, scenarioId, repeatIndex, summary, activity, exec)
    local log = ctx("log")
    local runner = exec and exec.runner or nil
    local useStream = streamActive(runner)
    if not useStream and type(log) ~= "function" then
        return
    end
    local verbose = isVerboseBenchLog(exec)
    local setExpected = tostring(activity.set_expected or "na")
    local setActual = tostring(activity.set_actual or "na")
    if not verbose then
        if tostring(activity.set_integrity or "na") == "mismatch" then
            local mismatchLine = string.format(
                "[AMS_BENCH_SET_MISMATCH] id=%s set=%s scenario=%s set_expected=%s set_actual=%s",
                tostring(runId),
                tostring(setDef.id),
                tostring(scenarioId),
                setExpected,
                setActual
            )
            if useStream then
                streamLine(runner, mismatchLine)
            else
                log(mismatchLine)
            end
        end
        setExpected = textSignature(setExpected)
        setActual = textSignature(setActual)
    end
    local line = string.format(
        "[AMS_BENCH_STEP_DONE] id=%s idx=%d/%d set=%s class=%s scenario=%s repeat_index=%d exit_reason=%s requested_swings=%d achieved_swings=%d requested_sec=%.2f achieved_sec=%.2f endDelta=%s thirstDelta=%s fatigueDelta=%s tempDelta=%s strainDelta=%s arm_stiffness_start=%s arm_stiffness_end=%s arm_stiffness_delta=%s stiffness_per_swing=%s swings_per_minute=%s load_fraction=%s set_expected=%s set_actual=%s set_integrity=%s driver=%s env_source=%s activity_source=%s step_validity=%s validity_gates_passed=%s gate_rejected=%s gate_failed=%s native_nav_mode=%s reset_ok=%s reset_attempts=%d reset_error=%s forward_rearm_attempts=%d forward_rearm_failures=%d teleport_jump_count=%d anchor_start_err_tiles=%s anchor_end_err_tiles=%s anchor_delta_before_start=%s anchor_delta_after_post_reset=%s valid_sample_ratio=%s movement_uptime=%s distance_moved=%s sample_window_sec=%s total_samples=%d valid_samples=%d moving_samples=%d stall_sec_accum=%s stall_reason=%s stall_reason_counts=%s phase_timeline=%s pct_idle=%s pct_walk=%s pct_run=%s pct_sprint=%s pct_combat=%s avg_move_speed=%s attack_attempts=%d attack_success=%d attack_success_ratio=%s attack_cooldown_blocks=%d attack_cooldown_sec=%s hit_events=%d",
        runId,
        index,
        total,
        tostring(setDef.id),
        tostring(setDef.class),
        tostring(scenarioId),
        tonumber(repeatIndex) or 1,
        tostring(activity.exit_reason or "completed"),
        tonumber(activity.requested_swings) or 0,
        tonumber(activity.achieved_swings) or 0,
        tonumber(activity.requested_sec) or 0,
        tonumber(activity.achieved_sec) or 0,
        metricOrNa(summary.endDelta, 6),
        metricOrNa(summary.thirstDelta, 6),
        metricOrNa(summary.fatigueDelta, 6),
        metricOrNa(summary.tempDelta, 6),
        metricOrNa(summary.strainDelta, 6),
        metricOrNa(summary.armStiffnessStart, 4),
        metricOrNa(summary.armStiffnessEnd, 4),
        metricOrNa(summary.armStiffnessDelta, 6),
        metricOrNa(summary.stiffnessPerSwing, 6),
        metricOrNa(summary.swingsPerMinute, 4),
        metricOrNa(summary.loadFraction, 5),
        setExpected,
        setActual,
        tostring(activity.set_integrity or "na"),
        tostring(activity.driver or "scripted"),
        tostring(activity.env_source or "scripted"),
        tostring(activity.activity_source or "scripted"),
        tostring(activity.step_validity or "na"),
        tostring(activity.validity_gates_passed),
        tostring(activity.gate_rejected),
        tostring(activity.gate_failed or "none"),
        tostring(activity.native_nav_mode or "na"),
        boolTag(activity.reset_ok),
        tonumber(activity.reset_attempts) or 0,
        tostring(activity.reset_error or "none"),
        tonumber(activity.forward_rearm_attempts) or 0,
        tonumber(activity.forward_rearm_failures) or 0,
        tonumber(activity.teleport_jump_count) or 0,
        metricOrNa(activity.anchor_start_err_tiles, 3),
        metricOrNa(activity.anchor_end_err_tiles, 3),
        metricOrNa(activity.anchor_delta_before_start, 3),
        metricOrNa(activity.anchor_delta_after_post_reset, 3),
        metricOrNa(activity.valid_sample_ratio, 4),
        metricOrNa(activity.movement_uptime, 4),
        metricOrNa(activity.distance_moved, 3),
        metricOrNa(activity.sample_window_sec, 3),
        tonumber(activity.total_samples) or 0,
        tonumber(activity.valid_samples) or 0,
        tonumber(activity.moving_samples) or 0,
        metricOrNa(activity.stall_sec_accum, 3),
        tostring(activity.stall_reason or "none"),
        tostring(activity.stall_reason_counts or "none"),
        tostring(activity.phase_timeline or "none"),
        metricOrNa(activity.pct_idle, 4),
        metricOrNa(activity.pct_walk, 4),
        metricOrNa(activity.pct_run, 4),
        metricOrNa(activity.pct_sprint, 4),
        metricOrNa(activity.pct_combat, 4),
        metricOrNa(activity.avg_move_speed, 4),
        tonumber(activity.attack_attempts) or 0,
        tonumber(activity.attack_success) or 0,
        metricOrNa(activity.attack_success_ratio, 4),
        tonumber(activity.attack_cooldown_blocks) or 0,
        metricOrNa(activity.attack_cooldown_sec, 3),
        tonumber(activity.hit_events) or 0
    )
    local diagStepSuffix = " " .. BenchRunnerEnv.formatRuntimeMetrics(summary.runtime, metricOrNa) .. string.format(
        " stat_strength=%s stat_fitness=%s stat_weapon_skill=%s stat_weapon_perk=%s requested_activity=%s target_activity_pct=%s tick_count=%d tick_gaps=%d natural_total=%s ams_total=%s realized_scale=%s tick_closure=%s arm_strain_gain=%s game_sec_per_frame=%s wall_sec=%s clock_rewind_sec=%s",
        metricOrNa(activity and activity.stat_strength, 0),
        metricOrNa(activity and activity.stat_fitness, 0),
        metricOrNa(activity and activity.stat_weapon_skill, 0),
        tostring((activity and activity.stat_weapon_perk) or "na"),
        tostring((activity and activity.requested_activity) or "na"),
        metricOrNa(activity and activity.target_activity_pct, 4),
        tonumber(summary.tickCount) or 0,
        tonumber(summary.tickGaps) or 0,
        metricOrNa(summary.naturalTotal, 6),
        metricOrNa(summary.amsTotal, 6),
        metricOrNa(summary.realizedScale, 4),
        metricOrNa(summary.tickClosure, 6),
        metricOrNa(summary.armStrainGain, 4),
        metricOrNa(summary.gameSecPerFrame, 3),
        metricOrNa(summary.wallSec, 2),
        metricOrNa(activity and activity.clock_rewind_sec, 3)
    )
    line = line .. diagStepSuffix
    if useStream then
        streamAppend(runner, line, "step")
    else
        log(line)
        benchSnapshotAppend(exec and exec.snapshot or nil, line, "step")
    end
end

-- -----------------------------------------------------------------------------
-- Activity execution lifecycle
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- Input disturbance retries
-- -----------------------------------------------------------------------------

BenchRunnerStep.MAX_INPUT_RETRIES = 2

local function logStepRetry(exec)
    local line = string.format(
        "[AMS_BENCH_STEP_RETRY] id=%s idx=%d/%d set=%s scenario=%s repeat_index=%d reason=%s attempt=%d",
        tostring(exec.runId),
        tonumber(exec.index) or 0,
        tonumber(exec.total) or 0,
        tostring(exec.setDef and exec.setDef.id or "?"),
        tostring(exec.scenarioId),
        tonumber(exec.repeatIndex) or 1,
        tostring(exec.disturbed),
        (tonumber(exec.retryCount) or 0) + 1
    )
    local runner = exec.runner
    if streamActive(runner) then
        streamLine(runner, line)
    elseif type(ctx("log")) == "function" then
        ctx("log")(line)
    end
end

local function registerVanillaSleep(player, hours, safeMethod)
    local sleepingEvent = type(getSleepingEvent) == "function" and getSleepingEvent() or nil
    if sleepingEvent then
        safeMethod(sleepingEvent, "setPlayerFallAsleep", player, hours)
    end
end

function BenchRunnerStep.runActivity(player, state, exec, block, deps)
    deps = deps or {}
    local ctx = depOr(deps, "ctx", ctx)
    local clamp = deps.clamp or (BenchUtils and BenchUtils.clamp)
    local setEnv = deps.setEnv
    local safeMethod = deps.safeMethod or (BenchUtils and BenchUtils.safeMethod)
    local startNativeDriver = deps.startNativeDriver
    local REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT = tonumber(deps.realSleepFatigueWakeThresholdDefault) or 0.02
    local REAL_SLEEP_SAFETY_HOURS_DEFAULT = tonumber(deps.realSleepSafetyHoursDefault) or 16.0
    local mode = tostring(block.mode or "")
    local requestedSwings = tonumber(block.requested_swings) or 0
    local achievedSwings = 0
    local requestedSec = tonumber(block.requested_sec) or 0
    local achievedSec = 0
    local exitReason = "completed"
    local pendingType = nil
    local setSource = (exec and exec.expectedSetHash) and "equipped_set" or "na"
    local driverLabel = "scripted"
    local envSource = "scripted"
    local activitySource = "scripted"
    local speedReq = nil
    local stepValidity = "valid"
    local hardFail = false

    if mode == "real_sleep" then
        local hours = tonumber(block.hours) or (requestedSec > 0 and (requestedSec / 3600.0) or REAL_SLEEP_SAFETY_HOURS_DEFAULT)
        hours = math.max(1.0, hours)
        local fatigueWakeThreshold = clamp(tonumber(block.fatigue_wake_threshold) or REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT, 0.0, 0.2)
        local tempC = tonumber(block.temp_c)
        local wetnessPct = tonumber(block.wetness_pct)
        if tempC ~= nil or wetnessPct ~= nil then
            setEnv(player, tempC or 37.0, wetnessPct or 0.0)
        end

        local canSleepApi = type(player.setForceWakeUpTime) == "function"
            and type(player.setAsleepTime) == "function"
            and type(player.setAsleep) == "function"
        if not canSleepApi then
            exitReason = "module_error"
        else
            local gameTime = getGameTime and getGameTime()
            local nowTod = tonumber(gameTime and safeMethod(gameTime, "getTimeOfDay")) or 0
            local wakeHour = nowTod + hours
            while wakeHour >= 24.0 do
                wakeHour = wakeHour - 24.0
            end
            local ensureState = ctx("ensureState")
            local amsState = type(ensureState) == "function" and ensureState(player) or nil
            if type(amsState) == "table" then
                amsState.sleepSnapshot = nil
                amsState.wasSleeping = false
            end
            safeMethod(player, "setForceWakeUpTime", wakeHour)
            safeMethod(player, "setAsleepTime", 0.0)
            safeMethod(player, "setAsleep", true)
            registerVanillaSleep(player, hours, safeMethod)
            pendingType = "real_sleep"
            if exec and exec.activityResult then
                exec.activityResult.sleep_force_wake_hour = wakeHour
            end
        end
        requestedSec = math.max(0, hours * 3600.0)
    elseif mode == "native_treadmill_simple" or mode == "native_combat_air" then
        driverLabel = "native"
        envSource = "vanilla"
        activitySource = "vanilla"
        speedReq = tonumber(block.speed_req)
        local nativeDriver, nativeStartErr = startNativeDriver(player, exec, block)
        if not nativeDriver then
            exitReason = tostring(nativeStartErr or "native_hard_start_failed")
            if string.find(exitReason, "native_soft_", 1, true) then
                hardFail = false
                stepValidity = "soft_fail"
            else
                hardFail = true
                stepValidity = "hard_fail"
            end
        else
            nativeDriver.speedReq = speedReq
            exec.nativeDriver = nativeDriver
            pendingType = "native_driver"
            requestedSec = tonumber(nativeDriver.targetSec) or requestedSec
            requestedSwings = tonumber(nativeDriver.targetSwings) or requestedSwings
        end
    else
        exitReason = "native_hard_unknown_activity_mode"
        hardFail = true
        stepValidity = "hard_fail"
    end

    return {
        requested_swings = requestedSwings,
        achieved_swings = achievedSwings,
        requested_sec = requestedSec,
        achieved_sec = achievedSec,
        exit_reason = exitReason,
        pending_type = pendingType,
        set_source = setSource,
        driver = driverLabel,
        env_source = envSource,
        activity_source = activitySource,
        speed_req = speedReq,
        step_validity = stepValidity,
        sleep_fatigue_threshold = (mode == "real_sleep") and clamp(tonumber(block.fatigue_wake_threshold) or REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT, 0.0, 0.2) or nil,
        sleep_safety_hours = (mode == "real_sleep") and math.max(1.0, tonumber(block.hours) or (requestedSec > 0 and (requestedSec / 3600.0) or REAL_SLEEP_SAFETY_HOURS_DEFAULT)) or nil,
        hard_fail = hardFail,
    }
end

function BenchRunnerStep.isPendingComplete(player, state, pendingType, exec, deps)
    deps = deps or {}
    local clamp = depOr(deps, "clamp", BenchUtils.clamp)
    local nowMinutes = depOr(deps, "nowMinutes", function() return BenchUtils.nowMinutes(ctx) end)
    local ctx = depOr(deps, "ctx", ctx)
    local toBoolArg = depOr(deps, "toBoolArg", BenchUtils.toBoolArg)
    local safeMethod = depOr(deps, "safeMethod", BenchUtils.safeMethod)
    local REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT = tonumber(deps.realSleepFatigueWakeThresholdDefault) or 0.02
    local REAL_SLEEP_ENTRY_GRACE_SECONDS = tonumber(deps.realSleepEntryGraceSeconds) or 90.0
    local REAL_SLEEP_SAFETY_HOURS_DEFAULT = tonumber(deps.realSleepSafetyHoursDefault) or 16.0
    if pendingType == "native_driver" then
        return false
    end
    if pendingType == "wait_window" then
        local requestedSec = math.max(0, tonumber(exec and exec.pendingWaitRequestedSec) or 0)
        local startedAt = tonumber(exec and exec.pendingStartedAt) or nowMinutes()
        if ((nowMinutes() - startedAt) * 60.0) < requestedSec then
            return false
        end
        if exec and exec.pendingWaitRuntimeAligned == true then
            local snapshot = type(state) == "table" and state.uiRuntimeSnapshot or nil
            local updatedMinute = tonumber(snapshot and snapshot.updatedMinute)
            return updatedMinute ~= nil and updatedMinute >= (startedAt + (requestedSec / 60.0))
        end
        return true
    end
    if pendingType == "runtime_tick" then
        local snapshot = type(state) == "table" and state.uiRuntimeSnapshot or nil
        local updatedMinute = tonumber(snapshot and snapshot.updatedMinute)
        local baseline = tonumber(exec and exec.pendingRuntimeUpdatedMinute)
        if updatedMinute ~= nil and (baseline == nil or updatedMinute > baseline) then
            return true
        end
        local timeoutSec = math.max(1, tonumber(exec and exec.pendingWaitRequestedSec) or 120)
        local startedAt = tonumber(exec and exec.pendingStartedAt) or nowMinutes()
        if ((nowMinutes() - startedAt) * 60.0) >= timeoutSec then
            exec.runtimeSyncTimedOut = true
            return true
        end
        return false
    end
    if pendingType == "real_sleep" then
        local startedAt = tonumber(exec and exec.pendingStartedAt) or nowMinutes()
        local elapsedSec = math.max(0, (nowMinutes() - startedAt) * 60.0)
        local threshold = clamp(
            tonumber(exec and exec.activityResult and exec.activityResult.sleep_fatigue_threshold)
                or REAL_SLEEP_FATIGUE_WAKE_THRESHOLD_DEFAULT,
            0.0,
            0.2
        )
        local fatigue = type(ctx("getFatigue")) == "function" and tonumber(ctx("getFatigue")(player)) or nil
        local asleep = toBoolArg(safeMethod(player, "isAsleep"))
        if exec and exec.activityResult and asleep then
            exec.activityResult.sleep_observed_asleep = true
        end
        if asleep and fatigue ~= nil and fatigue <= threshold then
            safeMethod(player, "forceAwake")
            if exec and exec.activityResult then
                exec.activityResult.exit_reason = "sleep_recovered"
            end
            return true
        end
        if not asleep then
            local observed = exec and exec.activityResult and exec.activityResult.sleep_observed_asleep == true
            if not observed and elapsedSec < REAL_SLEEP_ENTRY_GRACE_SECONDS then
                local wakeHour = tonumber(exec and exec.activityResult and exec.activityResult.sleep_force_wake_hour)
                if wakeHour ~= nil then
                    safeMethod(player, "setForceWakeUpTime", wakeHour)
                end
                safeMethod(player, "setAsleepTime", 0.0)
                safeMethod(player, "setAsleep", true)
                local sleepHours = tonumber(exec and exec.activityResult and exec.activityResult.sleep_safety_hours)
                    or REAL_SLEEP_SAFETY_HOURS_DEFAULT
                registerVanillaSleep(player, sleepHours, safeMethod)
                return false
            end
            if not observed then
                if exec and exec.activityResult then
                    exec.activityResult.exit_reason = "sleep_entry_failed"
                    exec.activityResult.step_validity = "soft_fail"
                end
                return true
            end
            if exec and exec.activityResult and tostring(exec.activityResult.exit_reason or "completed") == "completed" then
                exec.activityResult.exit_reason = "sleep_woke_external"
            end
            return true
        end

        local elapsedGameMin = math.max(0, nowMinutes() - startedAt)
        local requestedSec = tonumber(exec and exec.activityResult and exec.activityResult.requested_sec) or 0
        local requestedMin = requestedSec / 60.0
        if requestedMin > 0 and elapsedGameMin >= requestedMin then
            safeMethod(player, "forceAwake")
            if exec and exec.activityResult then
                exec.activityResult.exit_reason = "sleep_timeout"
                exec.activityResult.step_validity = "soft_fail"
            end
            return true
        end
        return false
    end
    return true
end

function BenchRunnerStep.maybeLogMidActivitySample(exec, player, deps)
    deps = deps or {}
    local clamp = depOr(deps, "clamp", BenchUtils.clamp)
    local nowMinutes = depOr(deps, "nowMinutes", function() return BenchUtils.nowMinutes(ctx) end)
    local collectMetrics = deps.collectMetrics
    local sampleLog = deps.sampleLog
    if not exec or exec.midSampleEnabled ~= true or not exec.pendingType then
        return
    end

    local everySec = clamp(tonumber(exec.midSampleEverySec) or 5.0, 0.25, 120.0)
    local now = nowMinutes()
    local lastAt = tonumber(exec.midSampleLastAt)
    if lastAt == nil then
        exec.midSampleLastAt = now
        return
    end

    if ((now - lastAt) * 60.0) < everySec then
        return
    end

    exec.midSampleLastAt = now
    exec.midSampleIndex = (tonumber(exec.midSampleIndex) or 0) + 1

    local sample = collectMetrics(player)
    local tagBase = tostring(exec.midSampleTag or "mid")
    local tag = string.format("%s_%s", tagBase, tostring(exec.pendingType or "pending"))
    sampleLog(exec.runId, exec.setDef, exec.scenarioId, tag, exec.midSampleIndex, sample, exec.activityResult, exec, exec.midSampleVerbose == true)
end

function BenchRunnerStep.resetPrepareStateCarryover(player, state, deps)
    deps = deps or {}
    local ctx = depOr(deps, "ctx", ctx)
    if type(state) ~= "table" then
        return
    end

    state.thermalModelState = nil
    state.uiRuntimeSnapshot = nil
    -- A nil tick minute makes the next Physiology.tick rebase instead of
    -- charging the reset jump as an endurance delta.
    state.lastTickMinute = nil
    local enduranceNow = type(ctx("getEndurance")) == "function" and ctx("getEndurance")(player) or nil
    state.lastEnduranceObserved = tonumber(enduranceNow)
end

function BenchRunnerStep.resetStepMuscleStrainState(player, deps)
    deps = deps or {}
    local safeMethod = depOr(deps, "safeMethod", BenchUtils.safeMethod)
    local FITNESS_STIFFNESS_GROUPS = deps.fitnessStiffnessGroups or { "arms", "chest", "abs", "legs" }
    local skipFitnessResetValues = deps.skipFitnessResetValues == true
    local body = safeMethod(player, "getBodyDamage")
    if body then
        local parts = safeMethod(body, "getBodyParts")
        local n = tonumber(parts and safeMethod(parts, "size")) or 0
        for i = 0, n - 1 do
            local part = safeMethod(parts, "get", i)
            if part then
                safeMethod(part, "setStiffness", 0.0)
                safeMethod(part, "setAdditionalPain", 0.0)
            end
        end
    end

    local fitness = safeMethod(player, "getFitness")
    if fitness then
        if not skipFitnessResetValues then
            safeMethod(fitness, "resetValues")
        end
        for _, group in ipairs(FITNESS_STIFFNESS_GROUPS) do
            safeMethod(fitness, "removeStiffnessValue", group)
        end
    end
end

-- -----------------------------------------------------------------------------
-- Runtime tick ledger
-- -----------------------------------------------------------------------------

-- Sums the vanilla (natural) and AMS endurance deltas of every production tick
-- inside the measured window. realized_scale = observed change / vanilla change
-- is the multiplier AMS actually applied; it does not depend on how long the
-- character spent sprinting, so one repeat is enough.
local function readLedgerInputs(player, state)
    local snapshot = type(state) == "table" and state.uiRuntimeSnapshot or nil
    local getEndurance = ctx("getEndurance")
    local endurance = type(getEndurance) == "function" and tonumber(getEndurance(player)) or nil
    return snapshot, endurance
end

-- Below this much vanilla change the ratio is rounding noise (a step that
-- starts at full endurance), so realized_scale is reported as na.
BenchRunnerStep.LEDGER_MIN_NATURAL = 0.001

function BenchRunnerStep.openLedger(exec, player, state)
    local snapshot, endurance = readLedgerInputs(player, state)
    local arm = BenchRunnerEnv.readArmStiffness(player)
    exec.ledger = {
        minute = tonumber(snapshot and snapshot.updatedMinute),
        startEndurance = endurance,
        lastEndurance = endurance,
        natural = 0,
        ams = 0,
        ticks = 0,
        gaps = 0,
        lastArm = arm,
        armGain = 0,
        armDecay = 0,
        frames = 0,
        openedAt = BenchUtils.nowMinutes(ctx),
        lastAt = BenchUtils.nowMinutes(ctx),
    }
end

-- Vanilla stiffness decays every frame in proportion to the game-time step, so
-- a net start/end delta depends on game speed. Summing per-frame increases and
-- adding back the previous frame's decay counts only what swings added.
local function observeArmStrain(ledger, player)
    local arm = BenchRunnerEnv.readArmStiffness(player)
    local delta = arm - ledger.lastArm
    if arm <= 0 then
        ledger.armDecay = 0
    elseif delta < 0 then
        ledger.armDecay = -delta
    elseif delta > 0 then
        ledger.armGain = ledger.armGain + delta + ledger.armDecay
    end
    ledger.lastArm = arm
end

function BenchRunnerStep.observeLedger(exec, player, state)
    local ledger = exec and exec.ledger
    if type(ledger) ~= "table" then
        return
    end
    observeArmStrain(ledger, player)
    local now = BenchUtils.nowMinutes(ctx)
    if now > ledger.lastAt then
        ledger.frames = ledger.frames + 1
        ledger.lastAt = now
    end
    local snapshot, endurance = readLedgerInputs(player, state)
    local minute = tonumber(snapshot and snapshot.updatedMinute)
    if minute == nil or minute == ledger.minute then
        return
    end
    if ledger.minute ~= nil and (minute - ledger.minute) > 1.5 then
        ledger.gaps = ledger.gaps + 1
    end
    ledger.minute = minute
    ledger.ticks = ledger.ticks + 1
    ledger.natural = ledger.natural + (tonumber(snapshot.naturalDelta) or 0)
    ledger.ams = ledger.ams + (tonumber(snapshot.amsDelta) or 0)
    ledger.lastEndurance = endurance
end

function BenchRunnerStep.summarizeLedger(ledger)
    if type(ledger) ~= "table" then
        return { tickCount = 0, tickGaps = 0 }
    end
    local span = (ledger.lastAt - ledger.openedAt) * 60.0
    local summary = {
        tickCount = ledger.ticks,
        tickGaps = ledger.gaps,
        armStrainGain = ledger.armGain,
        gameSecPerFrame = ledger.frames > 0 and (span / ledger.frames) or nil,
    }
    if ledger.ticks <= 0 then
        return summary
    end
    local observed = (ledger.lastEndurance ~= nil and ledger.startEndurance ~= nil)
        and (ledger.lastEndurance - ledger.startEndurance) or nil
    if observed ~= nil and math.abs(ledger.natural) >= BenchRunnerStep.LEDGER_MIN_NATURAL then
        summary.realizedScale = observed / ledger.natural
    end
    summary.naturalTotal = ledger.natural
    summary.amsTotal = ledger.ams
    summary.tickClosure = observed ~= nil and (observed - (ledger.natural + ledger.ams)) or nil
    return summary
end

function BenchRunnerStep.processStep(exec, player, state, deps)
    deps = deps or {}
    local refreshWeatherOverrides = deps.refreshWeatherOverrides
    local tickNativeDriver = deps.tickNativeDriver
    local finalizeNativeActivity = deps.finalizeNativeActivity
    local snapshotWornHash = deps.snapshotWornHash
    local clearExecWeatherOverride = deps.clearExecWeatherOverride
    local nowMinutes = depOr(deps, "nowMinutes", function() return BenchUtils.nowMinutes(ctx) end)
    local ctx = depOr(deps, "ctx", ctx)
    local setNativeTimeOfDay = deps.setNativeTimeOfDay
    local getThermoregulator = deps.getThermoregulator
    local safeMethod = depOr(deps, "safeMethod", BenchUtils.safeMethod)
    local equipSet = deps.equipSet
    local setEnv = deps.setEnv
    local readWeatherSpec = deps.readWeatherSpec
    local applyWeatherOverrides = deps.applyWeatherOverrides
    local clamp = depOr(deps, "clamp", BenchUtils.clamp)
    local collectMetrics = deps.collectMetrics
    local sampleLog = deps.sampleLog
    local evaluateStepGates = deps.evaluateStepGates
    local buildStepResult = deps.buildStepResult
    local logStepDone = deps.logStepDone
    local summarizeStep = deps.summarizeStep
    local runActivity = deps.runActivity or BenchRunnerStep.runActivity
    local isPendingComplete = deps.isPendingComplete or BenchRunnerStep.isPendingComplete
    local maybeLogMidActivitySample = deps.maybeLogMidActivitySample or BenchRunnerStep.maybeLogMidActivitySample
    local resetPrepareStateCarryover = deps.resetPrepareStateCarryover or BenchRunnerStep.resetPrepareStateCarryover
    local blocks = exec.scenario and exec.scenario.blocks or {}

    exec.wallStartMs = exec.wallStartMs or nowMs()
    BenchRunnerStep.observeLedger(exec, player, state)

    if exec.pendingType then
        if exec.weatherOverride then
            refreshWeatherOverrides(exec.weatherOverride)
        end
        if exec.pendingType == "native_driver" then
            local nativeStatus, nativeReason = tickNativeDriver(player, exec)
            if nativeStatus == "pending" then
                maybeLogMidActivitySample(exec, player)
                return "pending", nil
            end

            local outcome = nativeStatus == "done" and "done" or (nativeStatus == "soft_fail" and "soft_fail" or "hard_fail")
            local finalized, hardReason = finalizeNativeActivity(player, exec, exec.nativeDriver, outcome, nativeReason)
            exec.nativeDriver = nil
            exec.pendingType = nil
            exec.pendingSpeedReq = nil
            exec.pendingWaitRuntimeAligned = nil

            if exec.expectedSetHash then
                local actualHash = snapshotWornHash(player)
                updateSetIntegrity(exec.activityResult, exec.expectedSetHash, actualHash)
            end

            if finalized == "hard_fail" then
                clearExecWeatherOverride(exec)
                return "error", tostring(hardReason or nativeReason or "native_hard_failed")
            end
            if finalized == "soft_fail" then
                exec.softFail = true
            end
        else
            local completedPendingType = exec.pendingType
            if not isPendingComplete(player, state, exec.pendingType, exec) then
                maybeLogMidActivitySample(exec, player)
                return "pending", nil
            end
            if exec.runtimeSyncTimedOut then
                clearExecWeatherOverride(exec)
                return "error", "runtime_snapshot_timeout"
            end
            if completedPendingType ~= "wait_window" and completedPendingType ~= "runtime_tick" then
                local elapsedSec = math.max(0, (nowMinutes() - (exec.pendingStartedAt or nowMinutes())) * 60.0)
                exec.activityResult.achieved_sec = elapsedSec
                if exec.activityResult.requested_sec <= 0 then
                    exec.activityResult.requested_sec = elapsedSec
                end
            end
            if exec.expectedSetHash then
                local actualHash = snapshotWornHash(player)
                updateSetIntegrity(exec.activityResult, exec.expectedSetHash, actualHash)
            end
            exec.pendingType = nil
            exec.pendingSpeedReq = nil
            exec.pendingWaitRequestedSec = nil
            exec.pendingRuntimeUpdatedMinute = nil
        end
    end

    while exec.blockIndex <= #blocks do
        local block = blocks[exec.blockIndex]
        local kind = tostring(block.kind or "")
        if exec.softFail and kind == "run_activity" then
        elseif kind == "prepare_state" then
            if type(ctx("resetCharacterToEquilibrium")) == "function" then
                ctx("resetCharacterToEquilibrium")(player)
            end
            local caloriesTarget = tonumber(block.calories) or 300.0
            local nutrition = safeMethod(player, "getNutrition")
            if nutrition then
                safeMethod(nutrition, "setCalories", caloriesTarget)
            end
            if exec.pinnedTimeOfDay ~= nil then
                local setOk, setReason = setNativeTimeOfDay(exec.pinnedTimeOfDay)
                if not setOk then
                    return "error", tostring(setReason or "native_hard_missing_time_api")
                end
            end
            local thermoregulator = getThermoregulator(player)
            if thermoregulator then
                safeMethod(thermoregulator, "update")
            end
            resetPrepareStateCarryover(player, state)
        elseif kind == "equip_set" then
            equipSet(player, exec.setDef)
            exec.expectedSetHash = snapshotWornHash(player)
        elseif kind == "lock_weather_start" then
            clearExecWeatherOverride(exec)
            local weatherSpec, weatherSpecErr = readWeatherSpec(block)
            if weatherSpecErr then
                clearExecWeatherOverride(exec)
                return "error", tostring(weatherSpecErr)
            end
            if weatherSpec then
                local weatherToken, weatherApplyErr = applyWeatherOverrides(weatherSpec)
                if not weatherToken then
                    clearExecWeatherOverride(exec)
                    return "error", tostring(weatherApplyErr or "native_hard_weather_override_failed")
                end
                exec.weatherOverride = weatherToken
                refreshWeatherOverrides(exec.weatherOverride)
            end
        elseif kind == "lock_weather_end" then
            clearExecWeatherOverride(exec)
        elseif kind == "set_fatigue" then
            local fatigueValue = clamp(tonumber(block.value) or 0, 0, 1.0)
            if type(ctx("setFatigue")) == "function" then
                ctx("setFatigue")(player, fatigueValue)
            end
        elseif kind == "sample_once" then
            BenchRunnerStep.observeLedger(exec, player, state)
            local sample = collectMetrics(player)
            if block.baseline == true or not exec.startMetrics then
                exec.startMetrics = sample
                BenchRunnerStep.openLedger(exec, player, state)
            end
            sampleLog(exec.runId, exec.setDef, exec.scenarioId, block.tag or "once", 1, sample, exec.activityResult, exec)
            exec.endMetrics = sample
        elseif kind == "await_runtime_tick" then
            local snapshot = type(state) == "table" and state.uiRuntimeSnapshot or nil
            exec.pendingType = "runtime_tick"
            exec.pendingStartedAt = nowMinutes()
            exec.pendingWaitRequestedSec = math.max(1, tonumber(block.timeout_sec) or 120)
            exec.pendingRuntimeUpdatedMinute = tonumber(snapshot and snapshot.updatedMinute)
            exec.runtimeSyncTimedOut = false
            exec.blockIndex = exec.blockIndex + 1
            return "pending", nil
        elseif kind == "wait_window" then
            exec.pendingType = "wait_window"
            exec.pendingStartedAt = nowMinutes()
            exec.pendingWaitRequestedSec = math.max(0, tonumber(block.requested_sec) or 0)
            exec.pendingWaitRuntimeAligned = block.runtime_aligned == true
            exec.blockIndex = exec.blockIndex + 1
            return "pending", nil
        elseif kind == "run_activity" then
            if not exec.startMetrics then
                exec.startMetrics = collectMetrics(player)
                BenchRunnerStep.openLedger(exec, player, state)
            end
            if exec.expectedSetHash then
                local actualHash = snapshotWornHash(player)
                if actualHash ~= exec.expectedSetHash then
                    if type(ctx("logError")) == "function" then
                        ctx("logError")(string.format(
                            "[AMS_BENCH_SET_MISMATCH] id=%s set=%s scenario=%s expected=%s actual=%s",
                            tostring(exec.runId), tostring(exec.setDef and exec.setDef.id or "?"), tostring(exec.scenarioId), tostring(exec.expectedSetHash), tostring(actualHash)
                        ))
                    end
                    exec.activityResult = {
                        requested_swings = 0,
                        achieved_swings = 0,
                        requested_sec = 0,
                        achieved_sec = 0,
                        exit_reason = "set_mismatch",
                        set_source = "equipped_set",
                        driver = "scripted",
                        env_source = "scripted",
                        activity_source = "scripted",
                        step_validity = "soft_fail",
                        set_expected = exec.expectedSetHash,
                        set_actual = actualHash,
                        set_integrity = "mismatch",
                    }
                    exec.endMetrics = collectMetrics(player)
                    exec.blockIndex = #blocks + 1
                    break
                end
            end
            exec.activityResult = runActivity(player, state, exec, block)
            if exec.activityResult.hard_fail then
                clearExecWeatherOverride(exec)
                return "error", tostring(exec.activityResult.exit_reason or "native_hard_failed")
            end
            if exec.activityResult.pending_type then
                exec.pendingType = exec.activityResult.pending_type
                exec.pendingSpeedReq = tonumber(exec.activityResult.speed_req) or nil
                exec.pendingStartedAt = nowMinutes()
                local baselineAt = tonumber(exec.startMetrics and exec.startMetrics.t)
                if baselineAt ~= nil then
                    exec.activityResult.clock_rewind_sec = math.max(0, (baselineAt - exec.pendingStartedAt) * 60.0)
                end
                if block.mid_activity_samples ~= nil then
                    exec.midSampleEnabled = block.mid_activity_samples == true
                end
                if block.mid_activity_verbose ~= nil then
                    exec.midSampleVerbose = block.mid_activity_verbose == true
                end
                local blockMidEverySec = tonumber(block.mid_activity_every_sec)
                if blockMidEverySec ~= nil then
                    exec.midSampleEverySec = clamp(blockMidEverySec, 0.25, 120.0)
                end
                if block.mid_activity_tag ~= nil and tostring(block.mid_activity_tag) ~= "" then
                    exec.midSampleTag = tostring(block.mid_activity_tag)
                end
                exec.midSampleIndex = 0
                exec.midSampleLastAt = exec.pendingStartedAt
                exec.blockIndex = exec.blockIndex + 1
                return "pending", nil
            end
            if tostring(exec.activityResult.step_validity or "valid") == "soft_fail" then
                exec.softFail = true
            end
        else
            clearExecWeatherOverride(exec)
            return "error", "unknown_block_kind:" .. kind
        end
        exec.blockIndex = exec.blockIndex + 1
    end

    if not exec.endMetrics then
        exec.endMetrics = collectMetrics(player)
    end
    if not exec.startMetrics then
        exec.startMetrics = exec.endMetrics
    end

    local summary = summarizeStep(exec.startMetrics, exec.endMetrics)
    local ledgerSummary = BenchRunnerStep.summarizeLedger(exec.ledger)
    for key, value in pairs(ledgerSummary) do
        summary[key] = value
    end
    summary.wallSec = math.max(0, nowMs() - exec.wallStartMs) / 1000.0
    local finalActual = snapshotWornHash(player)
    if exec.expectedSetHash then
        local integrity = finalActual == exec.expectedSetHash and "match" or "mismatch"
        exec.activityResult.set_expected = exec.activityResult.set_expected or exec.expectedSetHash
        exec.activityResult.set_actual = exec.activityResult.set_actual or finalActual
        exec.activityResult.set_integrity = exec.activityResult.set_integrity or integrity
        if integrity == "mismatch" and tostring(exec.activityResult.exit_reason or "completed") == "completed" then
            exec.activityResult.exit_reason = "set_mismatch"
        end
    else
        exec.activityResult.set_expected = exec.activityResult.set_expected or "na"
        exec.activityResult.set_actual = exec.activityResult.set_actual or finalActual
        exec.activityResult.set_integrity = exec.activityResult.set_integrity or "na"
    end
    exec.activityResult.set_source = exec.activityResult.set_source or "na"
    exec.activityResult.driver = exec.activityResult.driver or "scripted"
    exec.activityResult.env_source = exec.activityResult.env_source or "scripted"
    exec.activityResult.activity_source = exec.activityResult.activity_source or "scripted"
    exec.activityResult.step_validity = exec.activityResult.step_validity or "valid"
    if exec.disturbed then
        exec.activityResult.input_disturbed = exec.disturbed
        if (tonumber(exec.retryCount) or 0) < BenchRunnerStep.MAX_INPUT_RETRIES then
            logStepRetry(exec)
            exec.retry = true
            clearExecWeatherOverride(exec)
            return "done", nil
        end
    end
    evaluateStepGates(exec, summary)
    exec.stepResult = buildStepResult(exec, summary)
    logStepDone(exec.runId, exec.index, exec.total, exec.setDef, exec.scenarioId, exec.repeatIndex, summary, exec.activityResult, exec)
    clearExecWeatherOverride(exec)
    return "done", nil
end

return BenchRunnerStep
