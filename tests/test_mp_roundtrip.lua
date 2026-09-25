local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

-- Server tick, snapshot request, wire payload, client decode and the MP
-- Burden-tab projection, wired end to end with the real runtimes.

ArmorMakesSense = {}
GameClient = nil
GameServer = nil

local nowMinutes = 1000
local wallSeconds = 100
getGameTime = function()
    return { getWorldAgeHours = function() return nowMinutes / 60 end }
end
getTimestamp = function() return wallSeconds end
getTimestampMs = function() return wallSeconds * 1000 end

local handlers = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local event = {
            Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
            Remove = function(fn)
                for i, h in ipairs(handlers[name] or {}) do
                    if h == fn then table.remove(handlers[name], i) break end
                end
            end,
        }
        rawset(t, name, event)
        return event
    end,
})
local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do
        fn(...)
    end
end

local vest = Support.makeItem({
    fullType = "Base.Vest_BulletArmy", type = "Vest_BulletArmy", displayName = "Military Vest",
    bodyLocation = "TorsoExtraVestBullet", actualWeight = 6.5, equippedWeight = 6.5, discomfort = 0.2, insulation = 0.3,
})
local helmet = Support.makeItem({
    fullType = "Base.Hat_Army", type = "Hat_Army", displayName = "Army Helmet",
    bodyLocation = "Hat", actualWeight = 2.0, equippedWeight = 2.0, discomfort = 0.1,
})
local function makeMpPlayer()
    local endurance, fatigue = 0.8, 0.5
    local p = Support.makePlayer({
        { item = vest, location = "TorsoExtraVestBullet" },
        { item = helmet, location = "Hat" },
    }, { moving = false, asleep = false, modData = {} })
    function p:getModData() return self.modData end
    function p:isAsleep() return self.asleep end
    function p:isPlayerMoving() return self.moving end
    function p:getOnlineID() return 7 end
    function p:getUsername() return "tester" end
    function p:isLocalPlayer() return true end
    function p:getPerkLevel() return 5 end
    function p:getNutrition() return { getWeight = function() return 80 end } end
    function p:getStats()
        return {
            getEndurance = function() return endurance end,
            setEndurance = function(_, v) endurance = v end,
            getFatigue = function() return fatigue end,
            setFatigue = function(_, v) fatigue = v end,
        }
    end
    p.readEndurance = function() return endurance end
    p.writeEndurance = function(v) endurance = v end
    p.readFatigue = function() return fatigue end
    p.writeFatigue = function(v) fatigue = v end
    return p
end

-- ---------------------------------------------------------------- server
local serverPlayer = makeMpPlayer()
isServer = function() return true end
isClient = function() return false end
getOnlinePlayers = function()
    return { size = function() return 1 end, get = function() return serverPlayer end }
end
local sent = {}
sendServerCommand = function(playerObj, module, command, args)
    sent[#sent + 1] = { player = playerObj, module = module, command = command, args = args }
end
local syncs = 0
syncPlayerStats = function(_, mask)
    Support.assertEqual(mask, 16, "fatigue stat mask")
    syncs = syncs + 1
end

dofile(Support.ROOT .. "/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua")
Support.assertTrue(ArmorMakesSense._mpServerRuntimeRegistered, "server runtime registered")
Support.assertTrue(handlers.EveryOneMinute and #handlers.EveryOneMinute == 1, "server minute tick registered")

local RuntimeState = require "ArmorMakesSense_RuntimeState"
local MP = require "ArmorMakesSense_MPCompat"

fire("EveryOneMinute")
local mpState = RuntimeState.peek(serverPlayer, RuntimeState.ROLE_MP_SERVER).mpServer
Support.assertTrue(type(mpState.runtimeSnapshot) == "table", "server tick builds a snapshot")
Support.assertTrue(mpState.runtimeSnapshot.burdenKg > 8, "server sees worn burden")
Support.assertTrue(#mpState.runtimeSnapshot.drivers >= 2, "server snapshot carries drivers")
Support.assertEqual(#sent, 0, "no snapshot sent without a request")

-- Walking tick: server scales vanilla recovery.
serverPlayer.moving = true
nowMinutes = nowMinutes + 1
serverPlayer.writeEndurance(0.81)
fire("EveryOneMinute")
Support.assertTrue(serverPlayer.readEndurance() < 0.81, "server applies walking recovery penalty")
Support.assertTrue(serverPlayer.readEndurance() > 0.80, "walking penalty only trims recovery")

-- Sleeping in rigid armor: extra fatigue written and synced.
serverPlayer.moving = false
serverPlayer.asleep = true
nowMinutes = nowMinutes + 1
fire("EveryOneMinute")
nowMinutes = nowMinutes + 1
serverPlayer.writeFatigue(0.49)
fire("EveryOneMinute")
Support.assertTrue(serverPlayer.readFatigue() > 0.49, "sleep penalty gives back part of recovery")
Support.assertEqual(syncs, 1, "fatigue synced once after penalty write")
serverPlayer.asleep = false

-- Client request: server refreshes and flushes one snapshot.
fire("OnClientCommand", MP.NET_MODULE, MP.REQUEST_SNAPSHOT_COMMAND, serverPlayer, {})
Support.assertEqual(#sent, 1, "snapshot sent on request")
Support.assertEqual(sent[1].module, MP.NET_MODULE, "snapshot module")
Support.assertEqual(sent[1].command, MP.SNAPSHOT_COMMAND, "snapshot command")
Support.assertEqual(sent[1].args.player_online_id, 7, "snapshot addressed to player")
fire("OnClientCommand", MP.NET_MODULE, MP.REQUEST_SNAPSHOT_COMMAND, serverPlayer, {})
Support.assertEqual(#sent, 1, "request throttled")

-- The payload must survive Kahlua's table transport: only plain values.
local function assertPlain(value, path)
    local kind = type(value)
    if kind == "table" then
        for k, v in pairs(value) do
            Support.assertTrue(type(k) == "string" or type(k) == "number", path .. " key type")
            assertPlain(v, path .. "." .. tostring(k))
        end
    else
        Support.assertTrue(kind == "number" or kind == "string" or kind == "boolean", path .. " plain value")
    end
end
assertPlain(sent[1].args, "payload")

-- ---------------------------------------------------------------- client
local clientPlayer = makeMpPlayer()
isServer = function() return false end
isClient = function() return true end
sendClientCommand = function() end
getPlayer = function() return clientPlayer end
getSpecificPlayer = function(i) return i == 0 and clientPlayer or nil end
getNumActivePlayers = function() return 1 end
package.loaded["core/ArmorMakesSense_UI"] = { markDirty = function() end, update = function() end }

local MPClientRuntime = dofile(Support.ROOT .. "/common/media/lua/client/ArmorMakesSense_MPClientRuntime.lua")
Support.assertTrue(MPClientRuntime.registerEvents({}), "client runtime registered")

fire("OnServerCommand", sent[1].module, sent[1].command, sent[1].args)
local clientState = RuntimeState.peek(clientPlayer, RuntimeState.ROLE_MP_CLIENT)
local snap = clientState and clientState.mpServerSnapshot
Support.assertTrue(type(snap) == "table", "client stored server snapshot")
Support.assertClose(snap.burdenKg, mpState.runtimeSnapshot.burdenKg, 1e-9, "burden survives the wire")
Support.assertEqual(#snap.drivers, #mpState.runtimeSnapshot.drivers, "drivers survive the wire")

local Physiology = require "ArmorMakesSense_PhysiologyShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
Support.assertEqual(ClientRuntime.ensureState(clientPlayer), clientState, "UI reads the MP client state")
local options = Options.get()
local analysis = LoadModel.analyzeWornGear(clientPlayer, options)
local runtime = Physiology.projectWithServerThermal(clientPlayer, options, analysis.profile, Physiology.getUiRuntimeSnapshot(clientState))
Support.assertClose(runtime.burdenKg, snap.burdenKg, 1e-9, "client gear matches server gear")
Support.assertClose(runtime.loadFraction, snap.loadFraction, 1e-9, "client load matches server load")

print("ams mp roundtrip checks passed")
