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

local function thermalTransientScenario(id, runSeconds)
    return {
        id = id,
        movement_uptime_min = 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "await_runtime_tick", timeout_sec = 120 },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "native_treadmill_simple", requested_sec = runSeconds, activity = "run", anchor_mode = "fixed_run", reset_to_anchor = true, forward_dir = "east", sterile_radius = 600.0, enforce_outdoors = false },
            { kind = "sample_once", tag = "after_run" },
            { kind = "wait_window", requested_sec = 3 * 60, runtime_aligned = true },
            { kind = "sample_once", tag = "after_3m_rest" },
            { kind = "lock_weather_end" },
        },
    }
end

local function breathingTreadmillScenario(id, runSeconds, activity)
    local block = {
        kind = "run_activity",
        mode = "native_treadmill_simple",
        requested_sec = runSeconds,
        activity = activity,
        anchor_mode = "fixed_run",
        reset_to_anchor = true,
        forward_dir = "east",
        sterile_radius = 600.0,
        enforce_outdoors = false,
        mid_activity_samples = true,
        mid_activity_every_sec = 30,
        mid_activity_tag = "breathing_live",
    }
    if activity == "sprint" then
        block.repath_sec = 0.20
        block.forward_rearm_retry_sec = 0.08
    end
    return {
        id = id,
        movement_uptime_min = activity == "sprint" and 0.25 or 0.50,
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "await_runtime_tick", timeout_sec = 120 },
            { kind = "sample_once", tag = "before" },
            block,
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    }
end

local SCENARIOS = {
    sleep_real_neutral_v1 = {
        id = "sleep_real_neutral_v1",
        blocks = {
            { kind = "prepare_state" },
            { kind = "equip_set" },
            { kind = "lock_weather_start", weather_profile = "baseline_neutral" },
            { kind = "set_fatigue", value = 0.8 },
            { kind = "sample_once", tag = "before" },
            { kind = "run_activity", mode = "real_sleep", requested_sec = 16 * 60 * 60, hours = 16, fatigue_wake_threshold = 0.02, temp_c = 37.0, wetness_pct = 0.0, mid_activity_samples = true, mid_activity_every_sec = 10 * 60 },
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
    breathing_treadmill_walk = breathingTreadmillScenario("breathing_treadmill_walk", 6 * 60, "walk"),
    breathing_treadmill_run = breathingTreadmillScenario("breathing_treadmill_run", 6 * 60, "run"),
    breathing_treadmill_sprint = breathingTreadmillScenario("breathing_treadmill_sprint", 2 * 60, "sprint"),
    thermal_transient_run_60s = thermalTransientScenario("thermal_transient_run_60s", 60),
    thermal_transient_run_180s = thermalTransientScenario("thermal_transient_run_180s", 180),
    thermal_transient_run_360s = thermalTransientScenario("thermal_transient_run_360s", 360),
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
            { kind = "run_activity", mode = "native_combat_air", requested_swings = 24, requested_sec = 420, timeout_sec = 420, sterile_radius = 8.0, expected_hit_events = 0, combat_stand_still = true },
            { kind = "sample_once", tag = "after" },
            { kind = "lock_weather_end" },
        },
    },
}

local ASYNC_MODES = {
    real_sleep = true,
    native_treadmill_simple = true,
    native_combat_air = true,
}

local BLOCK_KINDS = {
    prepare_state = true,
    equip_set = true,
    lock_weather_start = true,
    lock_weather_end = true,
    set_fatigue = true,
    sample_once = true,
    run_activity = true,
    await_runtime_tick = true,
    wait_window = true,
}

local ACTIVITY_MODES = {
    real_sleep = true,
    native_treadmill_simple = true,
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
        local kind = tostring(block.kind or "")
        if kind == "await_runtime_tick" or kind == "wait_window" then
            return true
        end
        if kind == "run_activity" and ASYNC_MODES[tostring(block.mode or "")] then
            return true
        end
    end
    return false
end

function BenchScenarios.validate(ids)
    local requested = ids or BenchScenarios.list()
    for _, id in ipairs(requested) do
        local scenarioId = tostring(id or "")
        local scenario = SCENARIOS[scenarioId]
        if type(scenario) ~= "table" then
            return false, "unknown scenario '" .. scenarioId .. "'"
        end
        if tostring(scenario.id or "") ~= scenarioId then
            return false, "scenario id mismatch for '" .. scenarioId .. "'"
        end
        if type(scenario.blocks) ~= "table" or #scenario.blocks == 0 then
            return false, "scenario has no blocks: " .. scenarioId
        end
        for blockIndex, block in ipairs(scenario.blocks) do
            local kind = tostring(block and block.kind or "")
            if not BLOCK_KINDS[kind] then
                return false, string.format("unknown block kind scenario=%s block=%d kind=%s", scenarioId, blockIndex, kind)
            end
            if kind == "run_activity" then
                local mode = tostring(block.mode or "")
                if not ACTIVITY_MODES[mode] then
                    return false, string.format("unknown activity mode scenario=%s block=%d mode=%s", scenarioId, blockIndex, mode)
                end
            end
            local duration = tonumber(block.requested_sec)
            if duration ~= nil and duration < 0 then
                return false, string.format("negative duration scenario=%s block=%d", scenarioId, blockIndex)
            end
        end
    end
    return true, nil
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
