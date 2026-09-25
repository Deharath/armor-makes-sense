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

local function treadmillBlock(activity, requestedSec, extra)
    local block = {
        kind = "run_activity",
        mode = "native_treadmill_simple",
        requested_sec = requestedSec,
        activity = activity,
        anchor_mode = "fixed_run",
        reset_to_anchor = true,
        forward_dir = "east",
        sterile_radius = 600.0,
        enforce_outdoors = false,
    }
    if activity == "sprint" then
        block.repath_sec = 0.20
        block.forward_rearm_retry_sec = 0.08
        -- Sprint start-up and re-arms cost real frames; at 16x a 2-minute sprint
        -- spans only 12-40 frames and misses its sprint-uptime gate.
        block.speed_req = 8
    end
    for key, value in pairs(extra or {}) do
        block[key] = value
    end
    return block
end

local function scenario(id, weatherProfile, measured, opts)
    opts = opts or {}
    local blocks = {
        { kind = "prepare_state" },
        { kind = "equip_set" },
        { kind = "lock_weather_start", weather_profile = weatherProfile },
    }
    if opts.fatigue ~= nil then
        blocks[#blocks + 1] = { kind = "set_fatigue", value = opts.fatigue }
    end
    if opts.align ~= false then
        blocks[#blocks + 1] = { kind = "await_runtime_tick", timeout_sec = 120 }
    end
    blocks[#blocks + 1] = { kind = "sample_once", tag = "before" }
    for _, block in ipairs(measured) do
        blocks[#blocks + 1] = block
    end
    blocks[#blocks + 1] = { kind = "lock_weather_end" }
    return {
        id = id,
        movement_uptime_min = opts.movement_uptime_min,
        blocks = blocks,
    }
end

local function treadmillScenario(id, activity, requestedSec, weatherProfile, extra)
    return scenario(id, weatherProfile or "baseline_neutral", {
        treadmillBlock(activity, requestedSec, extra),
        { kind = "sample_once", tag = "after" },
    }, { movement_uptime_min = activity == "sprint" and 0.25 or 0.50 })
end

local function breathingScenario(id, activity, requestedSec)
    return treadmillScenario(id, activity, requestedSec, "baseline_neutral", {
        mid_activity_samples = true,
        mid_activity_every_sec = 30,
        mid_activity_tag = "breathing_live",
    })
end

local function thermalTransientScenario(id, runSeconds)
    return scenario(id, "baseline_neutral", {
        treadmillBlock("run", runSeconds),
        { kind = "sample_once", tag = "after_run" },
        { kind = "wait_window", requested_sec = 3 * 60, runtime_aligned = true },
        { kind = "sample_once", tag = "after_3m_rest" },
    }, { movement_uptime_min = 0.50 })
end

-- Sprint to open an endurance deficit, then measure only the recovery window.
-- The "baseline" sample restarts the step deltas so endDelta is recovery alone.
local function recoveryScenario(id, recovery)
    local measured = {
        treadmillBlock("sprint", 2 * 60),
        { kind = "await_runtime_tick", timeout_sec = 120 },
        { kind = "sample_once", tag = "after_drain", baseline = true },
    }
    if recovery == "walk" then
        measured[#measured + 1] = treadmillBlock("walk", 5 * 60)
    else
        measured[#measured + 1] = { kind = "wait_window", requested_sec = 5 * 60, runtime_aligned = true }
    end
    measured[#measured + 1] = { kind = "sample_once", tag = "after_recovery" }
    return scenario(id, "baseline_neutral", measured, { movement_uptime_min = 0.25 })
end

local SCENARIOS = {}
local function add(def)
    SCENARIOS[def.id] = def
end

add(treadmillScenario("treadmill_walk", "walk", 6 * 60))
add(treadmillScenario("treadmill_run", "run", 6 * 60))
add(treadmillScenario("treadmill_sprint", "sprint", 2 * 60))
for _, weather in ipairs({ "hot", "cold", "cold_nowind" }) do
    add(treadmillScenario("treadmill_walk_" .. weather, "walk", 6 * 60, "thermal_" .. weather))
    add(treadmillScenario("treadmill_run_" .. weather, "run", 6 * 60, "thermal_" .. weather))
end
add(breathingScenario("breathing_walk", "walk", 6 * 60))
add(breathingScenario("breathing_run", "run", 6 * 60))
add(breathingScenario("breathing_sprint", "sprint", 2 * 60))
add(thermalTransientScenario("thermal_transient_run_60s", 60))
add(thermalTransientScenario("thermal_transient_run_180s", 180))
add(thermalTransientScenario("thermal_transient_run_360s", 360))
add(recoveryScenario("recovery_stand", "stand"))
add(recoveryScenario("recovery_walk", "walk"))
add(scenario("combat_air", "baseline_neutral", {
    -- Completes on swing count; the timeout only catches a stuck driver. The
    -- tick ledger and the per-frame strain gain are speed-invariant, but swing
    -- detection needs several frames per swing, so combat stays at 8x.
    { kind = "run_activity", mode = "native_combat_air", requested_swings = 12, timeout_sec = 1200, speed_req = 8, sterile_radius = 8.0, expected_hit_events = 0, combat_stand_still = true },
    { kind = "sample_once", tag = "after" },
}, { align = false }))
add(scenario("sleep_neutral", "baseline_neutral", {
    { kind = "run_activity", mode = "real_sleep", requested_sec = 16 * 60 * 60, hours = 16, fatigue_wake_threshold = 0.02, temp_c = 37.0, wetness_pct = 0.0, mid_activity_samples = true, mid_activity_every_sec = 10 * 60 },
    { kind = "sample_once", tag = "after" },
}, { fatigue = 0.8, align = false }))

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
