ArmorMakesSense = ArmorMakesSense or {}

-- Shared defaults. Sandbox options override the keys exposed in sandbox-options.txt.
ArmorMakesSense.DEFAULTS = {
    -- Sandbox channels.
    PhysicalLoadScale = 1.0,
    EnableThermalModel = true,
    EnableBreathingModel = true,
    EnableMuscleStrainModel = true,
    EnableSleepPenaltyModel = true,

    -- Burden: worn mass in effective kg. Each worn piece gets a small mass
    -- allowance so ordinary garments stay near zero; mass far from the trunk
    -- costs more per kg (see LoadModel placement table).
    BurdenItemMassAllowanceKg = 0.5,
    BurdenBulkPerRunPenalty = 6.0,
    BurdenBulkPerDiscomfort = 4.0,
    BurdenClothingAllowanceKg = 3.5,

    -- Load fraction = burden over body mass, scaled by Strength. The upper
    -- clamp stands in for lean mass: extra body fat does not carry armor.
    BodyMassMinKg = 50,
    BodyMassMaxKg = 90,
    StrengthFactorBase = 1.3,
    StrengthFactorPerLevel = 0.06,

    -- Endurance: AMS scales vanilla's own observed endurance change.
    -- Standing still under load slows recovery with the square of the load
    -- (never below zero); walking slows it linearly and can turn it into
    -- drain. Any endurance use costs one load share whatever the pace,
    -- because vanilla already charges faster paces more. Load is already
    -- trunk-equivalent kg (placement), so the share grows one to one with it
    -- plus a squared term: pieces stay cheap, full kits cost more. Minutes
    -- of melee without running pay CombatDrainShare of the load share.
    StandRegenLoadWeight = 1.0,
    WalkRegenLoadWeight = 2.0,
    WalkRegenFloor = -0.5,
    DrainLoadWeight = 1.0,
    DrainLoadCurveWeight = 1.0,
    CombatDrainShare = 0.5,

    -- Heat: insulation while overheating slows recovery and adds drain.
    ThermalRegenPenaltyMax = 0.5,
    ThermalDrainWeight = 0.25,

    -- Breathing: masks and sealed suits add drain at high exertion.
    BreathingEffortOnset = 0.20,
    BreathingDrainWeight = 0.35,

    -- Melee strain from armor on the swing chain (effective kg).
    MuscleStrainMaxExtra = 0.15,
    MuscleStrainArmKgStart = 1.0,
    MuscleStrainArmKgFull = 8.0,

    -- Sleep: rigid armor slows fatigue recovery while asleep.
    SleepPenaltyMax = 0.5,
    SleepPenaltyPerRigidKg = 0.025,

    -- Observed-delta steps longer than this are rebased instead of applied.
    MaxStepMinutes = 30,
}

return ArmorMakesSense.DEFAULTS
