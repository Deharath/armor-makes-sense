ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.DevBootstrap = Testing.DevBootstrap or {}

local DevBootstrap = Testing.DevBootstrap
local previousInitialize = DevBootstrap.initialize
local previousEventHandlers = DevBootstrap._eventHandlers
local initialized = false
local benchTickErrorLogged = false

local function removeEventHandler(eventName, handler)
    local event = Events and Events[eventName] or nil
    if event and type(event.Remove) == "function" and type(handler) == "function" then
        event.Remove(handler)
    end
end

removeEventHandler("OnGameStart", previousInitialize)
for eventName, handler in pairs(previousEventHandlers or {}) do
    removeEventHandler(eventName, handler)
end
DevBootstrap._eventHandlers = {}

local TEST_MODULES = {
    "testing/ArmorMakesSense_Gear",
    "testing/ArmorMakesSense_Reset",
    "testing/ArmorMakesSense_Commands",
    "testing/ArmorMakesSense_API",
    "testing/ArmorMakesSense_DevPanel",
    "testing/ArmorMakesSense_Benches",
    "testing/ArmorMakesSense_Weapons",
    "testing/ArmorMakesSense_BenchCatalog",
    "testing/ArmorMakesSense_BenchScenarios",
    "testing/ArmorMakesSense_BenchUtils",
    "testing/ArmorMakesSense_BenchRunnerRuntime",
    "testing/ArmorMakesSense_BenchRunnerEnv",
    "testing/ArmorMakesSense_BenchRunnerSnapshot",
    "testing/ArmorMakesSense_BenchRunnerReport",
    "testing/ArmorMakesSense_BenchRunnerNative",
    "testing/ArmorMakesSense_BenchRunnerStep",
    "testing/ArmorMakesSense_BenchRunner",
}

if not (ArmorMakesSense.Core and ArmorMakesSense.Core.State) then
    require "ArmorMakesSense_Main"
end
for i = 1, #TEST_MODULES do
    require(TEST_MODULES[i])
end

local function log(message)
    print("[ArmorMakesSense][DEV] " .. tostring(message))
end

local function logError(message)
    print("[ArmorMakesSense][DEV][ERROR] " .. tostring(message))
end

local function safeGlobalBool(name)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return false
    end
    local ok, value = pcall(fn)
    return ok and value == true
end

local function isMultiplayer()
    return safeGlobalBool("isClient") or safeGlobalBool("isServer")
end

local function isClientSide()
    return safeGlobalBool("isClient")
end

local function getLocalPlayer()
    local fn = _G.getPlayer
    if type(fn) ~= "function" then
        return nil
    end
    local ok, player = pcall(fn)
    return ok and player or nil
end

local function getWorldAgeMinutes(Utils)
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return (tonumber(Utils.safeMethod(gameTime, "getWorldAgeHours")) or 0) * 60.0
end

local function getCurrentGameSpeed(Utils)
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(Utils.safeMethod(gameTime, "getTrueMultiplier"))
end

local function setCurrentGameSpeed(Utils, multiplier)
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if gameTime then
        Utils.safeMethod(gameTime, "setMultiplier", Utils.clamp(tonumber(multiplier) or 1.0, 0.05, 40.0))
    end
end

local function sanitizeBenchHandle(state)
    local bench = state.benchRunner
    if type(bench) ~= "table" then
        state.benchRunner = nil
        return
    end

    local hasLegacyRuntimeBlob = bench.steps ~= nil
        or bench.snapshot ~= nil
        or bench.stepResults ~= nil
        or bench.baselineOutfit ~= nil
        or bench.nativeDriver ~= nil
        or bench.weatherOverride ~= nil
    local active = bench.active == true
    local id = tostring(bench.id or "")
    if hasLegacyRuntimeBlob or not active or id == "" then
        state.benchRunner = nil
        return
    end

    state.benchRunner = {
        active = true,
        id = id,
        preset = tostring(bench.preset or ""),
        label = tostring(bench.label or ""),
        mode = tostring(bench.mode or "lab"),
        speedReq = tonumber(bench.speedReq) or 0,
        startedAt = tonumber(bench.startedAt) or tonumber(state.lastUpdateGameMinutes) or 0,
        index = math.max(0, math.floor(tonumber(bench.index) or 0)),
        total = math.max(0, math.floor(tonumber(bench.total) or 0)),
        repeats = math.max(1, math.floor(tonumber(bench.repeats) or 1)),
        scriptVersion = tostring(bench.scriptVersion or "0.0.0"),
        scriptBuild = tostring(bench.scriptBuild or "na"),
    }
end

local function ensureDevelopmentState(State, player)
    local state = State.ensureState(player)
    state.testLock = state.testLock or {
        mode = nil,
        wetness = nil,
        bodyTemp = nil,
        untilMinute = 0,
    }
    state.gearProfiles = state.gearProfiles or {}
    sanitizeBenchHandle(state)
    return state
end

local function buildContext(modules)
    local Utils = modules.Utils
    local Stats = modules.Stats
    local Gear = modules.Gear
    local gearDeps = {
        safeMethod = Utils.safeMethod,
        toBoolean = Utils.toBoolean,
        lower = Utils.lower,
    }

    local function ensureState(player)
        return ensureDevelopmentState(modules.State, player)
    end

    return {
        Classifier = modules.Classifier,
        Commands = modules.Commands,
        clamp = Utils.clamp,
        softNorm = Utils.softNorm,
        toBoolean = Utils.toBoolean,
        safeMethod = Utils.safeMethod,
        hasFunction = function(target, name)
            return target and type(target[name]) == "function"
        end,
        log = log,
        logError = logError,
        scriptVersion = tostring(modules.MP.SCRIPT_VERSION),
        scriptBuild = tostring(modules.MP.SCRIPT_BUILD),
        getLocalPlayer = getLocalPlayer,
        getWorldAgeMinutes = function()
            return getWorldAgeMinutes(Utils)
        end,
        getCurrentGameSpeed = function()
            return getCurrentGameSpeed(Utils)
        end,
        setCurrentGameSpeed = function(multiplier)
            setCurrentGameSpeed(Utils, multiplier)
        end,
        isMultiplayer = isMultiplayer,
        isClientSide = isClientSide,
        ensureState = ensureState,
        getOptions = modules.Options.get,
        computeWornProfile = modules.LoadModel.computeWornProfile,
        analyzeWornGear = modules.LoadModel.analyzeWornGear,
        itemToBurdenSignal = modules.LoadModel.itemToBurdenSignal,
        getUiRuntimeSnapshot = modules.Physiology.getUiRuntimeSnapshot,
        getRuntimeState = modules.ClientRuntime and modules.ClientRuntime.ensureState or modules.State.ensureState,
        getVanillaMuscleStrainFactor = modules.Strain.getVanillaMuscleStrainFactor,
        getEndurance = Stats.getEndurance,
        getFatigue = Stats.getFatigue,
        getThirst = Stats.getThirst,
        getWetness = Stats.getWetness,
        getBodyTemperature = Stats.getBodyTemperature,
        setFatigue = Stats.setFatigue,
        setWetness = Stats.setWetness,
        setBodyTemperature = Stats.setBodyTemperature,
        resetCharacterToEquilibrium = modules.Reset.resetCharacterToEquilibrium,
        snapshotWornItems = function(player)
            return Gear.snapshotWornItems(player, gearDeps)
        end,
        getBaselineWearEntries = Gear.getBaselineWearEntries,
        getBuiltInGearProfile = function(profileName)
            return Gear.getBuiltInGearProfile(profileName, gearDeps)
        end,
        wearProfile = function(player, profileEntries, mode)
            return Gear.wearProfile(player, profileEntries, mode, gearDeps)
        end,
        isWearableItem = function(item, wornLocation)
            return Gear.isWearableItem(item, wornLocation, gearDeps)
        end,
        resolveItemWearLocation = function(item)
            return Gear.resolveItemWearLocation(item, gearDeps)
        end,
        createItemByFullType = Gear.createItemByFullType,
        getStaticCombatSnapshot = modules.Benches.getStaticCombatSnapshot,
        equipBestMeleeWeapon = function(player, candidates)
            return modules.Weapons.equipBestMeleeWeapon(player, candidates, {
                safeMethod = Utils.safeMethod,
            })
        end,
        clearBenchSpawnedWeapon = function(player)
            return modules.Weapons.clearBenchSpawnedWeapon(player, {
                safeMethod = Utils.safeMethod,
            })
        end,
        listBuiltInGearProfiles = modules.Gear.listBuiltInProfileNames,
        listBenchPresetIds = modules.BenchCatalog.listPresetIds,
        writeSupportReport = function(player)
            if modules.SupportReport and type(modules.SupportReport.writeCurrentPlayerReport) == "function" then
                return modules.SupportReport.writeCurrentPlayerReport(player)
            end
            return false, nil, "Support report writer unavailable."
        end,
    }
end

local function enforceTestLock(modules, player, state)
    local testLock = state.testLock
    if not testLock or not testLock.mode then
        return
    end

    local nowMinutes = getWorldAgeMinutes(modules.Utils)
    if tonumber(testLock.untilMinute) and nowMinutes <= tonumber(testLock.untilMinute) then
        if testLock.wetness ~= nil then
            modules.Stats.setWetness(player, testLock.wetness)
        end
        if testLock.bodyTemp ~= nil then
            modules.Stats.setBodyTemperature(player, testLock.bodyTemp)
        end
        return
    end

    if testLock.wetness ~= nil then
        modules.Stats.setWetness(player, 0.0)
    end
    if testLock.bodyTemp ~= nil then
        modules.Stats.setBodyTemperature(player, 37.0)
    end
    state.testLock = {
        mode = nil,
        wetness = nil,
        bodyTemp = nil,
        untilMinute = 0,
    }
end

local function tickBenchRunner(modules, player)
    if isMultiplayer() or not player then
        return
    end
    local state = ensureDevelopmentState(modules.State, player)
    local ok, failure = pcall(modules.BenchRunner.tick, player, state)
    if ok then
        return
    end
    pcall(modules.BenchRunner.stop)
    if not benchTickErrorLogged then
        benchTickErrorLogged = true
        logError("bench tick failed; active runner disabled: " .. tostring(failure))
    end
end

local function registerEvents(modules)
    if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        local handler = function()
            tickBenchRunner(modules, getLocalPlayer())
        end
        DevBootstrap._eventHandlers.EveryOneMinute = handler
        Events.EveryOneMinute.Add(handler)
    end
    if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        local handler = function(playerObj)
            if isMultiplayer() then
                return
            end
            local player = playerObj or getLocalPlayer()
            if not player then
                return
            end
            local state = ensureDevelopmentState(modules.State, player)
            tickBenchRunner(modules, player)
            enforceTestLock(modules, player, state)
        end
        DevBootstrap._eventHandlers.OnPlayerUpdate = handler
        Events.OnPlayerUpdate.Add(handler)
    end
end

function DevBootstrap.initialize()
    if initialized then
        return true
    end

    local modules = {
        Utils = ArmorMakesSense.Utils,
        Options = require "ArmorMakesSense_Options",
        State = ArmorMakesSense.Core.State,
        ClientRuntime = ArmorMakesSense.Core.ClientRuntime,
        SupportReport = ArmorMakesSense.Core.SupportReport,
        Stats = ArmorMakesSense.Core.Stats,
        LoadModel = ArmorMakesSense.Core.LoadModel,
        Strain = ArmorMakesSense.Core.Strain,
        Physiology = ArmorMakesSense.Models.Physiology,
        Classifier = ArmorMakesSense.Classifier,
        MP = ArmorMakesSense.MP,
        Gear = ArmorMakesSense.Testing.Gear,
        Reset = ArmorMakesSense.Testing.Reset,
        Commands = ArmorMakesSense.Testing.Commands,
        API = ArmorMakesSense.Testing.API,
        DevPanel = ArmorMakesSense.Testing.DevPanel,
        Benches = ArmorMakesSense.Testing.Benches,
        Weapons = ArmorMakesSense.Testing.Weapons,
        BenchCatalog = ArmorMakesSense.Testing.BenchCatalog,
        BenchScenarios = ArmorMakesSense.Testing.BenchScenarios,
        BenchRunner = ArmorMakesSense.Testing.BenchRunner,
    }
    local context = buildContext(modules)

    modules.Reset.setContext(context)
    modules.Benches.setContext(context)
    modules.BenchCatalog.setContext(context)
    modules.BenchScenarios.setContext(context)
    modules.Commands.setContext(context)
    modules.DevPanel.setContext(context)
    modules.API.setContext({
        logError = logError,
        getOptions = modules.Options.get,
        Commands = modules.Commands,
        Benches = modules.Benches,
        BenchRunner = modules.BenchRunner,
    })
    modules.API.bindGlobals()
    modules.DevPanel.initialize()
    registerEvents(modules)

    initialized = true
    log("development bootstrap initialized")
    return true
end

if Events and Events.OnGameStart and type(Events.OnGameStart.Add) == "function" then
    DevBootstrap._eventHandlers.OnGameStart = DevBootstrap.initialize
    Events.OnGameStart.Add(DevBootstrap.initialize)
end

return DevBootstrap
