local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
local Codec = dofile(Support.SHARED_LUA .. "/ArmorMakesSense_MPSnapshotCodec.lua")

local snapshot = {
    burdenKg = 34.5,
    armKg = 6.2,
    rigidKg = 18,
    driverCount = 4,
    bodyKg = 72,
    strength = 7,
    loadFraction = 0.35,
    heat = 0.4,
    thermalResistance = 0.82,
    hotPressure = 0.8,
    coldSuitability = 0.1,
    airflowResistance = 3.75,
    sealedRestriction = 1,
    breathingSeverity = 1,
    breathingEnabled = true,
    restRegenScale = 0.8,
    standRegenScale = 0.7,
    walkRegenScale = -0.2,
    runDrainScale = 1.6,
    sprintDrainScale = 2.1,
    fightDrainScale = 1.3,
    sleepPenaltyFraction = 0.45,
    naturalDelta = -0.01,
    amsDelta = -0.006,
    regenScale = 0.5,
    drainScale = 1.6,
    nmsRegenScale = 0.9,
    nmsDrain = 0.001,
    dtMinutes = 1,
    updatedMinute = 1234,
    activityLabel = "sprint",
    postureLabel = "stand",
    drivers = {
        { label = "Plate carrier", fullType = "Example.PlateCarrier", burdenKg = 12 },
        { label = "Helmet", fullType = "Base.Hat_Army", burdenKg = 2.4 },
    },
}

local encoded = Codec.encode(snapshot)
Support.assertEqual(encoded.snapshot_schema_version, Codec.SCHEMA_VERSION, "encoded schema version")
Support.assertEqual(encoded.activity_label, "sprint", "encoded activity")
Support.assertEqual(encoded.drivers[1].full_type, "Example.PlateCarrier", "encoded driver type")
Support.assertClose(encoded.burden_kg, 34.5, 1e-9, "encoded wire key")

local decoded, decodeError = Codec.decode(encoded)
Support.assertEqual(decodeError, nil, "round-trip decode error")
Support.assertEqual(decoded.schemaVersion, Codec.SCHEMA_VERSION, "decoded schema version")
Support.assertEqual(decoded.source, "server_snapshot", "decoded source tag")
Support.assertTrue(decoded.breathingEnabled, "round-trip breathing toggle")
Support.assertEqual(decoded.activityLabel, "sprint", "round-trip activity")
Support.assertEqual(decoded.postureLabel, "stand", "round-trip posture")
for key, value in pairs(snapshot) do
    if type(value) == "number" then
        Support.assertClose(decoded[key], value, 1e-9, "round-trip " .. key)
    end
end
Support.assertEqual(#decoded.drivers, 2, "round-trip driver count")
Support.assertEqual(decoded.drivers[2].fullType, "Base.Hat_Army", "round-trip driver type")
Support.assertClose(decoded.drivers[2].burdenKg, 2.4, 1e-9, "round-trip driver burden")

local empty = Codec.decode(Codec.encode({}))
Support.assertClose(empty.bodyKg, 80, 1e-9, "default body mass")
Support.assertClose(empty.walkRegenScale, 1, 1e-9, "default scales are vanilla")
Support.assertEqual(empty.activityLabel, "idle", "default activity")
Support.assertFalse(empty.breathingEnabled, "default breathing flag")
Support.assertFalse(pcall(Codec.encode, nil), "encode rejects non-table")

local rejected, schemaError = Codec.decode({ snapshot_schema_version = 6 })
Support.assertEqual(rejected, nil, "old schema rejection")
Support.assertTrue(string.find(schemaError, "unsupported snapshot schema", 1, true) ~= nil, "schema rejection message")

print("ams mp snapshot codec characterization passed")
