ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.MPSnapshotCodec = ArmorMakesSense.MPSnapshotCodec or {}

local Codec = ArmorMakesSense.MPSnapshotCodec

Codec.SCHEMA_VERSION = 7

local NUMBER_FIELDS = {
    { runtime = "burdenKg", wire = "burden_kg", default = 0 },
    { runtime = "armKg", wire = "arm_kg", default = 0 },
    { runtime = "rigidKg", wire = "rigid_kg", default = 0 },
    { runtime = "driverCount", wire = "driver_count", default = 0 },
    { runtime = "bodyKg", wire = "body_kg", default = 80 },
    { runtime = "strength", wire = "strength", default = 5 },
    { runtime = "loadFraction", wire = "load_fraction", default = 0 },
    { runtime = "heat", wire = "heat", default = 0 },
    { runtime = "thermalResistance", wire = "thermal_resistance", default = 0 },
    { runtime = "hotPressure", wire = "hot_pressure", default = 0 },
    { runtime = "coldSuitability", wire = "cold_suitability", default = 0 },
    { runtime = "airflowResistance", wire = "airflow_resistance", default = 0 },
    { runtime = "sealedRestriction", wire = "sealed_restriction", default = 0 },
    { runtime = "breathingSeverity", wire = "breathing_severity", default = 0 },
    { runtime = "restRegenScale", wire = "rest_regen_scale", default = 1 },
    { runtime = "standRegenScale", wire = "stand_regen_scale", default = 1 },
    { runtime = "walkRegenScale", wire = "walk_regen_scale", default = 1 },
    { runtime = "runDrainScale", wire = "run_drain_scale", default = 1 },
    { runtime = "sprintDrainScale", wire = "sprint_drain_scale", default = 1 },
    { runtime = "sleepPenaltyFraction", wire = "sleep_penalty_fraction", default = 0 },
    { runtime = "naturalDelta", wire = "natural_delta", default = 0 },
    { runtime = "amsDelta", wire = "ams_delta", default = 0 },
    { runtime = "regenScale", wire = "regen_scale", default = 1 },
    { runtime = "drainScale", wire = "drain_scale", default = 1 },
    { runtime = "nmsRegenScale", wire = "nms_regen_scale", default = 1 },
    { runtime = "nmsDrain", wire = "nms_drain", default = 0 },
    { runtime = "dtMinutes", wire = "dt_minutes", default = 0 },
    { runtime = "updatedMinute", wire = "updated_minute", default = 0 },
}

local STRING_FIELDS = {
    { runtime = "activityLabel", wire = "activity_label", default = "idle" },
    { runtime = "postureLabel", wire = "posture_label", default = "stand" },
}

local function encodeDrivers(drivers)
    local encoded = {}
    for i = 1, #(drivers or {}) do
        local row = drivers[i]
        if type(row) == "table" then
            encoded[#encoded + 1] = {
                label = tostring(row.label or "Unknown Item"),
                full_type = tostring(row.fullType or ""),
                burden_kg = tonumber(row.burdenKg) or 0,
            }
        end
    end
    return encoded
end

local function decodeDrivers(drivers)
    local decoded = {}
    for i = 1, #(drivers or {}) do
        local row = drivers[i]
        if type(row) == "table" then
            decoded[#decoded + 1] = {
                label = tostring(row.label or "Unknown Item"),
                fullType = tostring(row.full_type or ""),
                burdenKg = tonumber(row.burden_kg) or 0,
            }
        end
    end
    return decoded
end

function Codec.encode(snapshot)
    if type(snapshot) ~= "table" then
        error("snapshot must be a table", 2)
    end
    local encoded = {
        snapshot_schema_version = Codec.SCHEMA_VERSION,
        breathing_enabled = snapshot.breathingEnabled == true,
        drivers = encodeDrivers(snapshot.drivers),
    }
    for i = 1, #NUMBER_FIELDS do
        local field = NUMBER_FIELDS[i]
        encoded[field.wire] = tonumber(snapshot[field.runtime]) or field.default
    end
    for i = 1, #STRING_FIELDS do
        local field = STRING_FIELDS[i]
        encoded[field.wire] = tostring(snapshot[field.runtime] or field.default)
    end
    return encoded
end

function Codec.decode(payload)
    if type(payload) ~= "table" then
        return nil, "snapshot payload must be a table"
    end
    local schemaVersion = tonumber(payload.snapshot_schema_version)
    if schemaVersion ~= Codec.SCHEMA_VERSION then
        return nil, string.format(
            "unsupported snapshot schema version: expected %d got %s",
            Codec.SCHEMA_VERSION,
            tostring(payload.snapshot_schema_version)
        )
    end
    local decoded = {
        schemaVersion = schemaVersion,
        breathingEnabled = payload.breathing_enabled == true,
        drivers = decodeDrivers(payload.drivers),
        source = "server_snapshot",
    }
    for i = 1, #NUMBER_FIELDS do
        local field = NUMBER_FIELDS[i]
        decoded[field.runtime] = tonumber(payload[field.wire]) or field.default
    end
    for i = 1, #STRING_FIELDS do
        local field = STRING_FIELDS[i]
        decoded[field.runtime] = tostring(payload[field.wire] or field.default)
    end
    return decoded
end

return Codec
