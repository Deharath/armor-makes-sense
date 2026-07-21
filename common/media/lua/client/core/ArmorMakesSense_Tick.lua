ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local Options = require "ArmorMakesSense_Options"
local Simulation = require "ArmorMakesSense_Simulation"
local Stats = require "ArmorMakesSense_StatsShared"
local UI = require "core/ArmorMakesSense_UI"
local Utils = require "ArmorMakesSense_UtilsShared"

local Core = ArmorMakesSense.Core
Core.Tick = Core.Tick or {}

local Tick = Core.Tick

function Tick.tickPlayer(player)
    if not player then
        return
    end

    local state = ClientRuntime.ensureState(player)
    local options = Options.get()
    UI.update(player, nil, options)

    local nowMinutes = Utils.getWorldAgeMinutes()
    if not ClientRuntime.runPlayerStartupChecks(player) then
        return
    end
    local _, pendingCatchupMinutes = Simulation.accumulateElapsed(state, nowMinutes)

    if pendingCatchupMinutes <= 0 then
        state.pendingCatchupMinutes = 0
        return
    end

    local profile = LoadModel.computeWornProfile(player)
    local activity = Environment.resolveActivity(player, options)
    local activityFactor = activity.factor
    local activityLabel = activity.label
    local postureLabel = Environment.getPostureLabel(player)
    local sleeping = postureLabel == "sleep"
    local catchupCapped, pendingBeforeCap = Simulation.capActiveCatchup(
        state,
        postureLabel ~= "sleep",
        Stats.getEndurance(player)
    )
    if catchupCapped then
        ClientRuntime.log(string.format(
            "discarding stale active endurance catchup pending=%.3f cap=%.3f",
            tonumber(pendingBeforeCap) or 0,
            Simulation.ACTIVE_CATCHUP_MAX_MINUTES
        ))
    end

    UI.update(player, profile, options)

    local result = Simulation.advance({
        player = player,
        state = state,
        options = options,
        nowMinutes = nowMinutes,
        profile = profile,
        activityFactor = activityFactor,
        activityLabel = activityLabel,
        postureLabel = postureLabel,
        applySleepTransition = Physiology.applySleepTransition,
        applyEnduranceModel = not sleeping and Physiology.applyEnduranceModel or nil,
    })
    if result.failurePhase then
        ClientRuntime.log(string.format("simulation %s failed: %s", tostring(result.failurePhase), tostring(result.failure)))
    end
    return result
end

return Tick
