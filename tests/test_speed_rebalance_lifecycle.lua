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

-- Single combat-speed rule: swing-chain burden only, capped.
local Speed = ArmorMakesSense.SpeedRebalance
Support.assertClose(Speed.combatSpeedModifier("base:torso1", 10), 1.0, 1e-9, "torso armor keeps full combat speed")
Support.assertClose(Speed.combatSpeedModifier("base:shoulderholster", 10), 1.0, 1e-9, "holster is not swing-chain armor")
Support.assertClose(Speed.combatSpeedModifier("base:forearm_left", 2), 0.98, 1e-9, "forearm burden slows swings")
Support.assertClose(Speed.combatSpeedModifier("base:elbow_right", 50), 1.0 - Speed.COMBAT_PENALTY_MAX, 1e-9, "combat penalty cap")
Support.assertClose(Speed.combatSpeedModifier("base:hands", 0), 1.0, 1e-9, "weightless gloves cost nothing")

local function wearable(fullName, location, weight, discomfort)
    local item = { calls = {}, discomfort = discomfort }
    function item:getFullName() return fullName end
    function item:getBodyLocation() return location end
    function item:getActualWeight() return weight end
    function item:getDiscomfortModifier() return self.discomfort end
    function item:isCosmetic() return false end
    function item:DoParam(param)
        self.calls[#self.calls + 1] = param
        if param == "DiscomfortModifier = 0.00" then
            self.discomfort = 0
        end
    end
    return item
end
local bracer = wearable("Base.Vambrace_Test", "base:forearm_left", 2.5, 0.2)
local vest = wearable("Base.Vest_Test", "base:torsoextravest", 4.0, 0.1)
local worn = { bracer, vest }
ScriptManager.instance.getAllItems = function()
    return { size = function() return #worn end, get = function(_, i) return worn[i + 1] end }
end
ArmorMakesSense._originalDiscomfort = {}
handlers.OnGameBoot[1]()
local function paramStartingWith(item, prefix)
    for _, call in ipairs(item.calls) do
        if string.sub(call, 1, #prefix) == prefix then
            return call
        end
    end
end
local bracerCombat = tonumber(string.match(paramStartingWith(bracer, "CombatSpeedModifier") or "", "([%d%.]+)$"))
Support.assertTrue(bracerCombat and bracerCombat < 1 and bracerCombat >= 0.95, "vambrace gets a small combat penalty")
Support.assertEqual(paramStartingWith(vest, "CombatSpeedModifier"), "CombatSpeedModifier = 1.00", "vest keeps full combat speed")
Support.assertEqual(paramStartingWith(bracer, "DiscomfortModifier"), "DiscomfortModifier = 0.00", "vanilla discomfort is zeroed")
Support.assertClose(ArmorMakesSense._originalDiscomfort["Base.Vambrace_Test"], 0.2, 1e-9, "original discomfort cached")
bracer.calls = {}
handlers.OnGameBoot[1]()
Support.assertClose(ArmorMakesSense._originalDiscomfort["Base.Vambrace_Test"], 0.2, 1e-9, "re-apply keeps the original discomfort")
Support.assertEqual(
    tonumber(string.match(paramStartingWith(bracer, "CombatSpeedModifier") or "", "([%d%.]+)$")),
    bracerCombat,
    "re-apply is idempotent"
)
next = luaNext

print("ams speed rebalance lifecycle checks passed")
