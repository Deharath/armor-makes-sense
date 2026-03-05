ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Runtime = Core.Runtime or {}

local Runtime = Core.Runtime
local C = {}
local startupCheckedStatic = false
local startupCheckedPlayer = false

-- -----------------------------------------------------------------------------
-- Runtime lifecycle + event wiring
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

local function hasFunction(target, name)
    return target and type(target[name]) == "function"
end

function Runtime.setContext(context)
    C = context or {}
end

function Runtime.runStaticStartupChecks(options)
    if startupCheckedStatic then
        return not ctx("isRuntimeDisabled")()
    end
    startupCheckedStatic = true

    local issues = {}
    if not (Events and Events.EveryOneMinute and hasFunction(Events.EveryOneMinute, "Add")) then
        issues[#issues + 1] = "Events.EveryOneMinute.Add missing"
    end
    if not hasFunction(_G, "getPlayer") then
        issues[#issues + 1] = "global getPlayer missing"
    end
    if not (Events and Events.OnWeaponSwing and hasFunction(Events.OnWeaponSwing, "Add")) then
        ctx("logOnce")("startup_no_swing", "startup check: Events.OnWeaponSwing.Add missing (swing telemetry disabled)")
    end
    if not (Events and Events.OnPlayerUpdate and hasFunction(Events.OnPlayerUpdate, "Add")) then
        ctx("logOnce")("startup_no_player_update", "startup check: Events.OnPlayerUpdate.Add missing (discomfort clamp falls back to minute-tick)")
    end

    if #issues > 0 then
        ctx("setRuntimeDisabled")(true)
        ctx("logError")("startup check failed: " .. table.concat(issues, " | "))
        return false
    end

    return true
end

function Runtime.runPlayerStartupChecks(player)
    if startupCheckedPlayer or ctx("isRuntimeDisabled")() then
        return not ctx("isRuntimeDisabled")()
    end
    if not player then
        return true
    end

    local issues = {}
    local stats = ctx("safeMethod")(player, "getStats")
    if not stats then
        issues[#issues + 1] = "player:getStats unavailable"
    else
        local canGet = hasFunction(stats, "get")
        local canSet = hasFunction(stats, "set")

        local canReadEnd = hasFunction(stats, "getEndurance") or (CharacterStat and CharacterStat.ENDURANCE and canGet)
        local canWriteEnd = hasFunction(stats, "setEndurance") or (CharacterStat and CharacterStat.ENDURANCE and canSet)
        if not canReadEnd or not canWriteEnd then
            issues[#issues + 1] = "ENDURANCE bindings missing"
        end

        local canReadFatigue = hasFunction(stats, "getFatigue") or (CharacterStat and CharacterStat.FATIGUE and canGet)
        local canWriteFatigue = hasFunction(stats, "setFatigue") or (CharacterStat and CharacterStat.FATIGUE and canSet)
        if not canReadFatigue or not canWriteFatigue then
            issues[#issues + 1] = "FATIGUE bindings missing"
        end
    end

    if #issues > 0 then
        ctx("setRuntimeDisabled")(true)
        ctx("logError")("startup check failed: " .. table.concat(issues, " | "))
        return false
    end

    startupCheckedPlayer = true
    ctx("log")(string.format("[BOOT] startup checks passed version=%s build=%s", ctx("getLoadedModVersion")(), ctx("scriptBuild")))
    return true
end

function Runtime.enforceTestLockRealtime(player)
    if not player then
        return
    end
    local state = ctx("ensureState")(player)
    local testLock = state.testLock
    if not testLock or not testLock.mode then
        return
    end
    local nowMinutes = ctx("getWorldAgeMinutes")()
    if tonumber(testLock.untilMinute) and nowMinutes <= tonumber(testLock.untilMinute) then
        if testLock.wetness ~= nil then
            ctx("setWetness")(player, testLock.wetness)
        end
        if testLock.bodyTemp ~= nil then
            ctx("setBodyTemperature")(player, testLock.bodyTemp)
        end
    end
end

-- Single source of truth for vanilla discomfort suppression.
-- AMS supersedes vanilla discomfort completely, so keep this stat pinned at zero.
function Runtime.enforceDiscomfortInvariant(player, state, force)
    if not player then
        return
    end
    state = state or ctx("ensureState")(player)
    if type(state) ~= "table" then
        return
    end
    if type(ctx("getDiscomfort")) ~= "function" or type(ctx("setDiscomfort")) ~= "function" then
        return
    end

    local isMp = type(ctx("isMultiplayer")) == "function" and ctx("isMultiplayer")()
    if not isMp then
        local nowMinutes = tonumber(ctx("getWorldAgeMinutes")()) or 0
        local minuteNow = math.floor(nowMinutes)
        local lastMinute = tonumber(state.lastDiscomfortSuppressMinute)
        if (not force) and lastMinute ~= nil and minuteNow <= lastMinute then
            return
        end
        state.lastDiscomfortSuppressMinute = minuteNow
    end
    local discomfort = tonumber(ctx("getDiscomfort")(player)) or 0
    if discomfort > 0.0001 then
        ctx("setDiscomfort")(player, 0.0)
    end
end

function Runtime.onEveryOneMinute()
    if ctx("isRuntimeDisabled")() then
        return
    end

    if ctx("isMultiplayer")() then
        ctx("logOnce")("mp_client_read_only", "MP detected. Client gameplay mutations disabled; waiting for server-authoritative snapshots.")
        return
    end

    local player = ctx("getLocalPlayer")()
    if not player then
        return
    end

    ctx("runGuarded")("EveryOneMinute", ctx("tickPlayer"), player)
    local state = ctx("ensureState")(player)
    Runtime.enforceDiscomfortInvariant(player, state, true)
    ctx("runGuarded")("BenchRunner", ctx("tickBenchRunner"), player, state)
end

function Runtime.onPlayerUpdate(playerObj)
    if ctx("isRuntimeDisabled")() then
        return
    end

    local player = playerObj or ctx("getLocalPlayer")()
    if not player then
        return
    end

    local state = ctx("ensureState")(player)
    if ctx("isMultiplayer")() then
        Runtime.enforceDiscomfortInvariant(player, state, false)
        return
    end

    Runtime.enforceDiscomfortInvariant(player, state, false)
    ctx("runGuarded")("BenchRunner", ctx("tickBenchRunner"), player, state)

    if not ctx("isSystemEnabledCached")() then
        return
    end

    -- Sleep can advance many in-game minutes between real-time minute ticks.
    -- Run the core tick path per-frame while asleep so continuous sleep effects
    -- (e.g., fatigue counteraction) are applied during the actual sleep window.
    local sleeping = ctx("toBoolean")(ctx("safeMethod")(player, "isAsleep"))
    if sleeping then
        ctx("runGuarded")("OnPlayerUpdateSleepTick", ctx("tickPlayer"), player)
    end

    Runtime.enforceTestLockRealtime(player)
end

function Runtime.registerEvents(mod)
    local handlers = mod and mod._eventsRegisteredHandlers
    if handlers and type(handlers) == "table" then
        if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Remove) == "function" and handlers.onEveryOneMinute then
            pcall(Events.EveryOneMinute.Remove, handlers.onEveryOneMinute)
        end
        if Events and Events.OnWeaponSwing and type(Events.OnWeaponSwing.Remove) == "function" and handlers.onWeaponSwing then
            pcall(Events.OnWeaponSwing.Remove, handlers.onWeaponSwing)
        end
        if Events and Events.OnPlayerAttackFinished and type(Events.OnPlayerAttackFinished.Remove) == "function" and handlers.onPlayerAttackFinished then
            pcall(Events.OnPlayerAttackFinished.Remove, handlers.onPlayerAttackFinished)
        end
        if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Remove) == "function" and handlers.onPlayerUpdate then
            pcall(Events.OnPlayerUpdate.Remove, handlers.onPlayerUpdate)
        end
    end

    local bootOptions = ctx("getOptions")()
    ctx("setCachedEnableSystem")(true)
    ctx("setCachedDebugLogging")(ctx("toBoolean")(bootOptions.DebugLogging))
    local loadedVersion = ctx("getLoadedModVersion")()
    ctx("log")(string.format(
        "[BOOT] signature modVersion=%s scriptVersion=%s build=%s EnableSystem=%s DebugLogging=%s",
        loadedVersion,
        tostring(ctx("scriptVersion")),
        tostring(ctx("scriptBuild")),
        tostring(ctx("isSystemEnabledCached")()),
        tostring(ctx("isDebugLoggingCached")())
    ))
    ctx("log")(string.format(
        "[BOOT_MP] side=client isClient=%s isServer=%s isMultiplayer=%s ingame=%s scriptVersion=%s build=%s",
        tostring(ctx("isClientSide") and ctx("isClientSide")() or false),
        tostring(ctx("isServerSide") and ctx("isServerSide")() or false),
        tostring(ctx("isMultiplayer")()),
        tostring(GameClient and GameClient.ingame or false),
        tostring(ctx("scriptVersion")),
        tostring(ctx("scriptBuild"))
    ))

    Runtime.runStaticStartupChecks(bootOptions)
    if ctx("isRuntimeDisabled")() then
        ctx("logErrorOnce")("boot_disabled", "runtime disabled by startup checks; event registration skipped")
        return false
    end
    if not Events then
        ctx("setRuntimeDisabled")(true)
        ctx("logError")("Events table unavailable during boot; event registration skipped")
        return false
    end

    if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(ctx("onEveryOneMinute"))
    else
        ctx("setRuntimeDisabled")(true)
        ctx("logError")("Events.EveryOneMinute.Add unavailable during boot; runtime disabled")
        return false
    end
    if Events.OnWeaponSwing and type(Events.OnWeaponSwing.Add) == "function" then
        Events.OnWeaponSwing.Add(ctx("onWeaponSwing"))
    else
        ctx("logOnce")("no_swing_event", "OnWeaponSwing event not available on this build.")
    end
    if Events.OnPlayerAttackFinished and type(Events.OnPlayerAttackFinished.Add) == "function" then
        Events.OnPlayerAttackFinished.Add(ctx("onPlayerAttackFinished"))
    else
        ctx("logOnce")("no_attack_finished_event", "OnPlayerAttackFinished event not available; armor strain overlay disabled.")
    end
    if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(ctx("onPlayerUpdate"))
        ctx("logOnce")("per_frame_hooks_on", "OnPlayerUpdate hook enabled for realtime test-lock + minute-throttled discomfort clamp.")
    else
        ctx("logErrorOnce")("no_player_update_hook", "OnPlayerUpdate unavailable; discomfort clamp running on minute-tick fallback.")
    end

    if mod then
        mod._eventsRegistered = true
        mod._eventsRegisteredHandlers = {
            onEveryOneMinute = ctx("onEveryOneMinute"),
            onWeaponSwing = ctx("onWeaponSwing"),
            onPlayerAttackFinished = ctx("onPlayerAttackFinished"),
            onPlayerUpdate = ctx("onPlayerUpdate"),
        }
    end
    return true
end

return Runtime
