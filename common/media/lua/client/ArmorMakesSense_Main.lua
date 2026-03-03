ArmorMakesSense = ArmorMakesSense or {}

-- Module namespace convention:
--   ArmorMakesSense.Core.*     -- core runtime modules (State, Tick, Combat, etc.)
--   ArmorMakesSense.Models.*   -- formula models (Physiology)
--   ArmorMakesSense.Utils      -- shared utilities
--   ArmorMakesSense.Classifier -- armor classification
--   ArmorMakesSense.DEFAULTS   -- config defaults

require "ArmorMakesSense_Config"
local okModOptionsShared, errModOptionsShared = pcall(require, "ArmorMakesSense_ModOptionsShared")
if not okModOptionsShared then
    print("[ArmorMakesSense][WARN] optional require failed: ArmorMakesSense_ModOptionsShared :: " .. tostring(errModOptionsShared))
end
local okClassifier, errClassifier = pcall(require, "ArmorMakesSense_ArmorClassifier")
if not okClassifier then
    print("[ArmorMakesSense][WARN] optional require failed: ArmorMakesSense_ArmorClassifier :: " .. tostring(errClassifier))
end
pcall(require, "ArmorMakesSense_SlotCompat")
require "core/ArmorMakesSense_Utils"
require "core/ArmorMakesSense_Environment"
require "core/ArmorMakesSense_LoadModel"
require "core/ArmorMakesSense_UI"
require "core/ArmorMakesSense_ContextBinder"
require "core/ArmorMakesSense_ContextFactory"
require "core/ArmorMakesSense_ContextRefs"
require "core/ArmorMakesSense_Bootstrap"
require "core/ArmorMakesSense_State"
require "core/ArmorMakesSense_Tick"
require "core/ArmorMakesSense_Combat"
require "core/ArmorMakesSense_Strain"
require "core/ArmorMakesSense_WearDebug"
require "core/ArmorMakesSense_Runtime"
require "core/ArmorMakesSense_Stats"
require "models/ArmorMakesSense_Physiology"
require "testing/ArmorMakesSense_Gear"
require "testing/ArmorMakesSense_Commands"
require "testing/ArmorMakesSense_API"
require "testing/ArmorMakesSense_Benches"
require "testing/ArmorMakesSense_Weapons"
require "testing/ArmorMakesSense_BenchCatalog"
require "testing/ArmorMakesSense_BenchScenarios"
require "testing/ArmorMakesSense_BenchUtils"
require "testing/ArmorMakesSense_BenchRunnerRuntime"
require "testing/ArmorMakesSense_BenchRunnerEnv"
require "testing/ArmorMakesSense_BenchRunnerSnapshot"
require "testing/ArmorMakesSense_BenchRunnerReport"
require "testing/ArmorMakesSense_BenchRunnerNative"
require "testing/ArmorMakesSense_BenchRunnerStep"
require "testing/ArmorMakesSense_BenchRunner"

local Mod = ArmorMakesSense
local MOD_KEY = "ArmorMakesSenseState"
local MOD_OPTIONS_ID = "ArmorMakesSense"
local SCRIPT_VERSION = "1.0.3"
local SCRIPT_BUILD = "ams-b42-2026-03-03-v052"
local warned = {}
local cachedEnableSystem = true
local cachedDebugLogging = false
local errorKeys = {}
local runtimeDisabled = false
local suppressCountThisMinute = 0
local suppressMaxThisMinute = 0
local swingStateByPlayer = {}
local configureTestingContext
local getWetness
local onWeaponSwing
local onPlayerAttackFinished
local snapshotWornItems
local getBaselineWearEntries
local wearProfile
local getBuiltInGearProfile
local getStaticCombatSnapshot
local tickPlayer
local tickBenchRunner
local contextCoreCStatic
local contextCoreAStatic
local contextCoreBStatic
local stateContextStatic

-- -----------------------------------------------------------------------------
-- Module registry
-- -----------------------------------------------------------------------------

local function resolve(...)
    local current = ArmorMakesSense
    for i = 1, select("#", ...) do
        if not current then
            return nil
        end
        current = current[select(i, ...)]
    end
    return current
end

local modules = {
    Classifier = resolve("Classifier"),
    Utils = resolve("Utils"),
    Environment = resolve("Core", "Environment"),
    LoadModel = resolve("Core", "LoadModel"),
    UI = resolve("Core", "UI"),
    ContextBinder = resolve("Core", "ContextBinder"),
    ContextFactory = resolve("Core", "ContextFactory"),
    ContextRefs = resolve("Core", "ContextRefs"),
    Bootstrap = resolve("Core", "Bootstrap"),
    State = resolve("Core", "State"),
    Tick = resolve("Core", "Tick"),
    Combat = resolve("Core", "Combat"),
    Strain = resolve("Core", "Strain"),
    WearDebug = resolve("Core", "WearDebug"),
    Runtime = resolve("Core", "Runtime"),
    Stats = resolve("Core", "Stats"),
    Physiology = resolve("Models", "Physiology"),
    Gear = resolve("Testing", "Gear"),
    Commands = resolve("Testing", "Commands"),
    API = resolve("Testing", "API"),
    Benches = resolve("Testing", "Benches"),
    Weapons = resolve("Testing", "Weapons"),
    BenchCatalog = resolve("Testing", "BenchCatalog"),
    BenchScenarios = resolve("Testing", "BenchScenarios"),
    BenchRunner = resolve("Testing", "BenchRunner"),
}

local function safeGlobal(name)
    return function(...)
        local fn = _G[name]
        if type(fn) ~= "function" then
            return nil
        end
        return fn(...)
    end
end

local refs = {
    getGameTime = safeGlobal("getGameTime"),
    getCore = safeGlobal("getCore"),
    getModInfoByID = safeGlobal("getModInfoByID"),
}
local testingContextConfigured = false

local function moduleCall(moduleName, methodName, default)
    return function(...)
        configureTestingContext()
        local mod = modules[moduleName]
        if not mod or type(mod[methodName]) ~= "function" then
            if type(default) == "function" then
                return default(...)
            end
            return default
        end
        return mod[methodName](...)
    end
end

-- -----------------------------------------------------------------------------
-- Classifier-driven hint tables
-- -----------------------------------------------------------------------------

local classifierArmorKeywords = (modules.Classifier and modules.Classifier.ARMOR_KEYWORDS) or {}
local classifierArmorLocationHints = (modules.Classifier and modules.Classifier.ARMOR_LOCATION_HINTS) or {}
local classifierProtectiveTagHints = (modules.Classifier and modules.Classifier.PROTECTIVE_TAG_HINTS) or {}

local BREATHING_KEYWORDS = {
    "mask", "respirator", "gas", "hazmat", "filter", "welding", "visor"
}

local BREATHING_LOCATION_HINTS = {
    "face", "mask", "head", "eyes", "neck"
}

local function log(message)
    print("[ArmorMakesSense] " .. tostring(message))
end

local function logError(message)
    print("[ArmorMakesSense][ERROR] " .. tostring(message))
end

local logging = {
    log = log,
    logError = logError,
}

local function logOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    logging.log(message)
end

local function logErrorOnce(key, message)
    if errorKeys[key] then
        return
    end
    errorKeys[key] = true
    logging.logError(message)
end

logging.logOnce = logOnce
logging.logErrorOnce = logErrorOnce

local function runGuarded(label, fn, ...)
    if runtimeDisabled then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        runtimeDisabled = true
        logging.logError("runtime disabled after " .. tostring(label) .. " failure: " .. tostring(result))
        return nil
    end
    return result
end

local function clamp(value, minimum, maximum)
    return modules.Utils.clamp(value, minimum, maximum)
end

local function softNorm(value, pivot, maxNorm)
    return modules.Utils.softNorm(value, pivot, maxNorm)
end

local function toBoolean(value)
    return modules.Utils.toBoolean(value)
end

local function safeMethod(target, methodName, ...)
    return modules.Utils.safeMethodWithOptions(target, methodName, {
        onError = function(failedMethod, failedTarget, failure)
            local tname = tostring(failedTarget)
            local errKey = "safe:" .. tostring(failedMethod) .. ":" .. tname
            logging.logErrorOnce(errKey, "safeMethod failed for " .. tostring(failedMethod) .. " on " .. tname .. " :: " .. tostring(failure))
        end,
    }, ...)
end

local function lower(value)
    return modules.Utils.lower(value)
end

local function containsAny(text, patterns)
    return modules.Utils.containsAny(text, patterns)
end

local function getWorldAgeMinutes()
    local gameTime = refs.getGameTime()
    if not gameTime then
        return 0
    end
    local worldAgeHours = safeMethod(gameTime, "getWorldAgeHours") or 0
    return worldAgeHours * 60
end

local function getPlayerKey(player)
    local num = tonumber(safeMethod(player, "getPlayerNum"))
    if num ~= nil then
        return "p" .. tostring(num)
    end
    return tostring(player)
end

local function ensureSwingState(player)
    local key = getPlayerKey(player)
    local state = swingStateByPlayer[key]
    if not state then
        state = {
            lastSwingMinute = nil,
            swingsThisMinute = 0,
            intervalCount = 0,
            intervalSum = 0,
            intervalMin = nil,
            intervalMax = nil,
            intervalLast = nil,
        }
        swingStateByPlayer[key] = state
    end
    return state
end

local function safeGlobalBool(name)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return false
    end
    local ok, value = pcall(fn)
    if not ok then
        logging.logErrorOnce("global_bool:" .. tostring(name), "global check failed for " .. tostring(name) .. ": " .. tostring(value))
        return false
    end
    return toBoolean(value)
end

local function getLocalPlayer()
    local fn = _G["getPlayer"]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, player = pcall(fn)
    if not ok then
        logging.logErrorOnce("getLocalPlayer_failed", "getPlayer() failed: " .. tostring(player))
        return nil
    end
    return player
end

local function isMultiplayer()
    if safeGlobalBool("isClient") then
        return true
    end
    if safeGlobalBool("isServer") then
        return true
    end
    return false
end

local function hasFunction(target, name)
    return target and type(target[name]) == "function"
end

local function getLoadedModVersion()
    local info = refs.getModInfoByID("ArmorMakesSense")
    local v = safeMethod(info, "getVersion") or safeMethod(info, "getModVersion")
    if v ~= nil then
        return tostring(v)
    end
    return SCRIPT_VERSION
end

local function getGameVersionTag()
    local core = refs.getCore()
    if not core then
        return "unknown"
    end
    local v = safeMethod(core, "getVersionNumber")
        or safeMethod(core, "getVersion")
        or safeMethod(core, "getGameVersion")
    if v == nil then
        return "unknown"
    end
    return tostring(v)
end

local function getCurrentGameSpeed()
    local gameTime = refs.getGameTime()
    if not gameTime then
        return nil
    end
    return tonumber(safeMethod(gameTime, "getMultiplier"))
end

local function setCurrentGameSpeed(multiplier)
    local gameTime = refs.getGameTime()
    if not gameTime then
        return
    end
    safeMethod(gameTime, "setMultiplier", clamp(tonumber(multiplier) or 1.0, 0.05, 40.0))
end

local runPlayerStartupChecks = moduleCall("Runtime", "runPlayerStartupChecks", function()
    return not runtimeDisabled
end)

local getOptions = moduleCall("State", "getOptions", function()
    return {}
end)

local logOptionsSnapshot = moduleCall("State", "logOptionsSnapshot")

local ensureState = moduleCall("State", "ensureState", function()
    return {}
end)

local getPostureLabel = modules.ContextRefs.getPostureLabel

tickBenchRunner = function(player, state)
    configureTestingContext()
    if not modules.BenchRunner or type(modules.BenchRunner.tick) ~= "function" then
        return nil
    end
    local ok, result = pcall(modules.BenchRunner.tick, player, state)
    if not ok then
        logging.logErrorOnce("bench_tick_error", "bench tick failed; disabling bench runner: " .. tostring(result))
        if state and state.benchRunner then
            state.benchRunner.active = false
        end
        return nil
    end
    return result
end

local logWearChanges = moduleCall("WearDebug", "logWearChanges")

local itemToArmorSignal = moduleCall("LoadModel", "itemToArmorSignal")

local computeArmorProfile = modules.ContextRefs.computeArmorProfile
local getHeatFactor = modules.ContextRefs.getHeatFactor
local setBodyTemperature = modules.ContextRefs.setBodyTemperature
local getBodyTemperature = modules.ContextRefs.getBodyTemperature
local wetnessToFactor = modules.ContextRefs.wetnessToFactor
local getWetFactor = modules.ContextRefs.getWetFactor
local getActivityFactor = modules.ContextRefs.getActivityFactor
local getActivityLabel = modules.ContextRefs.getActivityLabel
local updateRecoveryTrace = modules.ContextRefs.updateRecoveryTrace
local getEndurance = modules.ContextRefs.getEndurance
local setEndurance = modules.ContextRefs.setEndurance
local getFatigue = modules.ContextRefs.getFatigue
local setFatigue = modules.ContextRefs.setFatigue
local getThirst = modules.ContextRefs.getThirst
local setThirst = modules.ContextRefs.setThirst
local getDiscomfort = modules.ContextRefs.getDiscomfort
local setWetness = modules.ContextRefs.setWetness

getWetness = modules.ContextRefs.getWetness

local setDiscomfort = modules.ContextRefs.setDiscomfort
local resetMuscleStrain = modules.ContextRefs.resetMuscleStrain
local resetCharacterToEquilibrium = modules.ContextRefs.resetCharacterToEquilibrium

local function getGearDeps()
    return {
        safeMethod = safeMethod,
        toBoolean = toBoolean,
        lower = lower,
    }
end

configureTestingContext = function()
    if testingContextConfigured then
        return
    end
    local context = {}
    if modules.ContextFactory and type(modules.ContextFactory.build) == "function" then
        context = modules.ContextFactory.build(contextCoreAStatic, contextCoreBStatic, contextCoreCStatic)
    end
    if modules.State and type(modules.State.setContext) == "function" then
        modules.State.setContext(stateContextStatic)
    end
    if modules.ContextRefs and type(modules.ContextRefs.setContext) == "function" then
        modules.ContextRefs.setContext({
            LoadModel = modules.LoadModel,
            Environment = modules.Environment,
            Stats = modules.Stats,
            Physiology = modules.Physiology,
            clamp = clamp,
        })
    end
    if modules.ContextBinder and type(modules.ContextBinder.bindAll) == "function" then
        modules.ContextBinder.bindAll(context, {
            Commands = modules.Commands,
            Benches = modules.Benches,
            Physiology = modules.Physiology,
            Stats = modules.Stats,
            Environment = modules.Environment,
            LoadModel = modules.LoadModel,
            UI = modules.UI,
            WearDebug = modules.WearDebug,
            Combat = modules.Combat,
            Strain = modules.Strain,
            Runtime = modules.Runtime,
            BenchCatalog = modules.BenchCatalog,
            BenchScenarios = modules.BenchScenarios,
            BenchRunner = modules.BenchRunner,
        })
    end
    testingContextConfigured = true
end

snapshotWornItems = function(player)
    if type(modules.Gear) ~= "table" or type(modules.Gear.snapshotWornItems) ~= "function" then
        return {}
    end
    return modules.Gear.snapshotWornItems(player, getGearDeps())
end

local function isWearableItem(item, wornLocation)
    if not item then return false end
    if type(modules.Gear) == "table" and type(modules.Gear.isWearableItem) == "function" then
        return modules.Gear.isWearableItem(item, wornLocation, getGearDeps())
    end
    local loc = tostring(wornLocation or "")
    if loc ~= "" then return true end
    local scriptItem = item.getScriptItem and item:getScriptItem()
    local scriptLoc = scriptItem and scriptItem.getBodyLocation and tostring(scriptItem:getBodyLocation() or "") or ""
    return scriptLoc ~= ""
end

getBaselineWearEntries = function()
    if type(modules.Gear) ~= "table" or type(modules.Gear.getBaselineWearEntries) ~= "function" then
        return {}
    end
    return modules.Gear.getBaselineWearEntries()
end

wearProfile = function(player, profileEntries, mode)
    if type(modules.Gear) ~= "table" or type(modules.Gear.wearProfile) ~= "function" then
        return 0, 0
    end
    return modules.Gear.wearProfile(player, profileEntries, mode, getGearDeps())
end

getBuiltInGearProfile = function(profileName)
    if type(modules.Gear) ~= "table" or type(modules.Gear.getBuiltInGearProfile) ~= "function" then
        return nil
    end
    return modules.Gear.getBuiltInGearProfile(profileName, getGearDeps())
end

local applySleepTransition = moduleCall("Physiology", "applySleepTransition")

local applyEnduranceModel = moduleCall("Physiology", "applyEnduranceModel")

local getUiRuntimeSnapshot = moduleCall("Physiology", "getUiRuntimeSnapshot")

getStaticCombatSnapshot = function(player)
    configureTestingContext()
    if type(modules.Benches) ~= "table" or type(modules.Benches.getStaticCombatSnapshot) ~= "function" then
        return nil
    end
    return modules.Benches.getStaticCombatSnapshot(player)
end

local getVanillaMuscleStrainFactor = moduleCall("Strain", "getVanillaMuscleStrainFactor")

local isMeleeStrainEligible = moduleCall("Strain", "isMeleeStrainEligible", false)

local computeArmorStrainExtra = moduleCall("Strain", "computeArmorStrainExtra", 0)

-- Multi-return default when Strain is unavailable.
local applyArmorStrainOverlay = moduleCall("Strain", "applyArmorStrainOverlay", function()
    return 0, 0
end)

tickPlayer = moduleCall("Tick", "tickPlayer")

onWeaponSwing = moduleCall("Combat", "onWeaponSwing")

onPlayerAttackFinished = moduleCall("Combat", "onPlayerAttackFinished")

local onEveryOneMinute = moduleCall("Runtime", "onEveryOneMinute")

local onPlayerUpdate = moduleCall("Runtime", "onPlayerUpdate")

contextCoreCStatic = {
    armorKeywords = classifierArmorKeywords,
    armorLocationHints = classifierArmorLocationHints,
    breathingKeywords = BREATHING_KEYWORDS,
    breathingLocationHints = BREATHING_LOCATION_HINTS,
    protectiveTagHints = classifierProtectiveTagHints,
    resetMuscleStrain = resetMuscleStrain,
    resetCharacterToEquilibrium = resetCharacterToEquilibrium,
    resetEquilibrium = function(...)
        local fn = _G["ams_reset_equilibrium"]
        if type(fn) == "function" then
            return fn(...)
        end
        return nil
    end,
    mark = function(label)
        local fn = _G["ams_mark"]
        if type(fn) == "function" then
            return fn(label)
        end
        return nil
    end,
    gearWearVirtual = function(name)
        local fn = _G["ams_gear_wear_virtual"]
        if type(fn) == "function" then
            return fn(name)
        end
        return nil
    end,
    sleepBench = function(hours, tempC, wetnessPct)
        local fn = _G["ams_sleep_bench"]
        if type(fn) == "function" then
            return fn(hours, tempC, wetnessPct)
        end
        return nil
    end,
    stopAutoRunner = function(player, state, reason)
        return false
    end,
    snapshotWornItems = snapshotWornItems,
    getBaselineWearEntries = getBaselineWearEntries,
    wearProfile = wearProfile,
    getBuiltInGearProfile = getBuiltInGearProfile,
    equipBestMeleeWeapon = function(player, candidates)
        if not modules.Weapons or type(modules.Weapons.equipBestMeleeWeapon) ~= "function" then
            return nil
        end
        return modules.Weapons.equipBestMeleeWeapon(player, candidates, {
            safeMethod = safeMethod,
        })
    end,
    clearBenchSpawnedWeapon = function(player)
        if not modules.Weapons or type(modules.Weapons.clearBenchSpawnedWeapon) ~= "function" then
            return 0
        end
        return modules.Weapons.clearBenchSpawnedWeapon(player, {
            safeMethod = safeMethod,
        })
    end,
    getStaticCombatSnapshot = getStaticCombatSnapshot,
    isWearableItem = isWearableItem,
    itemToArmorSignal = itemToArmorSignal,
    runGuarded = runGuarded,
    tickPlayer = tickPlayer,
    tickBenchRunner = tickBenchRunner,
    isDebugLoggingCached = function() return cachedDebugLogging end,
    ensureSwingState = ensureSwingState,
    getVanillaMuscleStrainFactor = getVanillaMuscleStrainFactor,
    isMeleeStrainEligible = isMeleeStrainEligible,
    computeArmorStrainExtra = computeArmorStrainExtra,
    applyArmorStrainOverlay = applyArmorStrainOverlay,
    onEveryOneMinute = onEveryOneMinute,
    onWeaponSwing = onWeaponSwing,
    onPlayerAttackFinished = onPlayerAttackFinished,
    onPlayerUpdate = onPlayerUpdate,
}

contextCoreAStatic = {
    scriptVersion = SCRIPT_VERSION,
    scriptBuild = SCRIPT_BUILD,
    log = logging.log,
    logError = logging.logError,
    logOnce = logging.logOnce,
    logErrorOnce = logging.logErrorOnce,
    safeMethod = safeMethod,
    hasFunction = hasFunction,
    containsAny = containsAny,
    lower = lower,
    toBoolean = toBoolean,
    clamp = clamp,
    softNorm = softNorm,
    getWorldAgeMinutes = getWorldAgeMinutes,
    isRuntimeDisabled = function() return runtimeDisabled end,
    isSystemEnabledCached = function() return cachedEnableSystem end,
    ensureState = ensureState,
    getLocalPlayer = getLocalPlayer,
    isMultiplayer = isMultiplayer,
    getCurrentGameSpeed = getCurrentGameSpeed,
    setCurrentGameSpeed = setCurrentGameSpeed,
    getGameVersionTag = getGameVersionTag,
    getLoadedModVersion = getLoadedModVersion,
    setCachedEnableSystem = function(value) cachedEnableSystem = toBoolean(value) end,
    setCachedDebugLogging = function(value) cachedDebugLogging = toBoolean(value) end,
    setRuntimeDisabled = function(value) runtimeDisabled = toBoolean(value) end,
}

contextCoreBStatic = {
    computeArmorProfile = computeArmorProfile,
    ensureState = ensureState,
    getBodyTemperature = getBodyTemperature,
    setBodyTemperature = setBodyTemperature,
    getWetness = function(player) return getWetness(player) end,
    setWetness = setWetness,
    getEndurance = getEndurance,
    setEndurance = setEndurance,
    getFatigue = getFatigue,
    setFatigue = setFatigue,
    getThirst = getThirst,
    setThirst = setThirst,
    getDiscomfort = getDiscomfort,
    setDiscomfort = setDiscomfort,
    getOptions = getOptions,
    getHeatFactor = getHeatFactor,
    getWetFactor = getWetFactor,
    getActivityFactor = getActivityFactor,
    getActivityLabel = getActivityLabel,
    getPostureLabel = getPostureLabel,
    getUiRuntimeSnapshot = getUiRuntimeSnapshot,
    Classifier = modules.Classifier,
}

stateContextStatic = {
    defaults = Mod.DEFAULTS,
    modOptionsId = MOD_OPTIONS_ID,
    modKey = MOD_KEY,
    getWorldAgeMinutes = getWorldAgeMinutes,
    safeMethod = safeMethod,
    toBoolean = toBoolean,
    logOnce = logOnce,
}

if modules.Tick and type(modules.Tick.setContext) == "function" then
    modules.Tick.setContext({
        ensureState = ensureState,
        getOptions = getOptions,
        setCachedDebugLogging = function(value) cachedDebugLogging = toBoolean(value) end,
        logOptionsSnapshot = logOptionsSnapshot,
        setCachedEnableSystem = function(value) cachedEnableSystem = toBoolean(value) end,
        getWorldAgeMinutes = getWorldAgeMinutes,
        runPlayerStartupChecks = runPlayerStartupChecks,
        logWearChanges = logWearChanges,
        clamp = clamp,
        getEndurance = getEndurance,
        setWetness = setWetness,
        setBodyTemperature = setBodyTemperature,
        log = logging.log,
        computeArmorProfile = computeArmorProfile,
        getHeatFactor = getHeatFactor,
        getWetFactor = getWetFactor,
        wetnessToFactor = wetnessToFactor,
        toBoolean = toBoolean,
        getActivityFactor = getActivityFactor,
        getActivityLabel = getActivityLabel,
        getPostureLabel = getPostureLabel,
        lower = lower,
        updateUiLayer = function(player, profile, options)
            configureTestingContext()
            if modules.UI and type(modules.UI.update) == "function" then
                modules.UI.update(player, profile, options)
            end
        end,
        markUiDirty = function()
            if modules.UI and type(modules.UI.markDirty) == "function" then
                modules.UI.markDirty()
            end
        end,
        applySleepTransition = applySleepTransition,
        applyEnduranceModel = applyEnduranceModel,
        updateRecoveryTrace = updateRecoveryTrace,
        getFatigue = getFatigue,
        getDiscomfort = getDiscomfort,
        ensureSwingState = ensureSwingState,
        getSuppressCount = function() return suppressCountThisMinute end,
        getSuppressMax = function() return suppressMaxThisMinute end,
        resetSuppressCounters = function()
            suppressCountThisMinute = 0
            suppressMaxThisMinute = 0
        end,
    })
end

configureTestingContext()
if modules.Bootstrap and type(modules.Bootstrap.bindApi) == "function" then
    modules.Bootstrap.bindApi(modules.API, {
        logError = logging.logError,
        getOptions = getOptions,
        Commands = modules.Commands,
        Benches = modules.Benches,
        BenchRunner = modules.BenchRunner,
    })
end

if modules.Bootstrap and type(modules.Bootstrap.registerRuntimeEvents) == "function" then
    modules.Bootstrap.registerRuntimeEvents(Mod, modules.Runtime)
end
