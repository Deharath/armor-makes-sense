local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {
    Utils = { clamp = Support.clamp, safeMethod = Support.safeMethod },
    Testing = {},
}
local root = (os.getenv("AMS_ROOT") or ".") .. "/common/media/lua/client/testing/"
dofile(root .. "ArmorMakesSense_BenchUtils.lua")
dofile(root .. "ArmorMakesSense_BenchRunnerEnv.lua")
dofile(root .. "ArmorMakesSense_BenchRunnerStep.lua")
local Report = dofile(root .. "ArmorMakesSense_BenchRunnerReport.lua")

Support.assertClose(Report.enduranceCost(-0.2, 1.4), 1.4, 1e-9, "drain cost is the realized scale")
Support.assertClose(Report.enduranceCost(0.2, 0.5), 2.0, 1e-9, "regen cost is the inverse realized scale")
Support.assertEqual(Report.enduranceCost(nil, 1.0), nil, "no ledger means no cost")

local function step(setId, class, natural, scale, endDelta)
    return {
        stepId = setId,
        setId = setId,
        setClass = class,
        scenarioId = "treadmill_run",
        validityGatesPassed = true,
        endDelta = endDelta,
        naturalTotal = natural,
        realizedScale = scale,
        enduranceCost = Report.enduranceCost(natural, scale),
        tickGaps = 0,
    }
end

local function build(results)
    return Report.buildBenchmarkReport({
        id = "t",
        preset = "core",
        setOrder = { "naked", "civilian_baseline", "bulletproof_vest", "heavy" },
        scenarioOrder = { "treadmill_run" },
        stepResults = results,
    }, {})
end

-- Raw endDelta ordering is inverted (activity-mix noise); cost ordering is right.
local report = build({
    step("naked", "baseline", -0.30, 1.00, -0.30),
    step("civilian_baseline", "civilian", -0.25, 1.00, -0.25),
    step("bulletproof_vest", "light", -0.20, 1.05, -0.21),
    step("heavy", "heavy", -0.10, 1.50, -0.15),
})
Support.assertEqual(report.monotonicity.status, "pass", "monotonicity follows cost, not raw endDelta")
Support.assertEqual(report.stability.status, "na", "single repeats skip stability")
Support.assertClose(report.scenarios.treadmill_run.heavy_light_ratio, 1.5 / 1.05, 1e-9, "heavy/light ratio uses cost")
Support.assertClose(report.scenarios.treadmill_run.separation_ratio, 0.45 / 0.05, 1e-9, "separation uses cost")

report = build({
    step("naked", "baseline", -0.30, 1.00, -0.30),
    step("bulletproof_vest", "light", -0.20, 1.30, -0.26),
    step("heavy", "heavy", -0.20, 1.20, -0.24),
})
Support.assertEqual(report.monotonicity.status, "fail", "heavy cheaper than vest breaks monotonicity")

report = build({
    step("naked", "baseline", -0.30, 1.00, -0.30),
    step("naked", "baseline", -0.20, 1.00, -0.20),
    step("heavy", "heavy", -0.30, 1.50, -0.45),
    step("heavy", "heavy", -0.10, 1.50, -0.15),
})
Support.assertEqual(report.stability.status, "pass", "stable cost passes despite noisy endDelta")

print("ams benchmark report checks passed")
