local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")
local root = os.getenv("AMS_ROOT") or "."

ArmorMakesSense = { Core = {} }
local playerOne = {}
local playerTwo = {}
local remotePlayer = {}
getPlayer = function() return playerOne end
getNumActivePlayers = function() return 2 end
getSpecificPlayer = function(index)
    return index == 0 and playerOne or playerTwo
end

package.loaded["core/ArmorMakesSense_ClientRuntime"] = nil
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local visited = {}
Support.assertEqual(ClientRuntime.forEachLocalPlayer(function(player, index)
    visited[index + 1] = player
end), 2, "local player enumeration count")
Support.assertEqual(visited[1], playerOne, "first local player")
Support.assertEqual(visited[2], playerTwo, "second local player")
Support.assertTrue(ClientRuntime.isLocalPlayer(playerTwo), "secondary player is local")
Support.assertFalse(ClientRuntime.isLocalPlayer(remotePlayer), "remote actor is not local")

local ticked = {}
local resolvedOptions = { EnableSleepPenaltyModel = false }
package.loaded["ArmorMakesSense_Options"] = { get = function() return resolvedOptions end }
package.loaded["core/ArmorMakesSense_Combat"] = { onPlayerAttackFinished = function() end }
package.loaded["core/ArmorMakesSense_Tick"] = {
    tickPlayer = function(player)
        ticked[#ticked + 1] = player
    end,
}
ArmorMakesSense.Core.Runtime = nil
local Runtime = dofile(root .. "/common/media/lua/client/core/ArmorMakesSense_Runtime.lua")
Runtime.onEveryOneMinute()
Support.assertEqual(#ticked, 2, "minute runtime ticks every local player")
Support.assertEqual(ticked[2], playerTwo, "minute runtime reaches secondary player")

local registeredHandlers = {}
local function event(name)
    return {
        Add = function(handler) registeredHandlers[name] = handler end,
        Remove = function(handler)
            if registeredHandlers[name] == handler then
                registeredHandlers[name] = nil
            end
        end,
    }
end
Events = {
    EveryOneMinute = event("EveryOneMinute"),
    OnPlayerAttackFinished = event("OnPlayerAttackFinished"),
    OnPlayerUpdate = event("OnPlayerUpdate"),
}
local runtimeMod = {}
Support.assertTrue(Runtime.registerEvents(runtimeMod), "runtime registers with sleep disabled")
Support.assertEqual(registeredHandlers.OnPlayerUpdate, nil, "disabled sleep model registers no realtime sleep observer")
resolvedOptions.EnableSleepPenaltyModel = true
Support.assertTrue(Runtime.registerEvents(runtimeMod), "runtime registers with sleep enabled")
Support.assertEqual(registeredHandlers.OnPlayerUpdate, Runtime.onPlayerUpdate, "enabled sleep model registers realtime observer")

local strainedPlayer = nil
package.loaded["ArmorMakesSense_Options"] = { get = function() return { EnableMuscleStrainModel = true } end }
package.loaded["ArmorMakesSense_StrainShared"] = {
    applyArmorStrainOverlay = function(player)
        strainedPlayer = player
    end,
}
ArmorMakesSense.Core.Combat = nil
local Combat = dofile(root .. "/common/media/lua/client/core/ArmorMakesSense_Combat.lua")
Combat.onPlayerAttackFinished(playerTwo, {})
Support.assertEqual(strainedPlayer, playerTwo, "combat applies to the attacking local player")
strainedPlayer = nil
Combat.onPlayerAttackFinished(remotePlayer, {})
Support.assertEqual(strainedPlayer, nil, "combat ignores remote actors")

print("ams local player ownership checks passed")
