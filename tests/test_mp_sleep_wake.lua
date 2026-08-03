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
    SLEEP_STATE_COMMAND = "sleep_state",
    REQUEST_SNAPSHOT_COMMAND = "request_snapshot",
    SNAPSHOT_REQUEST_MIN_SECONDS = 5,
    SNAPSHOT_REQUEST_TIMEOUT_SECONDS = 60,
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
package.loaded["core/ArmorMakesSense_ClientRuntime"] = {
    getLocalPlayer = function() return player end,
    forEachLocalPlayer = function(callback)
        callback(player, 0)
        return 1
    end,
    isLocalPlayer = function(candidate) return candidate == player end,
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
local snapshotRequestPlayer = nil
local snapshotRequestCalls = 0
sendClientCommand = function(commandPlayer)
    snapshotRequestPlayer = commandPlayer
    snapshotRequestCalls = snapshotRequestCalls + 1
end
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
}

package.loaded["ArmorMakesSense_MPClientRuntime"] = nil
local MPClientRuntime = require "ArmorMakesSense_MPClientRuntime"
Support.assertTrue(MPClientRuntime.registerEvents(), "MP client runtime registration")
Support.assertEqual(snapshotRequestPlayer, nil, "MP runtime does not request state during load")
Support.assertTrue(MPClientRuntime.requestSnapshot(player, 0, nil), "explicit UI snapshot request")
Support.assertEqual(snapshotRequestPlayer, player, "MP snapshot request addresses the local player")
Support.assertFalse(MPClientRuntime.requestSnapshot(player, 0, nil), "pending request is not duplicated")
Support.assertEqual(snapshotRequestCalls, 1, "one client command while request is pending")

handlers.OnServerCommand("ArmorMakesSenseRuntime", "snapshot", { drivers = {}, updatedMinute = 10 })
local freshSent, freshStatus = MPClientRuntime.requestSnapshot(player, 30, nil)
Support.assertFalse(freshSent, "fresh snapshot does not request again")
Support.assertEqual(freshStatus, "fresh", "fresh snapshot status")
handlers.OnServerCommand("ArmorMakesSenseRuntime", "sleep_state", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})

Support.assertEqual(wakeCalls, 1, "authoritative snapshot invokes vanilla wake once")
Support.assertTrue(wakeSuppressPacket, "authoritative wake suppresses packet echo")
Support.assertFalse(asleep, "vanilla wake clears asleep state")
Support.assertClose(fatigue, 0.30, 1e-9, "wake snapshot applies authoritative fatigue")

asleep = true
fatigue = 0.30
handlers.OnServerCommand("ArmorMakesSenseRuntime", "sleep_state", {
    serverSleeping = false,
    reason = "minute",
    authoritativeFatigue = 0.20,
    drivers = {},
})
Support.assertEqual(wakeCalls, 1, "ordinary awake snapshot cannot cancel a locally-started sleep")
Support.assertTrue(asleep, "ordinary awake snapshot preserves local sleep transition")
Support.assertClose(fatigue, 0.30, 1e-9, "ordinary awake snapshot does not apply wake fatigue")

asleep = true
fatigue = 0.45
handlers.OnServerCommand("ArmorMakesSenseRuntime", "sleep_state", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})
Support.assertEqual(wakeCalls, 2, "wake correction handles a more-rested server state")
Support.assertClose(fatigue, 0.30, 1e-9, "wake snapshot may lower stale client fatigue")

sleepEnabled = false
asleep = true
fatigue = 0.20
handlers.OnServerCommand("ArmorMakesSenseRuntime", "sleep_state", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})
Support.assertEqual(wakeCalls, 2, "disabled sleep model does not reconcile wake")
Support.assertTrue(asleep, "disabled sleep model leaves vanilla state untouched")
Support.assertClose(fatigue, 0.20, 1e-9, "disabled sleep model does not apply fatigue")

sleepEnabled = true
cmsOwnsFatigue = true
handlers.OnServerCommand("ArmorMakesSenseRuntime", "sleep_state", {
    serverSleeping = false,
    reason = "WakeTransition",
    authoritativeFatigue = 0.30,
    drivers = {},
})
Support.assertEqual(wakeCalls, 2, "CMS-owned sleep does not use AMS wake reconciliation")
Support.assertTrue(asleep, "CMS-owned sleep leaves wake state to CMS")
Support.assertClose(fatigue, 0.20, 1e-9, "CMS-owned sleep ignores AMS fatigue authority")

print("ams multiplayer sleep wake checks passed")
