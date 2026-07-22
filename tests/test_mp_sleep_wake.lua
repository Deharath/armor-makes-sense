local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local handlers = {}
local runtimeState = {}
local asleep = true
local fatigue = 0.20
local wakeCalls = 0
local wakeSuppressPacket = nil
local sleepEnabled = true
local cmsOwnsFatigue = false

local player = {
    isAsleep = function() return asleep end,
    isLocalPlayer = function() return true end,
    getOnlineID = function() return 1 end,
    getStats = function()
        return {
            getFatigue = function() return fatigue end,
            setFatigue = function(_, value) fatigue = value end,
        }
    end,
}

package.loaded["ArmorMakesSense_MPCompat"] = {
    NET_MODULE = "ArmorMakesSenseRuntime",
    SNAPSHOT_COMMAND = "snapshot",
    REQUEST_SNAPSHOT_COMMAND = "request_snapshot",
    SNAPSHOT_FALLBACK_SECONDS = 2,
    SCRIPT_VERSION = "test",
    SCRIPT_BUILD = "test",
}
ArmorMakesSense.Compat = {
    hasCapability = function(_, provider, capability)
        return cmsOwnsFatigue
            and provider == "CaffeineMakesSense"
            and capability == "fatigue_coordinator"
    end,
}
package.loaded["ArmorMakesSense_Compat"] = ArmorMakesSense.Compat
package.loaded["ArmorMakesSense_SleepOwnership"] = nil
package.loaded["ArmorMakesSense_RuntimeState"] = {
    ROLE_MP_CLIENT = "multiplayer_client",
    get = function()
        return runtimeState
    end,
}
package.loaded["ArmorMakesSense_MPSnapshotCodec"] = {
    decode = function(args)
        return args
    end,
}
package.loaded["core/ArmorMakesSense_IncidentTrace"] = {
    clear = function() end,
    getSeq = function() return 0 end,
    applyServerIncident = function() end,
}
package.loaded["core/ArmorMakesSense_ClientRuntime"] = {
    getLocalPlayer = function() return player end,
}
package.loaded["ArmorMakesSense_Options"] = {
    get = function() return { EnableSleepPenaltyModel = sleepEnabled } end,
}
package.loaded["core/ArmorMakesSense_UI"] = {
    update = function() end,
    markDirty = function() end,
}

GameClient = { bClient = true, ingame = true }
CharacterStat = nil
isClient = function() return true end
isServer = function() return false end
sendClientCommand = function() end
getTimestampMs = function() return 1000 end
getSleepingEvent = function()
    return {
        wakeUp = function(_, wokenPlayer, suppressPacket)
            Support.assertEqual(wokenPlayer, player, "vanilla wake player")
            wakeCalls = wakeCalls + 1
            wakeSuppressPacket = suppressPacket
            asleep = false
        end,
    }
end

local function event(name)
    return {
        Add = function(callback)
            handlers[name] = callback
        end,
    }
end

Events = {
    OnServerCommand = event("OnServerCommand"),
    OnConnected = event("OnConnected"),
    OnCreatePlayer = event("OnCreatePlayer"),
    OnClothingUpdated = event("OnClothingUpdated"),
    EveryOneMinute = event("EveryOneMinute"),
}

package.loaded["ArmorMakesSense_MPClientRuntime"] = nil
local MPClientRuntime = require "ArmorMakesSense_MPClientRuntime"
Support.assertTrue(MPClientRuntime.registerEvents(), "MP client runtime registration")

handlers.OnServerCommand("ArmorMakesSenseRuntime", "snapshot", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})

Support.assertEqual(wakeCalls, 1, "authoritative snapshot invokes vanilla wake once")
Support.assertTrue(wakeSuppressPacket, "authoritative wake suppresses packet echo")
Support.assertFalse(asleep, "vanilla wake clears asleep state")
Support.assertClose(fatigue, 0.30, 1e-9, "wake snapshot applies authoritative fatigue")

sleepEnabled = false
asleep = true
fatigue = 0.20
handlers.OnServerCommand("ArmorMakesSenseRuntime", "snapshot", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})
Support.assertEqual(wakeCalls, 1, "disabled sleep model does not reconcile wake")
Support.assertTrue(asleep, "disabled sleep model leaves vanilla state untouched")
Support.assertClose(fatigue, 0.20, 1e-9, "disabled sleep model does not apply fatigue")

sleepEnabled = true
cmsOwnsFatigue = true
handlers.OnServerCommand("ArmorMakesSenseRuntime", "snapshot", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})
Support.assertEqual(wakeCalls, 1, "CMS-owned sleep does not use AMS wake reconciliation")
Support.assertTrue(asleep, "CMS-owned sleep leaves wake state to CMS")
Support.assertClose(fatigue, 0.20, 1e-9, "CMS-owned sleep ignores AMS fatigue authority")

print("ams multiplayer sleep wake checks passed")
