ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.MPSnapshotBuilder = ArmorMakesSense.MPSnapshotBuilder or {}

local Builder = ArmorMakesSense.MPSnapshotBuilder

function Builder.build(mpState, profile, drivers, activityLabel, currentMinute)
    local state = type(mpState) == "table" and mpState or {}
    local wornProfile = type(profile) == "table" and profile or {}
    local uiSnapshot = type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or {}

    return {
        loadNorm = tonumber(uiSnapshot.loadNorm) or 0,
        physicalLoad = tonumber(wornProfile.physicalLoad) or 0,
        thermalResistance = tonumber(uiSnapshot.thermalResistance) or 0,
        airflowResistance = tonumber(wornProfile.airflowResistance) or 0,
        sealedRestriction = tonumber(wornProfile.sealedRestriction) or 0,
        rigidityLoad = tonumber(wornProfile.rigidityLoad) or 0,
        driverCount = tonumber(wornProfile.driverCount) or 0,
        effectiveLoad = tonumber(uiSnapshot.effectiveLoad) or tonumber(wornProfile.physicalLoad) or 0,
        thermalContribution = tonumber(uiSnapshot.thermalContribution) or 0,
        breathingContribution = tonumber(uiSnapshot.breathingContribution) or 0,
        metabolicRate = tonumber(uiSnapshot.metabolicRate) or 1.5,
        metabolicDemand = tonumber(uiSnapshot.metabolicDemand) or 1.5,
        metabolicNorm = tonumber(uiSnapshot.metabolicNorm) or 0,
        breathingEffortRamp = tonumber(uiSnapshot.breathingEffortRamp) or 0,
        breathingDynamicLoad = tonumber(uiSnapshot.breathingDynamicLoad) or 0,
        breathingSealedLoad = tonumber(uiSnapshot.breathingSealedLoad) or 0,
        drivers = type(drivers) == "table" and drivers or {},
        activityLabel = tostring(activityLabel or uiSnapshot.activityLabel or "idle"),
        hotPressure = tonumber(uiSnapshot.hotPressure) or 0,
        coldSuitability = tonumber(uiSnapshot.coldSuitability) or 0,
        thermalStrainScale = tonumber(uiSnapshot.thermalStrainScale) or 0,
        enduranceBeforeAms = tonumber(uiSnapshot.enduranceBeforeAms) or 0,
        enduranceAfterAms = tonumber(uiSnapshot.enduranceAfterAms) or 0,
        enduranceNaturalDelta = tonumber(uiSnapshot.enduranceNaturalDelta) or 0,
        enduranceAppliedDelta = tonumber(uiSnapshot.enduranceAppliedDelta) or 0,
        lastAppliedDtMinutes = tonumber(state.lastAppliedDtMinutes) or 0,
        catchupPendingMinutes = tonumber(state.pendingCatchupMinutes) or 0,
        updatedMinute = tonumber(uiSnapshot.updatedMinute) or tonumber(currentMinute) or 0,
    }
end

return Builder
