ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunnerReport = Testing.BenchRunnerReport or {}

local BenchRunnerReport = Testing.BenchRunnerReport
local C = {}

-- -----------------------------------------------------------------------------
-- Context wiring and numeric coercion helpers
-- -----------------------------------------------------------------------------

function BenchRunnerReport.setContext(context)
    C = context or {}
end

local function asMetricValue(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    return number
end

function BenchRunnerReport.makeStepResultId(result)
    return string.format(
        "%s:%s:r%d",
        tostring(result and result.setId or "na"),
        tostring(result and result.scenarioId or "na"),
        tonumber(result and result.repeatIndex) or 1
    )
end

-- -----------------------------------------------------------------------------
-- Step result shaping
-- -----------------------------------------------------------------------------

function BenchRunnerReport.buildStepResult(exec, summary)
    local activity = exec and exec.activityResult or {}
    local result = {
        runId = tostring(exec and exec.runId or "na"),
        index = tonumber(exec and exec.index) or 0,
        total = tonumber(exec and exec.total) or 0,
        setId = tostring(exec and exec.setDef and exec.setDef.id or "na"),
        setClass = tostring(exec and exec.setDef and exec.setDef.class or "na"),
        scenarioId = tostring(exec and exec.scenarioId or "na"),
        repeatIndex = tonumber(exec and exec.repeatIndex) or 1,
        repeats = tonumber(exec and exec.repeats) or 1,
        endDelta = asMetricValue(summary and summary.endDelta),
        thirstDelta = asMetricValue(summary and summary.thirstDelta),
        fatigueDelta = asMetricValue(summary and summary.fatigueDelta),
        tempDelta = asMetricValue(summary and summary.tempDelta),
        strainDelta = asMetricValue(summary and summary.strainDelta),
        armStiffnessDelta = asMetricValue(summary and summary.armStiffnessDelta),
        stiffnessPerSwing = asMetricValue(summary and summary.stiffnessPerSwing),
        swingsPerMinute = asMetricValue(summary and summary.swingsPerMinute),
        validityGatesPassed = activity.validity_gates_passed == true,
        gateRejected = activity.gate_rejected == true,
        gateFailed = tostring(activity.gate_failed or "none"),
        stepValidity = tostring(activity.step_validity or "na"),
        requestedSwings = tonumber(activity.requested_swings) or 0,
        achievedSwings = tonumber(activity.achieved_swings) or 0,
        requestedSec = tonumber(activity.requested_sec) or 0,
        achievedSec = tonumber(activity.achieved_sec) or 0,
        attackAttempts = tonumber(activity.attack_attempts) or 0,
        attackSuccess = tonumber(activity.attack_success) or 0,
        attackSuccessRatio = asMetricValue(activity.attack_success_ratio),
        attackCooldownBlocks = tonumber(activity.attack_cooldown_blocks) or 0,
        attackCooldownSec = asMetricValue(activity.attack_cooldown_sec),
        pctIdle = asMetricValue(activity.pct_idle),
        pctWalk = asMetricValue(activity.pct_walk),
        pctRun = asMetricValue(activity.pct_run),
        pctSprint = asMetricValue(activity.pct_sprint),
        pctCombat = asMetricValue(activity.pct_combat),
        exitReason = tostring(activity.exit_reason or "completed"),
    }
    result.stepId = BenchRunnerReport.makeStepResultId(result)
    return result
end

function BenchRunnerReport.appendStepResult(runner, stepResult)
    if type(runner) ~= "table" or type(stepResult) ~= "table" then
        return
    end

    runner.stepResults[#runner.stepResults + 1] = stepResult

    local gateFailed = tostring(stepResult.gateFailed or "none")
    if gateFailed ~= "" and gateFailed ~= "none" then
        runner.lastGateFailed = gateFailed
    end

    local stepValidity = tostring(stepResult.stepValidity or "none")
    if stepValidity ~= "" and stepValidity ~= "none" then
        runner.lastStepValidity = stepValidity
    end

    local exitReason = tostring(stepResult.exitReason or "none")
    if exitReason ~= "" and exitReason ~= "none" then
        runner.lastExitReason = exitReason
    end
end

-- -----------------------------------------------------------------------------
-- Aggregation helpers
-- -----------------------------------------------------------------------------

local function sortedKeys(map)
    local out = {}
    for key, _ in pairs(map or {}) do
        out[#out + 1] = key
    end
    table.sort(out)
    return out
end

local function joinList(values)
    if type(values) ~= "table" or #values == 0 then
        return "none"
    end
    return table.concat(values, ",")
end

local function metricValues(samples, key)
    local out = {}
    for _, sample in ipairs(samples or {}) do
        local value = asMetricValue(sample and sample[key])
        if value ~= nil then
            out[#out + 1] = value
        end
    end
    return out
end

local function mean(values)
    local count = #values
    if count <= 0 then
        return nil
    end
    local sum = 0
    for _, value in ipairs(values) do
        sum = sum + value
    end
    return sum / count
end

local function stddev(values, avg)
    local count = #values
    if count < 2 or avg == nil then
        return nil
    end
    local acc = 0
    for _, value in ipairs(values) do
        local delta = value - avg
        acc = acc + (delta * delta)
    end
    return math.sqrt(acc / (count - 1))
end

local function metricStats(samples, key)
    local values = metricValues(samples, key)
    local stats = {
        count = #values,
        mean = nil,
        stddev = nil,
        cv = nil,
    }
    stats.mean = mean(values)
    stats.stddev = stddev(values, stats.mean)
    if stats.stddev ~= nil and stats.mean ~= nil and math.abs(stats.mean) > 0.000001 then
        stats.cv = stats.stddev / math.abs(stats.mean)
    end
    return stats
end

local function isThermalScenarioId(scenarioId)
    local id = string.lower(tostring(scenarioId or ""))
    return string.find(id, "_hot", 1, true) ~= nil
        or string.find(id, "_cold", 1, true) ~= nil
        or string.find(id, "thermal", 1, true) ~= nil
end

local function scenarioSetOrder(runner, scenarioSetStats)
    local order = {}
    local seen = {}
    for _, setId in ipairs(runner and runner.setOrder or {}) do
        if scenarioSetStats and scenarioSetStats[setId] then
            order[#order + 1] = setId
            seen[setId] = true
        end
    end
    for _, setId in ipairs(sortedKeys(scenarioSetStats or {})) do
        if not seen[setId] then
            order[#order + 1] = setId
        end
    end
    return order
end

local function findSetByClass(scenarioData, className, excludeSetId)
    for _, setId in ipairs(scenarioData and scenarioData.setOrder or {}) do
        local setStats = scenarioData and scenarioData.sets and scenarioData.sets[setId] or nil
        if setStats and tostring(setStats.class) == tostring(className) and setId ~= excludeSetId then
            return setId
        end
    end
    return nil
end

local function monotonicBurden(value)
    local parsed = asMetricValue(value)
    if parsed == nil then
        return nil
    end
    return -parsed
end

local function checkMonotonicPair(leftLabel, leftValue, rightLabel, rightValue, scenarioId)
    if leftValue == nil or rightValue == nil then
        return true, nil
    end
    if leftValue > (rightValue + 0.000001) then
        return false, string.format("%s > %s in endDelta for %s", tostring(leftLabel), tostring(rightLabel), tostring(scenarioId))
    end
    return true, nil
end

-- -----------------------------------------------------------------------------
-- Benchmark report construction
-- -----------------------------------------------------------------------------

function BenchRunnerReport.buildBenchmarkReport(runner, deps)
    deps = deps or {}
    local resolveThreshold = deps.resolveThreshold
    local resolveScenarioGateProfile = deps.resolveScenarioGateProfile
    local reportDefaults = deps.reportDefaults or {}
    local benchScenarios = deps.benchScenarios

    local report = {
        id = tostring(runner and runner.id or "na"),
        preset = tostring(runner and runner.preset or "na"),
        total_steps = 0,
        validity_passed = 0,
        rejected_steps = {},
        scenarios = {},
        scenarioOrder = {},
        warnings = {},
        monotonicity = {
            status = "pass",
            breakDescription = "none",
        },
        stability = {
            status = "pass",
            flagged = {},
            insufficient = {},
        },
    }

    local thresholds = runner and runner.reportThresholds or {}
    local cvWarnThreshold = resolveThreshold and resolveThreshold(thresholds.stability_cv_warn, reportDefaults.stability_cv_warn, 0.0) or tonumber(thresholds.stability_cv_warn) or 0.15
    local separationDenominatorMin = resolveThreshold and resolveThreshold(thresholds.separation_ratio_denominator_min, reportDefaults.separation_ratio_denominator_min, 0.000001) or tonumber(thresholds.separation_ratio_denominator_min) or 0.005
    local separationRatioMin = resolveThreshold and resolveThreshold(thresholds.separation_ratio_min, reportDefaults.separation_ratio_min, 0.0) or tonumber(thresholds.separation_ratio_min) or 1.2

    local results = runner and runner.stepResults or {}
    report.total_steps = #results

    for _, stepResult in ipairs(results) do
        if stepResult.validityGatesPassed then
            report.validity_passed = report.validity_passed + 1
        else
            report.rejected_steps[#report.rejected_steps + 1] = tostring(stepResult.stepId or BenchRunnerReport.makeStepResultId(stepResult))
        end

        local scenarioId = tostring(stepResult.scenarioId or "na")
        local setId = tostring(stepResult.setId or "na")
        local scenario = report.scenarios[scenarioId]
        if not scenario then
            scenario = {
                id = scenarioId,
                sets = {},
                setOrder = {},
                monotonicity = "pass",
                monotonicity_break = "none",
                baseline_missing = false,
                heavy_light_ratio = nil,
                separation_ratio = nil,
                separation_ratio_check = "na",
            }
            report.scenarios[scenarioId] = scenario
            report.scenarioOrder[#report.scenarioOrder + 1] = scenarioId
        end

        local setStats = scenario.sets[setId]
        if not setStats then
            setStats = {
                id = setId,
                class = tostring(stepResult.setClass or "na"),
                samples = {},
                validSamples = {},
                total_count = 0,
                valid_count = 0,
            }
            scenario.sets[setId] = setStats
        end

        setStats.samples[#setStats.samples + 1] = stepResult
        setStats.total_count = setStats.total_count + 1
        if stepResult.validityGatesPassed then
            setStats.validSamples[#setStats.validSamples + 1] = stepResult
            setStats.valid_count = setStats.valid_count + 1
        end
    end

    local orderedScenarios = {}
    local seenScenarios = {}
    for _, scenarioId in ipairs(runner and runner.scenarioOrder or {}) do
        scenarioId = tostring(scenarioId)
        if report.scenarios[scenarioId] and not seenScenarios[scenarioId] then
            orderedScenarios[#orderedScenarios + 1] = scenarioId
            seenScenarios[scenarioId] = true
        end
    end
    for _, scenarioId in ipairs(sortedKeys(report.scenarios)) do
        if not seenScenarios[scenarioId] then
            orderedScenarios[#orderedScenarios + 1] = scenarioId
        end
    end
    report.scenarioOrder = orderedScenarios

    local hasNaked = false
    for _, setId in ipairs(runner and runner.setOrder or {}) do
        if setId == "naked" then
            hasNaked = true
            break
        end
    end
    if not hasNaked then
        report.warnings[#report.warnings + 1] = "naked_baseline_missing"
    end

    for _, scenarioId in ipairs(report.scenarioOrder) do
        local scenario = report.scenarios[scenarioId]
        scenario.setOrder = scenarioSetOrder(runner, scenario.sets)

        for _, setId in ipairs(scenario.setOrder) do
            local setStats = scenario.sets[setId]
            local endStats = metricStats(setStats.validSamples, "endDelta")
            local thirstStats = metricStats(setStats.validSamples, "thirstDelta")
            local fatigueStats = metricStats(setStats.validSamples, "fatigueDelta")
            local tempStats = metricStats(setStats.validSamples, "tempDelta")
            local strainStats = metricStats(setStats.validSamples, "strainDelta")
            local armStiffStats = metricStats(setStats.validSamples, "armStiffnessDelta")
            local stiffPerSwingStats = metricStats(setStats.validSamples, "stiffnessPerSwing")
            local achievedSecStats = metricStats(setStats.validSamples, "achievedSec")
            local swingStats = metricStats(setStats.validSamples, "swingsPerMinute")
            local pctIdleStats = metricStats(setStats.validSamples, "pctIdle")
            local pctWalkStats = metricStats(setStats.validSamples, "pctWalk")
            local pctRunStats = metricStats(setStats.validSamples, "pctRun")
            local pctSprintStats = metricStats(setStats.validSamples, "pctSprint")
            local pctCombatStats = metricStats(setStats.validSamples, "pctCombat")

            setStats.mean_end_delta = endStats.mean
            setStats.stddev_end_delta = endStats.stddev
            setStats.cv_end_delta = setStats.valid_count >= 2 and endStats.cv or nil
            setStats.mean_thirst_delta = thirstStats.mean
            setStats.stddev_thirst_delta = thirstStats.stddev
            setStats.cv_thirst_delta = setStats.valid_count >= 2 and thirstStats.cv or nil
            setStats.mean_fatigue_delta = fatigueStats.mean
            setStats.stddev_fatigue_delta = fatigueStats.stddev
            setStats.cv_fatigue_delta = setStats.valid_count >= 2 and fatigueStats.cv or nil
            setStats.mean_temp_delta = tempStats.mean
            setStats.stddev_temp_delta = tempStats.stddev
            setStats.cv_temp_delta = setStats.valid_count >= 2 and tempStats.cv or nil
            setStats.mean_strain_delta = strainStats.mean
            setStats.stddev_strain_delta = strainStats.stddev
            setStats.cv_strain_delta = setStats.valid_count >= 2 and strainStats.cv or nil
            setStats.mean_arm_stiffness_delta = armStiffStats.mean
            setStats.stddev_arm_stiffness_delta = armStiffStats.stddev
            setStats.cv_arm_stiffness_delta = setStats.valid_count >= 2 and armStiffStats.cv or nil
            setStats.mean_stiffness_per_swing = stiffPerSwingStats.mean
            setStats.stddev_stiffness_per_swing = stiffPerSwingStats.stddev
            setStats.cv_stiffness_per_swing = setStats.valid_count >= 2 and stiffPerSwingStats.cv or nil
            setStats.mean_achieved_sec = achievedSecStats.mean
            setStats.stddev_achieved_sec = achievedSecStats.stddev
            setStats.cv_achieved_sec = setStats.valid_count >= 2 and achievedSecStats.cv or nil
            setStats.mean_swings_per_minute = swingStats.mean
            setStats.stddev_swings_per_minute = swingStats.stddev
            setStats.cv_swings_per_minute = setStats.valid_count >= 2 and swingStats.cv or nil
            setStats.mean_pct_idle = pctIdleStats.mean
            setStats.mean_pct_walk = pctWalkStats.mean
            setStats.mean_pct_run = pctRunStats.mean
            setStats.mean_pct_sprint = pctSprintStats.mean
            setStats.mean_pct_combat = pctCombatStats.mean

            if setStats.valid_count < 2 then
                setStats.stability = "insufficient_data"
                report.stability.insufficient[#report.stability.insufficient + 1] = string.format("%s:%s", tostring(scenarioId), tostring(setId))
            elseif setStats.cv_end_delta ~= nil and setStats.cv_end_delta > cvWarnThreshold then
                setStats.stability = "warn"
                local metricOrNa = deps.metricOrNa or function(value) return tostring(value) end
                report.stability.flagged[#report.stability.flagged + 1] = string.format("%s:%s(cv=%s)", tostring(scenarioId), tostring(setId), metricOrNa(setStats.cv_end_delta, 4))
            else
                setStats.stability = "pass"
            end
        end

        local baseline = scenario.sets.naked
        local baselineEnd = baseline and asMetricValue(baseline.mean_end_delta) or nil
        local baselineThirst = baseline and asMetricValue(baseline.mean_thirst_delta) or nil
        local baselineTemp = baseline and asMetricValue(baseline.mean_temp_delta) or nil
        local baselineStrain = baseline and asMetricValue(baseline.mean_strain_delta) or nil
        local baselineArmStiffness = baseline and asMetricValue(baseline.mean_arm_stiffness_delta) or nil
        local baselineAchievedSec = baseline and asMetricValue(baseline.mean_achieved_sec) or nil
        if baseline == nil or baselineEnd == nil then
            scenario.baseline_missing = true
        end

        if not scenario.baseline_missing then
            for _, setId in ipairs(scenario.setOrder) do
                local setStats = scenario.sets[setId]
                setStats.marginal_end_delta = setStats.mean_end_delta ~= nil and (setStats.mean_end_delta - baselineEnd) or nil
                setStats.marginal_thirst_delta = (setStats.mean_thirst_delta ~= nil and baselineThirst ~= nil) and (setStats.mean_thirst_delta - baselineThirst) or nil
                setStats.marginal_temp_delta = (setStats.mean_temp_delta ~= nil and baselineTemp ~= nil) and (setStats.mean_temp_delta - baselineTemp) or nil
                setStats.marginal_strain_delta = (setStats.mean_strain_delta ~= nil and baselineStrain ~= nil) and (setStats.mean_strain_delta - baselineStrain) or nil
                setStats.marginal_arm_stiffness_delta = (setStats.mean_arm_stiffness_delta ~= nil and baselineArmStiffness ~= nil) and (setStats.mean_arm_stiffness_delta - baselineArmStiffness) or nil
                setStats.marginal_achieved_sec = (setStats.mean_achieved_sec ~= nil and baselineAchievedSec ~= nil) and (setStats.mean_achieved_sec - baselineAchievedSec) or nil
            end
        else
            report.warnings[#report.warnings + 1] = string.format("naked_baseline_missing:%s", tostring(scenarioId))
        end

        local lightSetId = scenario.sets.bulletproof_vest and "bulletproof_vest" or nil
        local lightStats = lightSetId and scenario.sets[lightSetId] or nil
        local heavyStats = scenario.sets.heavy
        if lightStats and heavyStats and lightStats.mean_end_delta ~= nil and heavyStats.mean_end_delta ~= nil and math.abs(lightStats.mean_end_delta) > 0.000001 then
            scenario.heavy_light_ratio = math.abs(heavyStats.mean_end_delta) / math.abs(lightStats.mean_end_delta)
        end
        if lightStats and heavyStats and lightStats.mean_achieved_sec ~= nil and heavyStats.mean_achieved_sec ~= nil and math.abs(lightStats.mean_achieved_sec) > 0.000001 then
            scenario.heavy_light_duration_ratio = math.abs(heavyStats.mean_achieved_sec) / math.abs(lightStats.mean_achieved_sec)
        end

        if not scenario.baseline_missing and lightStats and heavyStats and baseline and baseline.mean_end_delta ~= nil and lightStats.mean_end_delta ~= nil and heavyStats.mean_end_delta ~= nil then
            local denominator = lightStats.mean_end_delta - baseline.mean_end_delta
            if math.abs(denominator) < separationDenominatorMin then
                scenario.separation_ratio = "undefined_low_baseline"
                scenario.separation_ratio_check = "na"
            else
                scenario.separation_ratio = (heavyStats.mean_end_delta - lightStats.mean_end_delta) / denominator
                scenario.separation_ratio_check = scenario.separation_ratio >= separationRatioMin and "pass" or "fail"
            end
        end

        local scenarioDef = benchScenarios and type(benchScenarios.get) == "function" and benchScenarios.get(scenarioId) or nil
        local scenarioGateProfile = resolveScenarioGateProfile and resolveScenarioGateProfile(scenarioDef) or {}
        if scenarioGateProfile.realSleep then
            local civilianId = scenario.sets.civilian_baseline and "civilian_baseline" or findSetByClass(scenario, "civilian", "naked")
            local lightId = lightSetId
            local heavyId = scenario.sets.heavy and "heavy" or nil
            local sequence = {
                { label = "naked", value = scenario.sets.naked and asMetricValue(scenario.sets.naked.mean_achieved_sec) or nil },
                { label = "civilian", value = civilianId and asMetricValue(scenario.sets[civilianId].mean_achieved_sec) or nil },
                { label = "bulletproof_vest", value = lightId and asMetricValue(scenario.sets[lightId].mean_achieved_sec) or nil },
                { label = "heavy", value = heavyId and asMetricValue(scenario.sets[heavyId].mean_achieved_sec) or nil },
            }

            for i = 1, #sequence - 1 do
                local left = sequence[i]
                local right = sequence[i + 1]
                local ok, breakReason = checkMonotonicPair(left.label, left.value, right.label, right.value, scenarioId)
                if not ok then
                    scenario.monotonicity = "fail"
                    scenario.monotonicity_break = tostring(breakReason)
                    break
                end
            end
        elseif isThermalScenarioId(scenarioId) then
            local lightId = lightSetId
            local heavyId = scenario.sets.heavy and "heavy" or nil
            if lightId and heavyId then
                local left = monotonicBurden(scenario.sets[lightId].marginal_end_delta)
                local right = monotonicBurden(scenario.sets[heavyId].marginal_end_delta)
                local ok, breakReason = checkMonotonicPair("bulletproof_vest", left, "heavy", right, scenarioId)
                if not ok then
                    scenario.monotonicity = "fail"
                    scenario.monotonicity_break = tostring(breakReason)
                end
            end
        else
            local civilianId = scenario.sets.civilian_baseline and "civilian_baseline" or findSetByClass(scenario, "civilian", "naked")
            local lightId = lightSetId
            local heavyId = scenario.sets.heavy and "heavy" or nil

            local sequence = {
                { label = "naked", value = monotonicBurden(0.0) },
                { label = "civilian", value = civilianId and monotonicBurden(scenario.sets[civilianId].marginal_end_delta) or nil },
                { label = "bulletproof_vest", value = lightId and monotonicBurden(scenario.sets[lightId].marginal_end_delta) or nil },
                { label = "heavy", value = heavyId and monotonicBurden(scenario.sets[heavyId].marginal_end_delta) or nil },
            }

            for i = 1, #sequence - 1 do
                local left = sequence[i]
                local right = sequence[i + 1]
                local ok, breakReason = checkMonotonicPair(left.label, left.value, right.label, right.value, scenarioId)
                if not ok then
                    scenario.monotonicity = "fail"
                    scenario.monotonicity_break = tostring(breakReason)
                    break
                end
            end
        end

        if scenario.monotonicity == "fail" and report.monotonicity.status == "pass" then
            report.monotonicity.status = "fail"
            report.monotonicity.breakDescription = tostring(scenario.monotonicity_break or "unknown")
        end
    end

    if #report.stability.flagged > 0 then
        report.stability.status = "warn"
    elseif #report.stability.insufficient > 0 then
        report.stability.status = "insufficient_data"
    else
        report.stability.status = "pass"
    end

    return report
end

-- -----------------------------------------------------------------------------
-- Benchmark report logging
-- -----------------------------------------------------------------------------

function BenchRunnerReport.logBenchmarkReport(runner, report, deps)
    deps = deps or {}
    local log = C.log
    local metricOrNa = deps.metricOrNa or function(value) return tostring(value) end
    local benchSnapshotAppend = deps.benchSnapshotAppend
    local emitLine = deps.emitLine

    if not report then
        return
    end

    local function emit(line)
        if type(emitLine) == "function" then
            emitLine(runner, line, "report")
            return
        end
        if type(log) == "function" then
            log(line)
        end
        if type(benchSnapshotAppend) == "function" then
            benchSnapshotAppend(runner and runner.snapshot or nil, line, "report")
        end
    end

    emit(string.format(
        "[AMS_BENCHMARK_REPORT] id=%s preset=%s",
        tostring(report.id or "na"),
        tostring(report.preset or "na")
    ))
    emit(string.format(
        "[AMS_BENCHMARK_REPORT] validity=%d/%d rejected=%s",
        tonumber(report.validity_passed) or 0,
        tonumber(report.total_steps) or 0,
        joinList(report.rejected_steps)
    ))
    emit(string.format(
        "[AMS_BENCHMARK_REPORT] monotonicity=%s break=%s stability=%s flagged=%s insufficient=%s",
        tostring(report.monotonicity and report.monotonicity.status or "pass"),
        tostring(report.monotonicity and report.monotonicity.breakDescription or "none"),
        tostring(report.stability and report.stability.status or "pass"),
        joinList(report.stability and report.stability.flagged or {}),
        joinList(report.stability and report.stability.insufficient or {})
    ))

    if #report.warnings > 0 then
        emit(string.format("[AMS_BENCHMARK_REPORT] warnings=%s", joinList(report.warnings)))
    end

    for _, scenarioId in ipairs(report.scenarioOrder or {}) do
        local scenario = report.scenarios and report.scenarios[scenarioId] or nil
        if scenario then
            emit(string.format(
                "[AMS_BENCHMARK_REPORT] scenario=%s monotonicity=%s monotonicity_break=%s baseline_missing=%s heavy_light_ratio=%s separation_ratio=%s separation_ratio_check=%s",
                tostring(scenarioId),
                tostring(scenario.monotonicity or "pass"),
                tostring(scenario.monotonicity_break or "none"),
                tostring(scenario.baseline_missing),
                metricOrNa(scenario.heavy_light_ratio, 4),
                type(scenario.separation_ratio) == "number" and metricOrNa(scenario.separation_ratio, 4) or tostring(scenario.separation_ratio or "na"),
                tostring(scenario.separation_ratio_check or "na")
            ))
            if scenario.heavy_light_duration_ratio ~= nil then
                emit(string.format(
                    "[AMS_BENCHMARK_REPORT] scenario=%s heavy_light_duration_ratio=%s",
                    tostring(scenarioId),
                    metricOrNa(scenario.heavy_light_duration_ratio, 4)
                ))
            end

            for _, setId in ipairs(scenario.setOrder or {}) do
                local setStats = scenario.sets and scenario.sets[setId] or nil
                if setStats then
                    emit(string.format(
                        "[AMS_BENCHMARK_REPORT] scenario=%s set=%s class=%s valid=%d/%d mean_end_delta=%s stddev_end_delta=%s cv_end_delta=%s mean_thirst_delta=%s stddev_thirst_delta=%s cv_thirst_delta=%s mean_fatigue_delta=%s stddev_fatigue_delta=%s cv_fatigue_delta=%s mean_temp_delta=%s stddev_temp_delta=%s cv_temp_delta=%s mean_strain_delta=%s stddev_strain_delta=%s cv_strain_delta=%s mean_arm_stiffness_delta=%s stddev_arm_stiffness_delta=%s cv_arm_stiffness_delta=%s mean_stiffness_per_swing=%s stddev_stiffness_per_swing=%s cv_stiffness_per_swing=%s mean_achieved_sec=%s stddev_achieved_sec=%s cv_achieved_sec=%s swings_per_minute=%s stddev_swings_per_minute=%s cv_swings_per_minute=%s mean_pct_idle=%s mean_pct_walk=%s mean_pct_run=%s mean_pct_sprint=%s mean_pct_combat=%s marginal_end_delta=%s marginal_thirst_delta=%s marginal_temp_delta=%s marginal_strain_delta=%s marginal_arm_stiffness_delta=%s marginal_achieved_sec=%s stability=%s",
                        tostring(scenarioId),
                        tostring(setId),
                        tostring(setStats.class or "na"),
                        tonumber(setStats.valid_count) or 0,
                        tonumber(setStats.total_count) or 0,
                        metricOrNa(setStats.mean_end_delta, 6),
                        metricOrNa(setStats.stddev_end_delta, 6),
                        metricOrNa(setStats.cv_end_delta, 6),
                        metricOrNa(setStats.mean_thirst_delta, 6),
                        metricOrNa(setStats.stddev_thirst_delta, 6),
                        metricOrNa(setStats.cv_thirst_delta, 6),
                        metricOrNa(setStats.mean_fatigue_delta, 6),
                        metricOrNa(setStats.stddev_fatigue_delta, 6),
                        metricOrNa(setStats.cv_fatigue_delta, 6),
                        metricOrNa(setStats.mean_temp_delta, 6),
                        metricOrNa(setStats.stddev_temp_delta, 6),
                        metricOrNa(setStats.cv_temp_delta, 6),
                        metricOrNa(setStats.mean_strain_delta, 6),
                        metricOrNa(setStats.stddev_strain_delta, 6),
                        metricOrNa(setStats.cv_strain_delta, 6),
                        metricOrNa(setStats.mean_arm_stiffness_delta, 6),
                        metricOrNa(setStats.stddev_arm_stiffness_delta, 6),
                        metricOrNa(setStats.cv_arm_stiffness_delta, 6),
                        metricOrNa(setStats.mean_stiffness_per_swing, 6),
                        metricOrNa(setStats.stddev_stiffness_per_swing, 6),
                        metricOrNa(setStats.cv_stiffness_per_swing, 6),
                        metricOrNa(setStats.mean_achieved_sec, 3),
                        metricOrNa(setStats.stddev_achieved_sec, 3),
                        metricOrNa(setStats.cv_achieved_sec, 6),
                        metricOrNa(setStats.mean_swings_per_minute, 4),
                        metricOrNa(setStats.stddev_swings_per_minute, 4),
                        metricOrNa(setStats.cv_swings_per_minute, 6),
                        metricOrNa(setStats.mean_pct_idle, 4),
                        metricOrNa(setStats.mean_pct_walk, 4),
                        metricOrNa(setStats.mean_pct_run, 4),
                        metricOrNa(setStats.mean_pct_sprint, 4),
                        metricOrNa(setStats.mean_pct_combat, 4),
                        metricOrNa(setStats.marginal_end_delta, 6),
                        metricOrNa(setStats.marginal_thirst_delta, 6),
                        metricOrNa(setStats.marginal_temp_delta, 6),
                        metricOrNa(setStats.marginal_strain_delta, 6),
                        metricOrNa(setStats.marginal_arm_stiffness_delta, 6),
                        metricOrNa(setStats.marginal_achieved_sec, 3),
                        tostring(setStats.stability or "pass")
                    ))
                end
            end
        end
    end
end

return BenchRunnerReport
