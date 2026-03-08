ArmorMakesSense = ArmorMakesSense or {}

local runningOnServer = (type(isServer) == "function") and (isServer() == true)
if not runningOnServer then
    return
end

local okConfig, configErr = pcall(require, "ArmorMakesSense_Config")
if not okConfig then
    print("[ArmorMakesSense][MP][SERVER][ERROR] require failed: ArmorMakesSense_Config :: " .. tostring(configErr))
    return
end
local okMpCompat, mpCompatOrErr = pcall(require, "ArmorMakesSense_MPCompat")
if not okMpCompat then
    print("[ArmorMakesSense][MP][SERVER][ERROR] optional require failed: ArmorMakesSense_MPCompat :: " .. tostring(mpCompatOrErr))
    return
end

local MP = (type(mpCompatOrErr) == "table" and mpCompatOrErr) or ArmorMakesSense.MP
if type(MP) ~= "table" then
    print("[ArmorMakesSense][MP][SERVER][ERROR] MP compat constants unavailable; runtime disabled")
    return
end

pcall(require, "ArmorMakesSense_ArmorClassifier")
local Classifier = ArmorMakesSense and ArmorMakesSense.Classifier or nil

local okLoadModel, loadModelOrErr = pcall(require, "ArmorMakesSense_LoadModelShared")
if not okLoadModel or type(loadModelOrErr) ~= "table" then
    print("[ArmorMakesSense][MP][SERVER][ERROR] require failed: ArmorMakesSense_LoadModelShared :: " .. tostring(loadModelOrErr))
    return
end
local LoadModel = loadModelOrErr

local okEnvironment, environmentOrErr = pcall(require, "ArmorMakesSense_EnvironmentShared")
if not okEnvironment or type(environmentOrErr) ~= "table" then
    print("[ArmorMakesSense][MP][SERVER][ERROR] require failed: ArmorMakesSense_EnvironmentShared :: " .. tostring(environmentOrErr))
    return
end
local Environment = environmentOrErr

local okStrain, strainOrErr = pcall(require, "ArmorMakesSense_StrainShared")
if not okStrain or type(strainOrErr) ~= "table" then
    print("[ArmorMakesSense][MP][SERVER][ERROR] require failed: ArmorMakesSense_StrainShared :: " .. tostring(strainOrErr))
    return
end
local Strain = strainOrErr

local okPhysiology, physiologyOrErr = pcall(require, "ArmorMakesSense_PhysiologyShared")
if not okPhysiology or type(physiologyOrErr) ~= "table" then
    print("[ArmorMakesSense][MP][SERVER][ERROR] require failed: ArmorMakesSense_PhysiologyShared :: " .. tostring(physiologyOrErr))
    return
end
local Physiology = physiologyOrErr

local DEFAULTS = ArmorMakesSense.DEFAULTS or {}
local STATE_KEY = tostring(MP.MOD_STATE_KEY or "ArmorMakesSenseState")
local COST_DRIVER_THRESHOLD = 1.5
local COMBAT_LATCH_ATTACK_SECONDS = 1.25

local activeFormulaState = nil

local function log(message)
    print("[ArmorMakesSense][MP][SERVER] " .. tostring(message))
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

local function clamp(value, minimum, maximum)
    local minV = tonumber(minimum) or 0
    local maxV = tonumber(maximum) or minV
    if minV > maxV then
        minV, maxV = maxV, minV
    end

    local v = tonumber(value)
    if v == nil or v ~= v then
        return minV
    end
    if v < minV then
        return minV
    end
    if v > maxV then
        return maxV
    end
    return v
end

local function softNorm(value, pivot, maxNorm)
    local v = math.max(0, tonumber(value) or 0)
    local p = math.max(0.001, tonumber(pivot) or 1.0)
    local m = math.max(0.001, tonumber(maxNorm) or 1.0)
    local ratio = v / (v + p)
    return clamp(ratio * m, 0, m)
end

local function toBoolean(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "string" then
        local lowered = string.lower(value)
        return lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "on"
    end
    if type(value) == "number" then
        return value ~= 0
    end
    return false
end

local function lower(value)
    if value == nil then
        return ""
    end
    return string.lower(tostring(value))
end

local function containsAny(text, patterns)
    local t = lower(text)
    if t == "" or type(patterns) ~= "table" then
        return false
    end
    for i = 1, #patterns do
        if string.find(t, tostring(patterns[i]), 1, true) then
            return true
        end
    end
    return false
end

local function getWorldAgeMinutes()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local worldAgeHours = tonumber(gameTime and safeCall(gameTime, "getWorldAgeHours") or nil)
    if worldAgeHours == nil then
        return 0
    end
    return worldAgeHours * 60.0
end

local function getOptions()
    local options = {}
    for key, value in pairs(DEFAULTS) do
        options[key] = value
    end

    if SandboxVars and SandboxVars.ArmorMakesSense then
        for key, value in pairs(SandboxVars.ArmorMakesSense) do
            local defaultValue = options[key]
            if defaultValue ~= nil then
                if type(defaultValue) == "boolean" then
                    options[key] = toBoolean(value)
                elseif type(defaultValue) == "number" then
                    local parsed = tonumber(value)
                    if parsed ~= nil then
                        options[key] = parsed
                    end
                elseif type(defaultValue) == "string" then
                    options[key] = tostring(value)
                end
            end
        end
    end

    return options
end

local function playerName(playerObj)
    if not playerObj then
        return "unknown"
    end
    local username = safeCall(playerObj, "getUsername")
    if username ~= nil and tostring(username) ~= "" then
        return tostring(username)
    end
    local displayName = safeCall(playerObj, "getDisplayName")
    if displayName ~= nil and tostring(displayName) ~= "" then
        return tostring(displayName)
    end
    return "unknown"
end

local function ensurePlayerState(playerObj)
    local modData = safeCall(playerObj, "getModData")
    if type(modData) ~= "table" then
        return nil
    end

    modData[STATE_KEY] = modData[STATE_KEY] or {}
    local state = modData[STATE_KEY]
    state.version = tonumber(state.version) or 2
    state.mpServer = type(state.mpServer) == "table" and state.mpServer or {}

    local mpState = state.mpServer
    mpState.lastUpdateGameMinutes = tonumber(mpState.lastUpdateGameMinutes) or getWorldAgeMinutes()
    mpState.lastEnduranceObserved = tonumber(mpState.lastEnduranceObserved)
    mpState.wasSleeping = toBoolean(mpState.wasSleeping)
    mpState.recentCombatUntilMinute = tonumber(mpState.recentCombatUntilMinute)
    mpState.lastSnapshotSentSecond = tonumber(mpState.lastSnapshotSentSecond) or 0
    mpState.pendingCatchupMinutes = math.max(0, tonumber(mpState.pendingCatchupMinutes) or 0)
    mpState.runtimeSnapshot = type(mpState.runtimeSnapshot) == "table" and mpState.runtimeSnapshot or nil

    return state, mpState
end

local function getEndurance(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end

    local endurance = tonumber(safeCall(stats, "getEndurance"))
    if endurance ~= nil then
        return endurance
    end

    if CharacterStat and CharacterStat.ENDURANCE then
        return tonumber(safeCall(stats, "get", CharacterStat.ENDURANCE))
    end

    return nil
end

local function setEndurance(playerObj, value)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return
    end

    value = clamp(value, 0, 1)
    if type(stats.setEndurance) == "function" then
        safeCall(stats, "setEndurance", value)
        return
    end

    if CharacterStat and CharacterStat.ENDURANCE then
        safeCall(stats, "set", CharacterStat.ENDURANCE, value)
    end
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

local function setFatigue(playerObj, value)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return
    end

    value = clamp(value, 0, 1)
    if type(stats.setFatigue) == "function" then
        safeCall(stats, "setFatigue", value)
        return
    end

    if CharacterStat and CharacterStat.FATIGUE then
        safeCall(stats, "set", CharacterStat.FATIGUE, value)
    end
end

local function getWetness(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if stats and CharacterStat and CharacterStat.WETNESS then
        local wet = tonumber(safeCall(stats, "get", CharacterStat.WETNESS))
        if wet ~= nil then
            return wet
        end
    end

    local body = safeCall(playerObj, "getBodyDamage")
    if body then
        return tonumber(safeCall(body, "getWetness"))
    end

    return nil
end

local function getBodyTemperature(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        local temp = tonumber(safeCall(stats, "get", CharacterStat.TEMPERATURE))
        if temp ~= nil then
            return temp
        end
    end

    local body = safeCall(playerObj, "getBodyDamage")
    if body then
        local temp = tonumber(safeCall(body, "getTemperature"))
        if temp ~= nil then
            return temp
        end
    end

    return nil
end

local function getDiscomfort(playerObj)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return nil
    end

    local discomfort = tonumber(safeCall(stats, "getDiscomfort"))
    if discomfort ~= nil then
        return discomfort
    end

    if CharacterStat and CharacterStat.DISCOMFORT then
        return tonumber(safeCall(stats, "get", CharacterStat.DISCOMFORT))
    end

    return nil
end

local function setDiscomfort(playerObj, value)
    local stats = safeCall(playerObj, "getStats")
    if not stats then
        return
    end

    value = clamp(value, 0, 100)
    if type(stats.setDiscomfort) == "function" then
        safeCall(stats, "setDiscomfort", value)
        return
    end

    if CharacterStat and CharacterStat.DISCOMFORT then
        safeCall(stats, "set", CharacterStat.DISCOMFORT, value)
    end
end

local function enforceDiscomfortInvariant(playerObj)
    local discomfort = tonumber(getDiscomfort(playerObj)) or 0
    if discomfort > 0.0001 then
        setDiscomfort(playerObj, 0.0)
    end
end

local function getItemDisplayLabel(item)
    local displayName = tostring(safeCall(item, "getDisplayName") or safeCall(item, "getName") or "")
    if displayName ~= "" then
        return displayName
    end
    local fullType = tostring(safeCall(item, "getFullType") or "")
    if fullType ~= "" then
        return fullType
    end
    return "Unknown Item"
end

local function collectSnapshotDrivers(playerObj)
    local wornItems = safeCall(playerObj, "getWornItems")
    if not wornItems or type(LoadModel.itemToArmorSignal) ~= "function" then
        return {}
    end

    local itemCount = tonumber(safeCall(wornItems, "size")) or 0
    local drivers = {}

    for i = 0, itemCount - 1 do
        local worn = safeCall(wornItems, "get", i)
        local item = worn and safeCall(worn, "getItem")
        if item then
            local locationName = safeCall(worn, "getLocation")
            local signal = LoadModel.itemToArmorSignal(item, locationName)
            local physical = tonumber(signal and signal.physicalLoad) or 0
            if physical >= COST_DRIVER_THRESHOLD then
                drivers[#drivers + 1] = {
                    label = getItemDisplayLabel(item),
                    fullType = tostring(safeCall(item, "getFullType") or safeCall(item, "getType") or ""),
                    physical = physical,
                }
            end
        end
    end

    table.sort(drivers, function(a, b)
        return (tonumber(a and a.physical) or 0) > (tonumber(b and b.physical) or 0)
    end)

    return drivers
end

local function bindSharedContexts()
    local context = {
        Classifier = Classifier,
        armorKeywords = (Classifier and Classifier.ARMOR_KEYWORDS) or {},
        armorLocationHints = (Classifier and Classifier.ARMOR_LOCATION_HINTS) or {},
        clamp = clamp,
        computeArmorProfile = function(playerObj)
            return LoadModel.computeArmorProfile(playerObj)
        end,
        containsAny = containsAny,
        ensureState = function()
            return activeFormulaState
        end,
        getBodyTemperature = getBodyTemperature,
        getEndurance = getEndurance,
        getFatigue = getFatigue,
        getWetness = getWetness,
        getWorldAgeMinutes = getWorldAgeMinutes,
        isMultiplayer = function()
            return true
        end,
        log = log,
        lower = lower,
        markUiDirty = function()
            return
        end,
        safeMethod = safeCall,
        setEndurance = setEndurance,
        setFatigue = setFatigue,
        softNorm = softNorm,
        toBoolean = toBoolean,
    }

    if type(LoadModel.setContext) == "function" then
        LoadModel.setContext(context)
    end
    if type(Environment.setContext) == "function" then
        Environment.setContext(context)
    end
    if type(Strain.setContext) == "function" then
        Strain.setContext(context)
    end
    if type(Physiology.setContext) == "function" then
        Physiology.setContext(context)
    end
end

bindSharedContexts()

local function normalizeActivityLabel(label)
    local value = lower(label)
    if value == "sprint" or value == "run" or value == "walk" or value == "combat" or value == "idle" then
        return value
    end
    return nil
end

local function getActivityFactorForLabel(options, activityLabel)
    if activityLabel == "sprint" then
        return clamp(tonumber(options.ActivitySprint) or 1.35, 0.2, 1.8)
    end
    if activityLabel == "run" then
        return clamp(tonumber(options.ActivityJog) or 1.0, 0.2, 1.8)
    end
    if activityLabel == "walk" then
        return clamp(tonumber(options.ActivityWalk) or 0.75, 0.2, 1.8)
    end
    if activityLabel == "combat" then
        return clamp(tonumber(options.ActivityJog) or 1.0, 0.2, 1.8)
    end
    return clamp(tonumber(options.ActivityIdle) or 0.35, 0.2, 1.8)
end

local function prepareRuntimeInputs(playerObj, options)
    local profile = type(LoadModel.computeArmorProfile) == "function" and LoadModel.computeArmorProfile(playerObj) or nil
    if type(profile) ~= "table" then
        profile = {}
    end

    local drivers = collectSnapshotDrivers(playerObj)
    local heatFactor = type(Environment.getHeatFactor) == "function" and tonumber(Environment.getHeatFactor(playerObj, options)) or 1.0
    local wetFactor = type(Environment.getWetFactor) == "function" and tonumber(Environment.getWetFactor(playerObj, options)) or 1.0
    local activityLabel = normalizeActivityLabel(type(Environment.getActivityLabel) == "function" and Environment.getActivityLabel(playerObj) or "idle") or "idle"
    local activityFactor = getActivityFactorForLabel(options, activityLabel)
    local postureLabel = type(Environment.getPostureLabel) == "function" and Environment.getPostureLabel(playerObj) or "stand"

    return profile, drivers, heatFactor or 1.0, wetFactor or 1.0, activityFactor or 1.0, tostring(activityLabel or "idle"), tostring(postureLabel or "stand")
end

local function buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
    local uiSnapshot = type(mpState.uiRuntimeSnapshot) == "table" and mpState.uiRuntimeSnapshot or {}
    local hotStrain = tonumber(uiSnapshot.hotStrain) or 0
    local coldAppropriateness = tonumber(uiSnapshot.coldAppropriateness) or 0

    return {
        loadNorm = tonumber(uiSnapshot.loadNorm) or 0,
        physicalLoad = tonumber(profile.physicalLoad) or 0,
        thermalLoad = tonumber(profile.thermalLoad) or 0,
        breathingLoad = tonumber(profile.breathingLoad) or 0,
        rigidityLoad = tonumber(profile.rigidityLoad) or 0,
        armorCount = tonumber(profile.armorCount) or 0,
        effectiveLoad = tonumber(uiSnapshot.effectiveLoad) or tonumber(profile.combinedLoad) or 0,
        drivers = drivers or {},
        activityLabel = tostring(activityLabel or uiSnapshot.activityLabel or "idle"),
        thermalHot = hotStrain > 0.15,
        thermalCold = coldAppropriateness > 0.30,
        enduranceEnvFactor = tonumber(uiSnapshot.enduranceEnvFactor) or 1,
        updatedMinute = tonumber(uiSnapshot.updatedMinute) or getWorldAgeMinutes(),
    }
end

local function sendSnapshot(playerObj, snapshot, reason)
    if type(sendServerCommand) ~= "function" then
        return
    end
    if type(snapshot) ~= "table" then
        return
    end

    local args = {
        load_norm = tonumber(snapshot.loadNorm) or 0,
        physical_load = tonumber(snapshot.physicalLoad) or 0,
        thermal_load = tonumber(snapshot.thermalLoad) or 0,
        breathing_load = tonumber(snapshot.breathingLoad) or 0,
        rigidity_load = tonumber(snapshot.rigidityLoad) or 0,
        armor_count = tonumber(snapshot.armorCount) or 0,
        effective_load = tonumber(snapshot.effectiveLoad) or 0,
        activity_label = tostring(snapshot.activityLabel or "idle"),
        thermal_hot = snapshot.thermalHot == true,
        thermal_cold = snapshot.thermalCold == true,
        thermal_pressure_scale = tonumber(snapshot.thermalPressureScale) or 0,
        endurance_env_factor = tonumber(snapshot.enduranceEnvFactor) or 1,
        updated_minute = tonumber(snapshot.updatedMinute) or 0,
        reason = tostring(reason or "tick"),
    }

    local snapshotDrivers = {}
    if type(snapshot.drivers) == "table" then
        for i = 1, #snapshot.drivers do
            local row = snapshot.drivers[i]
            if type(row) == "table" then
                snapshotDrivers[#snapshotDrivers + 1] = {
                    label = tostring(row.label or "Unknown Item"),
                    full_type = tostring(row.fullType or ""),
                    physical = tonumber(row.physical) or 0,
                }
            end
        end
    end
    args.drivers = snapshotDrivers

    local ok, err = pcall(sendServerCommand, playerObj, tostring(MP.NET_MODULE), tostring(MP.SNAPSHOT_COMMAND), args)
    if not ok then
        log("snapshot send failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(err))
    end
end

local function buildFreshSnapshot(playerObj, mpState, options)
    activeFormulaState = mpState
    local okInputs, profile, drivers, heatFactor, wetFactor, activityFactor, activityLabel, postureLabel = pcall(prepareRuntimeInputs, playerObj, options)
    activeFormulaState = nil
    if not okInputs then
        log("shared model input prep failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile))
        return nil
    end
    return buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
end

local function updatePlayer(playerObj, reason)
    local _, mpState = ensurePlayerState(playerObj)
    if not mpState then
        return
    end
    enforceDiscomfortInvariant(playerObj)

    local nowMinute = tonumber(getWorldAgeMinutes()) or 0
    local lastMinute = tonumber(mpState.lastUpdateGameMinutes) or nowMinute
    local elapsed = math.max(0, nowMinute - lastMinute)
    mpState.lastUpdateGameMinutes = nowMinute
    mpState.pendingCatchupMinutes = (tonumber(mpState.pendingCatchupMinutes) or 0) + elapsed

    if mpState.pendingCatchupMinutes <= 0 then
        local normalizedReason = lower(reason)
        if normalizedReason ~= "minute" and normalizedReason ~= "tick" then
            local options = getOptions()
            local freshSnapshot = buildFreshSnapshot(playerObj, mpState, options)
            if freshSnapshot then
                mpState.runtimeSnapshot = freshSnapshot
                sendSnapshot(playerObj, freshSnapshot, reason)
                return
            end
        end
        if type(mpState.runtimeSnapshot) == "table" then
            sendSnapshot(playerObj, mpState.runtimeSnapshot, reason)
        end
        return
    end

    local options = getOptions()
    local dtCap = math.max(0.01, tonumber(options.DtMaxMinutes) or 3)
    local maxSlices = math.max(1, math.floor(tonumber(options.DtCatchupMaxSlices) or 240))
    local processed = 0
    local snapshot = nil

    activeFormulaState = mpState
    local okInputs, profile, drivers, heatFactor, wetFactor, activityFactor, activityLabel, postureLabel = pcall(prepareRuntimeInputs, playerObj, options)
    if not okInputs then
        activeFormulaState = nil
        log("shared model input prep failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(profile))
        return
    end

    while mpState.pendingCatchupMinutes > 0 and processed < maxSlices do
        local dtMinutes = clamp(mpState.pendingCatchupMinutes, 0, dtCap)
        if dtMinutes <= 0 then
            break
        end

        mpState.pendingCatchupMinutes = math.max(0, mpState.pendingCatchupMinutes - dtMinutes)
        processed = processed + 1

        local okSleep, sleepErr = pcall(Physiology.applySleepTransition, playerObj, mpState, options, dtMinutes, profile, heatFactor, wetFactor)
        if not okSleep then
            log("sleep model failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(sleepErr))
            break
        end

        local okEndurance, enduranceErr = pcall(Physiology.applyEnduranceModel,
            playerObj,
            mpState,
            options,
            dtMinutes,
            profile,
            heatFactor,
            wetFactor,
            activityFactor,
            activityLabel,
            postureLabel
        )
        if not okEndurance then
            log("endurance model failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(enduranceErr))
            break
        end

        snapshot = buildRuntimeSnapshot(mpState, profile, drivers, activityLabel)
    end
    activeFormulaState = nil

    if snapshot == nil and type(mpState.runtimeSnapshot) == "table" then
        snapshot = mpState.runtimeSnapshot
    end
    if snapshot then
        mpState.runtimeSnapshot = snapshot
        sendSnapshot(playerObj, snapshot, reason)
    end
end

local function onPlayerUpdate(playerObj)
    if not playerObj then
        return
    end
    enforceDiscomfortInvariant(playerObj)
end

local function onClientCommand(module, command, playerObj, args)
    if tostring(module) ~= tostring(MP.NET_MODULE) then
        return
    end
    if tostring(command) ~= tostring(MP.REQUEST_SNAPSHOT_COMMAND) then
        return
    end

    updatePlayer(playerObj, args and args.reason or "request")
end

local function onEveryOneMinute()
    local onlinePlayers = type(getOnlinePlayers) == "function" and getOnlinePlayers() or nil
    local count = tonumber(onlinePlayers and safeCall(onlinePlayers, "size")) or 0

    for i = 0, count - 1 do
        local playerObj = safeCall(onlinePlayers, "get", i)
        if playerObj then
            updatePlayer(playerObj, "minute")
        end
    end
end

local function onWeaponSwing(attacker, weapon)
    local playerObj = attacker
    if not playerObj or not weapon then
        return
    end

    local _, mpState = ensurePlayerState(playerObj)
    if mpState then
        mpState.recentCombatUntilMinute = (tonumber(getWorldAgeMinutes()) or 0) + (COMBAT_LATCH_ATTACK_SECONDS / 60.0)
    end

    local options = getOptions()
    if not toBoolean(options.EnableMuscleStrainModel) then
        return
    end

    local eligible = true
    if type(Strain.isMeleeStrainEligible) == "function" then
        local okEligible, eligibleOrErr = pcall(Strain.isMeleeStrainEligible, playerObj, weapon, false)
        if not okEligible then
            log("strain eligibility check failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(eligibleOrErr))
            return
        end
        eligible = toBoolean(eligibleOrErr)
    end
    if not eligible then
        return
    end

    local okProfile, profileOrErr = pcall(LoadModel.computeArmorProfile, playerObj)
    if not okProfile or type(profileOrErr) ~= "table" then
        log("strain profile compute failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(profileOrErr))
        return
    end

    local okExtra, extraOrErr = pcall(Strain.computeArmorStrainExtra, options, profileOrErr)
    if not okExtra then
        log("strain extra compute failed player=" .. tostring(playerName(playerObj)) .. " err=" .. tostring(extraOrErr))
        return
    end

    local extra = tonumber(extraOrErr) or 0
    if extra <= 0 then
        return
    end

    safeCall(playerObj, "addCombatMuscleStrain", weapon, 1, extra)
end

local function logBootBanner(contextTag)
    log(string.format(
        "[BOOT_MP] context=%s side=server isClient=%s isServer=%s scriptVersion=%s build=%s",
        tostring(contextTag or "load"),
        tostring(type(isClient) == "function" and isClient() or false),
        tostring(type(isServer) == "function" and isServer() or false),
        tostring(MP.SCRIPT_VERSION),
        tostring(MP.SCRIPT_BUILD)
    ))
end

local function registerEvents()
    if ArmorMakesSense._mpServerRuntimeRegistered then
        return
    end
    ArmorMakesSense._mpServerRuntimeRegistered = true

    if Events and Events.OnClientCommand and type(Events.OnClientCommand.Add) == "function" then
        Events.OnClientCommand.Add(onClientCommand)
        log("OnClientCommand runtime handler registered")
    else
        log("OnClientCommand.Add unavailable; MP runtime command channel inactive")
    end

    if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(onEveryOneMinute)
    else
        log("Events.EveryOneMinute.Add unavailable; server warm tick disabled")
    end

    if Events and Events.OnWeaponSwing and type(Events.OnWeaponSwing.Add) == "function" then
        Events.OnWeaponSwing.Add(onWeaponSwing)
    else
        log("Events.OnWeaponSwing.Add unavailable; server strain overlay disabled")
    end

    if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(onPlayerUpdate)
    else
        log("Events.OnPlayerUpdate.Add unavailable; discomfort invariant runs on snapshot cadence")
    end

    if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
        Events.OnGameBoot.Add(function()
            logBootBanner("OnGameBoot")
        end)
    end
end

registerEvents()
logBootBanner("load")
