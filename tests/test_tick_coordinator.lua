local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense.Core = ArmorMakesSense.Core or {}
ArmorMakesSense.Core.Tick = nil
local Tick = dofile((os.getenv("AMS_ROOT") or ".") .. "/common/media/lua/client/core/ArmorMakesSense_Tick.lua")
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local UI = require "core/ArmorMakesSense_UI"
local Utils = require "ArmorMakesSense_UtilsShared"

local player = {}
local state = {}
local options = Options.get()
local profile = { burdenKg = 10 }
local calls = {}
local startupOk = true

ClientRuntime.ensureState = function(receivedPlayer)
    Support.assertEqual(receivedPlayer, player, "tick player state lookup")
    return state
end
ClientRuntime.runPlayerStartupChecks = function() return startupOk end
Options.get = function() return options end
Utils.getWorldAgeMinutes = function() return 42 end
LoadModel.computeWornProfile = function(p, opts)
    Support.assertEqual(opts, options, "profile uses resolved options")
    calls[#calls + 1] = "profile"
    return profile
end
Physiology.tick = function(p, s, opts, prof, now)
    Support.assertEqual(s, state, "physiology receives player state")
    Support.assertEqual(prof, profile, "physiology receives the worn profile")
    Support.assertClose(now, 42, 1e-9, "physiology receives world minute")
    calls[#calls + 1] = "tick"
    return { burdenKg = prof.burdenKg }
end
UI.update = function(_, prof)
    Support.assertEqual(prof, profile, "UI receives the same profile")
    calls[#calls + 1] = "ui"
end

local snapshot = Tick.tickPlayer(player)
Support.assertEqual(table.concat(calls, "|"), "profile|tick|ui", "tick order")
Support.assertClose(snapshot.burdenKg, 10, 1e-9, "tick returns physiology snapshot")

calls = {}
startupOk = false
Support.assertEqual(Tick.tickPlayer(player), nil, "failed startup checks skip the tick")
Support.assertEqual(#calls, 0, "no work before startup checks pass")
Support.assertEqual(Tick.tickPlayer(nil), nil, "nil player is ignored")

print("ams singleplayer tick coordinator checks passed")
