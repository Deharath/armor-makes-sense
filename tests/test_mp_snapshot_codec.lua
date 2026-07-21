local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local Codec = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_MPSnapshotCodec.lua")

local snapshot = {
    loadNorm = 1.25,
    physicalLoad = 34.5,
    thermalResistance = 0.82,
    airflowResistance = 3.75,
    sealedRestriction = 1,
    rigidityLoad = 44,
    driverCount = 4,
    effectiveLoad = 40.5,
    thermalContribution = 6,
    breathingContribution = 2.5,
    metabolicRate = 4.2,
    metabolicDemand = 6.9,
    metabolicNorm = 0.675,
    breathingEffortRamp = 0.63897705078125,
    breathingDynamicLoad = 4.792327880859375,
    breathingSealedLoad = 23.961639404296875,
    activityLabel = "sprint",
    hotPressure = 0.8,
    coldSuitability = 0.1,
    thermalStrainScale = 0.75,
    enduranceBeforeAms = 0.8,
    enduranceAfterAms = 0.77,
    enduranceNaturalDelta = -0.01,
    enduranceAppliedDelta = -0.03,
    lastAppliedDtMinutes = 1.5,
    catchupPendingMinutes = 0.25,
    updatedMinute = 1234.5,
    drivers = {
        { label = "Plate carrier", fullType = "Example.PlateCarrier", physical = 28 },
        { label = "Helmet", fullType = "Base.Hat_Army", physical = 4.2 },
    },
}

local encoded = Codec.encode(snapshot, {
    authoritativeFatigue = 0.42,
    serverSleeping = false,
    reason = "OnClothingUpdated",
}, true)

Support.assertEqual(encoded.snapshot_schema_version, Codec.SCHEMA_VERSION, "encoded schema version")
Support.assertEqual(encoded.activity_label, "sprint", "encoded activity")
Support.assertEqual(encoded.drivers[1].full_type, "Example.PlateCarrier", "encoded driver type")

local decoded, decodeError = Codec.decode(encoded)
Support.assertEqual(decodeError, nil, "round-trip decode error")
Support.assertEqual(decoded.schemaVersion, Codec.SCHEMA_VERSION, "decoded schema version")
Support.assertEqual(decoded.activityLabel, snapshot.activityLabel, "round-trip activity")
local numericFields = {
    "loadNorm",
    "physicalLoad",
    "thermalResistance",
    "airflowResistance",
    "sealedRestriction",
    "rigidityLoad",
    "driverCount",
    "effectiveLoad",
    "thermalContribution",
    "breathingContribution",
    "metabolicRate",
    "metabolicDemand",
    "metabolicNorm",
    "breathingEffortRamp",
    "breathingDynamicLoad",
    "breathingSealedLoad",
    "hotPressure",
    "coldSuitability",
    "thermalStrainScale",
    "enduranceBeforeAms",
    "enduranceAfterAms",
    "enduranceNaturalDelta",
    "enduranceAppliedDelta",
    "lastAppliedDtMinutes",
    "catchupPendingMinutes",
    "updatedMinute",
}
for i = 1, #numericFields do
    local field = numericFields[i]
    Support.assertClose(decoded[field], snapshot[field], 1e-9, "round-trip " .. field)
end
Support.assertClose(decoded.authoritativeFatigue, 0.42, 1e-9, "round-trip fatigue")
Support.assertFalse(decoded.serverSleeping, "round-trip sleeping state")
Support.assertEqual(decoded.reason, "OnClothingUpdated", "round-trip reason")
Support.assertEqual(decoded.drivers[2].fullType, "Base.Hat_Army", "round-trip driver type")
Support.assertClose(decoded.drivers[2].physical, 4.2, 1e-9, "round-trip driver load")

local lightweight = Codec.encode(snapshot, {}, false)
Support.assertEqual(#lightweight.drivers, 0, "lightweight driver omission")

local rejected, schemaError = Codec.decode({ snapshot_schema_version = 2 })
Support.assertEqual(rejected, nil, "old schema rejection")
Support.assertTrue(string.find(schemaError, "unsupported snapshot schema", 1, true) ~= nil, "schema rejection message")

print("ams mp snapshot codec characterization passed")
