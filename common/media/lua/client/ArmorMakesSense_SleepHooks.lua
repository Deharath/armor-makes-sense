ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.SleepHooks = ArmorMakesSense.SleepHooks or {}

local SleepHooks = ArmorMakesSense.SleepHooks

local function log(msg)
    print("[ArmorMakesSense] " .. tostring(msg))
end

local function getCompat()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table" then
        return nil
    end
    if type(compat.getCallback) ~= "function" or type(compat.computePlannerExtraHours) ~= "function" then
        return nil
    end
    return compat
end

local function cmsOwnsPlanner()
    local compat = getCompat()
    return type(compat) == "table"
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("CaffeineMakesSense", "sleep_planner_coordinator")
end

local function getTimeOfDay()
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    if not gameTime then
        return nil
    end
    local ok, value = pcall(gameTime.getTimeOfDay, gameTime)
    if not ok then
        return nil
    end
    return tonumber(value)
end

local function getPlayerFromIndex(playerIndex)
    if type(getSpecificPlayer) == "function" then
        local ok, playerObj = pcall(getSpecificPlayer, playerIndex)
        if ok and playerObj then
            return playerObj
        end
    end
    if type(getPlayer) == "function" then
        local ok, playerObj = pcall(getPlayer)
        if ok and playerObj then
            return playerObj
        end
    end
    return nil
end

local function computeAdjustedHours(playerObj, baseHours)
    if cmsOwnsPlanner() then
        return tonumber(baseHours) or 0
    end

    local compat = getCompat()
    if not compat then
        return tonumber(baseHours) or 0
    end

    local callback = compat:getCallback("ArmorMakesSense", "estimateSleepPlannerPenalty")
    if type(callback) ~= "function" then
        return tonumber(baseHours) or 0
    end

    local ok, result = pcall(callback, playerObj, { baseHours = baseHours })
    local penalty = ok and type(result) == "table" and (tonumber(result.penaltyFraction) or 0) or 0
    if penalty <= 0 then
        return tonumber(baseHours) or 0
    end

    local extraHours = compat.computePlannerExtraHours(baseHours, penalty)
    return (tonumber(baseHours) or 0) + extraHours
end

local function adjustForceWakeTime(playerObj)
    if cmsOwnsPlanner() then
        return
    end
    if not playerObj or type(playerObj.isAsleep) ~= "function" or playerObj:isAsleep() ~= true then
        return
    end

    local compat = getCompat()
    local timeOfDay = getTimeOfDay()
    local wakeHour = type(playerObj.getForceWakeUpTime) == "function" and playerObj:getForceWakeUpTime() or nil
    local baseHours = compat and compat.computeHoursUntilWake(timeOfDay, wakeHour) or nil
    if baseHours == nil or baseHours <= 0 then
        return
    end

    local adjustedHours = computeAdjustedHours(playerObj, baseHours)
    if adjustedHours <= (baseHours + 0.01) then
        return
    end

    local adjustedWakeHour = compat.computeWakeHourFromNow(timeOfDay, adjustedHours)
    if adjustedWakeHour ~= nil and type(playerObj.setForceWakeUpTime) == "function" then
        playerObj:setForceWakeUpTime(adjustedWakeHour)
    end
end

local function wrapSleepDialog()
    if ArmorMakesSense._sleepDialogPlannerWrapped then
        return
    end

    pcall(require, "ISUI/ISSleepDialog")
    if type(ISSleepDialog) ~= "table" or type(ISSleepDialog.initialise) ~= "function" then
        return
    end

    local originalInitialise = ISSleepDialog.initialise
    ISSleepDialog.initialise = function(self)
        originalInitialise(self)

        if cmsOwnsPlanner() then
            return
        end

        local playerObj = self and self.player or nil
        local spinBox = self and self.spinBox or nil
        local baseHours = tonumber(spinBox and spinBox.selected) or nil
        if not playerObj or not spinBox or baseHours == nil or baseHours <= 0 then
            return
        end

        local adjustedHours = computeAdjustedHours(playerObj, baseHours)
        local roundedHours = math.max(baseHours, math.floor(adjustedHours + 0.5))
        for hour = baseHours + 1, roundedHours do
            spinBox:addOption(getText("IGUI_Sleep_NHours", hour))
        end
        spinBox.selected = roundedHours
    end

    ArmorMakesSense._sleepDialogPlannerWrapped = true
end

local function wrapAutoSleep()
    if ArmorMakesSense._autoSleepPlannerWrapped then
        return
    end

    pcall(require, "ISUI/ISWorldObjectContextMenu")
    if type(ISWorldObjectContextMenu) ~= "table" or type(ISWorldObjectContextMenu.onSleepWalkToComplete) ~= "function" then
        return
    end

    local originalOnSleepWalkToComplete = ISWorldObjectContextMenu.onSleepWalkToComplete
    ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerIndex, bed)
        originalOnSleepWalkToComplete(playerIndex, bed)
        local playerObj = getPlayerFromIndex(playerIndex)
        if playerObj then
            adjustForceWakeTime(playerObj)
        end
    end

    ArmorMakesSense._autoSleepPlannerWrapped = true
end

function SleepHooks.wrapSleepPlanning()
    wrapSleepDialog()
    wrapAutoSleep()
    if ArmorMakesSense._sleepPlannerHooksLogged ~= true then
        ArmorMakesSense._sleepPlannerHooksLogged = true
        log("wrapped sleep planner hooks")
    end
end

return SleepHooks
