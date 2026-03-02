ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunnerRuntime = Testing.BenchRunnerRuntime or {}

local BenchRunnerRuntime = Testing.BenchRunnerRuntime
local BenchUtils = Testing.BenchUtils
local CoreUtils = ArmorMakesSense and ArmorMakesSense.Utils
local C = {}

local RUNTIME_PENDING_BY_RUNID = {}
local RUNTIME_BENCH_RUNNER_BY_RUNID = {}

local NATIVE_TICK_ACTIVE = false
local NATIVE_TICK_PLAYER = nil
local NATIVE_TICK_DRIVER = nil

-- -----------------------------------------------------------------------------
-- Context wiring and safe-call helper
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function BenchRunnerRuntime.setContext(context)
    C = context or {}
end

-- Runtime keeps its own safeMethod with error logging (not just silent nil return).
local function safeMethod(target, methodName, ...)
    local fn = ctx("safeMethod")
    if type(fn) == "function" then return fn(target, methodName, ...) end
    if CoreUtils and type(CoreUtils.safeMethodWithOptions) == "function" then
        return CoreUtils.safeMethodWithOptions(target, methodName, {
            onError = function(failedMethod, failedTarget, failure)
                local log = ctx("log")
                if type(log) == "function" then
                    log(string.format("[BENCH_RUNTIME][WARN] safeMethod failed method=%s target=%s err=%s",
                        tostring(failedMethod), tostring(failedTarget), tostring(failure)))
                end
            end,
        }, ...)
    end
    return BenchUtils.safeMethod(target, methodName, ...)
end

local function nowMinutes()
    return BenchUtils.nowMinutes(ctx)
end

function BenchRunnerRuntime.runtimeRunKey(value)
    if type(value) == "table" then
        if value.id ~= nil then
            return tostring(value.id)
        end
        if value.runId ~= nil then
            return tostring(value.runId)
        end
    elseif value ~= nil then
        return tostring(value)
    end
    return nil
end

function BenchRunnerRuntime.getRuntimePending(value)
    local key = BenchRunnerRuntime.runtimeRunKey(value)
    return key and RUNTIME_PENDING_BY_RUNID[key] or nil
end

function BenchRunnerRuntime.setRuntimePending(value, exec)
    local key = BenchRunnerRuntime.runtimeRunKey(value)
    if not key then
        return
    end
    if exec == nil then
        RUNTIME_PENDING_BY_RUNID[key] = nil
    else
        RUNTIME_PENDING_BY_RUNID[key] = exec
    end
end

function BenchRunnerRuntime.getRuntimeBenchRunner(value)
    local key = BenchRunnerRuntime.runtimeRunKey(value)
    return key and RUNTIME_BENCH_RUNNER_BY_RUNID[key] or nil
end

function BenchRunnerRuntime.setRuntimeBenchRunner(value, runner)
    local key = BenchRunnerRuntime.runtimeRunKey(value)
    if not key then
        return
    end
    if runner == nil then
        RUNTIME_BENCH_RUNNER_BY_RUNID[key] = nil
    else
        RUNTIME_BENCH_RUNNER_BY_RUNID[key] = runner
    end
end

-- -----------------------------------------------------------------------------
-- Runtime state synchronization and native tick pump
-- -----------------------------------------------------------------------------

function BenchRunnerRuntime.getAnyActiveRuntimeBenchRunner()
    for _, runner in pairs(RUNTIME_BENCH_RUNNER_BY_RUNID) do
        if type(runner) == "table" and runner.active == true then
            return runner
        end
    end
    return nil
end

function BenchRunnerRuntime.syncStateBenchRunnerHandle(state, runner)
    if type(state) ~= "table" then
        return
    end
    if type(runner) ~= "table" or runner.active ~= true then
        state.benchRunner = nil
        return
    end
    state.benchRunner = {
        active = true,
        id = tostring(runner.id or ""),
        preset = tostring(runner.preset or ""),
        label = tostring(runner.label or ""),
        mode = tostring(runner.mode or "lab"),
        speedReq = tonumber(runner.speedReq) or 0,
        startedAt = tonumber(runner.startedAt) or nowMinutes(),
        index = math.max(0, math.floor(tonumber(runner.index) or 0)),
        total = math.max(0, math.floor(tonumber(runner.total) or 0)),
        repeats = math.max(1, math.floor(tonumber(runner.repeats) or 1)),
        scriptVersion = tostring(runner.scriptVersion or "0.0.0"),
        scriptBuild = tostring(runner.scriptBuild or "na"),
    }
end

function BenchRunnerRuntime.nativeOnTickPump()
    if not NATIVE_TICK_ACTIVE then return end
    local player = NATIVE_TICK_PLAYER
    local driver = NATIVE_TICK_DRIVER
    if not player or not driver then return end
    if not driver.waypoints or #driver.waypoints == 0 then return end

    local target = driver.waypoints[driver.waypointIndex]
    if not target then return end

    local activity = tostring(driver.activity or "walk")
    if activity == "sprint" then
        safeMethod(player, "setSprinting", true)
        safeMethod(player, "setRunning", false)
    elseif activity == "run" then
        safeMethod(player, "setSprinting", false)
        safeMethod(player, "setRunning", true)
    else
        safeMethod(player, "setSprinting", false)
        safeMethod(player, "setRunning", false)
    end

    safeMethod(player, "setIsAiming", false)
    safeMethod(player, "faceLocationF", tonumber(target.x) or 0, tonumber(target.y) or 0)
end

function BenchRunnerRuntime.registerNativeTickPump(player, driver)
    if NATIVE_TICK_ACTIVE then
        return
    end
    NATIVE_TICK_PLAYER = player
    NATIVE_TICK_DRIVER = driver
    NATIVE_TICK_ACTIVE = true
    if Events and Events.OnTick and type(Events.OnTick.Add) == "function" then
        pcall(Events.OnTick.Add, BenchRunnerRuntime.nativeOnTickPump)
    end
end

function BenchRunnerRuntime.unregisterNativeTickPump()
    if not NATIVE_TICK_ACTIVE then
        return
    end
    NATIVE_TICK_ACTIVE = false
    NATIVE_TICK_PLAYER = nil
    NATIVE_TICK_DRIVER = nil
    if Events and Events.OnTick and type(Events.OnTick.Remove) == "function" then
        pcall(Events.OnTick.Remove, BenchRunnerRuntime.nativeOnTickPump)
    end
end

return BenchRunnerRuntime
