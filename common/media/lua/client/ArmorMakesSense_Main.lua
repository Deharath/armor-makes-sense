ArmorMakesSense = ArmorMakesSense or {}

require "ArmorMakesSense_Config"
require "ArmorMakesSense_Compat"
require "ArmorMakesSense_ArmorClassifier"
require "ArmorMakesSense_SlotCompat"

local Bootstrap = require "core/ArmorMakesSense_Bootstrap"
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local MPClientRuntime = require "ArmorMakesSense_MPClientRuntime"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local Runtime = require "core/ArmorMakesSense_Runtime"
local UI = require "core/ArmorMakesSense_UI"

local Mod = ArmorMakesSense
local sleepHooksInstallResolved = false

local function registerCompatProvider()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or type(compat.registerProvider) ~= "function" then
        return
    end

    compat:registerProvider("ArmorMakesSense", {
        capabilities = {
            endurance_coordinator = true,
            sleep_penalty_provider = true,
            sleep_planner_penalty_provider = true,
        },
        callbacks = {
            computeSleepPenaltyContribution = function(playerObj, args)
                local player = playerObj or ClientRuntime.getLocalPlayer()
                if not player then
                    return {
                        penaltyFraction = 0,
                        sleeping = false,
                    }
                end

                local state = ClientRuntime.ensureState(player)
                local options = Options.get()
                local profile = LoadModel.computeWornProfile(player)
                return Physiology.computeSleepPenaltyContribution(
                    player,
                    state,
                    options,
                    tonumber(args and args.dtMinutes) or 0,
                    profile,
                    tonumber(args and args.currentFatigue)
                )
            end,
            estimateSleepPlannerPenalty = function(playerObj, args)
                local player = playerObj or ClientRuntime.getLocalPlayer()
                if not player then
                    return { penaltyFraction = 0 }
                end

                return Physiology.computeSleepPlannerPenalty(
                    player,
                    ClientRuntime.ensureState(player),
                    Options.get(),
                    LoadModel.computeWornProfile(player),
                    tonumber(args and args.currentFatigue)
                )
            end,
            buildTraceSnapshot = function(playerObj, _args)
                local player = playerObj or ClientRuntime.getLocalPlayer()
                if not player then
                    return {}
                end
                return Physiology.buildCompatTraceSnapshot(ClientRuntime.ensureState(player))
            end,
        },
    })
end

local function ensureClientUi(player)
    local ok, failure = pcall(UI.update, player or ClientRuntime.getLocalPlayer(), nil, Options.get())
    if not ok then
        ClientRuntime.logErrorOnce("ui_install_error", "UI installation failed: " .. tostring(failure))
        return false
    end
    return true
end

local function isEligibleLocalPlayer(playerObj)
    if not playerObj then
        return false
    end
    if type(playerObj.isLocalPlayer) == "function" then
        local ok, isLocal = pcall(playerObj.isLocalPlayer, playerObj)
        if ok and not isLocal then
            return false
        end
    end
    return true
end

local function tryInstallSleepHooks(playerObj)
    if sleepHooksInstallResolved or not isEligibleLocalPlayer(playerObj) then
        return
    end
    local loaded, SleepHooks = pcall(require, "ArmorMakesSense_SleepHooks")
    if loaded and type(SleepHooks) == "table" and type(SleepHooks.wrapSleepPlanning) == "function" then
        local installed = SleepHooks.wrapSleepPlanning()
        if installed == false then
            ClientRuntime.log("sleep planner hooks delegated to CMS coordinator after confirmed local player creation")
        else
            ClientRuntime.log("sleep planner hooks installed after confirmed local player creation")
        end
    end
    sleepHooksInstallResolved = true
end

local function onCreatePlayer(_playerIndex, playerObj)
    local player = playerObj or ClientRuntime.getLocalPlayer()
    if not isEligibleLocalPlayer(player) then
        return
    end
    ensureClientUi(player)
    tryInstallSleepHooks(player)
end

registerCompatProvider()

local registered, role = Bootstrap.registerClientRuntime(Mod, Runtime, MPClientRuntime)
if not registered then
    ClientRuntime.setDisabled(true)
    ClientRuntime.logError("client runtime registration failed for role=" .. tostring(role))
end

if Events and Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
    Events.OnCreatePlayer.Add(onCreatePlayer)
end

return Mod
