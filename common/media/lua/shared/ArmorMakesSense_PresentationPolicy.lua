ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.PresentationPolicy = ArmorMakesSense.PresentationPolicy or {}

local Policy = ArmorMakesSense.PresentationPolicy

Policy.BURDEN_THRESHOLDS = {
    light = 7,
    moderate = 20,
    heavy = 45,
    extreme = 75,
}

Policy.BREATHING_THRESHOLDS = {
    visible = 0.80,
    restricted = 2.00,
}

Policy.SLEEP_RIGIDITY_THRESHOLD = 10

function Policy.burdenTier(physicalLoad)
    local value = tonumber(physicalLoad) or 0
    if value < Policy.BURDEN_THRESHOLDS.light then
        return "negligible"
    end
    if value < Policy.BURDEN_THRESHOLDS.moderate then
        return "light"
    end
    if value < Policy.BURDEN_THRESHOLDS.heavy then
        return "moderate"
    end
    if value < Policy.BURDEN_THRESHOLDS.extreme then
        return "heavy"
    end
    return "extreme"
end

function Policy.breathingTier(airflowResistance, sealedRestriction)
    local resistance = tonumber(airflowResistance) or 0
    if resistance < Policy.BREATHING_THRESHOLDS.visible then
        return nil
    end
    if (tonumber(sealedRestriction) or 0) > 0 then
        return "heavy"
    end
    if resistance < Policy.BREATHING_THRESHOLDS.restricted then
        return "mild"
    end
    return "restricted"
end

function Policy.hasSleepRestriction(rigidityLoad)
    return (tonumber(rigidityLoad) or 0) >= Policy.SLEEP_RIGIDITY_THRESHOLD
end

return Policy
