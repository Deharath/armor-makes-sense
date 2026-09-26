ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.SupportReport = Core.SupportReport or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Environment = require "ArmorMakesSense_EnvironmentShared"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
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
    PhysicalLoadScale = true,
    EnableThermalModel = true,
    EnableBreathingModel = true,
    EnableMuscleStrainModel = true,
    EnableSleepPenaltyModel = true,
}

local function collectOptions(options)
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
    return tostring(Environment.resolveActivity(player) or "idle")
end

local function resolvePostureFlags(player)
    local postureLabel = tostring(Environment.getPostureLabel(player) or "")
    local flags = {
        sitting = callMethodIfPresent(player, "isSitOnGround") == true,
        asleep = callMethodIfPresent(player, "isAsleep") == true,
        resting = false,
        posture = postureLabel ~= "" and postureLabel or "na",
    }
    flags.resting = Environment.isResting(postureLabel)
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
        if row.burdenKg >= LoadModel.COST_DRIVER_THRESHOLD_KG then
            parts[#parts + 1] = string.format("%s (%s kg)", row.displayName, formatNumber(row.burdenKg, 1))
        end
    end
    if #parts == 0 then
        return "none"
    end
    return table.concat(parts, ", ")
end

local function snapshotAgeSeconds(state)
    local mpClient = type(state) == "table" and type(state.mpClient) == "table" and state.mpClient or nil
    local last = tonumber(mpClient and mpClient.lastSnapshotWallSecond) or 0
    if last <= 0 then
        return nil
    end
    return math.max(0, (Utils.getWallClockSeconds() or last) - last)
end

-- Snapshot fields in report order.
local SNAPSHOT_FIELDS = {
    { "activityLabel" }, { "postureLabel" },
    { "burdenKg", 3 }, { "armKg", 3 }, { "rigidKg", 3 }, { "driverCount", 0 },
    { "bodyKg", 1 }, { "strength", 0 }, { "loadFraction", 4 },
    { "heat", 4 }, { "thermalResistance", 4 }, { "hotPressure", 4 }, { "coldSuitability", 4 },
    { "airflowResistance", 3 }, { "sealedRestriction", 3 }, { "breathingSeverity", 3 }, { "breathingEnabled" },
    { "restRegenScale", 4 }, { "standRegenScale", 4 }, { "walkRegenScale", 4 }, { "runDrainScale", 4 }, { "sprintDrainScale", 4 }, { "fightDrainScale", 4 },
    { "sleepPenaltyFraction", 4 },
    { "naturalDelta", 6 }, { "amsDelta", 6 }, { "regenScale", 4 }, { "drainScale", 4 },
    { "nmsRegenScale", 4 }, { "nmsDrain", 6 }, { "dtMinutes", 3 }, { "updatedMinute", 3 },
}

local function appendSnapshot(lines, snapshot, worldMinutes)
    for _, field in ipairs(SNAPSHOT_FIELDS) do
        local value = snapshot[field[1]]
        if field[2] then
            appendLine(lines, string.format("%s=%s", field[1], formatNumber(value, field[2])))
        else
            appendLine(lines, string.format("%s=%s", field[1], formatScalar(value)))
        end
    end
    appendLine(lines, string.format("snapshotAgeMinutes=%s", formatNumber(
        math.max(0, (tonumber(worldMinutes) or 0) - (tonumber(snapshot.updatedMinute) or 0)), 3
    )))
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
    local resolvedOptions = Options.get()
    local options = collectOptions(resolvedOptions)
    local analysis = LoadModel.analyzeWornGear(player, resolvedOptions)
    local profile = analysis.profile
    local runtime = Physiology.getUiRuntimeSnapshot(state)
    local playerState = collectPlayerState(player)
    local climateState = collectClimateState(player)
    local wornRows = analysis.rows
    local activeMods = collectActiveMods()

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
    appendLine(lines, string.format("burden_kg=%s", formatNumber(profile.burdenKg, 3)))
    appendLine(lines, string.format("mass_kg=%s", formatNumber(profile.massKg, 3)))
    appendLine(lines, string.format("bulk_kg=%s", formatNumber(profile.bulkKg, 3)))
    appendLine(lines, string.format("arm_kg=%s", formatNumber(profile.armKg, 3)))
    appendLine(lines, string.format("rigid_kg=%s", formatNumber(profile.rigidKg, 3)))
    appendLine(lines, string.format("airflow_resistance=%s", formatNumber(profile.airflowResistance, 3)))
    appendLine(lines, string.format("sealed_restriction=%s", formatNumber(profile.sealedRestriction, 3)))
    appendLine(lines, string.format("driver_count=%s", formatScalar(profile.driverCount)))
    appendLine(lines, string.format("top_contributors=%s", topContributorsOneLiner(wornRows, 3)))
    appendLine(lines, "")

    -- Runtime: the SP tick snapshot, or the server-authoritative snapshot in MP.
    appendLine(lines, "## Runtime")
    appendLine(lines, string.format("source=%s", isMp and "server" or "local"))
    if type(runtime) == "table" then
        if isMp then
            appendLine(lines, string.format("ageSeconds=%s", formatNumber(snapshotAgeSeconds(state), 1)))
        end
        appendSnapshot(lines, runtime, worldMinutes)
        local drivers = isMp and (runtime.drivers or {}) or {}
        for i = 1, #drivers do
            appendLine(lines, string.format(
                "server_driver[%d]=%s | burden_kg=%s",
                i,
                formatScalar(drivers[i].label),
                formatNumber(drivers[i].burdenKg, 3)
            ))
        end
    else
        appendLine(lines, "runtime=unavailable")
    end
    appendLine(lines, "")

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
                "[%02d] loc=%s | type=%s | name=%s%s\n     burden=%s mass=%s x%s bulk=%s rigid=%s | weight=%s | discomfort=%s airflow=%s%s",
                i,
                formatScalar(row.bodyLocation),
                formatScalar(row.fullType),
                formatScalar(row.displayName),
                modPart,
                formatNumber(row.burdenKg, 3),
                formatNumber(row.massKg, 3),
                formatNumber(row.placement, 2),
                formatNumber(row.bulkKg, 3),
                formatNumber(row.rigidKg, 3),
                formatNumber(row.weightKg, 3),
                formatNumber(row.discomfort, 3),
                formatNumber(row.airflow, 3),
                breathingPart
            ))
            appendLine(lines, string.format(
                "     included=%s reason=%s | rigid=%s",
                formatScalar(row.included),
                formatScalar(row.inclusionReason),
                formatScalar(row.rigid)
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

    if Utils.isMultiplayer() then
        local state = ClientRuntime.ensureState(playerObj)
        if not (state and type(state.mpServerSnapshot) == "table") then
            local mpRuntime = ArmorMakesSense and ArmorMakesSense.MPClientRuntime or nil
            if mpRuntime and type(mpRuntime.requestSnapshot) == "function" then
                mpRuntime.requestSnapshot(playerObj, 0)
            end
            return false, nil, "Server snapshot requested. Try export again in a moment."
        end
    end

    local fileName = sanitizeFileToken("ams-report-" .. getWallClockFileStamp(), "ams-report") .. ".txt"
    local relativePath = "ams_reports/" .. fileName
    local okBuild, linesOrErr = pcall(buildReport, playerObj)
    if not okBuild or type(linesOrErr) ~= "table" then
        ClientRuntime.logError("support report build failed: " .. tostring(linesOrErr))
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
        ClientRuntime.logError("support report write failed: " .. tostring(writeErr))
        return false, nil, "Failed while writing report file."
    end

    local displayPath = resolveDisplayPath(relativePath)
    ClientRuntime.logInfo("support report written: " .. tostring(displayPath))
    return true, displayPath, nil
end

return SupportReport
