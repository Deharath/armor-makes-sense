local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")
local root = os.getenv("AMS_ROOT") or "."

ArmorMakesSense = {}
package.loaded["ArmorMakesSense_SlotCompat"] = true
ScriptManager = nil

local handlers = {}
local function event(name)
    handlers[name] = {}
    return {
        Add = function(callback)
            handlers[name][#handlers[name] + 1] = callback
        end,
        Remove = function(callback)
            for i = #handlers[name], 1, -1 do
                if handlers[name][i] == callback then
                    table.remove(handlers[name], i)
                end
            end
        end,
    }
end

Events = {
    OnGameBoot = event("OnGameBoot"),
    OnMainMenuEnter = event("OnMainMenuEnter"),
    OnGameStart = event("OnGameStart"),
}

local luaNext = next
next = nil
local first = dofile(root .. "/common/media/lua/shared/ArmorMakesSense_SpeedRebalance.lua")
Support.assertTrue(ArmorMakesSense._speedRebalanceLoaded, "speed lifecycle marks registered handlers")
Support.assertEqual(#handlers.OnGameBoot, 1, "speed boot handler registered once")
Support.assertEqual(#handlers.OnMainMenuEnter, 1, "speed menu handler registered once")
Support.assertEqual(#handlers.OnGameStart, 1, "speed game handler registered once")

local reloaded = dofile(root .. "/common/media/lua/shared/ArmorMakesSense_SpeedRebalance.lua")
Support.assertEqual(reloaded, first, "speed module preserves its public table on reload")
Support.assertEqual(#handlers.OnGameBoot, 1, "speed boot handler replaced on reload")
Support.assertEqual(#handlers.OnMainMenuEnter, 1, "speed menu handler replaced on reload")
Support.assertEqual(#handlers.OnGameStart, 1, "speed game handler replaced on reload")
next = luaNext

print("ams speed rebalance lifecycle checks passed")
