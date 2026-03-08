ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.SupportReport = Core.SupportReport or {}

local SupportReport = Core.SupportReport
local C = {}

local function ctx(name)
    return C[name]
end

function SupportReport.setContext(context)
    C = context or {}
end

local function callGlobalIfPresent(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then
        return nil
    end
    return fn(...)
end

local function callMethodIfPresent(target, methodName, ...)
    if target == nil then
        return nil
    end
    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end
    return method(target, ...)
end

local function getWallClockStamp()
    if type(os) == "table" and type(os.date) == "function" then
        local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
        if ok and value then
            return tostring(value)
        end
    end
    return "unknown"
end

local function getWallClockFileStamp()
    if type(os) == "table" and type(os.date) == "function" then
        local ok, value = pcall(os.date, "%Y-%m-%dT%H-%M-%S")
        if ok and value then
            return tostring(value)
        end
    end
    local worldMinutes = tonumber(type(ctx("getWorldAgeMinutes")) == "function" and ctx("getWorldAgeMinutes")() or 0) or 0
    return string.format("world-%d", math.floor(worldMinutes))
end



local function sanitizeFileToken(value, fallback)
    local token = tostring(value or "")
    token = string.gsub(token, "[^%w%-%._]", "_")
    token = string.gsub(token, "_+", "_")
    token = string.gsub(token, "^_+", "")
    token = string.gsub(token, "_+$", "")
    if token == "" then
        token = tostring(fallback or "na")
    end
    return token
end

local function formatNumber(value, precision)
    local num = tonumber(value)
    if num == nil then
        return "na"
    end
    return string.format("%." .. tostring(precision or 3) .. "f", num)
end

local function formatScalar(value)
    if value == nil then
        return "na"
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    if type(value) == "number" then
        if value == math.floor(value) then
            return tostring(math.floor(value))
        end
        return formatNumber(value, 3)
    end
    local text = tostring(value)
    if text == "" then
        return "na"
    end
    return text
end

local function appendLine(lines, text)
    lines[#lines + 1] = tostring(text or "")
end

local function buildReportPayload(lines)
    if #lines <= 0 then
        return ""
    end
    return table.concat(lines, "\n") .. "\n"
end

local function closeWriterQuietly(writer)
    if not writer then
        return
    end
    pcall(function()
        writer:close()
    end)
end

local function burdenTierLabel(physicalLoad)
    local value = tonumber(physicalLoad) or 0
    if value < 7 then
        return "Negligible"
    end
    if value < 20 then
        return "Light"
    end
    if value < 45 then
        return "Moderate"
    end
    if value < 75 then
        return "Heavy"
    end
    return "Extreme"
end

local function sleepPenaltyLabel(rigidityLoad)
    local rigidity = tonumber(rigidityLoad) or 0
    if rigidity < 10 then
        return nil
    end
    local rigidityNorm = rigidity / (rigidity + 80.0) * 2.0
    local sleepPct = math.floor(rigidityNorm * 6.75 + 0.5)
    if sleepPct < 1 then
        return nil
    end
    return string.format("~%d%% longer recovery", sleepPct)
end

local function javaListToArray(list)
    local out = {}
    if type(list) ~= "userdata" and type(list) ~= "table" then
        return out
    end
    local size = tonumber(callMethodIfPresent(list, "size")) or 0
    for i = 0, size - 1 do
        out[#out + 1] = callMethodIfPresent(list, "get", i)
    end
    return out
end

local function collectActiveMods()
    local mods = {}
    local list = callGlobalIfPresent("getActivatedMods")
    if not list then
        return mods
    end
    local items = javaListToArray(list)
    for i = 1, #items do
        mods[#mods + 1] = tostring(items[i] or "unknown")
    end
    table.sort(mods)
    return mods
end

local PLAYER_FACING_OPTIONS = {
    EnableMuscleStrainModel = true,
    EnableSleepPenaltyModel = true,
}

local function collectOptions()
    local options = type(ctx("getOptions")) == "function" and ctx("getOptions")() or {}
    if type(options) ~= "table" then
        return {}
    end
    local rows = {}
    for key, _ in pairs(PLAYER_FACING_OPTIONS) do
        if options[key] ~= nil then
            rows[#rows + 1] = { key = key, value = options[key] }
        end
    end
    table.sort(rows, function(a, b) return a.key < b.key end)
    return rows
end



local function resolveActivityLabel(player)
    if type(ctx("getActivityLabel")) == "function" then
        return tostring(ctx("getActivityLabel")(player) or "idle")
    end
    return "idle"
end

local function resolvePostureFlags(player)
    local postureLabel = nil
    if type(ctx("getPostureLabel")) == "function" then
        postureLabel = tostring(ctx("getPostureLabel")(player) or "")
    end
    local flags = {
        sitting = callMethodIfPresent(player, "isSitOnGround") == true,
        asleep = callMethodIfPresent(player, "isAsleep") == true,
        resting = false,
        posture = postureLabel ~= "" and postureLabel or "na",
    }
    if postureLabel == "sit" or postureLabel == "rest" or postureLabel == "resting" then
        flags.resting = true
    else
        local resting = callMethodIfPresent(player, "isResting")
        if type(resting) == "boolean" then
            flags.resting = resting == true
        end
    end
    return flags
end

local function collectPlayerState(player)
    local posture = resolvePostureFlags(player)
    local bodyTemp = nil
    if type(ctx("getBodyTemperature")) == "function" then
        bodyTemp = ctx("getBodyTemperature")(player)
    end
    return {
        endurance = type(ctx("getEndurance")) == "function" and ctx("getEndurance")(player) or nil,
        fatigue = type(ctx("getFatigue")) == "function" and ctx("getFatigue")(player) or nil,
        thirst = type(ctx("getThirst")) == "function" and ctx("getThirst")(player) or nil,
        wetness = type(ctx("getWetness")) == "function" and ctx("getWetness")(player) or nil,
        bodyTemperature = bodyTemp,
        carriedWeight = tonumber(callMethodIfPresent(player, "getInventoryWeight")),
        maxWeight = tonumber(callMethodIfPresent(player, "getMaxWeight")),
        activityLabel = resolveActivityLabel(player),
        postureLabel = posture.posture,
        sitting = posture.sitting,
        resting = posture.resting,
        asleep = posture.asleep,
    }
end

local function collectClimateState(player)
    local gameTime = callGlobalIfPresent("getGameTime")
    local climate = callGlobalIfPresent("getClimateManager")

    local ambient = tonumber(gameTime and callMethodIfPresent(gameTime, "getAmbient")) or nil
    local temperature = tonumber(climate and callMethodIfPresent(climate, "getTemperature")) or nil
    local windChill = tonumber(climate and player and callMethodIfPresent(climate, "getAirTemperatureForCharacter", player, true)) or nil
    local windIntensity = tonumber(climate and callMethodIfPresent(climate, "getWindIntensity")) or nil
    local cloudIntensity = tonumber(climate and callMethodIfPresent(climate, "getCloudIntensity")) or nil
    local precipitationIntensity = tonumber(climate and callMethodIfPresent(climate, "getPrecipitationIntensity")) or nil
    local raining = climate and callMethodIfPresent(climate, "isRaining") == true or false
    local snowing = climate and callMethodIfPresent(climate, "isSnowing") == true or false

    return {
        ambient = ambient,
        temperature = temperature,
        windChill = windChill,
        windIntensity = windIntensity,
        cloudIntensity = cloudIntensity,
        precipitationIntensity = precipitationIntensity,
        raining = raining,
        snowing = snowing,
    }
end

local function collectWornItems(player)
    local rows = {}
    local wornItems = callMethodIfPresent(player, "getWornItems")
    if not wornItems then
        return rows
    end
    local count = tonumber(callMethodIfPresent(wornItems, "size")) or 0
    for i = 0, count - 1 do
        local worn = callMethodIfPresent(wornItems, "get", i)
        local item = worn and callMethodIfPresent(worn, "getItem")
        if item then
            local bodyLocation = tostring(callMethodIfPresent(worn, "getLocation")
                or callMethodIfPresent(item, "getBodyLocation")
                or "unknown")
            local signal = nil
            if type(ctx("itemToArmorSignal")) == "function" then
                signal = ctx("itemToArmorSignal")(item, bodyLocation)
            end
            local modId = tostring(callMethodIfPresent(item, "getModID") or "")
            if modId == "" then
                local scriptItem = callMethodIfPresent(item, "getScriptItem")
                modId = tostring(callMethodIfPresent(scriptItem, "getModID") or "")
            end
            rows[#rows + 1] = {
                bodyLocation = bodyLocation,
                fullType = tostring(callMethodIfPresent(item, "getFullType") or callMethodIfPresent(item, "getType") or "unknown"),
                displayName = tostring(callMethodIfPresent(item, "getDisplayName") or callMethodIfPresent(item, "getName") or "Unknown Item"),
                sourceMod = modId ~= "" and modId or nil,
                physical = tonumber(signal and signal.physicalLoad) or 0,
                thermal = tonumber(signal and signal.thermalLoad) or 0,
                breathing = tonumber(signal and signal.breathingLoad) or 0,
                rigidity = tonumber(signal and signal.rigidityLoad) or 0,
                weightUsed = tonumber(signal and signal.weightUsed) or 0,
                weightSource = tostring(signal and signal.weightSource or "na"),
                discomfort = tonumber(signal and signal.discomfort) or 0,
                breathingClass = tostring(signal and signal.breathingClass or "none"),
                breathingHasFilter = (signal and tostring(signal.breathingClass or "none") ~= "none") and signal.breathingHasFilter or nil,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.physical == b.physical then
            return tostring(a.fullType) < tostring(b.fullType)
        end
        return a.physical > b.physical
    end)
    return rows
end

local function resolveDisplayPath(relativePath)
    local root = callGlobalIfPresent("getMyDocumentFolder")
    if root == nil or tostring(root) == "" then
        return "Lua/" .. tostring(relativePath or "")
    end
    local base = tostring(root)
    local sep = string.find(base, "\\", 1, true) and "\\" or "/"
    local rel = tostring(relativePath or "")
    if sep == "\\" then
        rel = string.gsub(rel, "/", "\\")
    else
        rel = string.gsub(rel, "\\", "/")
    end
    if string.sub(base, -1) ~= sep then
        base = base .. sep
    end
    return base .. "Lua" .. sep .. rel
end

local function topContributorsOneLiner(wornRows, limit)
    local parts = {}
    local maxRows = math.min(limit or 3, #wornRows)
    for i = 1, maxRows do
        local row = wornRows[i]
        if row.physical >= 1.5 then
            parts[#parts + 1] = string.format("%s (%s)", row.displayName, formatNumber(row.physical, 1))
        end
    end
    if #parts == 0 then
        return "none"
    end
    return table.concat(parts, ", ")
end

local function collectMpSnapshot(state)
    if type(state) ~= "table" then
        return nil
    end
    local snapshot = state.mpServerSnapshot
    if type(snapshot) ~= "table" then
        return nil
    end
    local ageSeconds = nil
    local mpClient = type(state.mpClient) == "table" and state.mpClient or nil
    local lastSnapshotWallSecond = tonumber(mpClient and mpClient.lastSnapshotWallSecond) or nil
    if lastSnapshotWallSecond ~= nil and lastSnapshotWallSecond > 0 then
        local nowSeconds = nil
        if type(getTimestampMs) == "function" then
            nowSeconds = math.floor((tonumber(getTimestampMs()) or 0) / 1000)
        elseif type(getTimestamp) == "function" then
            nowSeconds = math.floor(tonumber(getTimestamp()) or 0)
        end
        if nowSeconds ~= nil and nowSeconds > 0 then
            ageSeconds = math.max(0, nowSeconds - lastSnapshotWallSecond)
        end
    end
    return {
        updatedMinute = tonumber(snapshot.updatedMinute) or nil,
        loadNorm = tonumber(snapshot.loadNorm) or nil,
        physicalLoad = tonumber(snapshot.physicalLoad) or nil,
        thermalLoad = tonumber(snapshot.thermalLoad) or nil,
        breathingLoad = tonumber(snapshot.breathingLoad) or nil,
        rigidityLoad = tonumber(snapshot.rigidityLoad) or nil,
        effectiveLoad = tonumber(snapshot.effectiveLoad) or nil,
        enduranceEnvFactor = tonumber(snapshot.enduranceEnvFactor) or nil,
        activityLabel = tostring(snapshot.activityLabel or "idle"),
        ageSeconds = ageSeconds,
        drivers = type(snapshot.drivers) == "table" and snapshot.drivers or {},
    }
end

local function collectRuntime(state)
    if type(state) ~= "table" then
        return nil
    end
    local snapshot = state.uiRuntimeSnapshot
    if type(snapshot) ~= "table" then
        return nil
    end
    return snapshot
end

local function openWriter(path)
    if type(getFileWriter) ~= "function" then
        return nil, "getFileWriter unavailable"
    end
    local ok, writer = pcall(getFileWriter, path, true, false)
    if not ok or not writer then
        return nil, "unable to open writer"
    end
    return writer, nil
end

local function buildReport(player)
    local worldMinutes = tonumber(type(ctx("getWorldAgeMinutes")) == "function" and ctx("getWorldAgeMinutes")() or 0) or 0
    local isMp = type(ctx("isMultiplayer")) == "function" and ctx("isMultiplayer")() == true
    local state = type(ctx("ensureState")) == "function" and ctx("ensureState")(player) or nil
    local options = collectOptions()
    local profile = type(ctx("computeArmorProfile")) == "function" and (ctx("computeArmorProfile")(player) or {}) or {}
    local runtime = collectRuntime(state)
    local playerState = collectPlayerState(player)
    local climateState = collectClimateState(player)
    local wornRows = collectWornItems(player)
    local activeMods = collectActiveMods()
    local mpSnapshot = isMp and collectMpSnapshot(state) or nil

    local lines = {}

    -- Header
    appendLine(lines, "# AMS Support Report")
    appendLine(lines, string.format("timestamp=%s", getWallClockStamp()))
    appendLine(lines, string.format("world_age_minutes=%s", formatNumber(worldMinutes, 3)))
    appendLine(lines, string.format("ams_version=%s", formatScalar(type(ctx("getLoadedModVersion")) == "function" and ctx("getLoadedModVersion")() or nil)))
    appendLine(lines, string.format("script_version=%s", formatScalar(ctx("scriptVersion"))))
    appendLine(lines, string.format("script_build=%s", formatScalar(ctx("scriptBuild"))))
    appendLine(lines, string.format("game_version=%s", formatScalar(type(ctx("getGameVersionTag")) == "function" and ctx("getGameVersionTag")() or nil)))
    appendLine(lines, string.format("mode=%s", isMp and "MP" or "SP"))
    appendLine(lines, string.format("player_index=%s", formatScalar(callMethodIfPresent(player, "getPlayerNum"))))
    appendLine(lines, "")

    -- Environment
    appendLine(lines, "## Environment")
    if #activeMods > 0 then
        for i = 1, #activeMods do
            appendLine(lines, string.format("mod[%02d]=%s", i, activeMods[i]))
        end
    else
        appendLine(lines, "active_mods=unavailable")
    end
    if #options > 0 then
        for i = 1, #options do
            appendLine(lines, string.format("option.%s=%s", options[i].key, formatScalar(options[i].value)))
        end
    else
        appendLine(lines, "options=none")
    end
    appendLine(lines, "")

    -- Player State
    appendLine(lines, "## Player State")
    appendLine(lines, string.format("activity=%s", formatScalar(playerState.activityLabel)))
    appendLine(lines, string.format("posture=%s", formatScalar(playerState.postureLabel)))
    appendLine(lines, string.format("sitting=%s", formatScalar(playerState.sitting)))
    appendLine(lines, string.format("resting=%s", formatScalar(playerState.resting)))
    appendLine(lines, string.format("asleep=%s", formatScalar(playerState.asleep)))
    appendLine(lines, string.format("endurance=%s", formatNumber(playerState.endurance, 4)))
    appendLine(lines, string.format("fatigue=%s", formatNumber(playerState.fatigue, 4)))
    appendLine(lines, string.format("thirst=%s", formatNumber(playerState.thirst, 4)))
    appendLine(lines, string.format("wetness=%s", formatNumber(playerState.wetness, 3)))
    appendLine(lines, string.format("body_temperature=%s", formatNumber(playerState.bodyTemperature, 2)))
    appendLine(lines, string.format("ambient=%s", formatNumber(climateState.ambient, 3)))
    appendLine(lines, string.format("air_temperature=%s", formatNumber(climateState.temperature, 3)))
    appendLine(lines, string.format("air_and_wind_temperature=%s", formatNumber(climateState.windChill, 3)))
    appendLine(lines, string.format("raining=%s", formatScalar(climateState.raining)))
    appendLine(lines, string.format("snowing=%s", formatScalar(climateState.snowing)))
    appendLine(lines, string.format("precipitation_intensity=%s", formatNumber(climateState.precipitationIntensity, 3)))
    appendLine(lines, string.format("wind_intensity=%s", formatNumber(climateState.windIntensity, 3)))
    appendLine(lines, string.format("cloud_intensity=%s", formatNumber(climateState.cloudIntensity, 3)))
    appendLine(lines, string.format("carried_weight=%s", formatNumber(playerState.carriedWeight, 3)))
    appendLine(lines, string.format("max_weight=%s", formatNumber(playerState.maxWeight, 3)))
    appendLine(lines, "")

    -- AMS Totals (always from local computeArmorProfile)
    appendLine(lines, "## AMS Totals")
    appendLine(lines, string.format("source=%s", "local"))
    appendLine(lines, string.format("physical_load=%s", formatNumber(profile.physicalLoad, 3)))
    appendLine(lines, string.format("thermal_load=%s", formatNumber(profile.thermalLoad, 3)))
    appendLine(lines, string.format("breathing_load=%s", formatNumber(profile.breathingLoad, 3)))
    appendLine(lines, string.format("rigidity_load=%s", formatNumber(profile.rigidityLoad, 3)))
    appendLine(lines, string.format("effective_load=%s", formatNumber(profile.combinedLoad, 3)))
    appendLine(lines, string.format("burden_tier=%s", burdenTierLabel(profile.physicalLoad)))
    appendLine(lines, string.format("armor_count=%s", formatScalar(profile.armorCount)))
    appendLine(lines, string.format("sleep_penalty=%s", formatScalar(sleepPenaltyLabel(profile.rigidityLoad))))
    appendLine(lines, string.format("top_contributors=%s", topContributorsOneLiner(wornRows, 3)))
    appendLine(lines, "")

    -- Runtime snapshot -- SP only. In MP the client physiology tick does not run,
    -- so state.uiRuntimeSnapshot is stale. Server-authoritative data is in MP Snapshot.
    if not isMp then
        appendLine(lines, "## Runtime")
        if type(runtime) == "table" then
            appendLine(lines, string.format("loadNorm=%s", formatNumber(runtime.loadNorm, 4)))
            appendLine(lines, string.format("effectiveLoad=%s", formatNumber(runtime.effectiveLoad, 4)))
            appendLine(lines, string.format("thermalContribution=%s", formatNumber(runtime.thermalContribution, 4)))
            appendLine(lines, string.format("breathingContribution=%s", formatNumber(runtime.breathingContribution, 4)))
            appendLine(lines, string.format("hotStrain=%s", formatNumber(runtime.hotStrain, 4)))
            appendLine(lines, string.format("thermalHot=%s", formatScalar((tonumber(runtime.hotStrain) or 0) > 0.15)))
            appendLine(lines, string.format("coldAppropriateness=%s", formatNumber(runtime.coldAppropriateness, 4)))
            appendLine(lines, string.format("thermalCold=%s", formatScalar((tonumber(runtime.coldAppropriateness) or 0) > 0.30)))
            appendLine(lines, string.format("thermalPressureScale=%s", formatNumber(runtime.thermalPressureScale, 4)))
            appendLine(lines, string.format("enduranceEnvFactor=%s", formatNumber(runtime.enduranceEnvFactor, 4)))
            appendLine(lines, string.format("activityLabel=%s", formatScalar(runtime.activityLabel)))
            appendLine(lines, string.format("enduranceBeforeAms=%s", formatNumber(runtime.enduranceBeforeAms, 4)))
            appendLine(lines, string.format("enduranceAfterAms=%s", formatNumber(runtime.enduranceAfterAms, 4)))
            appendLine(lines, string.format("enduranceNaturalDelta=%s", formatNumber(runtime.enduranceNaturalDelta, 4)))
            appendLine(lines, string.format("enduranceAppliedDelta=%s", formatNumber(runtime.enduranceAppliedDelta, 4)))
            appendLine(lines, string.format("updatedMinute=%s", formatNumber(runtime.updatedMinute, 3)))
        else
            appendLine(lines, "runtime=unavailable")
        end
        appendLine(lines, "")
    end

    -- MP Snapshot (server-authoritative, shown alongside local data for comparison)
    if isMp then
        appendLine(lines, "## MP Snapshot")
        if type(mpSnapshot) == "table" then
            appendLine(lines, string.format("source=%s", "server"))
            appendLine(lines, string.format("updatedMinute=%s", formatNumber(mpSnapshot.updatedMinute, 3)))
            appendLine(lines, string.format("ageSeconds=%s", formatNumber(mpSnapshot.ageSeconds, 1)))
            appendLine(lines, string.format("loadNorm=%s", formatNumber(mpSnapshot.loadNorm, 4)))
            appendLine(lines, string.format("physicalLoad=%s", formatNumber(mpSnapshot.physicalLoad, 3)))
            appendLine(lines, string.format("thermalLoad=%s", formatNumber(mpSnapshot.thermalLoad, 3)))
            appendLine(lines, string.format("breathingLoad=%s", formatNumber(mpSnapshot.breathingLoad, 3)))
            appendLine(lines, string.format("rigidityLoad=%s", formatNumber(mpSnapshot.rigidityLoad, 3)))
            appendLine(lines, string.format("effectiveLoad=%s", formatNumber(mpSnapshot.effectiveLoad, 3)))
            appendLine(lines, string.format("enduranceEnvFactor=%s", formatNumber(mpSnapshot.enduranceEnvFactor, 4)))
            appendLine(lines, string.format("activityLabel=%s", formatScalar(mpSnapshot.activityLabel)))
            appendLine(lines, string.format("thermalHot=%s", formatScalar((tonumber(mpSnapshot.hotStrain) or 0) > 0)))
            appendLine(lines, string.format("thermalCold=%s", formatScalar((tonumber(mpSnapshot.coldAppropriateness) or 0) > 0)))
            local serverDrivers = mpSnapshot.drivers or {}
            if #serverDrivers > 0 then
                for i = 1, #serverDrivers do
                    local driver = serverDrivers[i] or {}
                    appendLine(lines, string.format(
                        "server_driver[%d]=%s | physical=%s",
                        i,
                        formatScalar(driver.label),
                        formatNumber(driver.physical, 3)
                    ))
                end
            else
                appendLine(lines, "server_drivers=none")
            end
        else
            appendLine(lines, "server_snapshot=unavailable")
        end
        appendLine(lines, "")
    end

    -- Worn Items
    appendLine(lines, "## Worn Items")
    if #wornRows <= 0 then
        appendLine(lines, "worn_items=none")
    else
        for i = 1, #wornRows do
            local row = wornRows[i]
            local modPart = row.sourceMod and (" | mod=" .. formatScalar(row.sourceMod)) or ""
            local breathingPart = ""
            if row.breathingClass ~= "none" then
                breathingPart = string.format(" | breathing=%s filter=%s",
                    formatScalar(row.breathingClass),
                    formatScalar(row.breathingHasFilter))
            end
            appendLine(lines, string.format(
                "[%02d] loc=%s | type=%s | name=%s%s\n     phy=%s thm=%s br=%s rig=%s | weight=%s source=%s | discomfort=%s%s",
                i,
                formatScalar(row.bodyLocation),
                formatScalar(row.fullType),
                formatScalar(row.displayName),
                modPart,
                formatNumber(row.physical, 3),
                formatNumber(row.thermal, 3),
                formatNumber(row.breathing, 3),
                formatNumber(row.rigidity, 3),
                formatNumber(row.weightUsed, 3),
                formatScalar(row.weightSource),
                formatNumber(row.discomfort, 3),
                breathingPart
            ))
        end
    end

    return lines
end

function SupportReport.writeCurrentPlayerReport(player)
    local playerObj = player
    if not playerObj and type(ctx("getLocalPlayer")) == "function" then
        playerObj = ctx("getLocalPlayer")()
    end
    if not playerObj then
        return false, nil, "No local player available."
    end

    local fileName = sanitizeFileToken("ams-report-" .. getWallClockFileStamp(), "ams-report") .. ".txt"
    local relativePath = "ams_reports/" .. fileName
    local okBuild, linesOrErr = pcall(buildReport, playerObj)
    if not okBuild or type(linesOrErr) ~= "table" then
        if type(ctx("log")) == "function" then
            ctx("log")("support report build failed: " .. tostring(linesOrErr))
        end
        return false, nil, "Failed while building report file."
    end

    local payload = buildReportPayload(linesOrErr)
    local writer, openErr = openWriter(relativePath)
    if not writer then
        return false, nil, tostring(openErr or "Failed to open report file.")
    end

    local okWrite, writeErr = pcall(function()
        writer:write(payload)
        writer:close()
    end)
    if not okWrite then
        closeWriterQuietly(writer)
        if type(ctx("log")) == "function" then
            ctx("log")("support report write failed: " .. tostring(writeErr))
        end
        return false, nil, "Failed while writing report file."
    end

    local displayPath = resolveDisplayPath(relativePath)
    if type(ctx("log")) == "function" then
        ctx("log")("support report written: " .. tostring(displayPath))
    end
    return true, displayPath, nil
end

return SupportReport
