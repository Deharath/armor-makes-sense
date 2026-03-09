ArmorMakesSense = ArmorMakesSense or {}

-- Shared defaults used by both client and shared modules.
ArmorMakesSense.DEFAULTS = {
    -- Armor load -> endurance pressure.
    ArmorLoadMin = 5.0,
    BaseEnduranceDrainPerMinute = 0.0033,
    EnduranceRegenPenalty = 0.45,

    -- Environment amplifiers are intentionally mild to avoid double-counting vanilla thermal systems.
    HeatAmplifierStrength = 0.25,
    WetAmplifierStrength = 0.18,

    -- Secondary physical effects.
    EnableThermalModel = true,
    EnableMuscleStrainModel = true,
    EnableSleepPenaltyModel = true,
    MuscleStrainMaxExtra = 0.15,
    MuscleStrainLoadStart = 3.0,
    MuscleStrainLoadFull = 22.0,
    ThermalEnduranceWeight = 0.35,

    -- Breathing restriction is intensity-thresholded: near invisible at low effort,
    -- then ramps with ventilation demand (sealed masks ramp steeper).
    BreathingDemandThreshold = 0.52,
    BreathingCombatDemandFloor = 0.50,
    BreathingPenaltyLoadStart = 1.20,
    BreathingPenaltyLoadSpan = 2.20,
    BreathingSealLoadStart = 3.45,
    BreathingSealLoadSpan = 0.20,
    BreathingReliefMaxLoad = 3.30,
    BreathingStaticReliefWeight = 0.25,
    BreathingDynamicLoadWeight = 5.10,
    BreathingSealedDynamicLoadWeight = 29.00,

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
