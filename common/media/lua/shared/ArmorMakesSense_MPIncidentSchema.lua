ArmorMakesSense = ArmorMakesSense or {}

ArmorMakesSense.MPIncidentSchema = ArmorMakesSense.MPIncidentSchema or {}

local Schema = ArmorMakesSense.MPIncidentSchema

Schema.TRACE_VERSION = 1
Schema.RING_SIZE = 60
Schema.PRE_TRIGGER_SLICES = 30
Schema.POST_TRIGGER_SLICES = 15

Schema.TRIGGERS = {
    DT_SPIKE = "dt_spike",
    PENDING_CATCHUP = "pending_catchup",
    SLICE_APPLIED_DROP = "slice_applied_drop",
    CUMULATIVE_APPLIED_DROP = "cumulative_applied_drop",
    NATURAL_DROP = "natural_drop",
}

Schema.THRESHOLDS = {
    DT_MINUTES = 1.0,
    PENDING_CATCHUP_MINUTES = 5.0,
    SLICE_APPLIED_DROP = -0.03,
    CUMULATIVE_APPLIED_DROP = -0.12,
    NATURAL_DROP = -0.15,
    NATURAL_DROP_APPLIED_GUARD = -0.01,
}

return Schema
