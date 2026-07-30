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

local params = {}
local shoulder = {
    getFullType = function() return "Base.Shoulderpad_Articulated_L_Metal" end,
    getBodyLocation = function() return "base:shoulderpadleft" end,
    getDiscomfortModifier = function() return 0.1 end,
    getRunSpeedModifier = function() return 1.0 end,
    getCombatSpeedModifier = function() return 0.97 end,
    DoParam = function(_, ...)
        params[#params + 1] = { ... }
    end,
}
local emptyItems = {
    size = function() return 0 end,
}
ScriptManager = {
    instance = {
        getItem = function(_, fullType)
            if fullType == "Base.Shoulderpad_Articulated_L_Metal" then
                return shoulder
            end
            return nil
        end,
        getAllItems = function()
            return emptyItems
        end,
    },
}
handlers.OnGameBoot[1]()

local clearedTooltip = false
for _, call in ipairs(params) do
    if call[1] == "Tooltip" and call[2] == "" then
        clearedTooltip = true
        break
    end
end
Support.assertTrue(clearedTooltip, "shoulder reslot clears the obsolete script tooltip through DoParam")
next = luaNext

print("ams speed rebalance lifecycle checks passed")
