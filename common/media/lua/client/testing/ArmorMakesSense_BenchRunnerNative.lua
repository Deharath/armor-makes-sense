ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunnerNative = Testing.BenchRunnerNative or {}

local BenchRunnerNative = Testing.BenchRunnerNative
local BenchUtils = Testing.BenchUtils
local C = {}
local D = {}

-- -----------------------------------------------------------------------------
-- Context and dependency wiring
-- -----------------------------------------------------------------------------

local function setDeps(deps)
    D = deps or {}
end

function BenchRunnerNative.setContext(context)
    C = context or {}
end

-- Dependency delegation: prefer injected D[name], fall back to BenchUtils or inline.
local function depCall(name, fallback)
    return function(...)
        local fn = D[name]
        if type(fn) == "function" then return fn(...) end
        if fallback then return fallback(...) end
        return nil
    end
end

local ctx          = depCall("ctx", function(name) return C[name] end)
local clamp        = depCall("clamp", BenchUtils.clamp)
local toBoolArg    = depCall("toBoolArg", BenchUtils.toBoolArg)
local boolTag      = depCall("boolTag", BenchUtils.boolTag)
local metricOrNa   = depCall("metricOrNa", BenchUtils.metricOrNa)

local nowMinutes = depCall("nowMinutes", function()
    return BenchUtils.nowMinutes(ctx)
end)

-- safeMethod: explicit fallback chain (deps -> ctx -> BenchUtils -> inline pcall).
local function safeMethod(target, methodName, ...)
    local fn = D.safeMethod
    if type(fn) == "function" then return fn(target, methodName, ...) end
    local sf = ctx("safeMethod")
    if type(sf) == "function" then return sf(target, methodName, ...) end
    return BenchUtils.safeMethod(target, methodName, ...)
end

-- -----------------------------------------------------------------------------
-- Runtime and environment dep delegates
-- -----------------------------------------------------------------------------

local benchSnapshotAppend               = depCall("benchSnapshotAppend")
local runtimeRunKey                     = depCall("runtimeRunKey", BenchUtils.runtimeRunKey or nil)
local getRuntimeBenchRunner             = depCall("getRuntimeBenchRunner")
local registerNativeTickPump            = depCall("registerNativeTickPump")
local unregisterNativeTickPump          = depCall("unregisterNativeTickPump")
local setIsoPlayerTestAIMode            = depCall("setIsoPlayerTestAIMode")
local setNativeTimeOfDay                = depCall("setNativeTimeOfDay")
local snapPlayerToCoords                = depCall("snapPlayerToCoords")
local applyNativeActivityMode           = depCall("applyNativeActivityMode")
local stabilizeNativeCombatStance       = depCall("stabilizeNativeCombatStance")
local clearNativeMovementState          = depCall("clearNativeMovementState")

local distance2D = depCall("distance2D", function(ax, ay, bx, by)
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    return math.sqrt((dx * dx) + (dy * dy))
end)

local readPlayerCoords = depCall("readPlayerCoords", function(player)
    return tonumber(safeMethod(player, "getX")) or 0,
        tonumber(safeMethod(player, "getY")) or 0,
        tonumber(safeMethod(player, "getZ")) or 0
end)

local readClimateSnapshot = depCall("readClimateSnapshot", function(player)
    local x, y, z = readPlayerCoords(player)
    return { x = x, y = y, z = z, outdoors = true, inVehicle = false, climbing = false }
end)


local buildPatrolWaypoints = depCall("buildPatrolWaypoints", function(x, y, z, radius, shape, axis, rectLongTiles, rectShortTiles)
    return {}
end)

local equipRequestedWeapon = depCall("equipRequestedWeapon", function(player, requestedWeapon)
    return nil, nil
end)

local logWeaponSelection = depCall("logWeaponSelection")

local readNativeOption = depCall("readNativeOption", function(exec, key, defaultValue)
    local options = exec and exec.nativeOptions or nil
    if type(options) == "table" and options[key] ~= nil then
        return options[key]
    end
    return defaultValue
end)

local logNativeProbe = depCall("logNativeProbe")

local function nativeDriverRecordPhaseEvent(driver, now, phase)
    if type(driver) ~= "table" then
        return
    end
    local phaseTag = tostring(phase or "unknown")
    if tostring(driver.phaseLast or "") == phaseTag then
        return
    end
    local baseAt = tonumber(driver.phaseZeroAt) or tonumber(now) or nowMinutes()
    local currentAt = tonumber(now) or nowMinutes()
    local relSec = math.max(0.0, (currentAt - baseAt) * 60.0)
    local events = type(driver.phaseTimelineEvents) == "table" and driver.phaseTimelineEvents or {}
    events[#events + 1] = string.format("%.2f:%s", relSec, phaseTag)
    if #events > 24 then
        table.remove(events, 1)
    end
    driver.phaseTimelineEvents = events
    driver.phaseLast = phaseTag
end

local function nativeDriverAddStallReason(driver, reasonTag, weightSec)
    if type(driver) ~= "table" then
        return
    end
    local reason = tostring(reasonTag or "unknown")
    local counts = type(driver.stallReasonCounts) == "table" and driver.stallReasonCounts or {}
    counts[reason] = (tonumber(counts[reason]) or 0) + 1
    driver.stallReasonCounts = counts
    local sec = tonumber(weightSec) or 0
    if sec > 0 then
        driver.stallSecAccum = (tonumber(driver.stallSecAccum) or 0) + sec
    end
end

local function formatStallReasonCounts(counts)
    if type(counts) ~= "table" then
        return "none"
    end
    local pairsList = {}
    for reason, count in pairs(counts) do
        local numeric = tonumber(count) or 0
        if numeric > 0 then
            pairsList[#pairsList + 1] = { reason = tostring(reason), count = numeric }
        end
    end
    if #pairsList == 0 then
        return "none"
    end
    table.sort(pairsList, function(a, b)
        if a.count == b.count then
            return a.reason < b.reason
        end
        return a.count > b.count
    end)
    local parts = {}
    for i = 1, #pairsList do
        parts[#parts + 1] = string.format("%s:%d", pairsList[i].reason, pairsList[i].count)
    end
    return table.concat(parts, ",")
end

local function ensureNativeDriverCapabilities(player, mode, block)
    local hasFunction = ctx("hasFunction")
    if type(hasFunction) ~= "function" then
        return false, "native_hard_missing_has_function"
    end
    if mode == "native_move" or mode == "native_warmup" or mode == "native_treadmill_simple" then
        local movementMode = string.lower(tostring(block and (block.movement_mode or block.native_movement_mode) or "path"))
        if mode == "native_treadmill_simple" then
            movementMode = "forward"
        end
        if movementMode == "forward" then
            if not hasFunction(player, "setForwardDirection") then
                return false, "native_hard_missing_forward_api"
            end
            if not hasFunction(player, "hasPath") then
                return false, "native_hard_missing_path_state_api"
            end
            if not hasFunction(player, "getPathFindBehavior2") then
                return false, "native_hard_missing_path_behavior_api"
            end
            if not hasFunction(player, "pathToLocationF") and not hasFunction(player, "pathToLocation") then
                return false, "native_hard_missing_path_api"
            end
        else
            if not hasFunction(player, "faceLocationF") then
                return false, "native_hard_missing_face_api"
            end
            if not hasFunction(player, "hasPath") then
                return false, "native_hard_missing_path_state_api"
            end
            if not hasFunction(player, "getPathFindBehavior2") then
                return false, "native_hard_missing_path_behavior_api"
            end
            if not hasFunction(player, "pathToLocationF") and not hasFunction(player, "pathToLocation") then
                return false, "native_hard_missing_path_api"
            end
        end
    elseif mode == "native_combat_air" then
        if not hasFunction(player, "setIsAiming") then
            return false, "native_hard_missing_aim_api"
        end
        if not hasFunction(player, "getMeleeDelay") then
            return false, "native_hard_missing_melee_delay_api"
        end
        if not hasFunction(player, "CanAttack") then
            return false, "native_hard_missing_can_attack_api"
        end
        if not hasFunction(player, "AttemptAttack") and not hasFunction(player, "DoAttack") then
            return false, "native_hard_missing_attack_api"
        end
    end
    return true, nil
end

local function resolveForwardVector(block)
    local dx = tonumber(block and block.forward_dx)
    local dy = tonumber(block and block.forward_dy)
    local dir = string.lower(tostring(block and block.forward_dir or ""))
    if dir ~= "" then
        if dir == "east" or dir == "right" then
            dx, dy = 1.0, 0.0
        elseif dir == "west" or dir == "left" then
            dx, dy = -1.0, 0.0
        elseif dir == "north" or dir == "up" then
            dx, dy = 0.0, -1.0
        elseif dir == "south" or dir == "down" then
            dx, dy = 0.0, 1.0
        end
    end
    dx = tonumber(dx) or 1.0
    dy = tonumber(dy) or 0.0
    local mag = math.sqrt((dx * dx) + (dy * dy))
    if mag < 0.0001 then
        return 1.0, 0.0
    end
    return dx / mag, dy / mag
end

local function readNativePathState(player)
    local behavior = safeMethod(player, "getPathFindBehavior2")
    return {
        hasPath = safeMethod(player, "hasPath"),
        goalLocation = behavior and safeMethod(behavior, "isGoalLocation") or nil,
        movingUsingPath = behavior and safeMethod(behavior, "isMovingUsingPathFind") or nil,
        startedMoving = behavior and safeMethod(behavior, "hasStartedMoving") or nil,
        shouldBeMoving = behavior and safeMethod(behavior, "shouldBeMoving") or nil,
        pathLength = behavior and safeMethod(behavior, "getPathLength") or nil,
        targetX = behavior and safeMethod(behavior, "getTargetX") or nil,
        targetY = behavior and safeMethod(behavior, "getTargetY") or nil,
        targetZ = behavior and safeMethod(behavior, "getTargetZ") or nil,
    }
end

local function nativePathStateActive(state)
    return state and (
        state.hasPath == true
        or state.goalLocation == true
        or state.movingUsingPath == true
        or state.shouldBeMoving == true
    )
end

local function nativeDriverIssueForwardPath(player, driver)
    if not player or not driver or driver.movementMode ~= "forward" then
        return false
    end
    local dx = tonumber(driver.forwardDirX) or 1.0
    local dy = tonumber(driver.forwardDirY) or 0.0
    local dist = math.max(24.0, tonumber(driver.forwardPathDistanceTiles) or 80.0)
    local isTreadmillSimple = (driver.mode == "native_treadmill_simple")
    local px, py, pz = readPlayerCoords(player)
    local baseX = tonumber(px) or tonumber(driver.anchorX) or 0
    local baseY = tonumber(py) or tonumber(driver.anchorY) or 0
    local baseZ = tonumber(pz) or tonumber(driver.anchorZ) or 0
    local goalX, goalY, goalZ
    if isTreadmillSimple then
        goalX = tonumber(driver.forwardGoalX)
        goalY = tonumber(driver.forwardGoalY)
        goalZ = tonumber(driver.forwardGoalZ)
        if goalX == nil or goalY == nil then
            local anchorX = tonumber(driver.anchorX) or baseX
            local anchorY = tonumber(driver.anchorY) or baseY
            local anchorZ = tonumber(driver.anchorZ) or baseZ
            goalX = anchorX + (dx * dist)
            goalY = anchorY + (dy * dist)
            goalZ = anchorZ
            driver.forwardGoalX = goalX
            driver.forwardGoalY = goalY
            driver.forwardGoalZ = goalZ
        end
    else
        goalX = baseX + (dx * dist)
        goalY = baseY + (dy * dist)
        goalZ = baseZ
    end

    safeMethod(player, "setForwardDirection", dx, dy)

    local issued = false
    local behavior = driver.behavior
    if behavior and driver.canBehaviorSetData then
        safeMethod(behavior, "setData", goalX, goalY, goalZ)
    end
    if behavior and driver.canBehaviorPathF then
        safeMethod(behavior, "pathToLocationF", goalX, goalY, goalZ)
        issued = true
    end
    if not issued and driver.canPathF then
        safeMethod(player, "pathToLocationF", goalX, goalY, goalZ)
        issued = true
    end
    if not issued and behavior and driver.canBehaviorPathI then
        safeMethod(behavior, "pathToLocation", math.floor(goalX), math.floor(goalY), math.floor(goalZ))
        issued = true
    end
    if not issued and driver.canPathI then
        safeMethod(player, "pathToLocation", math.floor(goalX), math.floor(goalY), math.floor(goalZ))
        issued = true
    end
    if issued then
        driver.lastPathIssueAt = nowMinutes()
        local state = readNativePathState(player)
        driver.pathState = state
        if nativePathStateActive(state) then
            driver.lastPathAcceptedAt = nowMinutes()
        end
    end
    return issued
end

local function nativeDriverSyncMovementBaseline(player, driver)
    if not player or not driver then
        return
    end
    local rx, ry, rz = readPlayerCoords(player)
    driver.lastX = tonumber(rx) or tonumber(driver.anchorX) or 0
    driver.lastY = tonumber(ry) or tonumber(driver.anchorY) or 0
    driver.lastZ = tonumber(rz) or tonumber(driver.anchorZ) or 0
    driver.progressRefX = driver.lastX
    driver.progressRefY = driver.lastY
    driver.distanceMoved = 0
end

local function nativeDriverResetToAnchor(player, driver, phaseTag)
    if not player or not driver then
        return false, "native_soft_reset_invalid_args"
    end
    if driver.resetToAnchor ~= true then
        return true, nil
    end

    local maxAttempts = math.max(1, math.floor(tonumber(driver.stepResetMaxAttempts) or 6))
    local tolerance = math.max(0.10, tonumber(driver.stepResetTolerance) or 0.25)
    local dx = tonumber(driver.forwardDirX) or 1.0
    local dy = tonumber(driver.forwardDirY) or 0.0
    local tx = tonumber(driver.anchorX) or 0
    local ty = tonumber(driver.anchorY) or 0
    local tz = tonumber(driver.anchorZ) or 0

    local attempts = 0
    for i = 1, maxAttempts do
        attempts = i
        local snapped = snapPlayerToCoords(player, tx, ty, tz)
        safeMethod(player, "setForwardDirection", dx, dy)
        safeMethod(player, "faceLocationF", tx + (dx * 8.0), ty + (dy * 8.0))
        local rx, ry, rz = readPlayerCoords(player)
        local atAnchor = distance2D(rx, ry, tx, ty) <= tolerance and math.abs((tonumber(rz) or 0) - tz) <= 0.55
        if snapped and atAnchor then
            driver.stepResetAttemptCount = (tonumber(driver.stepResetAttemptCount) or 0) + attempts
            driver.stepResetOk = true
            driver.stepResetError = nil
            driver.postResetOk = (phaseTag == "post") and true or driver.postResetOk
            nativeDriverSyncMovementBaseline(player, driver)
            return true, nil
        end
    end

    driver.stepResetAttemptCount = (tonumber(driver.stepResetAttemptCount) or 0) + attempts
    driver.stepResetOk = false
    driver.stepResetError = (phaseTag == "post") and "native_soft_post_reset_failed" or "native_soft_reset_failed"
    driver.postResetOk = (phaseTag == "post") and false or driver.postResetOk
    return false, tostring(driver.stepResetError)
end

local function nativeDriverForceForwardRearm(player, driver, now, reasonTag)
    if not player or not driver or driver.movementMode ~= "forward" then
        return false
    end
    local rearmEveryMin = math.max(0.02, tonumber(driver.forwardRearmRetryMin) or (0.10 / 60.0))
    if now and now - (tonumber(driver.lastForwardRearmAt) or 0) < rearmEveryMin then
        return false
    end
    nativeDriverRecordPhaseEvent(driver, now or nowMinutes(), "rearm")
    nativeDriverAddStallReason(driver, reasonTag or "native_forward_rearm", 0)
    driver.lastForwardRearmAt = now or nowMinutes()
    driver.forwardRearmAttempts = (tonumber(driver.forwardRearmAttempts) or 0) + 1

    safeMethod(player, "setPath2", nil)
    safeMethod(player, "setJustMoved", false)
    local dx = tonumber(driver.forwardDirX) or 1.0
    local dy = tonumber(driver.forwardDirY) or 0.0
    safeMethod(player, "setForwardDirection", dx, dy)
    safeMethod(player, "faceLocationF", (tonumber(driver.lastX) or 0) + (dx * 8.0), (tonumber(driver.lastY) or 0) + (dy * 8.0))
    applyNativeActivityMode(player, driver.activity)

    local issued = nativeDriverIssueForwardPath(player, driver)
    local state = readNativePathState(player)
    driver.pathState = state
    if issued and (state and (state.hasPath == true or state.goalLocation == true)) then
        driver.forwardRearmStreak = 0
        driver.pathBehaviorResult = tostring(reasonTag or "forward_rearm_ok")
        return true
    end

    driver.forwardRearmStreak = (tonumber(driver.forwardRearmStreak) or 0) + 1
    driver.forwardRearmFailures = (tonumber(driver.forwardRearmFailures) or 0) + 1
    driver.pathBehaviorResult = tostring(reasonTag or "forward_rearm_failed")
    return false
end

local function nativeDriverIssuePath(player, driver)
    if not driver or driver.movementMode ~= "path" then
        return false
    end
    if not driver.waypoints or #driver.waypoints == 0 then
        return false
    end

    local target = driver.waypoints[driver.waypointIndex]
    if not target then
        return false
    end

    local tx = tonumber(target.x) or 0
    local ty = tonumber(target.y) or 0
    local tz = tonumber(target.z) or 0
    local ix = math.floor(tx)
    local iy = math.floor(ty)
    local iz = math.floor(tz)
    local issued = false
    local behavior = driver.behavior

    if behavior and driver.canBehaviorSetData then
        safeMethod(behavior, "setData", tx, ty, tz)
    end

    if behavior and driver.canBehaviorPathF then
        safeMethod(behavior, "pathToLocationF", tx, ty, tz)
        issued = true
    end
    if not issued and driver.canPathF then
        safeMethod(player, "pathToLocationF", tx, ty, tz)
        issued = true
    end
    if not issued and behavior and driver.canBehaviorPathI then
        safeMethod(behavior, "pathToLocation", ix, iy, iz)
        issued = true
    end
    if not issued and driver.canPathI then
        safeMethod(player, "pathToLocation", ix, iy, iz)
        issued = true
    end

    if issued then
        driver.lastPathIssueAt = nowMinutes()
        local state = readNativePathState(player)
        driver.pathState = state
        if nativePathStateActive(state) then
            driver.lastPathAcceptedAt = nowMinutes()
        end
    end
    return issued
end

local function nativeDriverRetryPath(player, driver, now, x, y, z)
    if not driver or driver.movementMode ~= "path" then
        return false
    end

    local retries = tonumber(driver.pathRetryStreak) or 0
    local retryLimit = tonumber(driver.pathRetryLimit) or 0
    if retryLimit <= 0 or retries >= retryLimit then
        return false
    end

    retries = retries + 1
    driver.pathRetryStreak = retries
    driver.pathRetryCount = (tonumber(driver.pathRetryCount) or 0) + 1

    local baseRadius = tonumber(driver.patrolRadius) or 4.0
    local stepRadius = tonumber(driver.pathRetryRadiusStep) or 1.75
    local maxRadius = tonumber(driver.pathRetryMaxRadius) or 12.0
    local retryRadius = math.min(maxRadius, baseRadius + (stepRadius * retries))

    if driver.pathRetryReanchor ~= false then
        driver.anchorX = tonumber(x) or driver.anchorX
        driver.anchorY = tonumber(y) or driver.anchorY
        driver.anchorZ = tonumber(z) or driver.anchorZ
    end
    local previousIndex = math.max(1, math.floor(tonumber(driver.waypointIndex) or 1))
    driver.waypoints = buildPatrolWaypoints(
        driver.anchorX,
        driver.anchorY,
        driver.anchorZ,
        retryRadius,
        driver.patrolShape,
        driver.patrolAxis,
        driver.patrolRectLongTiles,
        driver.patrolRectShortTiles
    )
    local waypointCount = #driver.waypoints
    if waypointCount > 0 then
        previousIndex = math.min(previousIndex, waypointCount)
        if waypointCount == 2 and (driver.patrolShape == "line" or driver.patrolShape == "treadmill" or driver.patrolShape == "back_and_forth") then
            driver.waypointIndex = (previousIndex % waypointCount) + 1
        else
            driver.waypointIndex = previousIndex
        end
    else
        driver.waypointIndex = 1
    end
    driver.lastProgressAt = now
    driver.progressRefX = tonumber(x) or driver.anchorX
    driver.progressRefY = tonumber(y) or driver.anchorY

    return nativeDriverIssuePath(player, driver)
end

local function startNativeDriver(player, exec, block)
    local mode = tostring(block.mode or "native_move")
    local isTreadmillSimple = (mode == "native_treadmill_simple")
    local ok, reason = ensureNativeDriverCapabilities(player, mode, block)
    if not ok then
        return nil, reason
    end

    local x, y, z = readPlayerCoords(player)
    local movementMode = string.lower(tostring(block.movement_mode or block.native_movement_mode or "path"))
    if isTreadmillSimple then
        movementMode = "forward"
    end
    if movementMode ~= "forward" then
        movementMode = "path"
    end
    local forwardDirX, forwardDirY = resolveForwardVector(block)
    local stepBoundaryResetRaw = block.step_boundary_reset
    if stepBoundaryResetRaw == nil then
        stepBoundaryResetRaw = isTreadmillSimple or (movementMode == "forward")
    end
    local stepBoundaryReset = toBoolArg(stepBoundaryResetRaw)
    local anchorModeDefault = isTreadmillSimple and "fixed_run" or "dynamic"
    local anchorMode = string.lower(tostring(block.anchor_mode or anchorModeDefault))
    local useFixedRunAnchor = (anchorMode == "fixed_run")
    local useFixedScenarioAnchor = (anchorMode == "fixed_scenario" or anchorMode == "fixed")
    local patrolShapeRaw = string.lower(tostring(block.patrol_shape or block.path_shape or "line"))
    local startOnWaypointRaw = block.start_on_waypoint
    if startOnWaypointRaw == nil then
        startOnWaypointRaw = useFixedScenarioAnchor and (patrolShapeRaw == "rectangle" or patrolShapeRaw == "rect")
    end
    local startOnWaypoint = toBoolArg(startOnWaypointRaw)
    local resetToAnchorRaw = block.reset_to_anchor
    if resetToAnchorRaw == nil then
        resetToAnchorRaw = stepBoundaryReset
    end
    local resetToAnchor = toBoolArg(resetToAnchorRaw)
    local strictStepResetRaw = block.strict_step_reset
    if strictStepResetRaw == nil and movementMode == "forward" then
        strictStepResetRaw = true
    end
    local strictStepReset = toBoolArg(strictStepResetRaw)
    if (useFixedRunAnchor or useFixedScenarioAnchor) and exec and exec.runId then
        local runner = getRuntimeBenchRunner(exec.runId)
        if runner then
            local savedAnchor = nil
            if useFixedRunAnchor then
                savedAnchor = runner.fixedRunAnchor
                if not savedAnchor then
                    savedAnchor = { x = x, y = y, z = z }
                    runner.fixedRunAnchor = savedAnchor
                end
            else
                runner.fixedScenarioAnchors = runner.fixedScenarioAnchors or {}
                local anchorKey = string.format("%s::%s",
                    tostring(exec.setDef and exec.setDef.id or "na"),
                    tostring(exec.scenarioId or "na"))
                savedAnchor = runner.fixedScenarioAnchors[anchorKey]
                if not savedAnchor then
                    savedAnchor = { x = x, y = y, z = z }
                    runner.fixedScenarioAnchors[anchorKey] = savedAnchor
                end
            end
            x = tonumber(savedAnchor.x) or x
            y = tonumber(savedAnchor.y) or y
            z = tonumber(savedAnchor.z) or z

        end
    end
    if movementMode == "forward" then
        safeMethod(player, "setForwardDirection", forwardDirX, forwardDirY)
    end
    local completionMode = string.lower(tostring(block.completion_mode or "time"))
    if isTreadmillSimple or completionMode ~= "laps" then
        completionMode = "time"
    end
    local targetLaps = math.max(0, math.floor(tonumber(block.lap_target) or 0))
    local targetSec = tonumber(block.requested_sec) or 0
    if mode == "native_warmup" and targetSec <= 0 then
        targetSec = 45
    end
    if mode == "native_move" and completionMode ~= "laps" and targetSec <= 0 then
        targetSec = 600
    end
    if isTreadmillSimple and targetSec <= 0 then
        local treadmillActivity = tostring(block.activity or "walk")
        targetSec = treadmillActivity == "sprint" and 120 or 360
    end
    local targetSwings = math.max(0, math.floor(tonumber(block.requested_swings) or 0))
    local hasExplicitSec = tonumber(block.requested_sec) ~= nil and tonumber(block.requested_sec) > 0
    if mode == "native_combat_air" and targetSwings <= 0 and not hasExplicitSec then
        targetSwings = 60
    end

    local timeoutSec = tonumber(block.timeout_sec)
    if timeoutSec == nil then
        timeoutSec = (mode == "native_combat_air") and math.max(180, targetSwings * 6) or targetSec
    end

    local activitySetTime = nil
    if exec.pinnedTimeOfDay ~= nil then
        activitySetTime = tonumber(exec.pinnedTimeOfDay)
    else
        activitySetTime = tonumber(block.set_time_of_day)
    end
    if activitySetTime ~= nil then
        local setOk, setReason = setNativeTimeOfDay(activitySetTime)
        if not setOk then
            return nil, setReason
        end
    end

    local probeEnabledRaw = readNativeOption(exec, "nativeProbe", false)
    local probeEnabled = probeEnabledRaw == true or tostring(probeEnabledRaw) == "true" or tonumber(probeEnabledRaw) == 1
    local probeEverySec = math.max(0.2, tonumber(readNativeOption(exec, "nativeProbeEverySec", 1.0)) or 1.0)
    local attackCooldownSec = tonumber(readNativeOption(exec, "nativeAttackCooldownSec", block.attack_cooldown_sec))
        or tonumber(readNativeOption(exec, "native_attack_cooldown_sec", block.attack_cooldown_sec))
        or tonumber(readNativeOption(exec, "nativeAttackEverySec", block.attack_every_sec))
        or tonumber(block.attack_interval_sec)
        or 0.22
    attackCooldownSec = clamp(attackCooldownSec, 0.05, 2.0)

    local defaultForwardRepathSec = isTreadmillSimple and 0.75 or 0.25
    local defaultForwardRearmRetrySec = isTreadmillSimple and 0.25 or 0.10
    local driverStartAt = nowMinutes()

    local driver = {
        mode = mode,
        startedAt = driverStartAt,
        lastTickAt = driverStartAt,
        lastProgressAt = driverStartAt,
        anchorX = x,
        anchorY = y,
        anchorZ = z,
        lastX = x,
        lastY = y,
        lastZ = z,
        targetSec = math.max(0, targetSec),
        timeoutSec = math.max(0, timeoutSec or 0),
        targetSwings = math.max(0, targetSwings),
        completionMode = completionMode,
        targetLaps = targetLaps,
        lapsCompleted = 0,
        achievedSwings = 0,
        attackAttempts = 0,
        attackSuccess = 0,
        attackCooldownBlocks = 0,
        attackCooldownSec = attackCooldownSec,
        attackCooldownMin = attackCooldownSec / 60.0,
        lastAttackAttemptAt = 0,
        lastAttackSuccessAt = 0,
        hitEvents = 0,
        distanceMoved = 0,
        totalSamples = 0,
        validSamples = 0,
        movingSamples = 0,
        movingClaimedNoProgressSamples = 0,
        walkTicks = 0,
        runTicks = 0,
        sprintTicks = 0,
        idleTicks = 0,
        combatTicks = 0,
        speedSum = 0,
        speedSamples = 0,
        stallLimitMin = (math.max(10, tonumber(block.stall_sec) or 30)) / 60.0,
        patrolRadius = math.max(1.5, tonumber(block.patrol_radius) or 4.0),
        patrolShape = patrolShapeRaw,
        patrolAxis = string.lower(tostring(block.patrol_axis or block.path_axis or "x")),
        startOnWaypoint = startOnWaypoint,
        forwardDirX = forwardDirX,
        forwardDirY = forwardDirY,
        forwardPathDistanceTiles = math.max(24.0, tonumber(block.path_goal_distance_tiles) or tonumber(block.forward_path_distance_tiles) or (isTreadmillSimple and 360.0 or 80.0)),
        forwardRepathEveryMin = (math.max(0.05, tonumber(block.repath_sec) or tonumber(block.forward_repath_sec) or defaultForwardRepathSec)) / 60.0,
        forwardRearmMaxAttempts = math.max(1, math.floor(tonumber(block.rearm_max_attempts) or tonumber(block.forward_rearm_max_attempts) or 4)),
        forwardRearmRetryMin = math.max(0.02, tonumber(block.forward_rearm_retry_sec) or defaultForwardRearmRetrySec) / 60.0,
        forwardStartSettleMin = math.max(0.0, tonumber(block.start_settle_sec) or tonumber(block.forward_start_settle_sec) or 8.0) / 60.0,
        forwardStartLockTimeoutMin = math.max(1.0, tonumber(block.start_lock_timeout_sec) or 25.0) / 60.0,
        forwardAnchorTolerance = math.max(0.10, tonumber(block.anchor_tolerance_tiles) or tonumber(block.forward_anchor_tolerance) or 0.35),
        forwardStartPending = false,
        forwardStartReadyAt = nil,
        forwardStartDeadlineAt = nil,
        anchorStartErrorTiles = nil,
        anchorEndErrorTiles = nil,
        anchorDeltaBeforeStart = nil,
        anchorDeltaAfterPostReset = nil,
        forwardGoalX = nil,
        forwardGoalY = nil,
        forwardGoalZ = nil,
        forwardRearmAttempts = 0,
        forwardRearmFailures = 0,
        forwardRearmStreak = 0,
        lastForwardRearmAt = nil,
        patrolRectLongTiles = math.max(4.0, tonumber(block.patrol_rect_long_tiles) or 18.0),
        patrolRectShortTiles = math.max(3.0, tonumber(block.patrol_rect_short_tiles) or 9.0),
        pathIssueEveryMin = (math.max(1.0, tonumber(block.path_refresh_sec) or 3.0)) / 60.0,
        pathAcceptTimeoutMin = (math.max(3.0, tonumber(block.path_accept_timeout_sec) or 7.0)) / 60.0,
        waypointReachDistance = math.max(0.35, tonumber(block.waypoint_reach) or 0.70),
        progressEpsilon = math.max(0.01, tonumber(block.progress_epsilon) or 0.025),
        progressRefX = x,
        progressRefY = y,
        movementSampleEpsilon = math.max(0.0005, tonumber(block.movement_sample_epsilon) or (math.max(0.01, tonumber(block.progress_epsilon) or 0.025) * 0.05)),
        teleportDeltaThreshold = math.max(4.0, tonumber(block.teleport_jump_threshold_tiles) or tonumber(block.teleport_delta_threshold_tiles) or 8.0),
        teleportJumpCount = 0,
        stepBoundaryReset = stepBoundaryReset,
        resetToAnchor = resetToAnchor,
        strictStepReset = strictStepReset,
        stepResetMaxAttempts = math.max(1, math.floor(tonumber(block.reset_max_attempts) or tonumber(block.step_reset_max_attempts) or 6)),
        stepResetRetryMin = math.max(0.0, tonumber(block.step_reset_retry_sec) or 0.05) / 60.0,
        stepResetTolerance = math.max(0.10, tonumber(block.step_reset_tolerance) or 0.25),
        stepResetAttemptCount = 0,
        stepResetOk = nil,
        stepResetError = nil,
        postResetOk = nil,
        pathRetryLimit = math.max(0, math.floor(tonumber(block.path_retry_limit) or 4)),
        pathRetryCount = 0,
        pathRetryStreak = 0,
        pathRetryReanchor = not useFixedScenarioAnchor,
        pathRetryRadiusStep = math.max(0.5, tonumber(block.path_retry_radius_step) or 1.75),
        pathRetryMaxRadius = math.max(4.0, tonumber(block.path_retry_max_radius) or 12.0),
        combatStandStill = (mode == "native_combat_air") and (block.combat_stand_still ~= false) or (block.combat_stand_still == true),
        activity = tostring(block.activity or "walk"),
        waypoints = nil,
        waypointIndex = 1,
        movementMode = movementMode,
        useTestAIMode = (mode == "native_move" or mode == "native_warmup" or mode == "native_treadmill_simple" or mode == "native_combat_air") and block.test_ai_mode ~= false,
        testAIModeState = "disabled",
        behavior = nil,
        pathState = nil,
        pathBehaviorResult = nil,
        lastPathAcceptedAt = nil,
        lastPathIssueAt = nil,
        canPathF = false,
        canPathI = false,
        canBehaviorPathF = false,
        canBehaviorPathI = false,
        canBehaviorUpdate = false,
        canBehaviorSetData = false,
        probeEnabled = probeEnabled,
        probeEveryMin = probeEverySec / 60.0,
        probeLastAt = nil,
        probeSamples = 0,
        probeJustMovedSamples = 0,
        probeNPCSamples = 0,
        probePathShouldMoveSamples = 0,
        phaseZeroAt = driverStartAt,
        phaseTimelineEvents = {},
        phaseLast = nil,
        stallReasonCounts = {},
        stallSecAccum = 0,
    }
    nativeDriverRecordPhaseEvent(driver, driverStartAt, "init")

    if driver.useTestAIMode then
        if setIsoPlayerTestAIMode(true) then
            driver.testAIModeState = "enabled"
        else
            driver.testAIModeState = "unsupported"
        end
    end

    if mode == "native_move" or mode == "native_warmup" or mode == "native_treadmill_simple" then
        local hasFunction = ctx("hasFunction")
        local behavior = safeMethod(player, "getPathFindBehavior2")
        driver.behavior = behavior
        driver.canPathF = type(hasFunction) == "function" and hasFunction(player, "pathToLocationF") == true
        driver.canPathI = type(hasFunction) == "function" and hasFunction(player, "pathToLocation") == true
        driver.canBehaviorPathF = type(hasFunction) == "function" and behavior ~= nil and hasFunction(behavior, "pathToLocationF") == true
        driver.canBehaviorPathI = type(hasFunction) == "function" and behavior ~= nil and hasFunction(behavior, "pathToLocation") == true
        driver.canBehaviorUpdate = type(hasFunction) == "function" and behavior ~= nil and hasFunction(behavior, "update") == true
        driver.canBehaviorSetData = type(hasFunction) == "function" and behavior ~= nil and hasFunction(behavior, "setData") == true

        if not behavior then
            return nil, "native_hard_missing_path_behavior"
        end
        if not driver.canPathF and not driver.canPathI and not driver.canBehaviorPathF and not driver.canBehaviorPathI then
            return nil, "native_hard_missing_path_api"
        end
        if driver.movementMode == "path" then
            driver.waypoints = buildPatrolWaypoints(
                driver.anchorX,
                driver.anchorY,
                driver.anchorZ,
                driver.patrolRadius,
                driver.patrolShape,
                driver.patrolAxis,
                driver.patrolRectLongTiles,
                driver.patrolRectShortTiles
            )
            if driver.startOnWaypoint and driver.waypoints and #driver.waypoints >= 2 then
                local startWp = driver.waypoints[1]
                if startWp then
                    snapPlayerToCoords(player, startWp.x, startWp.y, startWp.z)
                    driver.lastX = tonumber(startWp.x) or driver.lastX
                    driver.lastY = tonumber(startWp.y) or driver.lastY
                    driver.lastZ = tonumber(startWp.z) or driver.lastZ
                    driver.progressRefX = driver.lastX
                    driver.progressRefY = driver.lastY
                end
                driver.waypointIndex = 2
            end
            if not nativeDriverIssuePath(player, driver) then
                return nil, "native_hard_path_issue_failed"
            end
        elseif driver.movementMode == "forward" then
            if driver.resetToAnchor and not startOnWaypoint then
                nativeDriverRecordPhaseEvent(driver, nowMinutes(), "pre_reset")
                local resetOk, resetErr = nativeDriverResetToAnchor(player, driver, "pre")
                if not resetOk and driver.strictStepReset == true then
                    return nil, tostring(resetErr or "native_soft_reset_failed")
                end
            end
            nativeDriverSyncMovementBaseline(player, driver)
            if isTreadmillSimple then
                local dx = tonumber(driver.forwardDirX) or 1.0
                local dy = tonumber(driver.forwardDirY) or 0.0
                local dist = math.max(24.0, tonumber(driver.forwardPathDistanceTiles) or 1000.0)
                local anchorX = tonumber(driver.anchorX) or driver.lastX or 0
                local anchorY = tonumber(driver.anchorY) or driver.lastY or 0
                local anchorZ = tonumber(driver.anchorZ) or driver.lastZ or 0
                driver.forwardGoalX = anchorX + (dx * dist)
                driver.forwardGoalY = anchorY + (dy * dist)
                driver.forwardGoalZ = anchorZ
            end
            driver.forwardStartPending = true
            driver.forwardStartReadyAt = nowMinutes() + (tonumber(driver.forwardStartSettleMin) or 0)
            driver.forwardStartDeadlineAt = nowMinutes() + (tonumber(driver.forwardStartLockTimeoutMin) or (12.0 / 60.0))
            nativeDriverRecordPhaseEvent(driver, nowMinutes(), "start_lock")
        end
        driver.startedAt = nil
        driver.lastTickAt = nowMinutes()
        driver.lastProgressAt = nowMinutes()
        registerNativeTickPump(player, driver)
    end

    if mode == "native_combat_air" then
        local requestedWeapon = exec and exec.scenario and exec.scenario.weapon or block.weapon
        local weaponType, requestedResolved = equipRequestedWeapon(player, requestedWeapon)
        logWeaponSelection(exec, mode, requestedWeapon, requestedResolved, weaponType, player)
        if not weaponType then
            return nil, "native_hard_weapon_missing"
        end
        safeMethod(player, "setLastHitCount", 0)
        if driver.combatStandStill then
            stabilizeNativeCombatStance(player, true)
        end
    end

    return driver, nil
end

local function finalizeNativeActivity(player, exec, driver, outcome, reason)
    local elapsedSec = math.max(0, (nowMinutes() - (driver.startedAt or nowMinutes())) * 60.0)
    local endX, endY = readPlayerCoords(player)
    local anchorEndError = distance2D(endX, endY, tonumber(driver.anchorX) or endX, tonumber(driver.anchorY) or endY)
    local totalSamples = tonumber(driver.totalSamples) or 0
    local validRatio = totalSamples > 0 and ((tonumber(driver.validSamples) or 0) / totalSamples) or 0
    local moveUptime = totalSamples > 0 and ((tonumber(driver.movingSamples) or 0) / totalSamples) or 0
    local walkTicks = tonumber(driver.walkTicks) or 0
    local runTicks = tonumber(driver.runTicks) or 0
    local sprintTicks = tonumber(driver.sprintTicks) or 0
    local idleTicks = tonumber(driver.idleTicks) or 0
    local combatTicks = tonumber(driver.combatTicks) or 0
    local stateTicks = walkTicks + runTicks + sprintTicks + idleTicks
    local labelTicks = stateTicks + combatTicks
    local avgMoveSpeed = nil
    local speedSamples = tonumber(driver.speedSamples) or 0
    if speedSamples > 0 then
        avgMoveSpeed = (tonumber(driver.speedSum) or 0) / speedSamples
    end

    exec.activityResult.driver = "native"
    exec.activityResult.env_source = "vanilla"
    exec.activityResult.activity_source = "vanilla"
    exec.activityResult.valid_sample_ratio = validRatio
    exec.activityResult.movement_uptime = moveUptime
    exec.activityResult.distance_moved = tonumber(driver.distanceMoved) or 0
    exec.activityResult.total_distance_tiles = tonumber(driver.distanceMoved) or 0
    exec.activityResult.elapsed_game_sec = elapsedSec
    exec.activityResult.walk_pct = stateTicks > 0 and (walkTicks / stateTicks) or nil
    exec.activityResult.run_pct = stateTicks > 0 and (runTicks / stateTicks) or nil
    exec.activityResult.sprint_pct = stateTicks > 0 and (sprintTicks / stateTicks) or nil
    exec.activityResult.idle_pct = stateTicks > 0 and (idleTicks / stateTicks) or nil
    exec.activityResult.pct_idle = labelTicks > 0 and (idleTicks / labelTicks) or nil
    exec.activityResult.pct_walk = labelTicks > 0 and (walkTicks / labelTicks) or nil
    exec.activityResult.pct_run = labelTicks > 0 and (runTicks / labelTicks) or nil
    exec.activityResult.pct_sprint = labelTicks > 0 and (sprintTicks / labelTicks) or nil
    exec.activityResult.pct_combat = labelTicks > 0 and (combatTicks / labelTicks) or nil
    exec.activityResult.avg_move_speed = avgMoveSpeed
    exec.activityResult.attack_attempts = tonumber(driver.attackAttempts) or 0
    exec.activityResult.attack_success = tonumber(driver.attackSuccess) or 0
    exec.activityResult.attack_cooldown_blocks = tonumber(driver.attackCooldownBlocks) or 0
    exec.activityResult.attack_cooldown_sec = tonumber(driver.attackCooldownSec)
    exec.activityResult.hit_events = tonumber(driver.hitEvents) or 0
    exec.activityResult.native_nav_mode = (driver.mode == "native_treadmill_simple") and "treadmill_simple" or tostring(driver.movementMode or "na")
    exec.activityResult.native_ai_mode = tostring(driver.testAIModeState or "na")
    exec.activityResult.native_npc_mode = tostring(driver.testAIModeState or "na")
    exec.activityResult.native_path_retries = tonumber(driver.pathRetryCount) or 0
    exec.activityResult.native_path_has = driver.pathState and driver.pathState.hasPath or nil
    exec.activityResult.native_path_goal = driver.pathState and driver.pathState.goalLocation or nil
    exec.activityResult.native_path_moving = driver.pathState and driver.pathState.movingUsingPath or nil
    exec.activityResult.native_path_started = driver.pathState and driver.pathState.startedMoving or nil
    exec.activityResult.native_path_len = driver.pathState and tonumber(driver.pathState.pathLength) or nil
    exec.activityResult.native_path_result = tostring(driver.pathBehaviorResult or "na")
    exec.activityResult.reset_ok = driver.stepResetOk
    exec.activityResult.reset_attempts = tonumber(driver.stepResetAttemptCount) or 0
    exec.activityResult.reset_error = tostring(driver.stepResetError or "none")
    exec.activityResult.forward_rearm_attempts = tonumber(driver.forwardRearmAttempts) or 0
    exec.activityResult.forward_rearm_failures = tonumber(driver.forwardRearmFailures) or 0
    exec.activityResult.teleport_jump_count = tonumber(driver.teleportJumpCount) or 0
    exec.activityResult.anchor_start_err_tiles = tonumber(driver.anchorStartErrorTiles)
    exec.activityResult.anchor_end_err_tiles = tonumber(anchorEndError)
    exec.activityResult.goal_x = tonumber(driver.forwardGoalX)
    exec.activityResult.goal_y = tonumber(driver.forwardGoalY)
    exec.activityResult.anchor_delta_before_start = tonumber(driver.anchorDeltaBeforeStart) or tonumber(driver.anchorStartErrorTiles)
    exec.activityResult.anchor_delta_after_post_reset = tonumber(driver.anchorDeltaAfterPostReset)
    exec.activityResult.sample_window_sec = elapsedSec
    exec.activityResult.total_samples = totalSamples
    exec.activityResult.valid_samples = tonumber(driver.validSamples) or 0
    exec.activityResult.moving_samples = tonumber(driver.movingSamples) or 0
    exec.activityResult.stall_sec_accum = tonumber(driver.stallSecAccum) or 0
    exec.activityResult.stall_reason_counts = formatStallReasonCounts(driver.stallReasonCounts)
    local topStallReason = "none"
    local topStallCount = 0
    local stallCounts = type(driver.stallReasonCounts) == "table" and driver.stallReasonCounts or nil
    if stallCounts ~= nil then
        for reasonTag, count in pairs(stallCounts) do
            local numeric = tonumber(count) or 0
            local reason = tostring(reasonTag or "none")
            if numeric > topStallCount or (numeric == topStallCount and reason < topStallReason) then
                topStallReason = reason
                topStallCount = numeric
            end
        end
    end
    exec.activityResult.stall_reason = topStallReason
    local phaseEvents = type(driver.phaseTimelineEvents) == "table" and driver.phaseTimelineEvents or {}
    exec.activityResult.phase_timeline = (#phaseEvents > 0) and table.concat(phaseEvents, "|") or "none"
    exec.activityResult.achieved_swings = tonumber(driver.achievedSwings) or 0
    exec.activityResult.achieved_sec = elapsedSec
    exec.activityResult.requested_sec = exec.activityResult.requested_sec or tonumber(driver.targetSec) or 0
    exec.activityResult.requested_swings = exec.activityResult.requested_swings or tonumber(driver.targetSwings) or 0

    if driver.probeEnabled then
        local probeTotal = math.max(1, tonumber(driver.probeSamples) or 0)
        local justMovedRatio = (tonumber(driver.probeJustMovedSamples) or 0) / probeTotal
        local npcRatio = (tonumber(driver.probeNPCSamples) or 0) / probeTotal
        local shouldMoveRatio = (tonumber(driver.probePathShouldMoveSamples) or 0) / probeTotal
        local claimedNoProgressRatio = totalSamples > 0 and ((tonumber(driver.movingClaimedNoProgressSamples) or 0) / totalSamples) or 0
        local log = ctx("log")
        if type(log) == "function" then
            log(string.format(
                "[AMS_NATIVE_PROBE_SUMMARY] id=%s scenario=%s samples=%d just_moved_ratio=%s npc_ratio=%s should_move_ratio=%s claimed_no_progress_ratio=%s distance_moved=%s nav_mode=%s",
                tostring(exec and exec.runId or "na"),
                tostring(exec and exec.scenarioId or "na"),
                tonumber(driver.probeSamples) or 0,
                metricOrNa(justMovedRatio, 4),
                metricOrNa(npcRatio, 4),
                metricOrNa(shouldMoveRatio, 4),
                metricOrNa(claimedNoProgressRatio, 4),
                metricOrNa(driver.distanceMoved, 3),
                tostring(driver.movementMode or "na")
            ))
        end
    end

    unregisterNativeTickPump()
    if driver.useTestAIMode then
        setIsoPlayerTestAIMode(false)
    end
    if driver.mode == "native_combat_air" then
        safeMethod(player, "setLastHitCount", 0)
    end
    clearNativeMovementState(player, driver)
    if driver.movementMode == "forward" and driver.stepBoundaryReset == true and driver.resetToAnchor == true then
        nativeDriverRecordPhaseEvent(driver, nowMinutes(), "post_reset")
        local postOk, postErr = nativeDriverResetToAnchor(player, driver, "post")
        if postOk then
            local px, py = readPlayerCoords(player)
            driver.anchorDeltaAfterPostReset = distance2D(px, py, tonumber(driver.anchorX) or px, tonumber(driver.anchorY) or py)
            exec.activityResult.anchor_delta_after_post_reset = tonumber(driver.anchorDeltaAfterPostReset) or 0
        end
        if not postOk and outcome == "done" then
            outcome = "soft_fail"
            reason = tostring(postErr or "native_soft_post_reset_failed")
        end
    end
    nativeDriverRecordPhaseEvent(driver, nowMinutes(), "done")
    if type(driver.phaseTimelineEvents) == "table" and #driver.phaseTimelineEvents > 0 then
        exec.activityResult.phase_timeline = table.concat(driver.phaseTimelineEvents, "|")
    end

    if outcome == "done" then
        exec.activityResult.step_validity = "valid"
        exec.activityResult.exit_reason = "completed"
        return "done", nil
    end
    if outcome == "soft_fail" then
        exec.activityResult.step_validity = "soft_fail"
        exec.activityResult.exit_reason = tostring(reason or "native_soft_unknown")
        return "soft_fail", nil
    end
    exec.activityResult.step_validity = "hard_fail"
    exec.activityResult.exit_reason = tostring(reason or "native_hard_unknown")
    exec.activityResult.hard_fail = true
    return "hard_fail", tostring(reason or "native_hard_unknown")
end

local function tickNativeDriver(player, exec)
    local driver = exec and exec.nativeDriver
    if not driver then
        return "hard_fail", "native_hard_missing_driver"
    end

    local now = nowMinutes()
    local previousTickAt = tonumber(driver.lastTickAt) or now
    if now < previousTickAt then
        previousTickAt = now
    end
    local tickDeltaSec = math.max(0.0, (now - previousTickAt) * 60.0)
    driver.lastTickAt = now

    local climate = readClimateSnapshot(player)
    local x = tonumber(climate.x) or 0
    local y = tonumber(climate.y) or 0
    local moved = distance2D(x, y, driver.lastX or x, driver.lastY or y)
    local teleportThreshold = math.max(4.0, tonumber(driver.teleportDeltaThreshold) or 8.0)
    if moved > teleportThreshold then
        moved = 0
        driver.teleportJumpCount = (tonumber(driver.teleportJumpCount) or 0) + 1
        driver.progressRefX = x
        driver.progressRefY = y
        driver.lastProgressAt = now
    end
    driver.lastX = x
    driver.lastY = y
    driver.lastZ = tonumber(climate.z) or driver.lastZ

    -- Ignore pre-start settle ticks so startup lock does not distort validity/sample ratios.
    if driver.startedAt == nil then
        driver.progressRefX = x
        driver.progressRefY = y
        driver.lastProgressAt = now
        moved = 0
    else
        driver.distanceMoved = (tonumber(driver.distanceMoved) or 0) + moved
        driver.totalSamples = (tonumber(driver.totalSamples) or 0) + 1
    end

    local elapsedSec = math.max(0, (now - (driver.startedAt or now)) * 60.0)
    local moving = safeMethod(player, "isPlayerMoving") == true or safeMethod(player, "isMoving") == true
    local isJustMoved = safeMethod(player, "isJustMoved")
    local isRunning = safeMethod(player, "isRunning") == true
    local isSprinting = safeMethod(player, "isSprinting") == true
    local isNPC = safeMethod(player, "isNPC")
    local isAiming = safeMethod(player, "isAiming")
    local movementSpeed = tonumber(safeMethod(player, "getMovementSpeed"))
    if driver.startedAt ~= nil and movementSpeed ~= nil then
        driver.speedSum = (tonumber(driver.speedSum) or 0) + movementSpeed
        driver.speedSamples = (tonumber(driver.speedSamples) or 0) + 1
    end
    local movementSampleEpsilon = math.max(0.0025, tonumber(driver.movementSampleEpsilon) or ((tonumber(driver.progressEpsilon) or 0.025) * 0.35))
    local movedForUptime = moved >= movementSampleEpsilon
    local movementClaimed = moving or isJustMoved == true
    if driver.startedAt ~= nil then
        local combatLabel = false
        if driver.mode == "native_combat_air" then
            combatLabel = (isAiming == true) or ((tonumber(driver.attackAttempts) or 0) > 0)
        end

        if combatLabel then
            driver.combatTicks = (tonumber(driver.combatTicks) or 0) + 1
        else
            -- Speed-tier classification using per-tick displacement from getMovementSpeed().
            -- Thresholds derived from observed data: sprint >=0.08, run >=0.04, walk >=0.005.
            -- isSprinting/isRunning flags are kept as telemetry above but not used for tick bins.
            local speed = movementSpeed or 0
            if speed >= 0.08 then
                driver.sprintTicks = (tonumber(driver.sprintTicks) or 0) + 1
            elseif speed >= 0.04 then
                driver.runTicks = (tonumber(driver.runTicks) or 0) + 1
            elseif speed >= 0.005 then
                driver.walkTicks = (tonumber(driver.walkTicks) or 0) + 1
            else
                driver.idleTicks = (tonumber(driver.idleTicks) or 0) + 1
            end
        end
    end
    if driver.startedAt ~= nil then
        if movedForUptime then
            driver.movingSamples = (tonumber(driver.movingSamples) or 0) + 1
            safeMethod(player, "setJustMoved", true)
            nativeDriverRecordPhaseEvent(driver, now, "moving")
        elseif movementClaimed then
            driver.movingClaimedNoProgressSamples = (tonumber(driver.movingClaimedNoProgressSamples) or 0) + 1
            nativeDriverAddStallReason(driver, "claimed_no_progress", tickDeltaSec)
        elseif driver.movementMode == "forward" then
            nativeDriverAddStallReason(driver, "idle_no_motion", tickDeltaSec)
        end
    end

    local progressRefX = tonumber(driver.progressRefX) or x
    local progressRefY = tonumber(driver.progressRefY) or y
    local progressDistance = distance2D(x, y, progressRefX, progressRefY)
    if progressDistance >= (driver.progressEpsilon or 0.025) then
        driver.lastProgressAt = now
        driver.pathRetryStreak = 0
        driver.progressRefX = x
        driver.progressRefY = y
    end

    if driver.startedAt ~= nil then
        driver.validSamples = (tonumber(driver.validSamples) or 0) + 1
    end

    if driver.mode == "native_move" or driver.mode == "native_warmup" or driver.mode == "native_treadmill_simple" then
        applyNativeActivityMode(player, driver.activity)

        if driver.movementMode == "forward" then
            local dx = tonumber(driver.forwardDirX) or 1.0
            local dy = tonumber(driver.forwardDirY) or 0.0
            if driver.forwardStartPending == true then
                nativeDriverRecordPhaseEvent(driver, now, "start_lock")
                local anchorX = tonumber(driver.anchorX) or x
                local anchorY = tonumber(driver.anchorY) or y
                local anchorZ = tonumber(driver.anchorZ) or driver.lastZ
                local anchorTol = math.max(0.10, tonumber(driver.forwardAnchorTolerance) or 0.35)
                local startDeadlineAt = tonumber(driver.forwardStartDeadlineAt) or (now + (12.0 / 60.0))
                if driver.resetToAnchor == true and distance2D(x, y, anchorX, anchorY) > anchorTol then
                    nativeDriverRecordPhaseEvent(driver, now, "pre_reset")
                    local resetOk = nativeDriverResetToAnchor(player, driver, "pre")
                    if not resetOk and driver.strictStepReset == true then
                        return "soft_fail", tostring(driver.stepResetError or "native_soft_reset_failed")
                    end
                    x, y = readPlayerCoords(player)
                end
                if now > startDeadlineAt then
                    return "soft_fail", "native_soft_start_lock_timeout"
                end

                safeMethod(player, "setPath2", nil)
                safeMethod(player, "setMoving", false)
                safeMethod(player, "setRunning", false)
                safeMethod(player, "setSprinting", false)
                safeMethod(player, "setForwardDirection", dx, dy)
                safeMethod(player, "faceLocationF", anchorX + (dx * 8.0), anchorY + (dy * 8.0))

                if now < (tonumber(driver.forwardStartReadyAt) or now) then
                    return "pending", nil
                end

                local issued = nativeDriverIssueForwardPath(player, driver)
                if not issued then
                    local rearmOk = nativeDriverForceForwardRearm(player, driver, now, "native_forward_bootstrap_rearm")
                    if not rearmOk then
                        return "soft_fail", "native_soft_forward_rearm_failed"
                    end
                end
                driver.pathState = readNativePathState(player)
                if nativePathStateActive(driver.pathState) then
                    local ax = tonumber(driver.anchorX) or anchorX
                    local ay = tonumber(driver.anchorY) or anchorY
                    driver.anchorStartErrorTiles = distance2D(x, y, ax, ay)
                    driver.anchorDeltaBeforeStart = driver.anchorStartErrorTiles
                    driver.startedAt = now
                    driver.lastTickAt = now
                    driver.lastProgressAt = now
                    driver.forwardStartPending = false
                    driver.lastPathAcceptedAt = now
                    nativeDriverRecordPhaseEvent(driver, now, "moving")
                end
                return "pending", nil
            end

            local forwardRearmLimit = math.max(1, math.floor(tonumber(driver.forwardRearmMaxAttempts) or 4))
            local behaviorFailed = false
            if driver.behavior and driver.canBehaviorUpdate then
                local behaviorResult = safeMethod(driver.behavior, "update")
                if behaviorResult ~= nil then
                    local resultTag = tostring(behaviorResult)
                    driver.pathBehaviorResult = resultTag
                    behaviorFailed = string.find(resultTag, "Failed", 1, true) ~= nil
                end
            end
            driver.pathState = readNativePathState(player)
            safeMethod(player, "setForwardDirection", dx, dy)
            safeMethod(player, "faceLocationF", x + (dx * 8.0), y + (dy * 8.0))
            if behaviorFailed then
                nativeDriverAddStallReason(driver, "native_forward_behavior_failed", tickDeltaSec)
                nativeDriverForceForwardRearm(player, driver, now, "native_forward_behavior_failed")
                driver.pathState = readNativePathState(player)
            elseif nativePathStateActive(driver.pathState) then
                driver.lastPathAcceptedAt = now
                nativeDriverRecordPhaseEvent(driver, now, "moving")
            elseif now - (driver.lastPathIssueAt or 0) >= (tonumber(driver.forwardRepathEveryMin) or (0.50 / 60.0)) then
                nativeDriverAddStallReason(driver, "native_forward_path_inactive", tickDeltaSec)
                nativeDriverForceForwardRearm(player, driver, now, "native_forward_path_inactive")
                driver.pathState = readNativePathState(player)
            end
            if (tonumber(driver.forwardRearmFailures) or 0) >= forwardRearmLimit then
                return "soft_fail", "native_soft_forward_rearm_failed"
            end
            if elapsedSec >= (driver.targetSec or 0) then
                return "done", nil
            end
            return "pending", nil
        end

        if driver.behavior and driver.canBehaviorUpdate then
            local behaviorResult = safeMethod(driver.behavior, "update")
            if behaviorResult ~= nil then
                local resultTag = tostring(behaviorResult)
                driver.pathBehaviorResult = resultTag
                if string.find(resultTag, "Failed", 1, true) then
                    if nativeDriverRetryPath(player, driver, now, x, y, driver.lastZ) then
                        return "pending", nil
                    end
                    return "soft_fail", "native_soft_path_failed"
                end
                if string.find(resultTag, "Succeeded", 1, true) then
                    driver.lastProgressAt = now
                    driver.pathRetryStreak = 0
                end
            end
        end

        driver.pathState = readNativePathState(player)

        if driver.waypoints and #driver.waypoints > 0 then
            local target = driver.waypoints[driver.waypointIndex]
            if target and distance2D(x, y, target.x, target.y) <= (driver.waypointReachDistance or 0.7) then
                local previousIndex = driver.waypointIndex
                driver.waypointIndex = (driver.waypointIndex % #driver.waypoints) + 1
                if previousIndex == #driver.waypoints and driver.waypointIndex == 1 then
                    driver.lapsCompleted = (tonumber(driver.lapsCompleted) or 0) + 1
                end
                driver.lastProgressAt = now
                driver.pathRetryStreak = 0
                nativeDriverIssuePath(player, driver)
            elseif now - (driver.lastPathIssueAt or 0) >= (driver.pathIssueEveryMin or 0.05) then
                if not nativePathStateActive(driver.pathState) then
                    nativeDriverIssuePath(player, driver)
                    driver.pathState = readNativePathState(player)
                end
            end
        end

        if nativePathStateActive(driver.pathState) then
            driver.lastPathAcceptedAt = now
        end

        if driver.probeEnabled then
            local probeJustMoved = safeMethod(player, "isJustMoved")
            local probeIsNPC = safeMethod(player, "isNPC")
            local probeState = driver.pathState or {}
            driver.probeSamples = (tonumber(driver.probeSamples) or 0) + 1
            if probeJustMoved == true then
                driver.probeJustMovedSamples = (tonumber(driver.probeJustMovedSamples) or 0) + 1
            end
            if probeIsNPC == true then
                driver.probeNPCSamples = (tonumber(driver.probeNPCSamples) or 0) + 1
            end
            if probeState.shouldBeMoving == true then
                driver.probePathShouldMoveSamples = (tonumber(driver.probePathShouldMoveSamples) or 0) + 1
            end

            if now - (driver.probeLastAt or 0) >= (driver.probeEveryMin or 0.0166) then
                driver.probeLastAt = now
                logNativeProbe(exec, driver, {
                    elapsedSec = elapsedSec,
                    x = x,
                    y = y,
                    moved = moved,
                    justMoved = probeJustMoved,
                    isNPC = probeIsNPC,
                    isAiming = safeMethod(player, "isAiming"),
                    hasPath = probeState.hasPath,
                    goalLocation = probeState.goalLocation,
                    movingUsingPath = probeState.movingUsingPath,
                    startedMoving = probeState.startedMoving,
                    shouldBeMoving = probeState.shouldBeMoving,
                    pathLength = probeState.pathLength,
                })
            end
        end

        if now - (driver.lastPathAcceptedAt or driver.startedAt or now) > (driver.pathAcceptTimeoutMin or 0.12) then
            if nativeDriverRetryPath(player, driver, now, x, y, driver.lastZ) then
                return "pending", nil
            end
            return "soft_fail", "native_soft_path_unavailable"
        end

        if now - (driver.lastProgressAt or now) > (driver.stallLimitMin or 0.5) then
            if nativeDriverRetryPath(player, driver, now, x, y, driver.lastZ) then
                return "pending", nil
            end
            return "soft_fail", "native_soft_path_stalled"
        end
        if driver.completionMode == "laps" and (tonumber(driver.targetLaps) or 0) > 0 then
            if (tonumber(driver.lapsCompleted) or 0) >= (tonumber(driver.targetLaps) or 0) then
                return "done", nil
            end
        elseif elapsedSec >= (driver.targetSec or 0) then
            return "done", nil
        end
        return "pending", nil
    end

    if driver.mode == "native_combat_air" then
        if driver.combatStandStill then
            stabilizeNativeCombatStance(player, true)
        else
            applyNativeActivityMode(player, "walk")
        end

        safeMethod(player, "setIsAiming", true)

        local canAttack = safeMethod(player, "CanAttack")
        local meleeDelayBefore = tonumber(safeMethod(player, "getMeleeDelay")) or 0
        local attackStartedBefore = safeMethod(player, "isAttackStarted")
        local attackCooldownMin = tonumber(driver.attackCooldownMin) or (0.22 / 60.0)
        local sinceAttempt = now - (tonumber(driver.lastAttackAttemptAt) or (now - attackCooldownMin))
        local sinceSuccess = now - (tonumber(driver.lastAttackSuccessAt) or (now - attackCooldownMin))
        local attackCooldownReady = sinceAttempt >= attackCooldownMin and sinceSuccess >= attackCooldownMin
        local attackReady = canAttack ~= false and meleeDelayBefore <= 0 and attackStartedBefore ~= true and attackCooldownReady

        if attackReady then
            driver.lastAttackAttemptAt = now
            local attackIssued = safeMethod(player, "AttemptAttack")
            if attackIssued == nil then
                safeMethod(player, "DoAttack", 1.0)
            end
            driver.attackAttempts = (tonumber(driver.attackAttempts) or 0) + 1

            local meleeDelayAfter = tonumber(safeMethod(player, "getMeleeDelay")) or 0
            local attackStartedAfter = safeMethod(player, "isAttackStarted")
            local attackAccepted = meleeDelayAfter > math.max(0, meleeDelayBefore)
            if not attackAccepted and attackStartedBefore ~= true and attackStartedAfter == true then
                attackAccepted = true
            end
            if attackAccepted then
                driver.attackSuccess = (tonumber(driver.attackSuccess) or 0) + 1
                driver.achievedSwings = (tonumber(driver.achievedSwings) or 0) + 1
                driver.lastAttackSuccessAt = now
                driver.lastProgressAt = now
            end
        elseif canAttack ~= false and meleeDelayBefore <= 0 and attackStartedBefore ~= true and not attackCooldownReady then
            driver.attackCooldownBlocks = (tonumber(driver.attackCooldownBlocks) or 0) + 1
        end

        if (tonumber(driver.targetSwings) or 0) > 0
            and (tonumber(driver.achievedSwings) or 0) >= (tonumber(driver.targetSwings) or 0) then
            return "done", nil
        end
        if elapsedSec >= (driver.timeoutSec or 0) then
            return (tonumber(driver.targetSwings) or 0) > 0 and "soft_fail" or "done",
                (tonumber(driver.targetSwings) or 0) > 0 and "native_soft_attack_timeout" or nil
        end
        return "pending", nil
    end

    return "hard_fail", "native_hard_unknown_mode"
end

-- -----------------------------------------------------------------------------
-- Public API (only expose what BenchRunner actually calls)
-- -----------------------------------------------------------------------------

local function exposeWithDeps(name, impl)
    BenchRunnerNative[name] = function(...)
        local argc = select("#", ...)
        if argc <= 0 then
            return impl()
        end
        local args = {...}
        setDeps(args[argc])
        args[argc] = nil
        return impl(unpack(args, 1, argc - 1))
    end
end

exposeWithDeps("startNativeDriver", startNativeDriver)
exposeWithDeps("tickNativeDriver", tickNativeDriver)
exposeWithDeps("finalizeNativeActivity", finalizeNativeActivity)

return BenchRunnerNative
