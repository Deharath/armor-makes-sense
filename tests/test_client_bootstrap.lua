local root = os.getenv("AMS_ROOT") or "."

local function loadBootstrap()
    ArmorMakesSense = nil
    package.loaded["core/ArmorMakesSense_Bootstrap"] = nil
    return dofile(root .. "/common/media/lua/client/core/ArmorMakesSense_Bootstrap.lua")
end

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function runCase(multiplayer)
    isClient = function()
        return multiplayer
    end

    local bootstrap = loadBootstrap()
    local calls = {
        singleplayer = 0,
        multiplayer = 0,
    }
    local mod = {}
    local singleplayerRuntime = {
        registerEvents = function(receivedMod)
            assertEqual(receivedMod, mod, "singleplayer mod")
            calls.singleplayer = calls.singleplayer + 1
            return true
        end,
    }
    local multiplayerRuntime = {
        registerEvents = function(receivedMod)
            assertEqual(receivedMod, mod, "multiplayer mod")
            calls.multiplayer = calls.multiplayer + 1
            return true
        end,
    }

    local registered, role = bootstrap.registerClientRuntime(
        mod,
        singleplayerRuntime,
        multiplayerRuntime
    )
    assertEqual(registered, true, "registration result")
    assertEqual(role, multiplayer and "multiplayer" or "singleplayer", "selected role")
    assertEqual(calls.singleplayer, multiplayer and 0 or 1, "singleplayer registrations")
    assertEqual(calls.multiplayer, multiplayer and 1 or 0, "multiplayer registrations")

    local repeated, repeatedRole = bootstrap.registerClientRuntime(
        mod,
        singleplayerRuntime,
        multiplayerRuntime
    )
    assertEqual(repeated, true, "repeat registration result")
    assertEqual(repeatedRole, role, "repeat selected role")
    assertEqual(calls.singleplayer + calls.multiplayer, 1, "total runtime registrations")
end

runCase(false)
runCase(true)

isClient = nil
local bootstrap = loadBootstrap()
local registered, role = bootstrap.registerClientRuntime({}, {}, {}, {})
assertEqual(registered, false, "missing role detector registration")
assertEqual(role, "unknown_role", "missing role detector failure")

print("ams client bootstrap checks passed")
