ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local Options = require "ArmorMakesSense_Options"
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
    if not ClientRuntime.runPlayerStartupChecks(player) then
        return
    end
    local options = Options.get()
    local profile = LoadModel.computeWornProfile(player, options)
    local snapshot = Physiology.tick(player, state, options, profile, Utils.getWorldAgeMinutes())
    UI.update(player, profile, options)
    return snapshot
end

return Tick
