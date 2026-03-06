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

local function diagnosticsEnabled()
    return true
end

if not diagnosticsEnabled() then
    return
end

local lastDiagDump = nil

local function log(message)
    print("[ArmorMakesSense][MP][DIAG][CLIENT] " .. tostring(message))
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
end

registerEvents()
log("diagnostics module active")
