local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_StatsShared"] = nil
local Stats = require "ArmorMakesSense_StatsShared"
local Utils = require "ArmorMakesSense_UtilsShared"

local endurance = 0.5
local writes = 0
local player = {
    getStats = function()
        return {
            getEndurance = function() return endurance end,
            setEndurance = function(_, value)
                endurance = value
                writes = writes + 1
            end,
        }
    end,
    getBodyDamage = function()
        return {
            getThermoregulator = function()
                return {
                    getMetabolicRate = function() return 3.9 end,
                }
            end,
        }
    end,
}

Support.assertClose(Stats.getMetabolicRate(player), 3.9, 1e-9, "vanilla metabolic rate read")

local function setRole(client, server, gameClient, gameServer)
    isClient = function() return client end
    isServer = function() return server end
    GameClient = gameClient and { bClient = true } or nil
    GameServer = gameServer and { bServer = true } or nil
end

setRole(false, false, false, false)
Support.assertEqual(Utils.getExecutionRole(), "singleplayer", "singleplayer execution role")
Stats.setEndurance(player, 0.6)
Support.assertEqual(writes, 1, "standalone stat write")

setRole(true, false, false, false)
Support.assertEqual(Utils.getExecutionRole(), "multiplayer_client", "client execution role")
Stats.setEndurance(player, 0.7)
Support.assertEqual(writes, 1, "multiplayer client stat write blocked")

setRole(false, true, false, false)
Support.assertEqual(Utils.getExecutionRole(), "server", "dedicated server execution role")
Stats.setEndurance(player, 0.8)
Support.assertEqual(writes, 2, "dedicated server stat write")

setRole(true, true, true, true)
Support.assertEqual(Utils.getExecutionRole(), "server", "listen server execution role")
Stats.setEndurance(player, 0.9)
Support.assertEqual(writes, 3, "listen server stat write")

setRole(false, false, true, false)
Support.assertEqual(Utils.getExecutionRole(), "multiplayer_client", "GameClient execution role")
Stats.setEndurance(player, 1.0)
Support.assertEqual(writes, 3, "GameClient stat write blocked")

print("ams stat authority checks passed")
