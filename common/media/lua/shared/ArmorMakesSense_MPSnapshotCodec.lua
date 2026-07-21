ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.MPSnapshotCodec = ArmorMakesSense.MPSnapshotCodec or {}

local Codec = ArmorMakesSense.MPSnapshotCodec

Codec.SCHEMA_VERSION = 4

local NUMBER_FIELDS = {
    { runtime = "loadNorm", wire = "load_norm", default = 0 },
    { runtime = "physicalLoad", wire = "physical_load", default = 0 },
    { runtime = "thermalResistance", wire = "thermal_resistance", default = 0 },
    { runtime = "airflowResistance", wire = "airflow_resistance", default = 0 },
    { runtime = "sealedRestriction", wire = "sealed_restriction", default = 0 },
    { runtime = "rigidityLoad", wire = "rigidity_load", default = 0 },
    { runtime = "driverCount", wire = "driver_count", default = 0 },
    { runtime = "effectiveLoad", wire = "effective_load", default = 0 },
    { runtime = "thermalContribution", wire = "thermal_contribution", default = 0 },
    { runtime = "breathingContribution", wire = "breathing_contribution", default = 0 },
    { runtime = "metabolicRate", wire = "metabolic_rate", default = 1.5 },
    { runtime = "metabolicDemand", wire = "metabolic_demand", default = 1.5 },
    { runtime = "metabolicNorm", wire = "metabolic_norm", default = 0 },
    { runtime = "breathingEffortRamp", wire = "breathing_effort_ramp", default = 0 },
    { runtime = "breathingDynamicLoad", wire = "breathing_dynamic_load", default = 0 },
    { runtime = "breathingSealedLoad", wire = "breathing_sealed_load", default = 0 },
    { runtime = "hotPressure", wire = "hot_pressure", default = 0 },
    { runtime = "coldSuitability", wire = "cold_suitability", default = 0 },
    { runtime = "thermalStrainScale", wire = "thermal_strain_scale", default = 0 },
    { runtime = "enduranceBeforeAms", wire = "endurance_before_ams", default = 0 },
    { runtime = "enduranceAfterAms", wire = "endurance_after_ams", default = 0 },
    { runtime = "enduranceNaturalDelta", wire = "endurance_natural_delta", default = 0 },
    { runtime = "enduranceAppliedDelta", wire = "endurance_applied_delta", default = 0 },
    { runtime = "lastAppliedDtMinutes", wire = "last_applied_dt_minutes", default = 0 },
    { runtime = "catchupPendingMinutes", wire = "catchup_pending_minutes", default = 0 },
    { runtime = "updatedMinute", wire = "updated_minute", default = 0 },
}

local function toBoolean(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        local lowered = string.lower(value)
        return lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "on"
    end
    return false
end

local function encodeDrivers(drivers)
    local encoded = {}
    for i = 1, #(drivers or {}) do
        local row = drivers[i]
        if type(row) == "table" then
            encoded[#encoded + 1] = {
                label = tostring(row.label or "Unknown Item"),
                full_type = tostring(row.fullType or ""),
                physical = tonumber(row.physical) or 0,
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
                physical = tonumber(row.physical) or 0,
            }
        end
    end
    return decoded
end

function Codec.encode(snapshot, metadata, includeDrivers)
    if type(snapshot) ~= "table" then
        error("snapshot must be a table", 2)
    end

    local resolvedMetadata = type(metadata) == "table" and metadata or {}
    local encoded = {
        snapshot_schema_version = Codec.SCHEMA_VERSION,
        activity_label = tostring(snapshot.activityLabel or "idle"),
        fatigue = tonumber(resolvedMetadata.authoritativeFatigue) or 0,
        server_sleeping = resolvedMetadata.serverSleeping == true,
        reason = tostring(resolvedMetadata.reason or "tick"),
        drivers = includeDrivers == false and {} or encodeDrivers(snapshot.drivers),
    }

    for i = 1, #NUMBER_FIELDS do
        local field = NUMBER_FIELDS[i]
        encoded[field.wire] = tonumber(snapshot[field.runtime]) or field.default
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
        activityLabel = tostring(payload.activity_label or "idle"),
        drivers = decodeDrivers(payload.drivers),
        authoritativeFatigue = tonumber(payload.fatigue),
        serverSleeping = toBoolean(payload.server_sleeping),
        reason = tostring(payload.reason or ""),
        source = "server_snapshot",
    }

    for i = 1, #NUMBER_FIELDS do
        local field = NUMBER_FIELDS[i]
        decoded[field.runtime] = tonumber(payload[field.wire]) or field.default
    end

    return decoded
end

return Codec
