ArmorMakesSense = ArmorMakesSense or {}

require "ArmorMakesSense_Config"
require "ArmorMakesSense_Compat"
local SlotCompat = require "ArmorMakesSense_SlotCompat"
local SpeedRebalance = require "ArmorMakesSense_SpeedRebalance"

local Bootstrap = require "core/ArmorMakesSense_Bootstrap"
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local MPClientRuntime = require "ArmorMakesSense_MPClientRuntime"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local Runtime = require "core/ArmorMakesSense_Runtime"
local UI = require "core/ArmorMakesSense_UI"

local Mod = ArmorMakesSense
local previousMainHandlers = Mod._mainEventHandlers or {}
Mod._mainEventHandlers = {}

local function removeEventHandler(eventName, handler)
    local event = Events and Events[eventName] or nil
    if event and type(event.Remove) == "function" and type(handler) == "function" then
        pcall(event.Remove, handler)
    end
end

for eventName, handler in pairs(previousMainHandlers) do
    removeEventHandler(eventName, handler)
end

local function registerCompatProvider()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" or type(compat.registerProvider) ~= "function" then
        return
    end

    local options = Options.get()
    local capabilities = {
        endurance_coordinator = true,
    }
    local callbacks = {
        buildTraceSnapshot = function(playerObj, _args)
            local player = playerObj or ClientRuntime.getLocalPlayer()
            if not player then
                return {}
            end
            return Physiology.buildCompatTraceSnapshot(ClientRuntime.ensureState(player))
        end,
    }
    if options.EnableSleepPenaltyModel then
        capabilities.sleep_penalty_provider = true
        capabilities.sleep_planner_penalty_provider = true
        callbacks.computeSleepPenaltyContribution = function(playerObj, _args)
            local player = playerObj or ClientRuntime.getLocalPlayer()
            local callbackOptions = Options.get()
            return Physiology.sleepPenaltyContribution(
                player,
                callbackOptions,
                player and LoadModel.computeWornProfile(player, callbackOptions) or nil
            )
        end
        callbacks.estimateSleepPlannerPenalty = function(playerObj, _args)
            local player = playerObj or ClientRuntime.getLocalPlayer()
            local callbackOptions = Options.get()
            local contribution = Physiology.sleepPenaltyContribution(
                player,
                callbackOptions,
                player and LoadModel.computeWornProfile(player, callbackOptions) or nil
            )
            return { penaltyFraction = contribution.penaltyFraction }
        end
    end

    compat:registerProvider("ArmorMakesSense", {
        capabilities = capabilities,
        callbacks = callbacks,
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
    return ClientRuntime.isLocalPlayer(playerObj)
end

local function onCreatePlayer(_playerIndex, playerObj)
    local player = playerObj or ClientRuntime.getLocalPlayer()
    if not isEligibleLocalPlayer(player) then
        return
    end
    ensureClientUi(player)
    SlotCompat.initialize()
    if not ArmorMakesSense._speedRebalanceLoaded then
        SpeedRebalance.registerEvents()
    end
end

registerCompatProvider()

local registered, role = Bootstrap.registerClientRuntime(Mod, Runtime, MPClientRuntime)
if not registered then
    ClientRuntime.setDisabled(true)
    ClientRuntime.logError("client runtime registration failed for role=" .. tostring(role))
end

if Events and Events.OnCreatePlayer and type(Events.OnCreatePlayer.Add) == "function" then
    Events.OnCreatePlayer.Add(onCreatePlayer)
    Mod._mainEventHandlers.OnCreatePlayer = onCreatePlayer
end

return Mod
