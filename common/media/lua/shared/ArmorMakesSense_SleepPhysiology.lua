ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Models = ArmorMakesSense.Models or {}
ArmorMakesSense.Models.SleepPhysiology = ArmorMakesSense.Models.SleepPhysiology or {}

local Utils = require "ArmorMakesSense_UtilsShared"
local Stats = require "ArmorMakesSense_StatsShared"
local SleepModel = require "ArmorMakesSense_SleepModel"
local SleepOwnership = require "ArmorMakesSense_SleepOwnership"

local SleepPhysiology = ArmorMakesSense.Models.SleepPhysiology
local NATIVE_WAKE_ADJUSTMENT_MIN_RATIO = 0.58

local function getCompat()
    return ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
end

local function isMultiplayerClientSession()
    return ((type(isClient) == "function" and isClient() == true)
        or (GameClient and GameClient.bClient == true))
        and not ((type(isServer) == "function" and isServer() == true)
            or (GameServer and GameServer.bServer == true))
end

local function isMultiplayerServerSession()
    return ((type(isServer) == "function" and isServer() == true)
        or (GameServer and GameServer.bServer == true))
end

local function playerHasTrait(player, traitName, traitEnum)
    if not player then
        return false
    end
    if traitEnum and _G.CharacterTrait and CharacterTrait[traitEnum] ~= nil then
        return Utils.safeMethod(player, "hasTrait", CharacterTrait[traitEnum]) == true
    end
    return Utils.safeMethod(player, "hasTrait", traitName) == true
end

local function buildSleepModelInput(player, bedType, fatigue, rigidityLoad, dtMinutes)
    return {
        bedType = tostring(bedType or ""),
        fatigue = tonumber(fatigue),
        rigidityLoad = tonumber(rigidityLoad) or 0,
        dtMinutes = math.max(0, tonumber(dtMinutes) or 0),
        insomniac = playerHasTrait(player, "Insomniac", "INSOMNIAC"),
        nightOwl = playerHasTrait(player, "NightOwl", "NIGHT_OWL"),
        needsLessSleep = playerHasTrait(player, "NeedsLessSleep", "NEEDS_LESS_SLEEP"),
        needsMoreSleep = playerHasTrait(player, "NeedsMoreSleep", "NEEDS_MORE_SLEEP"),
    }
end

local function resolveSleepBedType(player, state)
    local bedType = tostring(Utils.safeMethod(player, "getBedType") or "")
    if bedType == "" then
        bedType = tostring(type(state) == "table" and state.pendingSleepBedType or "")
    end
    return bedType
end

local function getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
    local fatigue = tonumber(currentFatigue)
    if fatigue == nil then
        fatigue = Stats.getFatigue(player)
    end
    if fatigue == nil then
        return 0
    end

    return SleepModel.calculatePenalty(options, buildSleepModelInput(
        player,
        snapshot and snapshot.bedType,
        fatigue,
        snapshot and snapshot.rigidityLoad,
        0
    )).penaltyFraction
end

local function observedWakeAdjustmentIsCredible(observedAdjustment, expectedWakeAdjustment)
    local observed = tonumber(observedAdjustment) or 0
    local expected = tonumber(expectedWakeAdjustment) or 0
    if math.abs(observed) <= 0.002 then
        return false
    end
    if expected == 0 then
        return true
    end
    if (observed < 0) ~= (expected < 0) then
        return false
    end
    return math.abs(observed) >= (math.abs(expected) * NATIVE_WAKE_ADJUSTMENT_MIN_RATIO)
end

local function applySleepWakeFatigueAdjustment(player, state, currentFatigue)
    if SleepOwnership.cmsOwnsWakeAdjustment() then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local compat = getCompat()
    if type(compat) ~= "table" or type(compat.computeSleepWakeFatigueDelta) ~= "function" then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local snapshot = state.sleepSnapshot
    if type(snapshot) ~= "table" then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local nowMinutes = tonumber(Utils.getWorldAgeMinutes())
    local startMinute = tonumber(snapshot.startMinute)
    if nowMinutes == nil or startMinute == nil then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    local fatigue = tonumber(currentFatigue)
    if fatigue == nil then
        fatigue = Stats.getFatigue(player)
    end
    local referenceFatigue = tonumber(snapshot.lastFatigue)
    if referenceFatigue == nil then
        referenceFatigue = fatigue
    end
    local sleptHours = math.max(0, nowMinutes - startMinute) / 60.0
    local expectedWakeAdjustment = tonumber(
        compat.computeSleepWakeFatigueDelta(snapshot.bedType, sleptHours)
    ) or 0

    if fatigue ~= nil and referenceFatigue ~= nil then
        local observedAdjustment = Utils.clamp(fatigue, 0, 1) - referenceFatigue
        if math.abs(observedAdjustment) > 0.002 then
            local trustObserved = not isMultiplayerServerSession()
                or observedWakeAdjustmentIsCredible(observedAdjustment, expectedWakeAdjustment)
            if trustObserved then
                state.lastSleepWakeAdjustment = observedAdjustment
                return observedAdjustment
            end
        end
    end

    if not isMultiplayerServerSession() then
        state.lastSleepWakeAdjustment = 0
        return 0
    end

    state.lastSleepWakeAdjustment = expectedWakeAdjustment
    if expectedWakeAdjustment == 0 then
        return 0
    end

    local baselineFatigue = fatigue or referenceFatigue
    if baselineFatigue == nil then
        return expectedWakeAdjustment
    end

    Stats.setFatigue(player, Utils.clamp(baselineFatigue + expectedWakeAdjustment, 0, 1))
    return expectedWakeAdjustment
end

function SleepPhysiology.computePenaltyContribution(player, state, options, dtMinutes, profile, currentFatigue)
    local sleeping = Utils.toBoolean(Utils.safeMethod(player, "isAsleep"))
    local wasSleeping = Utils.toBoolean(state.wasSleeping)
    if sleeping and not wasSleeping then
        state.sleepSnapshot = {
            rigidityLoad = tonumber(profile.rigidityLoad) or 0,
            bedType = resolveSleepBedType(player, state),
            startMinute = tonumber(Utils.getWorldAgeMinutes()),
            lastFatigue = tonumber(currentFatigue) or Stats.getFatigue(player),
        }
    end

    if sleeping then
        if not state.sleepSnapshot then
            state.sleepSnapshot = {
                rigidityLoad = tonumber(profile.rigidityLoad) or 0,
                bedType = resolveSleepBedType(player, state),
                startMinute = tonumber(Utils.getWorldAgeMinutes()),
                lastFatigue = tonumber(currentFatigue) or Stats.getFatigue(player),
            }
        end
        local snapshot = state.sleepSnapshot
        if snapshot.rigidityLoad == nil then
            snapshot.rigidityLoad = tonumber(profile.rigidityLoad) or 0
        end
        if snapshot.bedType == nil or tostring(snapshot.bedType or "") == "" then
            snapshot.bedType = resolveSleepBedType(player, state)
        end
        if snapshot.startMinute == nil then
            snapshot.startMinute = tonumber(Utils.getWorldAgeMinutes())
        end
        snapshot.lastFatigue = tonumber(currentFatigue) or Stats.getFatigue(player)
        local penaltyFraction = 0
        if options.EnableSleepPenaltyModel then
            penaltyFraction = getSleepRigidityPenaltyFraction(player, options, snapshot, currentFatigue)
        end
        state.lastSleepPenaltyFraction = penaltyFraction
        state.lastSleepWakeAdjustment = 0
        state.wasSleeping = true
        return {
            penaltyFraction = penaltyFraction,
            sleeping = true,
        }
    end

    if wasSleeping and state.sleepSnapshot then
        if options.EnableSleepPenaltyModel then
            applySleepWakeFatigueAdjustment(player, state, currentFatigue)
        else
            state.lastSleepWakeAdjustment = 0
        end
        state.sleepSnapshot = nil
        state.pendingSleepBedType = nil
    end
    state.wasSleeping = false
    state.lastSleepPenaltyFraction = 0

    return {
        penaltyFraction = 0,
        sleeping = false,
    }
end

function SleepPhysiology.computePlannerPenalty(player, state, options, profile, currentFatigue)
    local resolvedState = type(state) == "table" and state or {}
    if not options.EnableSleepPenaltyModel then
        resolvedState.lastSleepPenaltyFraction = 0
        return {
            penaltyFraction = 0,
            sleeping = false,
        }
    end

    local resolvedProfile = type(profile) == "table" and profile or {}
    local snapshot = {
        rigidityLoad = tonumber(resolvedProfile.rigidityLoad) or 0,
        bedType = resolveSleepBedType(player, resolvedState),
    }
    local penaltyFraction = getSleepRigidityPenaltyFraction(
        player,
        options,
        snapshot,
        currentFatigue
    )
    resolvedState.lastSleepPenaltyFraction = penaltyFraction

    return {
        penaltyFraction = penaltyFraction,
        sleeping = false,
    }
end

function SleepPhysiology.applyTransition(player, state, options, dtMinutes, profile)
    local result = SleepPhysiology.computePenaltyContribution(
        player,
        state,
        options,
        dtMinutes,
        profile,
        nil
    )
    result.extraFatigue = 0
    result.wroteFatigue = false

    if SleepOwnership.cmsOwnsFatigue() or isMultiplayerClientSession() then
        return result
    end

    local fatigue = Stats.getFatigue(player)
    local penaltyFraction = Utils.clamp(tonumber(result.penaltyFraction) or 0, 0, 0.95)
    local sampleMinutes = math.max(0, tonumber(dtMinutes) or 0)
    local extraFatigue = 0
    if fatigue ~= nil and penaltyFraction > 0 and sampleMinutes > 0 then
        local snapshot = state and state.sleepSnapshot or {}
        extraFatigue = SleepModel.calculateAppliedPenalty(options, buildSleepModelInput(
            player,
            snapshot.bedType,
            fatigue,
            snapshot.rigidityLoad,
            sampleMinutes
        )).extraFatigue
    end
    if extraFatigue > 0 and fatigue ~= nil then
        local cappedFatigue = math.min(0.85, fatigue + extraFatigue)
        if cappedFatigue > fatigue then
            Stats.setFatigue(player, cappedFatigue)
            result.wroteFatigue = true
        end
    end
    result.extraFatigue = extraFatigue
    return result
end

return SleepPhysiology
