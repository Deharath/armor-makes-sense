ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Combat = require "core/ArmorMakesSense_Combat"
local Tick = require "core/ArmorMakesSense_Tick"
local Utils = require "ArmorMakesSense_UtilsShared"

local Core = ArmorMakesSense.Core
Core.Runtime = Core.Runtime or {}

local Runtime = Core.Runtime
local startupCheckedStatic = false

local function hasFunction(target, name)
    return target and type(target[name]) == "function"
end

function Runtime.runStaticStartupChecks()
    if startupCheckedStatic then
        return not ClientRuntime.isDisabled()
    end
    startupCheckedStatic = true

    local issues = {}
    if not (Events and Events.EveryOneMinute and hasFunction(Events.EveryOneMinute, "Add")) then
        issues[#issues + 1] = "Events.EveryOneMinute.Add missing"
    end
    if not hasFunction(_G, "getPlayer") then
        issues[#issues + 1] = "global getPlayer missing"
    end
    if not (Events and Events.OnPlayerUpdate and hasFunction(Events.OnPlayerUpdate, "Add")) then
        ClientRuntime.logOnce("startup_no_player_update", "startup check: Events.OnPlayerUpdate.Add missing (sleep realtime tick disabled)")
    end

    if #issues > 0 then
        ClientRuntime.setDisabled(true)
        ClientRuntime.logError("startup check failed: " .. table.concat(issues, " | "))
        return false
    end
    return true
end

Runtime.runPlayerStartupChecks = ClientRuntime.runPlayerStartupChecks

function Runtime.onEveryOneMinute()
    if ClientRuntime.isDisabled() then
        return
    end
    ClientRuntime.forEachLocalPlayer(function(player)
        ClientRuntime.runGuarded("EveryOneMinute", Tick.tickPlayer, player)
    end)
end

function Runtime.onPlayerUpdate(playerObj)
    if ClientRuntime.isDisabled() then
        return
    end
    local player = playerObj or ClientRuntime.getLocalPlayer()
    if not ClientRuntime.isLocalPlayer(player) then
        return
    end

    -- Sleep can advance many game minutes between real-time minute ticks.
    if Utils.toBoolean(ClientRuntime.safeMethod(player, "isAsleep")) then
        ClientRuntime.runGuarded("OnPlayerUpdateSleepTick", Tick.tickPlayer, player)
    end
end

function Runtime.registerEvents(mod)
    local handlers = mod and mod._eventsRegisteredHandlers
    if handlers and type(handlers) == "table" then
        if Events and Events.EveryOneMinute and type(Events.EveryOneMinute.Remove) == "function" and handlers.onEveryOneMinute then
            pcall(Events.EveryOneMinute.Remove, handlers.onEveryOneMinute)
        end
        if Events and Events.OnPlayerAttackFinished and type(Events.OnPlayerAttackFinished.Remove) == "function" and handlers.onPlayerAttackFinished then
            pcall(Events.OnPlayerAttackFinished.Remove, handlers.onPlayerAttackFinished)
        end
        if Events and Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Remove) == "function" and handlers.onPlayerUpdate then
            pcall(Events.OnPlayerUpdate.Remove, handlers.onPlayerUpdate)
        end
    end

    ClientRuntime.log(string.format(
        "[BOOT] signature modVersion=%s scriptVersion=%s build=%s",
        ClientRuntime.getLoadedModVersion(),
        ClientRuntime.SCRIPT_VERSION,
        ClientRuntime.SCRIPT_BUILD
    ))
    ClientRuntime.log(string.format(
        "[BOOT_ROLE] role=singleplayer isClient=%s isServer=%s ingame=%s scriptVersion=%s build=%s",
        tostring(Utils.isClientSide()),
        tostring(Utils.isServerSide()),
        tostring(GameClient and GameClient.ingame or false),
        ClientRuntime.SCRIPT_VERSION,
        ClientRuntime.SCRIPT_BUILD
    ))

    Runtime.runStaticStartupChecks()
    if ClientRuntime.isDisabled() then
        ClientRuntime.logErrorOnce("boot_disabled", "runtime disabled by startup checks; event registration skipped")
        return false
    end
    if not Events then
        ClientRuntime.setDisabled(true)
        ClientRuntime.logError("Events table unavailable during boot; event registration skipped")
        return false
    end

    if Events.EveryOneMinute and type(Events.EveryOneMinute.Add) == "function" then
        Events.EveryOneMinute.Add(Runtime.onEveryOneMinute)
    else
        ClientRuntime.setDisabled(true)
        ClientRuntime.logError("Events.EveryOneMinute.Add unavailable during boot; runtime disabled")
        return false
    end
    if Events.OnPlayerAttackFinished and type(Events.OnPlayerAttackFinished.Add) == "function" then
        Events.OnPlayerAttackFinished.Add(Combat.onPlayerAttackFinished)
    else
        ClientRuntime.logOnce("no_attack_finished_event", "OnPlayerAttackFinished event not available; armor strain overlay disabled.")
    end
    if Events.OnPlayerUpdate and type(Events.OnPlayerUpdate.Add) == "function" then
        Events.OnPlayerUpdate.Add(Runtime.onPlayerUpdate)
        ClientRuntime.logOnce("per_frame_hooks_on", "OnPlayerUpdate hook enabled for realtime sleep ticks.")
    else
        ClientRuntime.logErrorOnce("no_player_update_hook", "OnPlayerUpdate unavailable; realtime sleep ticks disabled.")
    end

    if mod then
        mod._eventsRegistered = true
        mod._eventsRegisteredHandlers = {
            onEveryOneMinute = Runtime.onEveryOneMinute,
            onPlayerAttackFinished = Combat.onPlayerAttackFinished,
            onPlayerUpdate = Runtime.onPlayerUpdate,
        }
    end
    return true
end

return Runtime
