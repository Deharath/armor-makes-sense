ArmorMakesSense = ArmorMakesSense or {}

local okSchema, schemaOrErr = pcall(require, "ArmorMakesSense_MPIncidentSchema")
if not okSchema or type(schemaOrErr) ~= "table" then
    print("[ArmorMakesSense][MP][INCIDENT][SERVER][ERROR] require failed: ArmorMakesSense_MPIncidentSchema :: " .. tostring(schemaOrErr))
    return
end

ArmorMakesSense.MPIncidentRecorder = ArmorMakesSense.MPIncidentRecorder or {}

local Recorder = ArmorMakesSense.MPIncidentRecorder
local Schema = schemaOrErr
local C = {}

function Recorder.setContext(context)
    C = context or {}
end

local function ctx(name)
    return C[name]
end

local function cloneArray(rows)
    local out = {}
    for i = 1, #rows do
        local src = rows[i]
        if type(src) == "table" then
            local row = {}
            for key, value in pairs(src) do
                row[key] = value
            end
            out[#out + 1] = row
        end
    end
    return out
end

local function clampWindowStart(size, keep)
    return math.max(1, size - math.max(0, tonumber(keep) or 0))
end

local function ensureRecorderState(mpState)
    mpState.incidentRecorder = type(mpState.incidentRecorder) == "table" and mpState.incidentRecorder or {}
    local state = mpState.incidentRecorder
    state.seq = tonumber(state.seq) or 0
    state.ring = type(state.ring) == "table" and state.ring or {}
    state.frozen = type(state.frozen) == "table" and state.frozen or nil
    state.postRemaining = math.max(0, tonumber(state.postRemaining) or 0)
    state.lastActivityLabel = tostring(state.lastActivityLabel or "")
    state.lastEquipSignature = tostring(state.lastEquipSignature or "")
    state.invocation = type(state.invocation) == "table" and state.invocation or nil
    return state
end

local function appendRing(state, row)
    local ring = state.ring
    ring[#ring + 1] = row
    while #ring > Schema.RING_SIZE do
        table.remove(ring, 1)
    end
end

local function freezeIncident(state, triggerId, row)
    if type(state.frozen) == "table" then
        return state.frozen
    end

    state.seq = state.seq + 1
    local startIdx = clampWindowStart(#state.ring, Schema.PRE_TRIGGER_SLICES)
    local seedRows = {}
    for i = startIdx, #state.ring do
        seedRows[#seedRows + 1] = state.ring[i]
    end

    state.frozen = {
        traceVersion = Schema.TRACE_VERSION,
        seq = state.seq,
        trigger = tostring(triggerId or "unknown"),
        triggerMinute = tonumber(row and row.worldMinute) or 0,
        triggerReason = tostring(row and row.reason or "tick"),
        sealed = false,
        guardTripped = false,
        rows = cloneArray(seedRows),
    }
    state.postRemaining = Schema.POST_TRIGGER_SLICES
    if state.postRemaining <= 0 then
        state.frozen.sealed = true
    end
    return state.frozen
end

local function extendFrozen(state, row)
    local frozen = state.frozen
    if type(frozen) ~= "table" or state.postRemaining <= 0 then
        return
    end
    frozen.rows[#frozen.rows + 1] = row
    state.postRemaining = math.max(0, state.postRemaining - 1)
    if state.postRemaining <= 0 then
        frozen.sealed = true
    end
end

local function detectTrigger(state, row)
    local thresholds = Schema.THRESHOLDS
    if (tonumber(row.dtMinutes) or 0) >= thresholds.DT_MINUTES then
        return Schema.TRIGGERS.DT_SPIKE
    end
    if (tonumber(row.pendingCatchupMinutes) or 0) >= thresholds.PENDING_CATCHUP_MINUTES then
        return Schema.TRIGGERS.PENDING_CATCHUP
    end
    if (tonumber(row.enduranceAppliedDelta) or 0) <= thresholds.SLICE_APPLIED_DROP then
        return Schema.TRIGGERS.SLICE_APPLIED_DROP
    end
    if (tonumber(row.enduranceNaturalDelta) or 0) <= thresholds.NATURAL_DROP
        and (tonumber(row.enduranceAppliedDelta) or 0) > thresholds.NATURAL_DROP_APPLIED_GUARD then
        return Schema.TRIGGERS.NATURAL_DROP
    end
    return nil
end

function Recorder.clearSession(playerObj, mpState, nowMinute)
    local state = ensureRecorderState(mpState)
    state.ring = {}
    state.frozen = nil
    state.postRemaining = 0
    state.lastActivityLabel = ""
    state.lastEquipSignature = ""
    state.invocation = nil
    return true
end

function Recorder.beginInvocation(playerObj, mpState, meta)
    local state = ensureRecorderState(mpState)
    state.invocation = {
        reason = tostring(meta and meta.reason or "tick"),
        worldMinute = tonumber(meta and meta.worldMinute) or 0,
        cumulativeAppliedDelta = 0,
    }
    return state.invocation
end

function Recorder.recordSlice(playerObj, mpState, row)
    local state = ensureRecorderState(mpState)
    if type(row) ~= "table" then
        return { abortReplay = false }
    end

    row.activityLabel = tostring(row.activityLabel or "idle")
    row.equipSignature = tostring(row.equipSignature or "")
    row.activityChanged = (state.lastActivityLabel ~= "") and (state.lastActivityLabel ~= row.activityLabel) or false
    row.equipmentChanged = (state.lastEquipSignature ~= "") and (state.lastEquipSignature ~= row.equipSignature) or false
    state.lastActivityLabel = row.activityLabel
    state.lastEquipSignature = row.equipSignature

    appendRing(state, row)

    local invocation = state.invocation
    if type(invocation) == "table" then
        local appliedDelta = tonumber(row.enduranceAppliedDelta) or 0
        if appliedDelta < 0 then
            invocation.cumulativeAppliedDelta = tonumber(invocation.cumulativeAppliedDelta or 0) + appliedDelta
        end
    end

    local triggerId = detectTrigger(state, row)
    if triggerId then
        freezeIncident(state, triggerId, row)
    elseif type(state.frozen) == "table" and state.postRemaining > 0 then
        extendFrozen(state, row)
    end

    local cumulativeThreshold = Schema.THRESHOLDS.CUMULATIVE_APPLIED_DROP
    local abortReplay = type(invocation) == "table"
        and (tonumber(invocation.cumulativeAppliedDelta) or 0) <= cumulativeThreshold

    if abortReplay then
        local frozen = freezeIncident(state, Schema.TRIGGERS.CUMULATIVE_APPLIED_DROP, row)
        if frozen then
            frozen.guardTripped = true
        end
    end

    return {
        abortReplay = abortReplay,
        trigger = triggerId,
        seq = tonumber(state.seq) or 0,
    }
end

function Recorder.finishInvocation(playerObj, mpState)
    local state = ensureRecorderState(mpState)
    state.invocation = nil
end

function Recorder.buildSnapshotIncidentPayload(playerObj, mpState, clientKnownSeq)
    local state = ensureRecorderState(mpState)
    local currentSeq = tonumber(state.seq) or 0
    local knownSeq = tonumber(clientKnownSeq) or 0
    local frozen = state.frozen
    if currentSeq <= 0 or type(frozen) ~= "table" or currentSeq <= knownSeq then
        return currentSeq, nil
    end

    local payload = {
        trace_version = tonumber(frozen.traceVersion) or Schema.TRACE_VERSION,
        seq = currentSeq,
        trigger = tostring(frozen.trigger or "unknown"),
        trigger_minute = tonumber(frozen.triggerMinute) or 0,
        trigger_reason = tostring(frozen.triggerReason or "tick"),
        sealed = frozen.sealed == true,
        guard_tripped = frozen.guardTripped == true,
        rows = cloneArray(frozen.rows or {}),
    }
    return currentSeq, payload
end

return Recorder
