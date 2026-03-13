ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local okSchema, schemaOrErr = pcall(require, "ArmorMakesSense_MPIncidentSchema")
if not okSchema or type(schemaOrErr) ~= "table" then
    print("[ArmorMakesSense][MP][INCIDENT][CLIENT][ERROR] require failed: ArmorMakesSense_MPIncidentSchema :: " .. tostring(schemaOrErr))
    return
end

local Core = ArmorMakesSense.Core
Core.IncidentTrace = Core.IncidentTrace or {}

local IncidentTrace = Core.IncidentTrace
local Schema = schemaOrErr
local C = {}
local latestIncident = nil

local function ctx(name)
    return C[name]
end

function IncidentTrace.setContext(context)
    C = context or {}
end

local function formatNumber(value, precision)
    local num = tonumber(value)
    if num == nil then
        return "na"
    end
    return string.format("%." .. tostring(precision or 3) .. "f", num)
end

local function formatBool(value)
    return value == true and "true" or "false"
end

local function formatScalar(value)
    if value == nil then
        return "na"
    end
    if type(value) == "number" then
        return formatNumber(value, 3)
    end
    if type(value) == "boolean" then
        return formatBool(value)
    end
    local text = tostring(value)
    if text == "" then
        return "na"
    end
    return text
end

function IncidentTrace.clear()
    latestIncident = nil
end

function IncidentTrace.getSeq()
    return tonumber(latestIncident and latestIncident.seq) or 0
end

function IncidentTrace.applyServerIncident(payload)
    if type(payload) ~= "table" then
        return false
    end
    local seq = tonumber(payload.seq) or 0
    if seq <= 0 then
        return false
    end
    if latestIncident and seq <= (tonumber(latestIncident.seq) or 0) then
        return false
    end
    latestIncident = payload
    return true
end

function IncidentTrace.appendReportSection(lines)
    lines[#lines + 1] = "## Incident Trace"
    if type(latestIncident) ~= "table" then
        lines[#lines + 1] = "incident=none"
        lines[#lines + 1] = ""
        return
    end

    lines[#lines + 1] = string.format("trace_version=%s", formatScalar(latestIncident.trace_version or Schema.TRACE_VERSION))
    lines[#lines + 1] = string.format("incident_seq=%s", formatScalar(latestIncident.seq))
    lines[#lines + 1] = string.format("trigger=%s", formatScalar(latestIncident.trigger))
    lines[#lines + 1] = string.format("trigger_minute=%s", formatNumber(latestIncident.trigger_minute, 3))
    lines[#lines + 1] = string.format("trigger_reason=%s", formatScalar(latestIncident.trigger_reason))
    lines[#lines + 1] = string.format("sealed=%s", formatBool(latestIncident.sealed == true))
    lines[#lines + 1] = string.format("guard_tripped=%s", formatBool(latestIncident.guard_tripped == true))

    local rows = type(latestIncident.rows) == "table" and latestIncident.rows or {}
    if #rows <= 0 then
        lines[#lines + 1] = "incident_rows=none"
        lines[#lines + 1] = ""
        return
    end

    for i = 1, #rows do
        local row = rows[i] or {}
        local flagParts = {
            "moving=" .. formatBool(row.moving == true),
            "playerMoving=" .. formatBool(row.playerMoving == true),
            "run=" .. formatBool(row.running == true),
            "sprint=" .. formatBool(row.sprinting == true),
            "aim=" .. formatBool(row.aiming == true),
            "attack=" .. formatBool(row.attackStarted == true),
        }
        local driverParts = type(row.topDrivers) == "table" and table.concat(row.topDrivers, ", ") or "none"
        lines[#lines + 1] = string.format(
            "incident_row[%02d]=minute=%s reason=%s dt=%s pending=%s activity=%s equip_changed=%s activity_changed=%s",
            i,
            formatNumber(row.worldMinute, 3),
            formatScalar(row.reason),
            formatNumber(row.dtMinutes, 4),
            formatNumber(row.pendingCatchupMinutes, 4),
            formatScalar(row.activityLabel),
            formatBool(row.equipmentChanged == true),
            formatBool(row.activityChanged == true)
        )
        lines[#lines + 1] = string.format(
            "     end_before=%s end_after=%s nat_delta=%s ams_delta=%s | load_norm=%s eff=%s phy=%s thm=%s br=%s rig=%s | env=%s tcontrib=%s bcontrib=%s",
            formatNumber(row.enduranceBeforeAms, 4),
            formatNumber(row.enduranceAfterAms, 4),
            formatNumber(row.enduranceNaturalDelta, 4),
            formatNumber(row.enduranceAppliedDelta, 4),
            formatNumber(row.loadNorm, 4),
            formatNumber(row.effectiveLoad, 3),
            formatNumber(row.physicalLoad, 3),
            formatNumber(row.thermalLoad, 3),
            formatNumber(row.breathingLoad, 3),
            formatNumber(row.rigidityLoad, 3),
            formatNumber(row.enduranceEnvFactor, 4),
            formatNumber(row.thermalContribution, 4),
            formatNumber(row.breathingContribution, 4)
        )
        lines[#lines + 1] = string.format(
            "     flags=%s | worn_count=%s | top_drivers=%s | equip_signature=%s",
            table.concat(flagParts, " "),
            formatScalar(row.wornCount),
            formatScalar(driverParts),
            formatScalar(row.equipSignature)
        )
    end
    lines[#lines + 1] = ""
end

return IncidentTrace
