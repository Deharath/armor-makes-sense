local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = ArmorMakesSense or {}
require "ArmorMakesSense_Config"
local View = require "core/ArmorMakesSense_BurdenView"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Policy = require "ArmorMakesSense_PresentationPolicy"

local P = View.PART

local function options(overrides)
    local out = {}
    for k, v in pairs(ArmorMakesSense.DEFAULTS) do
        out[k] = v
    end
    for k, v in pairs(overrides or {}) do
        out[k] = v
    end
    return out
end

local function runtime(fields)
    local r = {
        burdenKg = 0, loadFraction = 0, bodyKg = 80, strength = 5, armKg = 0, heat = 0,
        restRegenScale = 1, standRegenScale = 1, walkRegenScale = 1, runDrainScale = 1, sprintDrainScale = 1,
        breathingSeverity = 0, sleepPenaltyFraction = 0, coldSuitability = 0, thermalResistance = 0,
    }
    for k, v in pairs(fields or {}) do
        r[k] = v
    end
    return r
end

local function row(name, location, kg, extra)
    local out = { included = true, displayName = name, fullType = "Base." .. name, bodyLocation = location, burdenKg = kg }
    for k, v in pairs(extra or {}) do
        out[k] = v
    end
    return out
end

local function build(r, rows, opts, extra)
    local input = { runtime = r, analysis = { rows = rows or {} }, options = opts or options() }
    for k, v in pairs(extra or {}) do
        input[k] = v
    end
    return View.build(input)
end

-- Civilian clothes: nothing to report, everything reads as free.
local civ = build(runtime({ burdenKg = 1.2 }), { row("Tshirt", "Tshirt", 0.2), row("Shoes", "Shoes", 1.0) })
Support.assertEqual(civ.verdictTone, "good", "civilian verdict is good")
Support.assertEqual(civ.verdict, "Your gear costs you nothing extra.", "civilian verdict")
Support.assertEqual(#civ.items, 0, "no item stands out")
Support.assertEqual(civ.gearSummary, "Nothing you wear is heavy enough to stand out.", "all-light summary")
Support.assertEqual(civ.load.state, "Negligible", "negligible load")
Support.assertEqual(civ.load.tone, "dim", "0 pips reads dim")
Support.assertEqual(civ.load.detail, "Within the 3.5 kg that everyday clothing gets for free.", "allowance detail")
Support.assertEqual(civ.endurance.state, "Unaffected", "endurance unaffected")
Support.assertEqual(#civ.channelOrder, 4, "heat, breathing, melee, sleep rows")
Support.assertEqual(civ.tip, nil, "no tip when light")
Support.assertClose(civ.parts[P.Foot_L], 0.5, 1e-9, "shoes spread over both feet")
Support.assertClose(civ.parts[P.Foot_R], 0.5, 1e-9, "shoes spread over both feet (right)")

-- Too heavy to recover while walking beats every other verdict.
local heavy = build(runtime({
    burdenKg = 30, loadFraction = 0.4, walkRegenScale = -0.1, restRegenScale = 0.9, standRegenScale = 0.8,
    runDrainScale = 1.5, sprintDrainScale = 1.7, heat = 0.7,
}), { row("Cuirass", "TorsoExtraVest", 12, { rigidKg = 10 }), row("Greaves", "Calf_Left", 3) })
Support.assertEqual(heavy.verdictTone, "bad", "drains walking is bad")
Support.assertEqual(heavy.verdict, "Too heavy to recover endurance even at a walk.", "drain verdict wins")
Support.assertEqual(heavy.endurance.state, "Drains even walking", "endurance state")
local recovery, exertion = heavy.endurance.groups[1], heavy.endurance.groups[2]
Support.assertEqual(recovery.label, "Recovery", "recovery group")
Support.assertEqual(recovery.paces[2].value, "drains", "walking pace drains")
Support.assertEqual(recovery.paces[2].tone, "bad", "walking pace is bad")
Support.assertEqual(recovery.paces[1].value, "-20%", "standing recovery shown as percent")
Support.assertEqual(exertion.label, "Exertion", "exertion group")
Support.assertEqual(exertion.paces[2].value, "+70%", "sprint cost shown as percent")
Support.assertEqual(heavy.load.tone, "bad", "extreme load is bad")
Support.assertEqual(heavy.items[1].label, "Cuirass", "heaviest item first")
Support.assertEqual(heavy.items[1].channels.sleep, 10, "rigid plate feeds sleep")
Support.assertClose(heavy.channelParts.sleep[P.Torso_Upper], 5, 1e-9, "sleep map shows rigid kg")
Support.assertEqual(heavy.channelParts.melee[P.LowerLeg_L], nil, "greaves are not swing-chain")
Support.assertEqual(heavy.load.key, "load", "load row keyed")
Support.assertEqual(heavy.channels.sleep.key, "sleep", "channel rows keyed")
Support.assertClose(heavy.parts[P.LowerLeg_L], 3, 1e-9, "left-side location only loads the left calf")
Support.assertEqual(heavy.parts[P.LowerLeg_R], nil, "right calf untouched")

-- Heat outranks a heavy load.
local hot = build(runtime({ loadFraction = 0.15, heat = 0.5, burdenKg = 15 }), {})
Support.assertEqual(hot.verdict, "You are overheating in this gear.", "overheating verdict")
Support.assertEqual(hot.channels.heat.state, "Overheating", "heat state")

-- MP: gear is local, heat waits for the server.
local pending = build(runtime({ heat = 0.9 }), {}, nil, { heatPending = true })
Support.assertEqual(pending.channels.heat.state, "Waiting for server...", "heat pending state")
Support.assertEqual(pending.channels.heat.fill, 0, "pending heat shows empty")

-- Cold weather: insulation is good news.
local warm = build(runtime({ coldSuitability = 0.6 }), {})
Support.assertEqual(warm.channels.heat.tone, "good", "keeping warm is good")
Support.assertEqual(warm.verdict, "Your clothes are keeping you warm.", "keeping warm verdict")

-- Disabled channels disappear.
local minimal = build(runtime(), {}, options({
    EnableThermalModel = false, EnableBreathingModel = false, EnableSleepPenaltyModel = false,
}))
Support.assertEqual(#minimal.channelOrder, 1, "only melee remains")
Support.assertEqual(minimal.channelOrder[1], minimal.channels.melee, "melee row")
Support.assertEqual(minimal.channels.heat, nil, "heat row omitted")

-- Tip: the one item whose removal drops the tier most.
local opts = options()
local carrier = { bodyKg = 80, strength = 5 }
local lf = LoadModel.loadFraction(opts, 16, carrier)
local tipView = build(runtime({ burdenKg = 16, loadFraction = lf }), {
    row("Plate", "TorsoExtraVest", 9),
    row("Helmet", "Hat", 3),
    row("Boots", "Shoes", 2),
}, opts)
Support.assertTrue(tipView.load.pips >= 2, "tip fixture is at least moderate")
Support.assertTrue(tipView.tip ~= nil and tipView.tip:find("^Without the Plate: %a+ load%.$") ~= nil, "tip names the plate: " .. tostring(tipView.tip))
Support.assertEqual(tipView.gearSummary, nil, "no summary when every item is listed")

-- Covered parts: Back folds into the upper torso and duplicates collapse.
local covered = build(runtime(), { row("Pack", "TorsoExtra", 4) }, nil, {
    covered = function() return { 17, P.Torso_Upper } end,
})
Support.assertClose(covered.parts[P.Torso_Upper], 4, 1e-9, "back folds into upper torso")
Support.assertEqual(covered.parts[P.Torso_Lower], nil, "covered parts override the location fallback")

-- Location fallback.
local function partsOf(location)
    local set = {}
    for _, p in ipairs(View.partsForLocation(location)) do
        set[p] = true
    end
    return set
end
Support.assertTrue(partsOf("Hands").Hand_L == nil and partsOf("Hands")[P.Hand_L] and partsOf("Hands")[P.Hand_R], "hands")
Support.assertTrue(partsOf("LeftWrist")[P.Hand_L] and not partsOf("LeftWrist")[P.Hand_R], "left wrist")
Support.assertTrue(partsOf("Boilersuit")[P.LowerLeg_L] and partsOf("Boilersuit")[P.Torso_Upper], "full suit covers body and legs")
Support.assertTrue(partsOf("Mystery")[P.Torso_Upper] and partsOf("Mystery")[P.Torso_Lower], "unknown defaults to torso")

-- Summary counts lighter items.
local mixed = build(runtime(), { row("Vest", "TorsoExtraVest", 5), row("Cap", "Hat", 0.4), row("Socks", "Socks", 0.1) })
Support.assertEqual(mixed.gearSummary, "+ 2 lighter items, 0.5 kg together", "lighter summary")

-- Left/right pairs share one row; the tip weighs removing one piece.
local grouped = build(runtime(), {
    row("ShinArmor_L", "ShinLeft", 1.9, { displayName = "Shin Armor" }),
    row("ShinArmor_R", "ShinRight", 1.9, { displayName = "Shin Armor" }),
    row("Vest", "TorsoExtraVest", 3),
})
Support.assertEqual(#grouped.items, 2, "pair grouped")
Support.assertEqual(grouped.items[1].label, "Shin Armor", "group sorts by combined kg")
Support.assertEqual(grouped.items[1].countText, "x2", "count shown")
Support.assertEqual(grouped.items[1].value, "3.8 kg", "combined kg")
Support.assertClose(grouped.items[1].fill, Policy.fill(1.9, Policy.ITEM_BANDS_KG), 1e-9, "cells rate one piece")
Support.assertClose(grouped.items[1].parts[P.LowerLeg_L], 1.9, 1e-9, "left shin on the group map")
Support.assertClose(grouped.items[1].parts[P.LowerLeg_R], 1.9, 1e-9, "right shin on the group map")

-- B42 returns translations as Java format strings.
-- B42 formats translations in Java: arguments go through getText.
getText = function(key, ...)
    if key == "UI_AMS_Load_Carrier" then
        local a, b = ...
        return "Build " .. a .. " kg, Strength " .. b .. "."
    end
    return key
end
Support.assertEqual(View.tr("UI_AMS_Load_Carrier", "x", "80", "5"), "Build 80 kg, Strength 5.", "translated with arguments")
Support.assertEqual(View.tr("UI_AMS_Missing", "Swings %1 slower.", "3%"), "Swings 3% slower.", "fallback substitutes")
getText = nil

print("ams burden view checks passed")
