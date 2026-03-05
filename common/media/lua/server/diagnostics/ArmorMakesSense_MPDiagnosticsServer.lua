ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local okMpCompat, mpCompatOrErr = pcall(require, "ArmorMakesSense_MPCompat")
if not okMpCompat then
    print("[ArmorMakesSense][MP][DIAG][SERVER][ERROR] optional require failed: ArmorMakesSense_MPCompat :: " .. tostring(mpCompatOrErr))
    return
end

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or ArmorMakesSense.MP
if type(MP) ~= "table" then
    print("[ArmorMakesSense][MP][DIAG][SERVER][ERROR] MP compat constants unavailable; diagnostics disabled")
    return
end

local function diagnosticsEnabled()
    if MP and MP.DEV_DIAGNOSTICS_ENABLED == true then
        return true
    end
    if _G.ams_enable_mp_diagnostics == true then
        return true
    end
    if type(isDebugEnabled) == "function" then
        local okDebug, enabled = pcall(isDebugEnabled)
        if okDebug and enabled == true then
            return true
        end
    end
    return false
end

local function minuteSummaryEnabled()
    if MP and MP.DEV_DIAG_MINUTE_SUMMARY_ENABLED == true then
        return true
    end
    if _G.ams_enable_mp_diag_minute_summary == true then
        return true
    end
    return false
end

if not diagnosticsEnabled() then
    return
end

local STATE_KEY = tostring(MP.MOD_STATE_KEY or "ArmorMakesSenseState")

local function log(message)
    print("[ArmorMakesSense][MP][DIAG][SERVER] " .. tostring(message))
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

local function playerName(playerObj)
    if not playerObj then
        return "unknown"
    end
    local username = safeCall(playerObj, "getUsername")
    if username and tostring(username) ~= "" then
        return tostring(username)
    end
    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName and tostring(displayName) ~= "" then
        return tostring(displayName)
    end
    return "unknown"
end

local function playerOnlineID(playerObj)
    return tonumber(safeCall(playerObj, "getOnlineID")) or -1
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local worldAgeHours = tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
    if worldAgeHours == nil then
        return 0
    end
    return worldAgeHours * 60.0
end

local function readStat(playerObj, directMethod, charStat)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end
    local direct = tonumber(safeCall(stats, directMethod))
    if direct ~= nil then
        return direct
    end
    if charStat ~= nil then
        return tonumber(safeCall(stats, "get", charStat))
    end
    return nil
end

local function getEndurance(playerObj)
    return readStat(playerObj, "getEndurance", CharacterStat and CharacterStat.ENDURANCE)
end

local function getFatigue(playerObj)
    return readStat(playerObj, "getFatigue", CharacterStat and CharacterStat.FATIGUE)
end

local function getThirst(playerObj)
    return readStat(playerObj, "getThirst", CharacterStat and CharacterStat.THIRST)
end

local function getPlayerState(playerObj)
    local modData = safeCall(playerObj, "getModData")
    if type(modData) ~= "table" then
        return nil, nil
    end
    local state = modData[STATE_KEY]
    if type(state) ~= "table" then
        return nil, nil
    end
    local mpState = type(state.mpServer) == "table" and state.mpServer or nil
    return state, mpState
end

local function buildDumpPayload(playerObj, reason)
    local _, mpState = getPlayerState(playerObj)
    local snapshot = (mpState and type(mpState.runtimeSnapshot) == "table") and mpState.runtimeSnapshot or {}
    local worldMinute = tonumber(getWorldAgeMinutes()) or 0

    local payload = {
        kind = "server_dump",
        reason = tostring(reason or "manual"),
        world_minute = worldMinute,
        player = tostring(playerName(playerObj)),
        online_id = playerOnlineID(playerObj),
        endurance = tonumber(getEndurance(playerObj)) or -1,
        fatigue = tonumber(getFatigue(playerObj)) or -1,
        thirst = tonumber(getThirst(playerObj)) or -1,
        load_norm = tonumber(snapshot.loadNorm) or 0,
        physical_load = tonumber(snapshot.physicalLoad) or 0,
        thermal_load = tonumber(snapshot.thermalLoad) or 0,
        breathing_load = tonumber(snapshot.breathingLoad) or 0,
        armor_count = tonumber(snapshot.armorCount) or 0,
        activity_label = tostring(snapshot.activityLabel or "idle"),
        thermal_hot = snapshot.thermalHot == true,
        thermal_cold = snapshot.thermalCold == true,
        updated_minute = tonumber(snapshot.updatedMinute) or worldMinute,
        pending_catchup = tonumber(mpState and mpState.pendingCatchupMinutes) or 0,
        drivers = type(snapshot.drivers) == "table" and snapshot.drivers or {},
    }

    return payload
end

local function emitMinuteSummary(playerObj)
    local payload = buildDumpPayload(playerObj, "minute")
    log(string.format(
        "[MIN] user=%s id=%d end=%.3f fat=%.3f thirst=%.3f loadNorm=%.3f physical=%.2f drivers=%d activity=%s hot=%s cold=%s pending=%.3f",
        tostring(payload.player),
        tonumber(payload.online_id) or -1,
        tonumber(payload.endurance) or -1,
        tonumber(payload.fatigue) or -1,
        tonumber(payload.thirst) or -1,
        tonumber(payload.load_norm) or 0,
        tonumber(payload.physical_load) or 0,
        #(payload.drivers or {}),
        tostring(payload.activity_label or "idle"),
        tostring(payload.thermal_hot == true),
        tostring(payload.thermal_cold == true),
        tonumber(payload.pending_catchup) or 0
    ))
end

local function sendDiagDump(playerObj, reason)
    if type(sendServerCommand) ~= "function" then
        log("sendServerCommand unavailable; diag dump cannot be delivered")
        return false
    end

    local payload = buildDumpPayload(playerObj, reason)
    local ok, err = pcall(
        sendServerCommand,
        playerObj,
        tostring(MP.NET_MODULE),
        tostring(MP.DIAG_DUMP_COMMAND),
        payload
    )
    if not ok then
        log("diag dump send failed user=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(err))
        return false
    end

    log(string.format(
        "[DUMP] sent user=%s id=%d reason=%s loadNorm=%.3f physical=%.2f drivers=%d",
        tostring(payload.player),
        tonumber(payload.online_id) or -1,
        tostring(payload.reason),
        tonumber(payload.load_norm) or 0,
        tonumber(payload.physical_load) or 0,
        #(payload.drivers or {})
    ))
    return true
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.DIAG_DUMP_REQUEST_COMMAND) then
        return
    end
    sendDiagDump(playerObj, args and args.reason or "client_request")
end

local function onEveryOneMinute()
    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and safeCall(onlinePlayers, "size")) or 0
    for i = 0, count - 1 do
        local playerObj = safeCall(onlinePlayers, "get", i)
        if playerObj then
            emitMinuteSummary(playerObj)
        end
    end
end

local function registerEvents()
    if ArmorMakesSense._mpDiagnosticsServerRegistered then
        return
    end
    ArmorMakesSense._mpDiagnosticsServerRegistered = true

    if Events and Events.OnClientCommand and type(Events.OnClientCommand.Add) == "function" then
        Events.OnClientCommand.Add(onClientCommand)
    else
        log("OnClientCommand.Add unavailable; diag dump request handler inactive")
    end

    if minuteSummaryEnabled() and Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    elseif minuteSummaryEnabled() then
        log("EveryOneMinute.Add unavailable; minute diagnostics inactive")
    end
end

registerEvents()
log("diagnostics module active")
