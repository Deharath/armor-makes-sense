ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.SleepHooks = ArmorMakesSense.SleepHooks or {}

require "ArmorMakesSense_MPCompat"
local Utils = require "ArmorMakesSense_UtilsShared"

local SleepHooks = ArmorMakesSense.SleepHooks
local MP = ArmorMakesSense.MP or {}

local function log(message)
    print("[ArmorMakesSense] " .. tostring(message))
end

local safeMethod = Utils.safeMethod

local function getCompat()
    local compat = ArmorMakesSense.Compat or rawget(_G, "MakesSenseCompat")
    if type(compat) ~= "table"
        or type(compat.getCallback) ~= "function"
        or type(compat.computePlannerExtraHours) ~= "function" then
        return nil
    end
    return compat
end

local function cmsOwnsPlanner()
    local compat = getCompat()
    return compat
        and type(compat.hasCapability) == "function"
        and compat:hasCapability("CaffeineMakesSense", "sleep_planner_coordinator")
end

local function getPlayerFromIndex(playerIndex)
    if type(getSpecificPlayer) == "function" then
        local ok, player = pcall(getSpecificPlayer, playerIndex)
        if ok and player then
            return player
        end
    end
    if type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok then
            return player
        end
    end
    return nil
end

local function sendSleepBedType(bedType)
    if type(isClient) ~= "function" or isClient() ~= true or type(sendClientCommand) ~= "function" then
        return
    end
    pcall(sendClientCommand, tostring(MP.NET_MODULE), tostring(MP.SLEEP_BED_TYPE_COMMAND), {
        bed_type = tostring(bedType or ""),
    })
end

local function collectPenaltyFractions(player, baseHours)
    local compat = getCompat()
    if not compat then
        return nil, {}
    end
    local penalties = {}
    local providers = { "CaffeineMakesSense", "ArmorMakesSense" }
    for i = 1, #providers do
        local callback = compat:getCallback(providers[i], "estimateSleepPlannerPenalty")
        if type(callback) == "function" then
            local ok, result = pcall(callback, player, { baseHours = baseHours })
            local penalty = ok and type(result) == "table" and tonumber(result.penaltyFraction) or 0
            if penalty and penalty > 0 then
                penalties[#penalties + 1] = penalty
            end
        end
    end
    return compat, penalties
end

local function computeAdjustedHours(player, baseHours)
    local base = math.max(0, tonumber(baseHours) or 0)
    local compat, penalties = collectPenaltyFractions(player, base)
    if not compat or #penalties == 0 then
        return base
    end
    local combined = compat.combinePenaltyFractions(penalties)
    return base + compat.computePlannerExtraHours(base, combined)
end

local function usesServerSleepFlow()
    if type(isClient) ~= "function" or isClient() ~= true then
        return false
    end
    if type(getServerOptions) ~= "function" then
        return false
    end
    local serverOptions = getServerOptions()
    return safeMethod(serverOptions, "getBoolean", "SleepAllowed") == true
end

local function wrapSleepDialog()
    if ArmorMakesSense._sleepDialogPlannerWrapped then
        return
    end
    pcall(require, "ISUI/ISSleepDialog")
    if type(ISSleepDialog) ~= "table" or type(ISSleepDialog.initialise) ~= "function" then
        return
    end
    local original = ISSleepDialog.initialise
    ISSleepDialog.initialise = function(self)
        original(self)
        local player = self and self.player
        local spinBox = self and self.spinBox
        local baseHours = tonumber(spinBox and spinBox.selected)
        if not player or not spinBox or not baseHours or baseHours <= 0 then
            return
        end
        local adjusted = math.max(baseHours, math.floor(computeAdjustedHours(player, baseHours) + 0.5))
        for hour = baseHours + 1, adjusted do
            spinBox:addOption(getText("IGUI_Sleep_NHours", hour))
        end
        spinBox.selected = adjusted
    end
    ArmorMakesSense._sleepDialogPlannerWrapped = true
end

local function wrapAutoSleep()
    if ArmorMakesSense._autoSleepPlannerWrapped then
        return
    end
    pcall(require, "ISUI/ISWorldObjectContextMenu")
    if type(ISWorldObjectContextMenu) ~= "table"
        or type(ISWorldObjectContextMenu.onSleepWalkToComplete) ~= "function" then
        return
    end

    local original = ISWorldObjectContextMenu.onSleepWalkToComplete
    ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerIndex, bed)
        local result = original(playerIndex, bed)
        local player = getPlayerFromIndex(playerIndex)
        if not player or safeMethod(player, "isAsleep") ~= true then
            return result
        end

        local gameTime = nil
        if GameTime and type(GameTime.getInstance) == "function" then
            local ok, instance = pcall(GameTime.getInstance)
            gameTime = ok and instance or nil
        end
        local timeOfDay = tonumber(gameTime and safeMethod(gameTime, "getTimeOfDay"))
        local wakeHour = tonumber(safeMethod(player, "getForceWakeUpTime"))
        if timeOfDay == nil or wakeHour == nil then
            return result
        end
        local baseHours = (wakeHour - timeOfDay) % 24
        local adjustedHours = computeAdjustedHours(player, baseHours)
        local adjustedWakeHour = (timeOfDay + adjustedHours) % 24
        safeMethod(player, "setForceWakeUpTime", adjustedWakeHour)

        -- Vanilla delegates this branch to the server and deliberately skips
        -- SleepingEvent setup on the multiplayer client.
        if not usesServerSleepFlow() then
            local sleepingEvent = type(getSleepingEvent) == "function" and getSleepingEvent() or nil
            safeMethod(sleepingEvent, "setPlayerFallAsleep", player, adjustedHours)
        end
        sendSleepBedType(safeMethod(player, "getBedType"))
        return result
    end
    ArmorMakesSense._autoSleepPlannerWrapped = true
end

function SleepHooks.wrapSleepPlanning()
    if cmsOwnsPlanner() then
        if not ArmorMakesSense._sleepPlannerHooksLogged then
            ArmorMakesSense._sleepPlannerHooksLogged = true
            log("sleep planner hooks delegated to CMS coordinator")
        end
        return false
    end
    wrapSleepDialog()
    wrapAutoSleep()
    if not ArmorMakesSense._sleepPlannerHooksLogged then
        ArmorMakesSense._sleepPlannerHooksLogged = true
        log("wrapped sleep duration hooks")
    end
    return true
end

return SleepHooks
