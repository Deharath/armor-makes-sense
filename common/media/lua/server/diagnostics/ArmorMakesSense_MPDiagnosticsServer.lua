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

local okLoadModel, loadModelOrErr = pcall(require, "ArmorMakesSense_LoadModelShared")
local LoadModel = okLoadModel and type(loadModelOrErr) == "table" and loadModelOrErr or nil

local function diagnosticsEnabled()
    return true
end

local function minuteSummaryEnabled()
    return true
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

local function getItemFullType(item)
    local fullType = tostring(safeCall(item, "getFullType") or "")
    if fullType ~= "" then
        return fullType
    end

    local scriptItem = safeCall(item, "getScriptItem")
    fullType = tostring(safeCall(scriptItem, "getFullName") or "")
    if fullType ~= "" then
        return fullType
    end

    local moduleName = tostring(safeCall(scriptItem, "getModuleName") or "")
    local typeName = tostring(safeCall(scriptItem, "getName") or safeCall(item, "getType") or "unknown")
    if moduleName ~= "" and typeName ~= "" then
        return moduleName .. "." .. typeName
    end
    return typeName
end

local function collectDetailedItems(playerObj)
    local rows = {}
    if not LoadModel or type(LoadModel.itemToArmorSignal) ~= "function" then
        return rows
    end

    local wornItems = safeCall(playerObj, "getWornItems")
    local count = tonumber(wornItems and safeCall(wornItems, "size")) or 0
    for i = 0, count - 1 do
        local worn = safeCall(wornItems, "get", i)
        local item = safeCall(worn, "getItem")
        if item then
            local wornLocation = tostring(safeCall(worn, "getLocation") or "")
            local bodyLocation = tostring(safeCall(item, "getBodyLocation") or "")
            local signal = LoadModel.itemToArmorSignal(item, wornLocation)
            if type(signal) == "table" then
                local reasons = type(signal.breathingReasons) == "table" and signal.breathingReasons or {}
                local row = {
                    idx = #rows + 1,
                    name = tostring(safeCall(item, "getDisplayName") or safeCall(item, "getName") or "Unknown Item"),
                    type = tostring(getItemFullType(item)),
                    worn = wornLocation,
                    body = bodyLocation,
                    phy = tonumber(signal.physicalLoad) or 0,
                    thm = tonumber(signal.thermalLoad) or 0,
                    br = tonumber(signal.breathingLoad) or 0,
                    rig = tonumber(signal.rigidityLoad) or 0,
                    br_class = tostring(signal.breathingClass or "none"),
                    br_filter = signal.breathingHasFilter == true and "filter" or (signal.breathingHasFilter == false and "nofilter" or "na"),
                    br_slot = tostring(reasons.slotClass or ""),
                    br_tag = tostring(reasons.tagClass or ""),
                    br_kw = tostring(reasons.keywordClass or ""),
                }
                rows[#rows + 1] = row
            end
        end
    end

    table.sort(rows, function(a, b)
        local aScore = math.max(a.phy or 0, a.br or 0, a.thm or 0, a.rig or 0)
        local bScore = math.max(b.phy or 0, b.br or 0, b.thm or 0, b.rig or 0)
        if aScore == bScore then
            return tostring(a.name) < tostring(b.name)
        end
        return aScore > bScore
    end)

    for i = 1, #rows do
        rows[i].idx = i
    end
    return rows
end

local function countBreathingItems(items)
    local n = 0
    for i = 1, #items do
        if (tonumber(items[i].br) or 0) > 0 then
            n = n + 1
        end
    end
    return n
end

local function buildDumpPayload(playerObj, reason)
    local _, mpState = getPlayerState(playerObj)
    local snapshot = (mpState and type(mpState.runtimeSnapshot) == "table") and mpState.runtimeSnapshot or {}
    local uiSnapshot = (mpState and type(mpState.uiRuntimeSnapshot) == "table") and mpState.uiRuntimeSnapshot or {}
    local worldMinute = tonumber(getWorldAgeMinutes()) or 0
    local detailedItems = collectDetailedItems(playerObj)
    local breathingItems = countBreathingItems(detailedItems)

    local payload = {
        kind = "server_dump",
        reason = tostring(reason or "manual"),
        script_version = tostring(MP.SCRIPT_VERSION or "unknown"),
        script_build = tostring(MP.SCRIPT_BUILD or "unknown"),
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
        rigidity_load = tonumber(snapshot.rigidityLoad) or 0,
        armor_count = tonumber(snapshot.armorCount) or 0,
        effective_load = tonumber(snapshot.effectiveLoad) or 0,
        breathing_contribution = tonumber(uiSnapshot.breathingContribution) or 0,
        thermal_contribution = tonumber(uiSnapshot.thermalContribution) or 0,
        thermal_pressure_scale = tonumber(uiSnapshot.thermalPressureScale) or 0,
        endurance_env_factor = tonumber(uiSnapshot.enduranceEnvFactor) or 1,
        endurance_before_ams = tonumber(uiSnapshot.enduranceBeforeAms),
        endurance_after_ams = tonumber(uiSnapshot.enduranceAfterAms),
        endurance_natural_delta = tonumber(uiSnapshot.enduranceNaturalDelta),
        endurance_applied_delta = tonumber(uiSnapshot.enduranceAppliedDelta),
        activity_label = tostring(snapshot.activityLabel or "idle"),
        thermal_hot = snapshot.thermalHot == true,
        thermal_cold = snapshot.thermalCold == true,
        updated_minute = tonumber(snapshot.updatedMinute) or worldMinute,
        pending_catchup = tonumber(mpState and mpState.pendingCatchupMinutes) or 0,
        drivers = type(snapshot.drivers) == "table" and snapshot.drivers or {},
        items = detailedItems,
        items_count = #detailedItems,
        breathing_item_count = breathingItems,
    }

    return payload
end

local function emitMinuteSummary(playerObj)
    local payload = buildDumpPayload(playerObj, "minute")
    log(string.format(
        "[MIN] user=%s id=%d end=%.3f fat=%.3f thirst=%.3f loadNorm=%.3f eff=%.2f physical=%.2f breathing=%.2f rigidity=%.2f envF=%.3f thermContrib=%.3f breathContrib=%.3f endBefore=%s endAfter=%s endNatD=%s endAppD=%s drivers=%d activity=%s hot=%s cold=%s pending=%.3f",
        tostring(payload.player),
        tonumber(payload.online_id) or -1,
        tonumber(payload.endurance) or -1,
        tonumber(payload.fatigue) or -1,
        tonumber(payload.thirst) or -1,
        tonumber(payload.load_norm) or 0,
        tonumber(payload.effective_load) or 0,
        tonumber(payload.physical_load) or 0,
        tonumber(payload.breathing_load) or 0,
        tonumber(payload.rigidity_load) or 0,
        tonumber(payload.endurance_env_factor) or 1,
        tonumber(payload.thermal_contribution) or 0,
        tonumber(payload.breathing_contribution) or 0,
        payload.endurance_before_ams ~= nil and string.format("%.4f", payload.endurance_before_ams) or "na",
        payload.endurance_after_ams ~= nil and string.format("%.4f", payload.endurance_after_ams) or "na",
        payload.endurance_natural_delta ~= nil and string.format("%.4f", payload.endurance_natural_delta) or "na",
        payload.endurance_applied_delta ~= nil and string.format("%.4f", payload.endurance_applied_delta) or "na",
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
        "[DUMP] sent user=%s id=%d reason=%s version=%s build=%s loadNorm=%.3f physical=%.2f breathing=%.2f rigidity=%.2f eff=%.2f bcontrib=%.4f tcontrib=%.4f envF=%.3f endBefore=%s endAfter=%s endNatD=%s endAppD=%s drivers=%d items=%d breathing_items=%d activity=%s hot=%s cold=%s",
        tostring(payload.player),
        tonumber(payload.online_id) or -1,
        tostring(payload.reason),
        tostring(payload.script_version or "unknown"),
        tostring(payload.script_build or "unknown"),
        tonumber(payload.load_norm) or 0,
        tonumber(payload.physical_load) or 0,
        tonumber(payload.breathing_load) or 0,
        tonumber(payload.rigidity_load) or 0,
        tonumber(payload.effective_load) or 0,
        tonumber(payload.breathing_contribution) or 0,
        tonumber(payload.thermal_contribution) or 0,
        tonumber(payload.endurance_env_factor) or 1,
        payload.endurance_before_ams ~= nil and string.format("%.4f", payload.endurance_before_ams) or "na",
        payload.endurance_after_ams ~= nil and string.format("%.4f", payload.endurance_after_ams) or "na",
        payload.endurance_natural_delta ~= nil and string.format("%.4f", payload.endurance_natural_delta) or "na",
        payload.endurance_applied_delta ~= nil and string.format("%.4f", payload.endurance_applied_delta) or "na",
        #(payload.drivers or {}),
        tonumber(payload.items_count) or 0,
        tonumber(payload.breathing_item_count) or 0,
        tostring(payload.activity_label or "idle"),
        tostring(payload.thermal_hot == true),
        tostring(payload.thermal_cold == true)
    ))
    local items = type(payload.items) == "table" and payload.items or {}
    local maxRows = math.min(#items, 24)
    for i = 1, maxRows do
        local row = items[i]
        if type(row) == "table" then
            log(string.format(
                "[DUMP_ITEM] reason=%s id=%d idx=%d type=%s worn=%s body=%s phy=%.2f thm=%.2f br=%.2f rig=%.2f class=%s filter=%s slot=%s tag=%s kw=%s name=%s",
                tostring(payload.reason),
                tonumber(payload.online_id) or -1,
                tonumber(row.idx) or i,
                tostring(row.type or "unknown"),
                tostring(row.worn or ""),
                tostring(row.body or ""),
                tonumber(row.phy) or 0,
                tonumber(row.thm) or 0,
                tonumber(row.br) or 0,
                tonumber(row.rig) or 0,
                tostring(row.br_class or "none"),
                tostring(row.br_filter or "na"),
                tostring(row.br_slot or ""),
                tostring(row.br_tag or ""),
                tostring(row.br_kw or ""),
                tostring(row.name or "Unknown Item")
            ))
        end
    end
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
