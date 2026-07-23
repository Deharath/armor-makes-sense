ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.SupportReport = Core.SupportReport or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local IncidentTrace = require "core/ArmorMakesSense_IncidentTrace"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local PresentationPolicy = require "ArmorMakesSense_PresentationPolicy"
local Stats = require "ArmorMakesSense_StatsShared"
local Utils = require "ArmorMakesSense_UtilsShared"

local SupportReport = Core.SupportReport

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
    local worldMinutes = tonumber(Utils.getWorldAgeMinutes()) or 0
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
    local labels = {
        negligible = "Negligible",
        light = "Light",
        moderate = "Moderate",
        heavy = "Heavy",
        extreme = "Extreme",
    }
    return labels[PresentationPolicy.burdenTier(physicalLoad)] or labels.negligible
end

local function sleepPenaltyLabel(rigidityLoad)
    if not PresentationPolicy.hasSleepRestriction(rigidityLoad) then
        return nil
    end
    return "Slower recovery"
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
    EnableThermalModel = true,
    EnableMuscleStrainModel = true,
    EnableSleepPenaltyModel = true,
}

local function collectOptions()
    local options = Options.get()
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
    local activity = Environment.resolveActivity(player, Options.get())
    return tostring(activity.label or "idle")
end

local function resolvePostureFlags(player)
    local postureLabel = tostring(Environment.getPostureLabel(player) or "")
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
    return {
        endurance = Stats.getEndurance(player),
        fatigue = Stats.getFatigue(player),
        thirst = Stats.getThirst(player),
        wetness = Stats.getWetness(player),
        bodyTemperature = Stats.getBodyTemperature(player),
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
        local nowSeconds = Utils.getWallClockSeconds()
        if nowSeconds ~= nil and nowSeconds > 0 then
            ageSeconds = math.max(0, nowSeconds - lastSnapshotWallSecond)
        end
    end
    return {
        updatedMinute = tonumber(snapshot.updatedMinute) or nil,
        loadNorm = tonumber(snapshot.loadNorm) or nil,
        physicalLoad = tonumber(snapshot.physicalLoad) or nil,
        thermalResistance = tonumber(snapshot.thermalResistance) or nil,
        airflowResistance = tonumber(snapshot.airflowResistance) or nil,
        sealedRestriction = tonumber(snapshot.sealedRestriction) or nil,
        rigidityLoad = tonumber(snapshot.rigidityLoad) or nil,
        effectiveLoad = tonumber(snapshot.effectiveLoad) or nil,
        thermalContribution = tonumber(snapshot.thermalContribution) or nil,
        breathingContribution = tonumber(snapshot.breathingContribution) or nil,
        metabolicRate = tonumber(snapshot.metabolicRate) or nil,
        metabolicDemand = tonumber(snapshot.metabolicDemand) or nil,
        metabolicNorm = tonumber(snapshot.metabolicNorm) or nil,
        breathingEffortRamp = tonumber(snapshot.breathingEffortRamp) or nil,
        breathingDynamicLoad = tonumber(snapshot.breathingDynamicLoad) or nil,
        breathingSealedLoad = tonumber(snapshot.breathingSealedLoad) or nil,
        hotPressure = tonumber(snapshot.hotPressure) or nil,
        coldSuitability = tonumber(snapshot.coldSuitability) or nil,
        thermalStrainScale = tonumber(snapshot.thermalStrainScale) or nil,
        enduranceBeforeAms = tonumber(snapshot.enduranceBeforeAms) or nil,
        enduranceAfterAms = tonumber(snapshot.enduranceAfterAms) or nil,
        enduranceNaturalDelta = tonumber(snapshot.enduranceNaturalDelta) or nil,
        enduranceAppliedDelta = tonumber(snapshot.enduranceAppliedDelta) or nil,
        lastAppliedDtMinutes = tonumber(snapshot.lastAppliedDtMinutes) or nil,
        catchupPendingMinutes = tonumber(snapshot.catchupPendingMinutes) or nil,
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
    local worldMinutes = tonumber(Utils.getWorldAgeMinutes()) or 0
    local isMp = Utils.isMultiplayer()
    local state = ClientRuntime.ensureState(player)
    local options = collectOptions()
    local analysis = LoadModel.analyzeWornGear(player)
    local profile = analysis.profile
    local runtime = collectRuntime(state)
    local playerState = collectPlayerState(player)
    local climateState = collectClimateState(player)
    local wornRows = analysis.rows
    local activeMods = collectActiveMods()
    local mpSnapshot = isMp and collectMpSnapshot(state) or nil

    local lines = {}

    -- Header
    appendLine(lines, "# AMS Support Report")
    appendLine(lines, string.format("timestamp=%s", getWallClockStamp()))
    appendLine(lines, string.format("world_age_minutes=%s", formatNumber(worldMinutes, 3)))
    appendLine(lines, string.format("ams_version=%s", formatScalar(ClientRuntime.getLoadedModVersion())))
    appendLine(lines, string.format("script_version=%s", formatScalar(ClientRuntime.SCRIPT_VERSION)))
    appendLine(lines, string.format("script_build=%s", formatScalar(ClientRuntime.SCRIPT_BUILD)))
    appendLine(lines, string.format("game_version=%s", formatScalar(ClientRuntime.getGameVersionTag())))
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

    -- AMS Totals (always from the local worn profile)
    appendLine(lines, "## AMS Totals")
    appendLine(lines, string.format("source=%s", "local"))
    appendLine(lines, string.format("physical_load=%s", formatNumber(profile.physicalLoad, 3)))
    appendLine(lines, string.format("airflow_resistance=%s", formatNumber(profile.airflowResistance, 3)))
    appendLine(lines, string.format("sealed_restriction=%s", formatNumber(profile.sealedRestriction, 3)))
    appendLine(lines, string.format("rigidity_load=%s", formatNumber(profile.rigidityLoad, 3)))
    appendLine(lines, string.format("burden_tier=%s", burdenTierLabel(profile.physicalLoad)))
    appendLine(lines, string.format("driver_count=%s", formatScalar(profile.driverCount)))
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
            appendLine(lines, string.format("metabolicRate=%s", formatNumber(runtime.metabolicRate, 4)))
            appendLine(lines, string.format("metabolicDemand=%s", formatNumber(runtime.metabolicDemand, 4)))
            appendLine(lines, string.format("metabolicNorm=%s", formatNumber(runtime.metabolicNorm, 4)))
            appendLine(lines, string.format("breathingEffortRamp=%s", formatNumber(runtime.breathingEffortRamp, 4)))
            appendLine(lines, string.format("breathingDynamicLoad=%s", formatNumber(runtime.breathingDynamicLoad, 4)))
            appendLine(lines, string.format("breathingSealedLoad=%s", formatNumber(runtime.breathingSealedLoad, 4)))
            appendLine(lines, string.format("thermalResistance=%s", formatNumber(runtime.thermalResistance, 4)))
            appendLine(lines, string.format("hotPressure=%s", formatNumber(runtime.hotPressure, 4)))
            appendLine(lines, string.format("thermalHot=%s", formatScalar((tonumber(runtime.thermalStrainScale) or 0) >= 0.15)))
            appendLine(lines, string.format("coldSuitability=%s", formatNumber(runtime.coldSuitability, 4)))
            appendLine(lines, string.format("thermalCold=%s", formatScalar((tonumber(runtime.coldSuitability) or 0) > 0.45)))
            appendLine(lines, string.format("thermalStrainScale=%s", formatNumber(runtime.thermalStrainScale, 4)))
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
            appendLine(lines, string.format("thermalResistance=%s", formatNumber(mpSnapshot.thermalResistance, 3)))
            appendLine(lines, string.format("airflowResistance=%s", formatNumber(mpSnapshot.airflowResistance, 3)))
            appendLine(lines, string.format("sealedRestriction=%s", formatNumber(mpSnapshot.sealedRestriction, 3)))
            appendLine(lines, string.format("rigidityLoad=%s", formatNumber(mpSnapshot.rigidityLoad, 3)))
            appendLine(lines, string.format("effectiveLoad=%s", formatNumber(mpSnapshot.effectiveLoad, 3)))
            appendLine(lines, string.format("thermalContribution=%s", formatNumber(mpSnapshot.thermalContribution, 4)))
            appendLine(lines, string.format("breathingContribution=%s", formatNumber(mpSnapshot.breathingContribution, 4)))
            appendLine(lines, string.format("metabolicRate=%s", formatNumber(mpSnapshot.metabolicRate, 4)))
            appendLine(lines, string.format("metabolicDemand=%s", formatNumber(mpSnapshot.metabolicDemand, 4)))
            appendLine(lines, string.format("metabolicNorm=%s", formatNumber(mpSnapshot.metabolicNorm, 4)))
            appendLine(lines, string.format("breathingEffortRamp=%s", formatNumber(mpSnapshot.breathingEffortRamp, 4)))
            appendLine(lines, string.format("breathingDynamicLoad=%s", formatNumber(mpSnapshot.breathingDynamicLoad, 4)))
            appendLine(lines, string.format("breathingSealedLoad=%s", formatNumber(mpSnapshot.breathingSealedLoad, 4)))
            appendLine(lines, string.format("activityLabel=%s", formatScalar(mpSnapshot.activityLabel)))
            appendLine(lines, string.format("hotPressure=%s", formatNumber(mpSnapshot.hotPressure, 4)))
            appendLine(lines, string.format("coldSuitability=%s", formatNumber(mpSnapshot.coldSuitability, 4)))
            appendLine(lines, string.format("thermalStrainScale=%s", formatNumber(mpSnapshot.thermalStrainScale, 4)))
            appendLine(lines, string.format("thermalHot=%s", formatScalar((tonumber(mpSnapshot.thermalStrainScale) or 0) >= 0.15)))
            appendLine(lines, string.format("thermalCold=%s", formatScalar((tonumber(mpSnapshot.coldSuitability) or 0) > 0.45)))
            appendLine(lines, string.format("enduranceBeforeAms=%s", formatNumber(mpSnapshot.enduranceBeforeAms, 4)))
            appendLine(lines, string.format("enduranceAfterAms=%s", formatNumber(mpSnapshot.enduranceAfterAms, 4)))
            appendLine(lines, string.format("enduranceNaturalDelta=%s", formatNumber(mpSnapshot.enduranceNaturalDelta, 4)))
            appendLine(lines, string.format("enduranceAppliedDelta=%s", formatNumber(mpSnapshot.enduranceAppliedDelta, 4)))
            appendLine(lines, string.format("lastAppliedDtMinutes=%s", formatNumber(mpSnapshot.lastAppliedDtMinutes, 4)))
            appendLine(lines, string.format("catchupPendingMinutes=%s", formatNumber(mpSnapshot.catchupPendingMinutes, 4)))
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

        local appendIncidentTraceSection = IncidentTrace.appendReportSection
        if type(appendIncidentTraceSection) == "function" then
            appendIncidentTraceSection(lines)
        else
            appendLine(lines, "## Incident Trace")
            appendLine(lines, "incident=unavailable")
            appendLine(lines, "")
        end
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
            if row.respiratoryClass ~= "none" then
                breathingPart = string.format(" | respiratory=%s filter=%s sealed=%s",
                    formatScalar(row.respiratoryClass),
                    formatScalar(row.respiratoryHasFilter),
                    formatNumber(row.sealedRestriction, 2))
            end
            appendLine(lines, string.format(
                "[%02d] loc=%s | type=%s | name=%s%s\n     phy=%s thm=%s airflow=%s rig=%s | weight=%s source=%s | discomfort=%s%s",
                i,
                formatScalar(row.bodyLocation),
                formatScalar(row.fullType),
                formatScalar(row.displayName),
                modPart,
                formatNumber(row.physical, 3),
                formatNumber(row.thermal, 3),
                formatNumber(row.airflow, 3),
                formatNumber(row.rigidity, 3),
                formatNumber(row.weightUsed, 3),
                formatScalar(row.weightSource),
                formatNumber(row.discomfort, 3),
                breathingPart
            ))
            appendLine(lines, string.format(
                "     included=%s reason=%s | armor_like=%s classification=%s",
                formatScalar(row.included),
                formatScalar(row.inclusionReason),
                formatScalar(row.armorLike),
                formatScalar(row.classificationReason)
            ))
        end
    end

    return lines
end

function SupportReport.writeCurrentPlayerReport(player)
    local playerObj = player
    if not playerObj then
        playerObj = ClientRuntime.getLocalPlayer()
    end
    if not playerObj then
        return false, nil, "No local player available."
    end

    local fileName = sanitizeFileToken("ams-report-" .. getWallClockFileStamp(), "ams-report") .. ".txt"
    local relativePath = "ams_reports/" .. fileName
    local okBuild, linesOrErr = pcall(buildReport, playerObj)
    if not okBuild or type(linesOrErr) ~= "table" then
        ClientRuntime.log("support report build failed: " .. tostring(linesOrErr))
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
        ClientRuntime.log("support report write failed: " .. tostring(writeErr))
        return false, nil, "Failed while writing report file."
    end

    local displayPath = resolveDisplayPath(relativePath)
    ClientRuntime.log("support report written: " .. tostring(displayPath))
    return true, displayPath, nil
end

return SupportReport
