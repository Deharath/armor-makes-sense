ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.Tick = Core.Tick or {}

local Tick = Core.Tick
local C = {}

-- -----------------------------------------------------------------------------
-- Minute-tick player processing
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function Tick.setContext(context)
    C = context or {}
end

function Tick.tickPlayer(player)
    if not player then
        return
    end

    local state = ctx("ensureState")(player)
    local options = ctx("getOptions")()
    ctx("logOptionsSnapshot")(options)
    ctx("setCachedEnableSystem")(true)
    if ctx("updateUiLayer") then
        ctx("updateUiLayer")(player, nil, options)
    end
    local nowMinutes = ctx("getWorldAgeMinutes")()
    if not ctx("runPlayerStartupChecks")(player) then
        return
    end
    local autoPhase = nil
    local getAutoRunnerPhase = ctx("getAutoRunnerPhase")
    if type(getAutoRunnerPhase) == "function" then
        autoPhase = getAutoRunnerPhase(player, state, nowMinutes)
    end
    local elapsedMinutes = nowMinutes - state.lastUpdateGameMinutes
    state.lastUpdateGameMinutes = nowMinutes

    local pendingCatchupMinutes = math.max(0, tonumber(state.pendingCatchupMinutes) or 0)
    if elapsedMinutes > 0 then
        pendingCatchupMinutes = pendingCatchupMinutes + elapsedMinutes
    end

    if pendingCatchupMinutes <= 0 then
        state.pendingCatchupMinutes = 0
        return
    end

    local testLock = state.testLock
    if testLock and tonumber(testLock.untilMinute) and nowMinutes <= tonumber(testLock.untilMinute) then
        if testLock.wetness ~= nil then
            ctx("setWetness")(player, testLock.wetness)
        end
        if testLock.bodyTemp ~= nil then
            ctx("setBodyTemperature")(player, testLock.bodyTemp)
        end
    elseif testLock and testLock.mode then
        if testLock.wetness ~= nil then
            ctx("setWetness")(player, 0.0)
        end
        if testLock.bodyTemp ~= nil then
            ctx("setBodyTemperature")(player, 37.0)
        end
        state.testLock = {
            mode = nil,
            wetness = nil,
            bodyTemp = nil,
            untilMinute = 0,
        }
        testLock = state.testLock
    end

    local profile = ctx("computeArmorProfile")(player)
    local heatFactor = ctx("getHeatFactor")(player, options)
    local wetFactor = ctx("getWetFactor")(player, options)
    if testLock and nowMinutes <= (tonumber(testLock.untilMinute) or 0) then
        if testLock.wetness ~= nil then
            wetFactor = ctx("wetnessToFactor")(testLock.wetness, options)
        end
        if testLock.bodyTemp ~= nil then
            local over = ctx("clamp")((testLock.bodyTemp - 37.0) / 2.3, 0, 1.5)
            heatFactor = 1.0 + (over * ctx("clamp")(options.HeatAmplifierStrength or 0.25, 0, 1.0))
        end
    end
    local activityFactor = ctx("getActivityFactor")(player, options)
    local activityLabel = ctx("getActivityLabel")(player)
    local postureLabel = ctx("getPostureLabel")(player)
    if autoPhase then
        local forcedAct = ctx("lower")(autoPhase.activity or "")
        if forcedAct == "walk" then
            activityLabel = "walk"
            activityFactor = ctx("clamp")(tonumber(options.ActivityWalk) or activityFactor, 0.2, 1.8)
        elseif forcedAct == "run" then
            activityLabel = "run"
            activityFactor = ctx("clamp")(tonumber(options.ActivityJog) or activityFactor, 0.2, 1.8)
        elseif forcedAct == "sprint" then
            activityLabel = "sprint"
            activityFactor = ctx("clamp")(tonumber(options.ActivitySprint) or activityFactor, 0.2, 1.8)
        elseif forcedAct == "idle" then
            activityLabel = "idle"
            activityFactor = ctx("clamp")(tonumber(options.ActivityIdle) or activityFactor, 0.2, 1.8)
        end
        if autoPhase.posture then
            postureLabel = tostring(autoPhase.posture)
        end
    end

    local dtCap = math.max(0.01, tonumber(options.DtMaxMinutes) or 3)
    local maxCatchupSlices = math.max(1, math.floor(tonumber(options.DtCatchupMaxSlices) or 240))
    local processedDtMinutes = 0
    local slicesProcessed = 0
    local sliceNowMinutes = nowMinutes - pendingCatchupMinutes

    if ctx("updateUiLayer") then
        ctx("updateUiLayer")(player, profile, options)
    end

    state.lastArmorLoad = profile.physicalLoad

    while pendingCatchupMinutes > 0 and slicesProcessed < maxCatchupSlices do
        local dtMinutes = ctx("clamp")(pendingCatchupMinutes, 0, dtCap)
        if dtMinutes <= 0 then
            break
        end

        pendingCatchupMinutes = pendingCatchupMinutes - dtMinutes
        processedDtMinutes = processedDtMinutes + dtMinutes
        slicesProcessed = slicesProcessed + 1
        sliceNowMinutes = sliceNowMinutes + dtMinutes

        ctx("applySleepTransition")(player, state, options, dtMinutes, profile, heatFactor, wetFactor)
        local endModelDelta = ctx("applyEnduranceModel")(player, state, options, dtMinutes, profile, heatFactor, wetFactor, activityFactor, activityLabel, postureLabel)
        ctx("updateRecoveryTrace")(state, options, sliceNowMinutes, dtMinutes, profile, activityLabel, postureLabel, ctx("getEndurance")(player))

        local auto = state.autoRunner
        if auto and auto.active and auto.phaseStats and auto.index and auto.index > 0 then
            local phaseStats = auto.phaseStats[auto.index]
            if phaseStats then
                local last = state.lastAutoSample or {}
                local enduranceNow = ctx("getEndurance")(player)
                if endModelDelta ~= nil then
                    phaseStats.endN = (phaseStats.endN or 0) + 1
                    phaseStats.endSum = (phaseStats.endSum or 0) + endModelDelta
                end
                if last.endurance ~= nil and enduranceNow ~= nil then
                    phaseStats.netEndN = (phaseStats.netEndN or 0) + 1
                    phaseStats.netEndSum = (phaseStats.netEndSum or 0) + (enduranceNow - last.endurance)
                end
                state.lastAutoSample = {
                    endurance = enduranceNow,
                    fatigue = ctx("getFatigue")(player),
                }
            end
        end
    end

    state.pendingCatchupMinutes = math.max(0, pendingCatchupMinutes)
    if processedDtMinutes <= 0 then
        return
    end

end

return Tick
