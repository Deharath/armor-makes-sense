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

local breathingRun = Scenarios.get("breathing_run")
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

local sleepScenario = Scenarios.get("sleep_neutral")
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

local function blockKinds(id)
    local out = {}
    for _, block in ipairs(Scenarios.get(id).blocks) do
        out[#out + 1] = block.kind .. (block.baseline and ":baseline" or "")
    end
    return table.concat(out, ",")
end
Support.assertEqual(
    blockKinds("treadmill_run"),
    "prepare_state,equip_set,lock_weather_start,await_runtime_tick,sample_once,run_activity,sample_once,lock_weather_end",
    "treadmill scenarios start on a production tick"
)
Support.assertEqual(Scenarios.get("treadmill_sprint").blocks[6].speed_req, 8, "sprint blocks slow to 8x for enough frames")
Support.assertEqual(Scenarios.get("recovery_stand").blocks[6].speed_req, 8, "recovery drain sprint slows to 8x")
Support.assertEqual(Scenarios.get("treadmill_run").blocks[6].speed_req, nil, "run keeps the preset speed")
Support.assertEqual(Scenarios.get("treadmill_run_cold_nowind").blocks[3].weather_profile, "thermal_cold_nowind", "weather variants carry their profile")
Support.assertEqual(Scenarios.get("treadmill_sprint").movement_uptime_min, 0.25, "sprint keeps its relaxed uptime gate")
Support.assertEqual(
    blockKinds("recovery_stand"),
    "prepare_state,equip_set,lock_weather_start,await_runtime_tick,sample_once,run_activity,await_runtime_tick,sample_once:baseline,wait_window,sample_once,lock_weather_end",
    "stand recovery rebases after the drain and measures idle time"
)
Support.assertEqual(
    blockKinds("recovery_walk"),
    "prepare_state,equip_set,lock_weather_start,await_runtime_tick,sample_once,run_activity,await_runtime_tick,sample_once:baseline,run_activity,sample_once,lock_weather_end",
    "walk recovery rebases after the drain and measures walking"
)
Support.assertEqual(blockKinds("sleep_neutral"), "prepare_state,equip_set,lock_weather_start,set_fatigue,sample_once,run_activity,sample_once,lock_weather_end", "sleep raises fatigue before sampling")

local explicit = Catalog.resolveRunPlan("core", { sets = "heavy,naked", repeats = 1 })
Support.assertEqual(explicit.sets[1].id, "heavy", "explicit sets keep requested order")
Support.assertEqual(explicit.repeats, 1, "repeat override applies")
Support.assertEqual(explicit.speed, 16.0, "preset speed applies")
Support.assertEqual(Catalog.resolveRunPlan("sleep").speed, 8.0, "sleep keeps its validated speed")
local outside = Catalog.resolveRunPlan("core", { sets = { "mask_gas" } })
Support.assertEqual(outside.sets[1].id, "mask_gas", "explicit sets can come from outside the preset")
local _, unknownErr = Catalog.resolveRunPlan("core", { sets = "nope" })
Support.assertEqual(unknownErr, "unknown set ids: nope", "unknown sets fail before execution")
local current = Catalog.resolveRunPlan("core", { current_set = true })
Support.assertEqual(current.sets[1].id, "current_equipped", "current_set runs the worn outfit")
local _, mixedErr = Catalog.resolveRunPlan("core", { current_set = true, sets = "heavy" })
Support.assertTrue(mixedErr ~= nil, "current_set rejects explicit sets")
local classOnly = Catalog.resolveRunPlan("core", { classes = "armor" })
for _, setDef in ipairs(classOnly.sets) do
    Support.assertEqual(setDef.class, "armor", "class filter keeps only armor sets")
end
Support.assertEqual(Catalog.resolveRunPlan("benchmark_core_v1"), nil, "legacy preset ids are gone")

print("ams benchmark catalog contracts passed")
