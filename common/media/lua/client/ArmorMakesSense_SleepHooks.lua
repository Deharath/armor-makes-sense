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

local function isMultiplayerSession()
    return (type(isClient) == "function" and isClient() == true)
        or (type(isServer) == "function" and isServer() == true)
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

local function stringContains(value, needle)
    local text = tostring(value or "")
    if type(text.contains) == "function" then
        return text:contains(needle)
    end
    return string.find(text, needle, 1, true) ~= nil
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
    if cmsOwnsPlanner() then
        return
    end

    pcall(require, "ISUI/ISWorldObjectContextMenu")
    if type(ISWorldObjectContextMenu) ~= "table" or type(ISWorldObjectContextMenu.onSleepWalkToComplete) ~= "function" then
        return
    end

    ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerIndex, bed)
        local playerObj = getPlayerFromIndex(playerIndex)
        if not playerObj then
            return
        end

        local stats = type(playerObj.getStats) == "function" and playerObj:getStats() or nil
        local moodles = type(playerObj.getMoodles) == "function" and playerObj:getMoodles() or nil
        local isZombies = stats and (
            (tonumber(stats:getNumVisibleZombies()) or 0) > 0
            or (tonumber(stats:getNumChasingZombies()) or 0) > 0
            or (tonumber(stats:getNumVeryCloseZombies()) or 0) > 0
        ) or false
        if isZombies then
            HaloTextHelper.addBadText(playerObj, getText("IGUI_Sleep_NotSafe"))
            return
        end

        if (tonumber(playerObj:getSleepingTabletEffect()) or 0) < 2000 then
            local fatigue = stats and stats:get(CharacterStat.FATIGUE) or 0
            if moodles and moodles:getMoodleLevel(MoodleType.PAIN) >= 2 and fatigue <= 0.85 then
                HaloTextHelper.addBadText(playerObj, getText("ContextMenu_PainNoSleep"))
                return
            end
            if moodles and moodles:getMoodleLevel(MoodleType.PANIC) >= 1 then
                HaloTextHelper.addBadText(playerObj, getText("ContextMenu_PanicNoSleep"))
                return
            end
        end

        if playerObj:getVariableBoolean("ExerciseEnded") == false then
            return
        end

        ISTimedActionQueue.clear(playerObj)

        local fatigue = tonumber(stats and stats:get(CharacterStat.FATIGUE)) or 0
        local sleepFor = ZombRand(fatigue * 10, fatigue * 13) + 1
        local bedType = ISWorldObjectContextMenu.getBedQuality(playerObj, bed)
        if bedType == "goodBed" or stringContains(bedType, "goodBedPillow") then
            sleepFor = sleepFor - 1
        end
        if bedType == "badBed" or stringContains(bedType, "badBedPillow") then
            sleepFor = sleepFor + 1
        end
        if bedType == "floor" or stringContains(bedType, "floorPillow") then
            sleepFor = sleepFor * 0.7
        end
        if playerObj:hasTrait(CharacterTrait.INSOMNIAC) then
            sleepFor = sleepFor * 0.5
        end
        if playerObj:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then
            sleepFor = sleepFor * 0.75
        end
        if playerObj:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then
            sleepFor = sleepFor * 1.18
        end
        if sleepFor > 16 then
            sleepFor = 16
        end
        if sleepFor < 3 then
            sleepFor = 3
        end

        sleepFor = computeAdjustedHours(playerObj, sleepFor)

        local gameTime = GameTime.getInstance()
        local sleepHours = sleepFor + gameTime:getTimeOfDay()
        if sleepHours >= 24 then
            sleepHours = sleepHours - 24
        end

        playerObj:setBed(bed)
        playerObj:setBedType(bedType)
        playerObj:setForceWakeUpTime(tonumber(sleepHours))
        playerObj:setAsleepTime(0.0)
        playerObj:setAsleep(true)

        if playerObj:getVehicle() then
            playerObj:playSound("VehicleGoToSleep")
        end

        if isClient() and getServerOptions():getBoolean("SleepAllowed") then
            UIManager.setFadeBeforeUI(playerIndex, true)
            UIManager.FadeOut(playerIndex, 1)
            if playerObj:getVehicle() then
                sendClientCommand(playerObj, "player", "onVehicleSleep", { id = playerObj:getOnlineID(), isAsleep = true })
            end
            return
        end

        getSleepingEvent():setPlayerFallAsleep(playerObj, sleepFor)
        UIManager.setFadeBeforeUI(playerObj:getPlayerNum(), true)
        UIManager.FadeOut(playerObj:getPlayerNum(), 1)

        if IsoPlayer.allPlayersAsleep() then
            UIManager.getSpeedControls():SetCurrentGameSpeed(3)
            save(true)
        end
    end

    ArmorMakesSense._autoSleepPlannerWrapped = true
end

function SleepHooks.wrapSleepPlanning()
    if isMultiplayerSession() then
        return
    end
    wrapSleepDialog()
    wrapAutoSleep()
    if ArmorMakesSense._sleepPlannerHooksLogged ~= true then
        ArmorMakesSense._sleepPlannerHooksLogged = true
        log("wrapped sleep planner hooks")
    end
end

return SleepHooks
