local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local BreathingClassifier = require "ArmorMakesSense_BreathingClassifier"
local LoadModel = require "ArmorMakesSense_LoadModelShared"

local civilian = Support.makeItem({
    fullType = "Base.Tshirt_DefaultTEXTURE_TINT",
    type = "Tshirt_DefaultTEXTURE_TINT",
    bodyLocation = "Torso1",
    equippedWeight = 0.50,
    actualWeight = 0.50,
    scratchDefense = 0,
    biteDefense = 0,
    bulletDefense = 0,
    neckProtection = 0,
    discomfort = 0,
    insulation = 0.25,
    windResistance = 0.10,
    waterResistance = 0,
    runSpeedModifier = 1,
    combatSpeedModifier = 1,
})

local plateCarrier = Support.makeItem({
    fullType = "Example.PlateCarrier",
    type = "PlateCarrier",
    displayName = "Plate carrier",
    modId = "ExampleMod",
    bodyLocation = "TorsoExtra",
    displayCategory = "ProtectiveGear",
    tags = { "Bulletproof" },
    equippedWeight = 4.0,
    actualWeight = 5.0,
    scratchDefense = 40,
    biteDefense = 30,
    bulletDefense = 20,
    neckProtection = 0,
    discomfort = 0.25,
    insulation = 0.40,
    windResistance = 0.40,
    waterResistance = 0.20,
    runSpeedModifier = 0.85,
    combatSpeedModifier = 0.90,
})

local gasMaskNoFilter = Support.makeItem({
    fullType = "Base.Hat_GasMaskNoFilter",
    type = "Hat_GasMaskNoFilter",
    bodyLocation = "MaskFull",
    tags = { "GasMaskNoFilter" },
    equippedWeight = 1.0,
    actualWeight = 1.0,
    discomfort = 0.10,
    insulation = 0.20,
    windResistance = 0.20,
    runSpeedModifier = 1,
    combatSpeedModifier = 1,
})

local unfamiliarSlot = Support.makeItem({
    fullType = "Example.UtilityHarness",
    type = "UtilityHarness",
    bodyLocation = "AlienLayer",
    equippedWeight = 1.20,
    actualWeight = 1.20,
    discomfort = 0,
    insulation = 0,
    windResistance = 0,
    runSpeedModifier = 1,
    combatSpeedModifier = 1,
})

local wearableContainer = Support.makeItem({
    fullType = "Example.ArmoredRig",
    bodyLocation = "TorsoExtra",
    container = true,
    equippedWeight = 6,
    actualWeight = 6,
    bulletDefense = 100,
    runSpeedModifier = 0.80,
    combatSpeedModifier = 0.80,
})

-- Rigidity is vanilla's authored discomfort, not defense: a leather jacket
-- protects well but is fine to sleep in.
local leatherJacket = Support.makeItem({
    fullType = "Base.Jacket_Leather",
    bodyLocation = "Jacket",
    actualWeight = 2.0,
    scratchDefense = 50,
    biteDefense = 30,
    discomfort = 0,
})
local leatherSignal = LoadModel.itemToBurdenSignal(leatherJacket, "Jacket")
Support.assertFalse(leatherSignal.rigid, "protective clothing without discomfort is not rigid")
Support.assertClose(leatherSignal.rigidKg, 0, 1e-9, "leather jacket costs no sleep")
Support.assertTrue(LoadModel.itemToBurdenSignal(plateCarrier, "TorsoExtra").rigid, "authored discomfort marks rigid gear")

local respirator = Support.makeItem({
    fullType = "Example.Respirator",
    bodyLocation = "MaskFull",
    tags = { "Respirator" },
})
local respiratorSignals = BreathingClassifier.computeSignals(respirator, nil, "MaskFull")
Support.assertEqual(respiratorSignals.class, "respirator", "respirator class")
Support.assertTrue(respiratorSignals.hasFilter, "respirator filter")
Support.assertClose(respiratorSignals.airflowResistance, 3.30, 1e-9, "respirator airflow resistance")
Support.assertClose(respiratorSignals.sealedRestriction, 0, 1e-9, "respirator sealed restriction")

local filteredGasMask = Support.makeItem({
    fullType = "Example.FilteredGasMask",
    bodyLocation = "MaskFull",
    tags = { "GasMask" },
})
local filteredGasMaskSignals = BreathingClassifier.computeSignals(filteredGasMask, nil, "MaskFull")
Support.assertEqual(filteredGasMaskSignals.class, "sealed_mask", "filtered gas mask class")
Support.assertTrue(filteredGasMaskSignals.hasFilter, "filtered gas mask filter")
Support.assertClose(filteredGasMaskSignals.airflowResistance, 3.75, 1e-9, "filtered gas mask airflow resistance")
Support.assertClose(filteredGasMaskSignals.sealedRestriction, 1, 1e-9, "filtered gas mask sealed restriction")

local noFilterSignals = BreathingClassifier.computeSignals(gasMaskNoFilter, nil, "MaskFull")
Support.assertEqual(noFilterSignals.class, "sealed_mask", "no-filter gas mask class")
Support.assertFalse(noFilterSignals.hasFilter, "no-filter gas mask filter")
Support.assertClose(noFilterSignals.airflowResistance, 1.35, 1e-9, "no-filter gas mask airflow resistance")
Support.assertClose(noFilterSignals.sealedRestriction, 0, 1e-9, "no-filter gas mask sealed restriction")

local tagOnlyNoFilter = Support.makeItem({
    fullType = "Example.FilterHousing",
    bodyLocation = "MaskFull",
    tags = { "GasMaskNoFilter" },
})
local tagOnlyNoFilterSignals = BreathingClassifier.computeSignals(tagOnlyNoFilter, nil, "MaskFull")
Support.assertEqual(tagOnlyNoFilterSignals.class, "sealed_mask", "tag-only no-filter gas mask class")
Support.assertFalse(tagOnlyNoFilterSignals.hasFilter, "tag-only no-filter gas mask filter")
Support.assertClose(tagOnlyNoFilterSignals.airflowResistance, 1.35, 1e-9, "tag-only no-filter airflow resistance")
Support.assertClose(tagOnlyNoFilterSignals.sealedRestriction, 0, 1e-9, "tag-only no-filter sealed restriction")

local decorativeMask = Support.makeItem({
    fullType = "Example.CeremonialMask",
    bodyLocation = "MaskFull",
    tags = { "Cosmetic" },
})
local decorativeSignals = BreathingClassifier.computeSignals(decorativeMask, nil, "MaskFull")
Support.assertEqual(decorativeSignals.class, "face_covering", "decorative mask slot floor")
Support.assertClose(decorativeSignals.airflowResistance, 0, 1e-9, "decorative mask airflow resistance")

-- Placement, swing chain and sleep contact tables.
Support.assertClose(LoadModel.placementFactor("Shoes"), 2.0, 1e-9, "feet placement")
Support.assertClose(LoadModel.placementFactor("TorsoExtraVest"), 1.0, 1e-9, "trunk placement")
Support.assertClose(LoadModel.placementFactor("Hands"), 1.6, 1e-9, "hand placement")
Support.assertClose(LoadModel.placementFactor("Pants"), 1.4, 1e-9, "leg placement")
Support.assertClose(LoadModel.placementFactor("AlienLayer"), 1.0, 1e-9, "unknown slots count as trunk")
Support.assertTrue(LoadModel.isSwingChainLocation("ShoulderpadLeft"), "shoulder is swing chain")
Support.assertTrue(LoadModel.isSwingChainLocation("Hands"), "hands are swing chain")
Support.assertFalse(LoadModel.isSwingChainLocation("ShoulderHolster"), "holster is not swing chain")
Support.assertFalse(LoadModel.isSwingChainLocation("TorsoExtraVest"), "vest is not swing chain")
Support.assertClose(LoadModel.sleepContactWeight("MaskFull"), 0.0, 1e-9, "masks never press when sleeping")
Support.assertClose(LoadModel.sleepContactWeight("Knee_Left"), 0.4, 1e-9, "limb contact")
Support.assertClose(LoadModel.sleepContactWeight("Thigh_Left"), 0.7, 1e-9, "hip contact")
Support.assertClose(LoadModel.sleepContactWeight("TorsoExtraVest"), 1.0, 1e-9, "trunk contact")

-- burdenFromStats: (weight - allowance) * placement + bulk.
local burden, mass, placement, bulk = LoadModel.burdenFromStats(nil, 3.0, 0.5, 0.1, "Shoes")
Support.assertClose(mass, 2.5, 1e-9, "per-item mass allowance")
Support.assertClose(placement, 2.0, 1e-9, "stats placement")
Support.assertClose(bulk, 0.6 + 2.0, 1e-9, "bulk from run penalty and discomfort")
Support.assertClose(burden, 5.0 + 2.6, 1e-9, "burden from stats")
Support.assertClose(LoadModel.burdenFromStats(nil, 0.3, 0, 0, "Torso1"), 0, 1e-9, "light garments cost nothing")

local civilianSignal = LoadModel.itemToBurdenSignal(civilian, "Torso1")
Support.assertClose(civilianSignal.burdenKg, 0, 1e-9, "civilian burden")
Support.assertClose(civilianSignal.rigidKg, 0, 1e-9, "civilian clothing is not rigid")
Support.assertFalse(civilianSignal.swingChain, "civilian shirt swing chain")

local sparseWearable = Support.makeItem({
    fullType = "Example.SparseWearable",
    bodyLocation = "TorsoExtra",
    actualWeight = 0.5,
})
local sparseSignal = LoadModel.itemToBurdenSignal(sparseWearable, "TorsoExtra")
Support.assertClose(sparseSignal.burdenKg, 0, 1e-9, "missing speed modifiers are neutral")

local stiffHarness = Support.makeItem({
    fullType = "Example.StiffHarness",
    bodyLocation = "TorsoExtra",
    actualWeight = 0.5,
    runSpeedModifier = 0.80,
})
Support.assertClose(LoadModel.itemToBurdenSignal(stiffHarness, "TorsoExtra").bulkKg, 1.2, 1e-9, "run penalty adds bulk")

local heavyBoots = Support.makeItem({
    fullType = "Example.HeavyBoots",
    bodyLocation = "Shoes",
    actualWeight = 2.0,
    runSpeedModifier = 0.80,
})
local bootSignal = LoadModel.itemToBurdenSignal(heavyBoots, "Shoes")
Support.assertClose(bootSignal.bulkKg, 0, 1e-9, "footwear run modifiers are traction, not bulk")
Support.assertClose(bootSignal.burdenKg, 3.0, 1e-9, "footwear mass costs double")

-- Vanilla footwear all sits at the 1.0 kg script default; AMS authors pairs.
local function shoe(fullType)
    return LoadModel.itemToBurdenSignal(Support.makeItem({ fullType = fullType, bodyLocation = "Shoes", actualWeight = 1.0 }), "Shoes")
end
Support.assertClose(shoe("Base.Shoes_ArmyBoots").weightKg, 1.8, 1e-9, "army boots authored weight")
Support.assertClose(shoe("Base.Shoes_ArmyBoots").burdenKg, 2.6, 1e-9, "army boots burden")
Support.assertClose(shoe("Base.Shoes_TrainerTINT").burdenKg, 0.4, 1e-9, "trainers are light")
Support.assertClose(shoe("Base.Shoes_Slippers").burdenKg, 0, 1e-9, "slippers cost nothing")
Support.assertClose(shoe("Example.ModdedBoots").weightKg, 1.0, 1e-9, "modded footwear keeps its script weight")

ArmorMakesSense._originalDiscomfort = { ["Example.Rebalanced"] = 0.5 }
local rebalanced = Support.makeItem({
    fullType = "Example.Rebalanced",
    bodyLocation = "TorsoExtra",
    actualWeight = 0.5,
    discomfort = 0,
})
Support.assertClose(LoadModel.itemToBurdenSignal(rebalanced, "TorsoExtra").bulkKg, 2.0, 1e-9, "burden uses authored discomfort")
ArmorMakesSense._originalDiscomfort = nil

local forcedContainer = Support.makeItem({
    fullType = "Example.ForcedArmoredRig",
    bodyLocation = "TorsoExtra",
    container = true,
    tags = { "AMSIncludeBurden", "AMSArmor" },
    actualWeight = 2,
    runSpeedModifier = 1,
    combatSpeedModifier = 1,
})
local forcedContainerSignal = LoadModel.itemToBurdenSignal(forcedContainer, "TorsoExtra")
Support.assertTrue(forcedContainerSignal ~= nil, "explicit include accepts wearable container")
Support.assertTrue(forcedContainerSignal.rigid, "AMSArmor tag marks rigid gear")
Support.assertClose(forcedContainerSignal.rigidKg, 2.0, 1e-9, "forced armor rigid kg")
Support.assertEqual(forcedContainerSignal.inclusionReason, "forced_include", "explicit inclusion reason")

local forcedExclude = Support.makeItem({
    fullType = "Example.ExcludedWearable",
    bodyLocation = "TorsoExtra",
    tags = { "AMSExcludeBurden" },
    actualWeight = 2,
})
Support.assertEqual(LoadModel.itemToBurdenSignal(forcedExclude, "TorsoExtra"), nil, "explicit burden exclusion")

local cosmetic = Support.makeItem({
    fullType = "Example.Cape",
    bodyLocation = "Back",
    cosmetic = true,
    actualWeight = 3,
})
Support.assertEqual(LoadModel.itemToBurdenSignal(cosmetic, "Back"), nil, "cosmetic items carry no burden")

local classifierSignalCalls = 0
local computeSignals = BreathingClassifier.computeSignals
BreathingClassifier.computeSignals = function(...)
    classifierSignalCalls = classifierSignalCalls + 1
    return computeSignals(...)
end
LoadModel.clearSignalCache()
local plateSignal = LoadModel.itemToBurdenSignal(plateCarrier, "TorsoExtra")
LoadModel.itemToBurdenSignal(plateCarrier, "TorsoExtra")
BreathingClassifier.computeSignals = computeSignals
Support.assertEqual(classifierSignalCalls, 1, "item signals are cached per type")
Support.assertClose(plateSignal.massKg, 4.5, 1e-9, "plate mass")
Support.assertClose(plateSignal.bulkKg, 0.9 + 1.0, 1e-9, "plate bulk")
Support.assertClose(plateSignal.burdenKg, 6.4, 1e-9, "plate burden")
Support.assertClose(plateSignal.rigidKg, 5.0, 1e-9, "plate rigid kg on trunk")

local maskSignal = LoadModel.itemToBurdenSignal(gasMaskNoFilter, "MaskFull")
Support.assertClose(maskSignal.burdenKg, 1.0, 1e-9, "mask burden")
Support.assertClose(maskSignal.airflowResistance, 1.35, 1e-9, "mask airflow resistance")
Support.assertClose(maskSignal.sealedRestriction, 0, 1e-9, "mask sealed restriction")
Support.assertClose(maskSignal.rigidKg, 0, 1e-9, "masks add no sleep rigidity")

Support.assertEqual(LoadModel.itemToBurdenSignal(wearableContainer, "TorsoExtra"), nil, "wearable container exclusion")

local gauntlets = Support.makeItem({
    fullType = "Example.Gauntlets",
    bodyLocation = "Hands",
    actualWeight = 1.0,
})

local wornSet = {
    { item = civilian, location = "Torso1" },
    { item = plateCarrier, location = "TorsoExtra" },
    { item = gasMaskNoFilter, location = "MaskFull" },
    { item = unfamiliarSlot, location = "AlienLayer" },
    { item = wearableContainer, location = "TorsoExtra" },
    { item = gauntlets, location = "Hands" },
}
local profile = LoadModel.computeWornProfile(Support.makePlayer(wornSet))

Support.assertClose(profile.burdenKg, 6.4 + 1.0 + 0.7 + 0.8, 1e-9, "aggregate burden")
Support.assertClose(profile.massKg, 4.5 + 0.5 + 0.7 + 0.5, 1e-9, "aggregate mass")
Support.assertClose(profile.bulkKg, 1.9 + 0.4, 1e-9, "aggregate bulk")
Support.assertClose(profile.armKg, 0.8, 1e-9, "aggregate swing-chain burden")
Support.assertClose(profile.airflowResistance, 1.35, 1e-9, "aggregate airflow resistance")
Support.assertClose(profile.sealedRestriction, 0, 1e-9, "aggregate sealed restriction")
Support.assertEqual(profile.driverCount, 1, "default-weight items are not cost drivers")

local analysis = LoadModel.analyzeWornGear(Support.makePlayer(wornSet))
Support.assertClose(analysis.profile.burdenKg, profile.burdenKg, 1e-9, "analysis profile parity")
Support.assertEqual(#analysis.rows, 6, "analysis worn rows")
Support.assertEqual(#analysis.costDrivers, 1, "analysis cost drivers")
Support.assertEqual(analysis.costDrivers[1].fullType, "Example.PlateCarrier", "top cost driver")
Support.assertEqual(analysis.costDrivers[1].label, "Plate carrier", "cost driver display name")
Support.assertClose(analysis.costDrivers[1].burdenKg, 6.4, 1e-9, "cost driver burden")
Support.assertEqual(analysis.rows[1].sourceMod, "ExampleMod", "analysis source mod")
Support.assertEqual(analysis.rows[6].fullType, "Example.ArmoredRig", "excluded item retained in rows")
Support.assertFalse(analysis.rows[6].included, "excluded row marker")
local noFilterRow = nil
for i = 1, #analysis.rows do
    if analysis.rows[i].fullType == "Base.Hat_GasMaskNoFilter" then
        noFilterRow = analysis.rows[i]
        break
    end
end
Support.assertTrue(noFilterRow ~= nil, "no-filter mask row retained")
Support.assertFalse(noFilterRow.respiratoryHasFilter, "no-filter row preserves explicit false")
Support.assertEqual(
    analysis.equipmentSignature,
    "AlienLayer=Example.UtilityHarness;Hands=Example.Gauntlets;MaskFull=Base.Hat_GasMaskNoFilter;Torso1=Base.Tshirt_DefaultTEXTURE_TINT;TorsoExtra=Example.ArmoredRig;TorsoExtra=Example.PlateCarrier",
    "analysis equipment signature"
)
Support.assertEqual(analysis.wornCount, 6, "analysis worn count")

-- Carrier: burden relative to body mass and Strength.
Support.assertClose(LoadModel.loadFraction(nil, 3.5, { bodyKg = 80, strength = 5 }), 0, 1e-9, "clothing allowance")
Support.assertClose(LoadModel.loadFraction(nil, 13.5, { bodyKg = 80, strength = 5 }), 0.125, 1e-9, "average carrier")
Support.assertClose(LoadModel.loadFraction(nil, 13.5, { bodyKg = 80, strength = 10 }), 0.0875, 1e-9, "strong carrier")
Support.assertClose(LoadModel.loadFraction(nil, 13.5, { bodyKg = 50, strength = 5 }), 0.2, 1e-9, "light carrier")
Support.assertClose(
    LoadModel.loadFraction({ BurdenClothingAllowanceKg = 3, PhysicalLoadScale = 2, StrengthFactorBase = 1.3, StrengthFactorPerLevel = 0.06 }, 13.0, { bodyKg = 80, strength = 5 }),
    0.25,
    1e-9,
    "sandbox load scale"
)
local carrier = LoadModel.resolveCarrier({
    getNutrition = function()
        return { getWeight = function() return 200 end }
    end,
}, nil)
Support.assertClose(carrier.bodyKg, 90, 1e-9, "body mass clamps at lean-mass ceiling")
Support.assertClose(carrier.strength, 5, 1e-9, "default strength without perks")

local stackedRespirators = LoadModel.computeWornProfile(Support.makePlayer({
    { item = respirator, location = "Mask" },
    { item = respirator, location = "MaskFull" },
}))
Support.assertClose(stackedRespirators.airflowResistance, 6.6, 1e-9, "stacked respirator airflow")
Support.assertClose(stackedRespirators.sealedRestriction, 0, 1e-9, "stacked respirators remain unsealed")

print("ams item model characterization passed")
