ArmorMakesSense = ArmorMakesSense or {}

local okMpCompat, mpCompatOrErr = pcall(require, "ArmorMakesSense_MPCompat")
if not okMpCompat then
    print("[ArmorMakesSense][MP][DIAG][CLIENT][ERROR] optional require failed: ArmorMakesSense_MPCompat :: " .. tostring(mpCompatOrErr))
    return
end

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or ArmorMakesSense.MP
if type(MP) ~= "table" then
    print("[ArmorMakesSense][MP][DIAG][CLIENT][ERROR] MP compat constants unavailable; diagnostics disabled")
    return
end

local lastDiagDump = nil
local sleepTrace = {}

local function log(message)
    print("[ArmorMakesSense][MP][DIAG][CLIENT] " .. tostring(message))
end

local function safeCall(target, methodName, ...)
    if not target then
        return nil
    end
    local fn = target[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, target, ...)
    if not ok then
        return nil
    end
    return result
end

local function getWorldAgeMinutes()
    if type(getGameTime) ~= "function" then
        return 0
    end
    local gameTime = getGameTime()
    local worldAgeHours = tonumber(gameTime and gameTime:getWorldAgeHours() or nil)
    if worldAgeHours == nil then
        return 0
    end
    return worldAgeHours * 60.0
end

local function getTimeOfDay()
    if type(getGameTime) ~= "function" then
        return 0
    end
    local gameTime = getGameTime()
    return tonumber(gameTime and safeCall(gameTime, "getTimeOfDay") or nil) or 0
end

local function getTimeMultiplier()
    if type(getGameTime) ~= "function" then
        return 1
    end
    local gameTime = getGameTime()
    return tonumber(gameTime and safeCall(gameTime, "getMultiplier") or nil) or 1
end

local function canSendRequest(playerObj)
    if not playerObj then
        return false
    end
    if type(isClient) == "function" and not isClient() then
        return false
    end
    if type(sendClientCommand) ~= "function" then
        return false
    end
    if GameClient and GameClient.ingame ~= nil and GameClient.ingame ~= true then
        return false
    end
    if type(playerObj.isLocalPlayer) == "function" and not playerObj:isLocalPlayer() then
        return false
    end
    return true
end

local function getLocalPlayer()
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, playerObj = pcall(getPlayer)
    if not ok then
        return nil
    end
    return playerObj
end

local function getFatigue(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end
    local fatigue = tonumber(safeCall(stats, "getFatigue"))
    if fatigue ~= nil then
        return fatigue
    end
    if CharacterStat and CharacterStat.FATIGUE then
        return tonumber(safeCall(stats, "get", CharacterStat.FATIGUE))
    end
    return nil
end

local function getForceWakeUpTime(playerObj)
    return tonumber(safeCall(playerObj, "getForceWakeUpTime"))
end

local function getAsleepTime(playerObj)
    return tonumber(safeCall(playerObj, "getAsleepTime"))
end

local function computeHoursUntilWake(timeOfDay, wakeHour)
    local now = tonumber(timeOfDay)
    local wake = tonumber(wakeHour)
    if now == nil or wake == nil then
        return nil
    end
    local delta = wake - now
    if delta < 0 then
        delta = delta + 24.0
    end
    return delta
end

local function getMovementFlags(playerObj)
    return {
        moving = safeCall(playerObj, "isMoving") == true,
        playerMoving = safeCall(playerObj, "isPlayerMoving") == true,
        running = safeCall(playerObj, "isRunning") == true,
        sprinting = safeCall(playerObj, "isSprinting") == true,
        aiming = safeCall(playerObj, "isAiming") == true,
        attackStarted = safeCall(playerObj, "isAttackStarted") == true,
    }
end

local function sendSleepWakeDiagnostic(playerObj, payload)
    if not canSendRequest(playerObj) then
        log("sleep wake diag blocked (not ready)")
        return false
    end

    local ok, err = pcall(
        sendClientCommand,
        tostring(MP.NET_MODULE),
        tostring(MP.SLEEP_WAKE_DIAG_COMMAND),
        payload
    )
    if not ok then
        log("sleep wake diag failed: " .. tostring(err))
        return false
    end

    log(string.format(
        "[SLEEP_WAKE_DIAG] side=client sent tod=%.2f world=%.2f fat=%.3f wake=%s until=%s asleepTime=%s mult=%.2f moving=%s playerMoving=%s running=%s sprinting=%s aiming=%s attack=%s",
        tonumber(payload.tod) or -1,
        tonumber(payload.world) or -1,
        tonumber(payload.fat) or -1,
        payload.wake ~= nil and string.format("%.2f", tonumber(payload.wake) or -1) or "nil",
        payload.wakeUntil ~= nil and string.format("%.2f", tonumber(payload.wakeUntil) or -1) or "nil",
        payload.asleepTime ~= nil and string.format("%.2f", tonumber(payload.asleepTime) or -1) or "nil",
        tonumber(payload.mult) or -1,
        tostring(payload.moving == true),
        tostring(payload.playerMoving == true),
        tostring(payload.running == true),
        tostring(payload.sprinting == true),
        tostring(payload.aiming == true),
        tostring(payload.attack == true)
    ))
    return true
end

local function emitSleepDiagnostics()
    local playerObj = getLocalPlayer()
    if not playerObj then
        return
    end

    local worldMinute = tonumber(getWorldAgeMinutes()) or 0
    local minuteKey = math.floor(worldMinute)
    local timeOfDay = tonumber(getTimeOfDay()) or 0
    local sleeping = safeCall(playerObj, "isAsleep") == true
    local forceWake = getForceWakeUpTime(playerObj)
    local hoursUntilWake = computeHoursUntilWake(timeOfDay, forceWake)
    local asleepTime = getAsleepTime(playerObj)
    local fatigue = tonumber(getFatigue(playerObj)) or -1
    local multiplier = tonumber(getTimeMultiplier()) or 1
    local flags = getMovementFlags(playerObj)

    if sleepTrace.lastSleeping == nil or sleepTrace.lastSleeping ~= sleeping then
        log(string.format(
            "[SLEEP] side=client transition=%s tod=%.2f world=%.2f fat=%.3f wake=%s until=%s asleepTime=%s mult=%.2f moving=%s playerMoving=%s running=%s sprinting=%s aiming=%s attack=%s",
            sleeping and "start" or "end",
            timeOfDay,
            worldMinute,
            fatigue,
            forceWake ~= nil and string.format("%.2f", forceWake) or "nil",
            hoursUntilWake ~= nil and string.format("%.2f", hoursUntilWake) or "nil",
            asleepTime ~= nil and string.format("%.2f", asleepTime) or "nil",
            multiplier,
            tostring(flags.moving),
            tostring(flags.playerMoving),
            tostring(flags.running),
            tostring(flags.sprinting),
            tostring(flags.aiming),
            tostring(flags.attackStarted)
        ))

        if not sleeping then
            sendSleepWakeDiagnostic(playerObj, {
                tod = timeOfDay,
                world = worldMinute,
                fat = fatigue,
                wake = forceWake,
                wakeUntil = hoursUntilWake,
                asleepTime = asleepTime,
                mult = multiplier,
                moving = flags.moving,
                playerMoving = flags.playerMoving,
                running = flags.running,
                sprinting = flags.sprinting,
                aiming = flags.aiming,
                attack = flags.attackStarted,
                script_version = tostring(MP.SCRIPT_VERSION),
                script_build = tostring(MP.SCRIPT_BUILD),
            })
        end
    end

    if (not sleeping) and multiplier > 1.05 and sleepTrace.lastAwakeFastMinute ~= minuteKey then
        sleepTrace.lastAwakeFastMinute = minuteKey
        log(string.format(
            "[SLEEP_ANOM] side=client kind=awake_fast_time tod=%.2f world=%.2f fat=%.3f wake=%s until=%s asleepTime=%s mult=%.2f moving=%s playerMoving=%s running=%s sprinting=%s aiming=%s attack=%s",
            timeOfDay,
            worldMinute,
            fatigue,
            forceWake ~= nil and string.format("%.2f", forceWake) or "nil",
            hoursUntilWake ~= nil and string.format("%.2f", hoursUntilWake) or "nil",
            asleepTime ~= nil and string.format("%.2f", asleepTime) or "nil",
            multiplier,
            tostring(flags.moving),
            tostring(flags.playerMoving),
            tostring(flags.running),
            tostring(flags.sprinting),
            tostring(flags.aiming),
            tostring(flags.attackStarted)
        ))
    end

    if sleepTrace.lastFatigue ~= nil
        and (not sleeping)
        and fatigue < (sleepTrace.lastFatigue - 0.002)
        and sleepTrace.lastAwakeDecayMinute ~= minuteKey then
        sleepTrace.lastAwakeDecayMinute = minuteKey
        log(string.format(
            "[SLEEP_ANOM] side=client kind=awake_fatigue_drop tod=%.2f world=%.2f fat_now=%.3f fat_prev=%.3f wake=%s until=%s asleepTime=%s mult=%.2f",
            timeOfDay,
            worldMinute,
            fatigue,
            tonumber(sleepTrace.lastFatigue) or -1,
            forceWake ~= nil and string.format("%.2f", forceWake) or "nil",
            hoursUntilWake ~= nil and string.format("%.2f", hoursUntilWake) or "nil",
            asleepTime ~= nil and string.format("%.2f", asleepTime) or "nil",
            multiplier
        ))
    end

    sleepTrace.lastSleeping = sleeping
    sleepTrace.lastFatigue = fatigue
    sleepTrace.lastForceWake = forceWake
    sleepTrace.lastWorldMinute = worldMinute
end

function ams_mp_diag_dump(reason)
    local playerObj = getLocalPlayer()
    if not canSendRequest(playerObj) then
        log("diag dump request blocked (not ready)")
        return false
    end

    local args = {
        reason = tostring(reason or "manual"),
        world_minute = math.floor(getWorldAgeMinutes()),
        script_version = tostring(MP.SCRIPT_VERSION),
        script_build = tostring(MP.SCRIPT_BUILD),
    }

    local ok, err = pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.DIAG_DUMP_REQUEST_COMMAND), args)
    if not ok then
        log("diag dump request failed: " .. tostring(err))
        return false
    end

    log("diag dump requested reason=" .. tostring(args.reason))
    return true
end

function ams_mp_diag_last()
    if type(lastDiagDump) ~= "table" then
        log("diag last: none")
        return nil
    end
    log(string.format(
        "diag last: user=%s id=%s reason=%s version=%s build=%s end=%.3f fat=%.3f thirst=%.3f loadNorm=%.3f physical=%.2f breathing=%.2f rigidity=%.2f eff=%.2f bcontrib=%.4f tcontrib=%.4f drivers=%d items=%d breathing_items=%d activity=%s hot=%s cold=%s",
        tostring(lastDiagDump.player or "unknown"),
        tostring(lastDiagDump.online_id or -1),
        tostring(lastDiagDump.reason or "na"),
        tostring(lastDiagDump.script_version or "unknown"),
        tostring(lastDiagDump.script_build or "unknown"),
        tonumber(lastDiagDump.endurance) or -1,
        tonumber(lastDiagDump.fatigue) or -1,
        tonumber(lastDiagDump.thirst) or -1,
        tonumber(lastDiagDump.load_norm) or 0,
        tonumber(lastDiagDump.physical_load) or 0,
        tonumber(lastDiagDump.breathing_load) or 0,
        tonumber(lastDiagDump.rigidity_load) or 0,
        tonumber(lastDiagDump.effective_load) or 0,
        tonumber(lastDiagDump.breathing_contribution) or 0,
        tonumber(lastDiagDump.thermal_contribution) or 0,
        #(lastDiagDump.drivers or {}),
        tonumber(lastDiagDump.items_count) or 0,
        tonumber(lastDiagDump.breathing_item_count) or 0,
        tostring(lastDiagDump.activity_label or "idle"),
        tostring(lastDiagDump.thermal_hot == true),
        tostring(lastDiagDump.thermal_cold == true)
    ))
    return lastDiagDump
end

local function onServerCommand(module, command, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.DIAG_DUMP_COMMAND) then
        return
    end

    if type(args) ~= "table" then
        return
    end

    lastDiagDump = args
    log(string.format(
        "diag dump recv user=%s id=%s reason=%s version=%s build=%s end=%.3f fat=%.3f thirst=%.3f loadNorm=%.3f physical=%.2f breathing=%.2f rigidity=%.2f eff=%.2f bcontrib=%.4f tcontrib=%.4f drivers=%d items=%d breathing_items=%d activity=%s hot=%s cold=%s",
        tostring(args.player or "unknown"),
        tostring(args.online_id or -1),
        tostring(args.reason or "na"),
        tostring(args.script_version or "unknown"),
        tostring(args.script_build or "unknown"),
        tonumber(args.endurance) or -1,
        tonumber(args.fatigue) or -1,
        tonumber(args.thirst) or -1,
        tonumber(args.load_norm) or 0,
        tonumber(args.physical_load) or 0,
        tonumber(args.breathing_load) or 0,
        tonumber(args.rigidity_load) or 0,
        tonumber(args.effective_load) or 0,
        tonumber(args.breathing_contribution) or 0,
        tonumber(args.thermal_contribution) or 0,
        #(args.drivers or {}),
        tonumber(args.items_count) or 0,
        tonumber(args.breathing_item_count) or 0,
        tostring(args.activity_label or "idle"),
        tostring(args.thermal_hot == true),
        tostring(args.thermal_cold == true)
    ))
end

local function registerEvents()
    if ArmorMakesSense._mpDiagnosticsClientRegistered then
        return
    end
    ArmorMakesSense._mpDiagnosticsClientRegistered = true

    if Events and Events.OnServerCommand and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(onServerCommand)
    else
        log("OnServerCommand.Add unavailable; diagnostics receive inactive")
    end

    if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(emitSleepDiagnostics)
    else
        log("OnPlayerUpdate.Add unavailable; sleep diagnostics inactive")
    end
end

registerEvents()
log("diagnostics module active")
