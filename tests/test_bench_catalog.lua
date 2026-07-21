local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = { Testing = {} }
local Scenarios = dofile(
    (os.getenv("AMS_ROOT") or ".")
        .. "/common/media/lua/client/testing/ArmorMakesSense_BenchScenarios.lua"
)
local Catalog = dofile(
    (os.getenv("AMS_ROOT") or ".")
        .. "/common/media/lua/client/testing/ArmorMakesSense_BenchCatalog.lua"
)

local errors = {}
Catalog.setContext({
    logError = function(message)
        errors[#errors + 1] = tostring(message)
    end,
})

local scenariosValid, scenarioError = Scenarios.validate()
Support.assertTrue(scenariosValid, scenarioError or "scenario catalog validates")
Support.assertTrue(Catalog.validate(Scenarios.exists), "preset references validate")
Support.assertEqual(#errors, 0, "catalog validation emits no errors")

Support.assertTrue(Scenarios.isAsyncScenario("native_treadmill_run"), "treadmill scenarios are asynchronous")
Support.assertTrue(Scenarios.isAsyncScenario("thermal_transient_run_60s"), "transient scenarios are asynchronous")
Support.assertEqual(Scenarios.get("thermal_transient_run_15s"), nil, "sub-minute transient scenario is not offered")

local transient = Scenarios.get("thermal_transient_run_60s")
local activityCount = 0
local hasRuntimeAlignment = false
local hasRecoveryWait = false
for _, block in ipairs(transient.blocks) do
    if block.kind == "run_activity" then
        activityCount = activityCount + 1
    elseif block.kind == "await_runtime_tick" then
        hasRuntimeAlignment = true
    elseif block.kind == "wait_window" then
        hasRecoveryWait = block.runtime_aligned == true
    end
end
Support.assertEqual(activityCount, 1, "transient scenario has one measured activity")
Support.assertTrue(hasRuntimeAlignment, "transient scenario aligns to a production runtime tick")
Support.assertTrue(hasRecoveryWait, "transient rest ends on a production runtime tick")

local breathingRun = Scenarios.get("breathing_treadmill_run")
local breathingHasAlignment = false
local breathingHasMidSamples = false
for _, block in ipairs(breathingRun.blocks) do
    if block.kind == "await_runtime_tick" then
        breathingHasAlignment = true
    elseif block.kind == "run_activity" then
        breathingHasMidSamples = block.mid_activity_samples == true
            and tonumber(block.mid_activity_every_sec) == 30
    end
end
Support.assertTrue(breathingHasAlignment, "breathing scenario starts from a fresh production tick")
Support.assertTrue(breathingHasMidSamples, "breathing scenario records live effort samples")

local sleepScenario = Scenarios.get("sleep_real_neutral_v1")
local sleepSampleInterval = nil
for _, block in ipairs(sleepScenario.blocks) do
    if block.kind == "run_activity" then
        sleepSampleInterval = tonumber(block.mid_activity_every_sec)
    end
end
Support.assertEqual(sleepSampleInterval, 10 * 60, "sleep trace samples every ten game minutes")

for _, presetId in ipairs(Catalog.listPresetIds()) do
    local plan, planError = Catalog.resolveRunPlan(presetId, {})
    Support.assertTrue(plan ~= nil, planError or ("preset resolves: " .. presetId))
    Support.assertTrue(#plan.sets > 0, "preset has sets: " .. presetId)
    Support.assertTrue(#plan.scenarios > 0, "preset has scenarios: " .. presetId)
end

local noStatMutationPlan, noStatMutationError = Catalog.resolveRunPlan("benchmark_core_v1", {
    stat_profile = { strength = 10, fitness = 10 },
})
Support.assertEqual(noStatMutationPlan, nil, "benchmark plans reject removed destructive stat profiles")
Support.assertTrue(string.find(noStatMutationError, "must not rewrite character XP", 1, true) ~= nil, "stat-profile rejection explains the safety boundary")

print("ams benchmark catalog contracts passed")
