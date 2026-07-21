local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local Classifier = require "ArmorMakesSense_ArmorClassifier"
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

local civilianClassification = Classifier.evaluateArmorLike(civilian, nil, "Torso1")
Support.assertFalse(civilianClassification.isArmorLike, "light civilian item classification")

local plateClassification = Classifier.evaluateArmorLike(plateCarrier, nil, "TorsoExtra")
Support.assertTrue(plateClassification.isArmorLike, "plate carrier classification")
Support.assertClose(plateClassification.classifierDefenseScore, 59.5, 1e-9, "plate defense score")
local plateSignals = Classifier.computeArmorLikeSignals(plateCarrier, nil, "TorsoExtra")
local plateClassificationFromSignals = Classifier.evaluateArmorLikeSignals(plateSignals)
Support.assertEqual(
    plateClassificationFromSignals.isArmorLike,
    plateClassification.isArmorLike,
    "precomputed plate classification parity"
)
Support.assertClose(
    plateClassificationFromSignals.classifierDefenseScore,
    plateClassification.classifierDefenseScore,
    1e-9,
    "precomputed plate defense parity"
)

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

local civilianSignal = LoadModel.itemToBurdenSignal(civilian, "Torso1")
Support.assertClose(civilianSignal.physicalLoad, 1.6, 1e-9, "civilian physical load")
Support.assertEqual(civilianSignal.thermalLoad, nil, "item model does not infer thermal load")
Support.assertClose(civilianSignal.rigidityLoad, 2.5, 1e-9, "civilian rigidity")

local sparseWearable = Support.makeItem({
    fullType = "Example.SparseWearable",
    bodyLocation = "TorsoExtra",
    actualWeight = 0.5,
})
local sparseSignal = LoadModel.itemToBurdenSignal(sparseWearable, "TorsoExtra")
Support.assertClose(sparseSignal.physicalLoad, 1.6, 1e-9, "missing speed modifiers are neutral")

local patchedMovement = Support.makeItem({
    fullType = "Example.PatchedMovement",
    bodyLocation = "TorsoExtra",
    actualWeight = 0.5,
    runSpeedModifier = 0.80,
    combatSpeedModifier = 0.80,
})
ArmorMakesSense._originalRunSpeedModifier = { ["Example.PatchedMovement"] = 0.95 }
ArmorMakesSense._originalCombatSpeedModifier = { ["Example.PatchedMovement"] = 0.97 }
local originalMovementSignal = LoadModel.itemToBurdenSignal(patchedMovement, "TorsoExtra")
Support.assertClose(originalMovementSignal.physicalLoad, 4.42, 1e-9, "burden uses original movement modifiers")

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
Support.assertTrue(forcedContainerSignal.armorLike, "explicit armor category")
Support.assertEqual(forcedContainerSignal.inclusionReason, "forced_include", "explicit inclusion reason")
Support.assertEqual(forcedContainerSignal.classificationReason, "forced_armor", "explicit armor reason")

local forcedExclude = Support.makeItem({
    fullType = "Example.ExcludedWearable",
    bodyLocation = "TorsoExtra",
    tags = { "AMSExcludeBurden" },
    actualWeight = 2,
})
Support.assertEqual(LoadModel.itemToBurdenSignal(forcedExclude, "TorsoExtra"), nil, "explicit burden exclusion")

local classifierSignalCalls = 0
local computeArmorLikeSignals = Classifier.computeArmorLikeSignals
Classifier.computeArmorLikeSignals = function(...)
    classifierSignalCalls = classifierSignalCalls + 1
    return computeArmorLikeSignals(...)
end
local plateSignal = LoadModel.itemToBurdenSignal(plateCarrier, "TorsoExtra")
Classifier.computeArmorLikeSignals = computeArmorLikeSignals
Support.assertEqual(classifierSignalCalls, 1, "load model classifier signal pass count")
Support.assertClose(plateSignal.physicalLoad, 28, 1e-9, "plate physical clamp")
Support.assertClose(plateSignal.rigidityLoad, 53.7, 1e-9, "plate rigidity")

local maskSignal = LoadModel.itemToBurdenSignal(gasMaskNoFilter, "MaskFull")
Support.assertClose(maskSignal.physicalLoad, 0, 1e-9, "mask physical load")
Support.assertClose(maskSignal.airflowResistance, 1.35, 1e-9, "mask airflow resistance")
Support.assertClose(maskSignal.sealedRestriction, 0, 1e-9, "mask sealed restriction")
Support.assertClose(maskSignal.rigidityLoad, 5.1, 1e-9, "mask rigidity")

Support.assertEqual(LoadModel.itemToBurdenSignal(wearableContainer, "TorsoExtra"), nil, "wearable container exclusion")

local profile = LoadModel.computeWornProfile(Support.makePlayer({
    { item = civilian, location = "Torso1" },
    { item = plateCarrier, location = "TorsoExtra" },
    { item = gasMaskNoFilter, location = "MaskFull" },
    { item = unfamiliarSlot, location = "AlienLayer" },
    { item = wearableContainer, location = "TorsoExtra" },
}))

Support.assertClose(profile.physicalLoad, 36.8, 1e-9, "aggregate physical load")
Support.assertClose(profile.swingChainLoad, 0, 1e-9, "aggregate swing-chain load")
Support.assertEqual(profile.thermalLoad, nil, "worn profile has no inferred thermal load")
Support.assertClose(profile.airflowResistance, 1.35, 1e-9, "aggregate airflow resistance")
Support.assertClose(profile.sealedRestriction, 0, 1e-9, "aggregate sealed restriction")
Support.assertClose(profile.rigidityLoad, 60.4, 1e-9, "aggregate rigidity")
Support.assertEqual(profile.driverCount, 3, "aggregate load-driver count")
Support.assertClose(profile.weightUsedTotal, 6.7, 1e-9, "aggregate equipped weight")
Support.assertEqual(profile.fallbackWeightCount, 0, "aggregate weight fallbacks")

local analysis = LoadModel.analyzeWornGear(Support.makePlayer({
    { item = civilian, location = "Torso1" },
    { item = plateCarrier, location = "TorsoExtra" },
    { item = gasMaskNoFilter, location = "MaskFull" },
    { item = unfamiliarSlot, location = "AlienLayer" },
    { item = wearableContainer, location = "TorsoExtra" },
}))
Support.assertClose(analysis.profile.physicalLoad, profile.physicalLoad, 1e-9, "analysis profile parity")
Support.assertEqual(#analysis.rows, 5, "analysis worn rows")
Support.assertEqual(#analysis.costDrivers, 3, "analysis cost drivers")
Support.assertEqual(analysis.costDrivers[1].fullType, "Example.PlateCarrier", "top cost driver")
Support.assertEqual(analysis.costDrivers[1].label, "Plate carrier", "cost driver display name")
Support.assertEqual(analysis.rows[1].sourceMod, "ExampleMod", "analysis source mod")
Support.assertEqual(analysis.rows[5].fullType, "Example.ArmoredRig", "excluded item retained in rows")
Support.assertFalse(analysis.rows[5].included, "excluded row marker")
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
    "AlienLayer=Example.UtilityHarness;MaskFull=Base.Hat_GasMaskNoFilter;Torso1=Base.Tshirt_DefaultTEXTURE_TINT;TorsoExtra=Example.ArmoredRig;TorsoExtra=Example.PlateCarrier",
    "analysis equipment signature"
)
Support.assertEqual(analysis.wornCount, 5, "analysis worn count")

local stackedRespirators = LoadModel.computeWornProfile(Support.makePlayer({
    { item = respirator, location = "Mask" },
    { item = respirator, location = "MaskFull" },
}))
Support.assertClose(stackedRespirators.airflowResistance, 6.6, 1e-9, "stacked respirator airflow")
Support.assertClose(stackedRespirators.sealedRestriction, 0, 1e-9, "stacked respirators remain unsealed")

print("ams item model characterization passed")
