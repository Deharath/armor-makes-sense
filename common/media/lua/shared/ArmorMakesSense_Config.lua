ArmorMakesSense = ArmorMakesSense or {}

-- Shared defaults used by both client and shared modules.
ArmorMakesSense.DEFAULTS = {
    -- Armor load -> endurance pressure.
    ArmorLoadMin = 5.0,
    BaseEnduranceDrainPerMinute = 0.0033,
    EnduranceRegenPenalty = 0.45,

    -- Secondary physical effects.
    EnableThermalModel = true,
    EnableMuscleStrainModel = true,
    EnableSleepPenaltyModel = true,
    MuscleStrainMaxExtra = 0.15,
    MuscleStrainLoadStart = 3.0,
    MuscleStrainLoadFull = 22.0,
    ThermalContributionMax = 14.0,

    -- Vanilla rate plus immediate native movement floors. Brisk walking stays
    -- free; modest equivalent-load weights avoid exaggerating mask performance.
    BreathingEffortOnset = 0.20,
    BreathingDynamicLoadWeight = 0.70,
    BreathingSealedDynamicLoadWeight = 1.00,

    -- Sleep-in-armor continuous fatigue recovery slowdown.
    SleepRigidityFatigueRate = 0.0045,

    -- Activity bands.
    ActivityIdle = 0.35,
    ActivityWalk = 0.75,
    ActivityJog = 1.00,
    ActivitySprint = 1.35,

    DtMaxMinutes = 3,
    DtCatchupMaxSlices = 240,
}

return ArmorMakesSense.DEFAULTS
