ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local MP = require "ArmorMakesSense_MPCompat"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local BreathingClassifier = require "ArmorMakesSense_BreathingClassifier"
local Options = require "ArmorMakesSense_Options"
local RuntimeState = require "ArmorMakesSense_RuntimeState"

-- Every diagnostics line is `[TAG] key=value ...` so
-- tools/armor_makes_sense/scripts/parse_debug.py can read it generically.
-- `name=` is always last because display names contain spaces.

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

local function fmt(value, digits)
    local number = tonumber(value)
    if number == nil then
        return value == nil and "na" or tostring(value)
    end
    return string.format("%." .. tostring(digits or 3) .. "f", number)
end

local function kv(tag, fields)
    local parts = { tag }
    for i = 1, #fields do
        local field = fields[i]
        parts[#parts + 1] = field[1] .. "=" .. fmt(field[2], field[3])
    end
    return table.concat(parts, " ")
end

local function playerName(playerObj)
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
    return (tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours")) or 0) * 60.0
end

local function getTimeOfDay()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(gameTime and safeCall(gameTime, "getTimeOfDay")) or 0
end

local function readStat(playerObj, charStat)
    local stats = safeCall(playerObj, "getStats")
    if not stats or charStat == nil then
        return nil
    end
    return tonumber(safeCall(stats, "get", charStat))
end

local function getMpState(playerObj)
    local state = RuntimeState.peek(playerObj, RuntimeState.ROLE_MP_SERVER)
    if type(state) ~= "table" or type(state.mpServer) ~= "table" then
        return {}
    end
    return state.mpServer
end

local function getSnapshot(mpState)
    return type(mpState.runtimeSnapshot) == "table" and mpState.runtimeSnapshot or {}
end

local function getMovementFlags(playerObj)
    return {
        moving = safeCall(playerObj, "isMoving") == true,
        running = safeCall(playerObj, "isRunning") == true,
        sprinting = safeCall(playerObj, "isSprinting") == true,
        aiming = safeCall(playerObj, "isAiming") == true,
        attack = safeCall(playerObj, "isAttackStarted") == true,
    }
end

-- -----------------------------------------------------------------------------
-- Sleep trace: transitions and activity-while-asleep anomalies.
-- -----------------------------------------------------------------------------

local sleepTraceByPlayer = {}

local function sleepFields(playerObj, mpState)
    local snapshot = getSnapshot(mpState)
    local flags = getMovementFlags(playerObj)
    return {
        { "user", playerName(playerObj) },
        { "id", playerOnlineID(playerObj), 0 },
        { "tod", getTimeOfDay(), 2 },
        { "world", getWorldAgeMinutes(), 2 },
        { "fatigue", readStat(playerObj, CharacterStat and CharacterStat.FATIGUE), 4 },
        { "rigid_kg", snapshot.rigidKg, 2 },
        { "penalty", mpState.sleepPenaltyFraction, 4 },
        { "extra_fatigue", mpState.lastSleepExtraFatigue, 6 },
        { "moving", tostring(flags.moving) },
        { "running", tostring(flags.running) },
        { "sprinting", tostring(flags.sprinting) },
        { "aiming", tostring(flags.aiming) },
        { "attack", tostring(flags.attack) },
    }, flags
end

local function emitSleepDiagnostics(playerObj)
    local key = tostring(playerOnlineID(playerObj))
    local trace = sleepTraceByPlayer[key] or {}
    sleepTraceByPlayer[key] = trace

    local mpState = getMpState(playerObj)
    local sleeping = safeCall(playerObj, "isAsleep") == true
    local fields, flags = sleepFields(playerObj, mpState)

    if trace.lastSleeping ~= sleeping then
        table.insert(fields, 1, { "transition", sleeping and "start" or "end" })
        log(kv("[SLEEP]", fields))
        table.remove(fields, 1)
    end

    local minuteKey = math.floor(getWorldAgeMinutes())
    local activeWhileAsleep = sleeping and (flags.moving or flags.running or flags.sprinting or flags.aiming or flags.attack)
    if activeWhileAsleep and trace.lastAnomalyMinute ~= minuteKey then
        trace.lastAnomalyMinute = minuteKey
        table.insert(fields, 1, { "kind", "asleep_with_activity" })
        log(kv("[SLEEP_ANOM]", fields))
    end

    trace.lastSleeping = sleeping
end

-- -----------------------------------------------------------------------------
-- Diagnostic dump
-- -----------------------------------------------------------------------------

local function getItemFullType(item)
    local fullType = tostring(safeCall(item, "getFullType") or "")
    if fullType ~= "" then
        return fullType
    end
    return tostring(safeCall(safeCall(item, "getScriptItem"), "getFullName") or "unknown")
end

local function collectDetailedItems(playerObj, options)
    local rows = {}
    local wornItems = safeCall(playerObj, "getWornItems")
    local count = tonumber(wornItems and safeCall(wornItems, "size")) or 0
    for i = 0, count - 1 do
        local worn = safeCall(wornItems, "get", i)
        local item = safeCall(worn, "getItem")
        if item then
            local wornLocation = tostring(safeCall(worn, "getLocation") or "")
            local signal = LoadModel.itemToBurdenSignal(item, wornLocation, options)
            if type(signal) == "table" then
                local respiratory = BreathingClassifier.computeSignals(item, safeCall(item, "getScriptItem"), wornLocation)
                local reasons = type(respiratory.reasons) == "table" and respiratory.reasons or {}
                rows[#rows + 1] = {
                    name = tostring(safeCall(item, "getDisplayName") or safeCall(item, "getName") or "Unknown Item"),
                    type = getItemFullType(item),
                    worn = wornLocation,
                    burden_kg = signal.burdenKg,
                    mass_kg = signal.massKg,
                    bulk_kg = signal.bulkKg,
                    placement = signal.placement,
                    rigid_kg = signal.rigidKg,
                    rigid = signal.rigid == true,
                    airflow = signal.airflowResistance,
                    sealed = signal.sealedRestriction,
                    br_class = tostring(signal.respiratoryClass or "none"),
                    br_filter = signal.respiratoryHasFilter == true and "filter" or (signal.respiratoryHasFilter == false and "nofilter" or "na"),
                    br_slot = tostring(reasons.slotClass or ""),
                    br_tag = tostring(reasons.tagClass or ""),
                    br_kw = tostring(reasons.keywordClass or ""),
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        local left = math.max(tonumber(a.burden_kg) or 0, tonumber(a.airflow) or 0)
        local right = math.max(tonumber(b.burden_kg) or 0, tonumber(b.airflow) or 0)
        if left == right then
            return tostring(a.name) < tostring(b.name)
        end
        return left > right
    end)
    for i = 1, #rows do
        rows[i].idx = i
    end
    return rows
end

local function countBreathingItems(items)
    local n = 0
    for i = 1, #items do
        if (tonumber(items[i].airflow) or 0) > 0 then
            n = n + 1
        end
    end
    return n
end

local function buildDumpPayload(playerObj, reason)
    local mpState = getMpState(playerObj)
    local snapshot = getSnapshot(mpState)
    local items = collectDetailedItems(playerObj, Options.get())
    local payload = {
        kind = "server_dump",
        reason = tostring(reason or "manual"),
        script_version = tostring(MP.SCRIPT_VERSION),
        script_build = tostring(MP.SCRIPT_BUILD),
        world_minute = getWorldAgeMinutes(),
        player = playerName(playerObj),
        online_id = playerOnlineID(playerObj),
        endurance = readStat(playerObj, CharacterStat and CharacterStat.ENDURANCE) or -1,
        fatigue = readStat(playerObj, CharacterStat and CharacterStat.FATIGUE) or -1,
        thirst = readStat(playerObj, CharacterStat and CharacterStat.THIRST) or -1,
        sleep_extra_fatigue = tonumber(mpState.lastSleepExtraFatigue) or 0,
        drivers = type(snapshot.drivers) == "table" and snapshot.drivers or {},
        items = items,
        items_count = #items,
        breathing_item_count = countBreathingItems(items),
    }
    for key, value in pairs(snapshot) do
        if type(value) ~= "table" and payload[key] == nil then
            payload[key] = value
        end
    end
    return payload
end

local DUMP_FIELDS = {
    { "burden_kg", "burdenKg", 3 },
    { "arm_kg", "armKg", 3 },
    { "rigid_kg", "rigidKg", 3 },
    { "body_kg", "bodyKg", 1 },
    { "strength", "strength", 0 },
    { "load_fraction", "loadFraction", 5 },
    { "heat", "heat", 4 },
    { "resistance", "thermalResistance", 3 },
    { "hot_pressure", "hotPressure", 3 },
    { "cold_suitability", "coldSuitability", 3 },
    { "airflow", "airflowResistance", 3 },
    { "sealed", "sealedRestriction", 3 },
    { "breathing_severity", "breathingSeverity", 4 },
    { "breathing_pressure", "breathingPressure", 4 },
    { "regen_scale", "regenScale", 4 },
    { "drain_scale", "drainScale", 4 },
    { "natural_delta", "naturalDelta", 6 },
    { "ams_delta", "amsDelta", 6 },
    { "sleep_penalty", "sleepPenaltyFraction", 4 },
    { "sleep_extra_fatigue", "sleep_extra_fatigue", 6 },
    { "dt_minutes", "dtMinutes", 3 },
    { "updated_minute", "updatedMinute", 2 },
}

local function logDump(payload)
    local fields = {
        { "user", payload.player },
        { "id", payload.online_id, 0 },
        { "reason", payload.reason },
        { "version", payload.script_version },
        { "build", payload.script_build },
        { "endurance", payload.endurance, 4 },
        { "fatigue", payload.fatigue, 4 },
        { "thirst", payload.thirst, 4 },
    }
    for i = 1, #DUMP_FIELDS do
        local spec = DUMP_FIELDS[i]
        fields[#fields + 1] = { spec[1], payload[spec[2]], spec[3] }
    end
    fields[#fields + 1] = { "drivers", #(payload.drivers or {}), 0 }
    fields[#fields + 1] = { "items", payload.items_count, 0 }
    fields[#fields + 1] = { "breathing_items", payload.breathing_item_count, 0 }
    fields[#fields + 1] = { "activity", payload.activityLabel or "idle" }
    fields[#fields + 1] = { "posture", payload.postureLabel or "stand" }
    log(kv("[DUMP] sent", fields))

    local items = payload.items
    for i = 1, math.min(#items, 24) do
        local row = items[i]
        log(kv("[DUMP_ITEM]", {
            { "reason", payload.reason },
            { "id", payload.online_id, 0 },
            { "idx", row.idx, 0 },
            { "type", row.type },
            { "worn", row.worn },
            { "burden_kg", row.burden_kg, 3 },
            { "mass_kg", row.mass_kg, 3 },
            { "bulk_kg", row.bulk_kg, 3 },
            { "placement", row.placement, 2 },
            { "rigid_kg", row.rigid_kg, 3 },
            { "rigid", tostring(row.rigid) },
            { "airflow", row.airflow, 3 },
            { "sealed", row.sealed, 3 },
            { "class", row.br_class },
            { "filter", row.br_filter },
            { "slot", row.br_slot },
            { "tag", row.br_tag },
            { "kw", row.br_kw },
            { "name", row.name },
        }))
    end
end

local function sendDiagDump(playerObj, reason)
    local payload = buildDumpPayload(playerObj, reason)
    sendServerCommand(playerObj, tostring(MP.NET_MODULE), tostring(MP.DIAG_DUMP_COMMAND), payload)
    logDump(payload)
    return true
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) == tostring(MP.DIAG_DUMP_REQUEST_COMMAND) then
        sendDiagDump(playerObj, args and args.reason or "client_request")
    end
end

local function onEveryOneMinute()
    local onlinePlayers = getOnlinePlayers()
    local count = tonumber(onlinePlayers and onlinePlayers:size()) or 0
    for i = 0, count - 1 do
        local playerObj = onlinePlayers:get(i)
        if playerObj then
            emitSleepDiagnostics(playerObj)
        end
    end
end

local function registerEvents()
    if ArmorMakesSense._mpDiagnosticsServerRegistered then
        return
    end
    ArmorMakesSense._mpDiagnosticsServerRegistered = true
    Events.OnClientCommand.Add(onClientCommand)
    Events.EveryOneMinute.Add(onEveryOneMinute)
end

registerEvents()
log("diagnostics module active")
