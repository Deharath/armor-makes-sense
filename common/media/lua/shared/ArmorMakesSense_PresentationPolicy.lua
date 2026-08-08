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
Policy.THERMAL_PRESSURE_VISIBLE_MIN = 0.25
Policy.ACTIVE_PRESSURE_EPSILON = 0.0001

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

function Policy.recoveryPenaltyPercent(regenScale, naturalDelta)
    if (tonumber(naturalDelta) or 0) <= 0 then
        return 0
    end
    local scale = math.max(0, math.min(1, tonumber(regenScale) or 1))
    return (1 - scale) * 100
end

function Policy.drainPercentPerMinute(drainApplied, elapsedMinutes)
    local elapsed = math.max(0, tonumber(elapsedMinutes) or 0)
    if elapsed <= 0 then
        return 0
    end
    return (math.max(0, tonumber(drainApplied) or 0) / elapsed) * 100
end

function Policy.sleepPenaltyPercent(penaltyFraction, enabled)
    if enabled ~= true then
        return 0
    end
    local fraction = math.max(0, math.min(0.95, tonumber(penaltyFraction) or 0))
    return fraction * 100
end

function Policy.snapshotAgeMinutes(currentMinute, updatedMinute)
    local current = tonumber(currentMinute)
    local updated = tonumber(updatedMinute)
    if current == nil or updated == nil then
        return nil
    end
    return math.max(0, current - updated)
end

function Policy.hasThermalPressure(contribution)
    return (tonumber(contribution) or 0) >= Policy.THERMAL_PRESSURE_VISIBLE_MIN
end

function Policy.hasBreathingPressure(contribution)
    return (tonumber(contribution) or 0) > Policy.ACTIVE_PRESSURE_EPSILON
end

function Policy.hasSleepPressure(penaltyFraction, enabled)
    return enabled == true
        and (tonumber(penaltyFraction) or 0) > Policy.ACTIVE_PRESSURE_EPSILON
end

function Policy.hasSleepRestriction(rigidityLoad)
    return (tonumber(rigidityLoad) or 0) >= Policy.SLEEP_RIGIDITY_THRESHOLD
end

return Policy
