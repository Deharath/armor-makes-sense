ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.API = Testing.API or {}

local API = Testing.API
local C = {}

-- -----------------------------------------------------------------------------
-- Context wiring and availability checks
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function API.setContext(context)
    C = context or {}
end

local function ensure(name, obj, method)
    if obj and type(obj[method]) == "function" then
        return true
    end
    ctx("logError")(name .. " unavailable: module not loaded")
    return false
end

local function ensureCtxMethod(name, key, method)
    local obj = ctx(key)
    return ensure(name, obj, method), obj
end

function API.ams_test_unlock()
    if not ensure("test unlock", ctx("Commands"), "testUnlock") then
        return false
    end
    return ctx("Commands").testUnlock()
end

function API.ams_lock_env(tempC, wetnessPct, minutes)
    if not ensure("env lock", ctx("Commands"), "lockEnv") then
        return false
    end
    return ctx("Commands").lockEnv(tempC, wetnessPct, minutes)
end

function API.ams_env_now()
    if not ensure("env read", ctx("Commands"), "envNow") then
        return false
    end
    return ctx("Commands").envNow()
end

function API.ams_mark(label)
    if not ensure("mark", ctx("Commands"), "mark") then
        return false
    end
    return ctx("Commands").mark(label)
end

function API.ams_reset_equilibrium()
    if not ensure("reset equilibrium", ctx("Commands"), "resetEquilibrium") then
        return false
    end
    return ctx("Commands").resetEquilibrium()
end

function API.ams_gear_save(name)
    if not ensure("gear save", ctx("Commands"), "gearSave") then
        return false
    end
    return ctx("Commands").gearSave(name)
end

function API.ams_gear_wear(name)
    if not ensure("gear wear", ctx("Commands"), "gearWear") then
        return false
    end
    return ctx("Commands").gearWear(name, "inventory")
end

function API.ams_gear_wear_spawn(name)
    if not ensure("gear wear spawn", ctx("Commands"), "gearWear") then
        return false
    end
    return ctx("Commands").gearWear(name, "spawn")
end

function API.ams_gear_wear_virtual(name)
    if not ensure("gear wear virtual", ctx("Commands"), "gearWear") then
        return false
    end
    return ctx("Commands").gearWear(name, "virtual")
end

function API.ams_gear_clear()
    if not ensure("gear clear", ctx("Commands"), "gearClear") then
        return false
    end
    return ctx("Commands").gearClear()
end

function API.ams_gear_list()
    if not ensure("gear list", ctx("Commands"), "gearList") then
        return false
    end
    return ctx("Commands").gearList()
end

function API.ams_gear_reload_builtin(name)
    if not ensure("gear reload built-in", ctx("Commands"), "gearReloadBuiltin") then
        return false
    end
    return ctx("Commands").gearReloadBuiltin(name)
end

function API.ams_gear_dump(name)
    if not ensure("gear dump", ctx("Commands"), "gearDump") then
        return false
    end
    return ctx("Commands").gearDump(name)
end

-- -----------------------------------------------------------------------------
-- Benchmark and probe entrypoints
-- -----------------------------------------------------------------------------

function API.ams_fitness_probe()
    local ok, benches = ensureCtxMethod("fitness probe", "Benches", "fitnessProbe")
    if not ok then
        return false
    end
    return benches.fitnessProbe()
end

function API.ams_discomfort_audit()
    if not ensure("discomfort audit", ctx("Commands"), "discomfortAudit") then
        return false
    end
    return ctx("Commands").discomfortAudit()
end

function API.ams_ui_probe()
    if not ensure("ui probe", ctx("Commands"), "uiProbeCurrentGear") then
        return false
    end
    return ctx("Commands").uiProbeCurrentGear()
end

function API.ams_ui_probe_suite(id)
    if not ensure("ui probe suite", ctx("Commands"), "uiProbeSuite") then
        return false
    end
    return ctx("Commands").uiProbeSuite(id)
end

function API.ams_ui_probe_set_list(id)
    if not ensure("ui probe set list", ctx("Commands"), "uiProbeSetList") then
        return false
    end
    return ctx("Commands").uiProbeSetList(id)
end

function API.ams_ui_probe_wear_set(id, setId)
    if not ensure("ui probe wear set", ctx("Commands"), "uiProbeWearSet") then
        return false
    end
    return ctx("Commands").uiProbeWearSet(id, setId)
end

function API.ams_ui_probe_wear_set_default(setId)
    if not ensure("ui probe wear set default", ctx("Commands"), "uiProbeWearSetDefault") then
        return false
    end
    return ctx("Commands").uiProbeWearSetDefault(setId)
end

function API.ams_sleep_bench(hours, tempC, wetnessPct)
    local ok, benches = ensureCtxMethod("sleep bench", "Benches", "sleepBench")
    if not ok then
        return false
    end
    return benches.sleepBench(hours, tempC, wetnessPct)
end

function API.ams_bench_run(presetId, optsTable)
    if not ensure("bench run", ctx("Commands"), "benchRun") then
        return false
    end
    return ctx("Commands").benchRun(presetId, optsTable)
end

function API.ams_bench_status()
    if not ensure("bench status", ctx("Commands"), "benchStatus") then
        return false
    end
    return ctx("Commands").benchStatus()
end

function API.ams_bench_stop()
    if not ensure("bench stop", ctx("Commands"), "benchStop") then
        return false
    end
    return ctx("Commands").benchStop()
end

function API.ams_bench_set_list(presetId)
    if not ensure("bench set list", ctx("Commands"), "benchSetList") then
        return false
    end
    return ctx("Commands").benchSetList(presetId)
end

function API.ams_bench_scenario_list(presetId)
    if not ensure("bench scenario list", ctx("Commands"), "benchScenarioList") then
        return false
    end
    return ctx("Commands").benchScenarioList(presetId)
end

function API.ams_bench_wear_set(presetId, setId)
    if not ensure("bench wear set", ctx("Commands"), "benchWearSet") then
        return false
    end
    return ctx("Commands").benchWearSet(presetId, setId)
end

function API.bindGlobals()
    _G.ams_test_unlock = API.ams_test_unlock
    _G.ams_lock_env = API.ams_lock_env
    _G.ams_env_now = API.ams_env_now
    _G.ams_mark = API.ams_mark
    _G.ams_reset_equilibrium = API.ams_reset_equilibrium
    _G.ams_gear_save = API.ams_gear_save
    _G.ams_gear_wear = API.ams_gear_wear
    _G.ams_gear_wear_spawn = API.ams_gear_wear_spawn
    _G.ams_gear_wear_virtual = API.ams_gear_wear_virtual
    _G.ams_gear_clear = API.ams_gear_clear
    _G.ams_gear_list = API.ams_gear_list
    _G.ams_gear_reload_builtin = API.ams_gear_reload_builtin
    _G.ams_gear_dump = API.ams_gear_dump
    _G.ams_fitness_probe = API.ams_fitness_probe
    _G.ams_discomfort_audit = API.ams_discomfort_audit
    _G.ams_ui_probe = API.ams_ui_probe
    _G.ams_ui_probe_suite = API.ams_ui_probe_suite
    _G.ams_ui_probe_set_list = API.ams_ui_probe_set_list
    _G.ams_ui_probe_wear_set = API.ams_ui_probe_wear_set
    _G.ams_ui_probe_wear_set_default = API.ams_ui_probe_wear_set_default
    _G.ams_sleep_bench = API.ams_sleep_bench
    _G.ams_bench_run = API.ams_bench_run
    _G.ams_bench_status = API.ams_bench_status
    _G.ams_bench_stop = API.ams_bench_stop
    _G.ams_bench_set_list = API.ams_bench_set_list
    _G.ams_bench_scenario_list = API.ams_bench_scenario_list
    _G.ams_bench_wear_set = API.ams_bench_wear_set

    return true
end

return API
