local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = nil
package.loaded["ArmorMakesSense_RuntimeState"] = nil
local RuntimeState = require "ArmorMakesSense_RuntimeState"

local legacyState = {
    lastUpdateGameMinutes = 12,
    pendingCatchupMinutes = 999,
    mpClient = { lastRequestWallSecond = 500 },
    mpServer = { pendingCatchupMinutes = 999 },
}
local player = {
    modData = {
        ArmorMakesSenseState = legacyState,
    },
}
function player:getModData()
    return self.modData
end

local singleplayer = RuntimeState.get(player, RuntimeState.ROLE_SINGLEPLAYER)
Support.assertTrue(type(singleplayer) == "table", "singleplayer state created")
Support.assertEqual(player.modData.ArmorMakesSenseState, nil, "legacy state purged")
Support.assertEqual(singleplayer.pendingCatchupMinutes, nil, "legacy catch-up not imported")
Support.assertTrue(singleplayer ~= legacyState, "legacy table not reused")

local mpClient = RuntimeState.get(player, RuntimeState.ROLE_MP_CLIENT)
local mpServer = RuntimeState.get(player, RuntimeState.ROLE_MP_SERVER)
Support.assertTrue(singleplayer ~= mpClient, "SP and MP-client stores isolated")
Support.assertTrue(singleplayer ~= mpServer, "SP and MP-server stores isolated")
Support.assertTrue(mpClient ~= mpServer, "MP role stores isolated")
Support.assertEqual(RuntimeState.get(player, RuntimeState.ROLE_SINGLEPLAYER), singleplayer, "state stable within session")

local singleplayerStore = RuntimeState._stores[RuntimeState.ROLE_SINGLEPLAYER]
Support.assertEqual(getmetatable(singleplayerStore).__mode, "k", "state store uses weak player keys")

Support.assertTrue(RuntimeState.clear(player, RuntimeState.ROLE_SINGLEPLAYER), "state clear reports prior value")
local replacement = RuntimeState.get(player, RuntimeState.ROLE_SINGLEPLAYER)
Support.assertTrue(replacement ~= singleplayer, "cleared state is not replayed")

local noModDataPlayer = {}
local noModDataState = RuntimeState.get(noModDataPlayer, RuntimeState.ROLE_SINGLEPLAYER)
Support.assertTrue(type(noModDataState) == "table", "transient state does not depend on modData")
Support.assertEqual(RuntimeState.get(player, "unknown"), nil, "unknown role rejected")

local reloaded = dofile((os.getenv("AMS_ROOT") or ".") .. "/common/media/lua/shared/ArmorMakesSense_RuntimeState.lua")
Support.assertEqual(reloaded.get(player, reloaded.ROLE_SINGLEPLAYER), replacement, "module reload preserves live session state")

print("ams transient runtime state checks passed")
