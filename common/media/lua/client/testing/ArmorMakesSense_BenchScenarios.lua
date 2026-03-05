ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchScenarios = Testing.BenchScenarios or {}

local BenchScenarios = Testing.BenchScenarios
local C = {}

-- -----------------------------------------------------------------------------
-- Context wiring and static scenario catalog
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function BenchScenarios.setContext(context)
    C = context or {}
end

local SCENARIOS = {
    snapshot = {
        id = "snapshot",
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "sample_once", tag = "snapshot" },
        },
    },
    sleep_real_neutral_v1 = {
        id = "sleep_real_neutral_v1",
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "set_fatigue", value = 0.8 },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "real_sleep", requested_sec = 16 * 60 * 60, hours = 16, fatigue_wake_threshold = 0.02, temp_c = 37.0, wetness_pct = 0.0, mid_activity_samples = true, mid_activity_every_sec = 60 },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_walk = {
        id = "native_treadmill_walk",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "walk", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_run = {
        id = "native_treadmill_run",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "run", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_sprint = {
        id = "native_treadmill_sprint",
        movement_uptime_min = 0.25,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 2 * 60, activity = "sprint", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false, repath_sec = 0.20, forward_rearm_retry_sec = 0.08 },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_walk_hot = {
        id = "native_treadmill_walk_hot",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "thermal_hot" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "walk", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_run_hot = {
        id = "native_treadmill_run_hot",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "thermal_hot" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "run", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_walk_cold = {
        id = "native_treadmill_walk_cold",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "thermal_cold" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "walk", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_run_cold = {
        id = "native_treadmill_run_cold",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "thermal_cold" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "run", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_walk_cold_nowind = {
        id = "native_treadmill_walk_cold_nowind",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "thermal_cold_nowind" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "walk", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_treadmill_run_cold_nowind = {
        id = "native_treadmill_run_cold_nowind",
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "thermal_cold_nowind" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = 6 * 60, activity = "run", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
    native_standing_combat_air = {
        id = "native_standing_combat_air",
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_combat_air", requested_swings = 60, requested_sec = 420, timeout_sec = 420, sterile_radius = 8.0, expected_hit_events = 0, combat_stand_still = true },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
}

local ASYNC_MODES = {
    idle_window = true,
    real_sleep = true,
    native_warmup = true,
    native_move = true,
    native_combat_air = true,
}

-- -----------------------------------------------------------------------------
-- Scenario query helpers
-- -----------------------------------------------------------------------------

function BenchScenarios.get(id)
    return SCENARIOS[tostring(id or "")]
end

function BenchScenarios.exists(id)
    return SCENARIOS[tostring(id or "")] ~= nil
end

function BenchScenarios.isAsyncScenario(id)
    local scenario = BenchScenarios.get(id)
    if not scenario then
        return false
    end
    for _, block in ipairs(scenario.blocks or {}) do
        if tostring(block.kind or "") == "run_activity" and ASYNC_MODES[tostring(block.mode or "")] then
            return true
        end
    end
    return false
end

function BenchScenarios.list(ids)
    local out = {}
    local requested = ids or {}
    if #requested == 0 then
        for id, _ in pairs(SCENARIOS) do
            out[#out + 1] = id
        end
        table.sort(out)
        return out
    end
    for _, id in ipairs(requested) do
        if BenchScenarios.exists(id) then
            out[#out + 1] = tostring(id)
        end
    end
    return out
end

return BenchScenarios
