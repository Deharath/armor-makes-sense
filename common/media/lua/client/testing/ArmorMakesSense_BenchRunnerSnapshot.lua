ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunnerSnapshot = Testing.BenchRunnerSnapshot or {}

local BenchRunnerSnapshot = Testing.BenchRunnerSnapshot
local C = {}

local DEFAULT_NORM_FLOOR = 0.05

-- -----------------------------------------------------------------------------
-- Context wiring and snapshot buffering
-- -----------------------------------------------------------------------------

function BenchRunnerSnapshot.setContext(context)
    C = context or {}
end

function BenchRunnerSnapshot.sanitizeFileToken(value, fallback)
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

function BenchRunnerSnapshot.benchSnapshotAppend(snapshot, line, markerType)
    if type(snapshot) ~= "table" or type(line) ~= "string" then
        return
    end
    snapshot.lines = snapshot.lines or {}
    snapshot.lines[#snapshot.lines + 1] = line
    local keyByMarker = {
        start = "startCount",
        step_start = "stepStartCount",
        sample = "sampleCount",
        step = "stepCount",
        report = "reportCount",
        done = "doneCount",
    }
    local counterKey = keyByMarker[tostring(markerType or "")]
    if counterKey then
        snapshot[counterKey] = (tonumber(snapshot[counterKey]) or 0) + 1
    end
end

local function resolveBenchLogPaths(runner)
    local runId = BenchRunnerSnapshot.sanitizeFileToken(runner and runner.id, "run")
    local labelToken = BenchRunnerSnapshot.sanitizeFileToken(runner and runner.label, "nolabel")
    local fileName = string.format("bench_%s_%s.log", labelToken, runId)
    return fileName, "benchlogs/" .. fileName, fileName
end

-- -----------------------------------------------------------------------------
-- Stream writer lifecycle
-- -----------------------------------------------------------------------------

local function closeWriterSafe(writer)
    if not writer then
        return
    end
    pcall(function()
        writer:close()
    end)
end

function BenchRunnerSnapshot.openStreamWriter(runner)
    if type(runner) ~= "table" then
        return false, nil, "stream_missing_runner"
    end

    runner.streamWriter = nil
    runner.streamWriterPath = nil
    runner.streamWriterFailed = false
    runner.streamWriterOpen = false
    runner.streamWriterErr = nil

    local _, relPrimary, relFallback = resolveBenchLogPaths(runner)
    local attempts = {
        { path = relPrimary, factory = (type(getFileWriter) == "function") and getFileWriter or nil },
        { path = relPrimary, factory = (type(getSandboxFileWriter) == "function") and getSandboxFileWriter or nil },
        { path = relFallback, factory = (type(getFileWriter) == "function") and getFileWriter or nil },
        { path = relFallback, factory = (type(getSandboxFileWriter) == "function") and getSandboxFileWriter or nil },
    }

    for _, attempt in ipairs(attempts) do
        if type(attempt.factory) == "function" then
            local okOpen, writer = pcall(attempt.factory, attempt.path, true, false)
            if okOpen and writer then
                runner.streamWriter = writer
                runner.streamWriterPath = attempt.path
                runner.streamWriterOpen = true
                local banner = "# AMS Bench Stream (final header written at completion)"
                local okBanner = pcall(function()
                    writer:writeln(banner)
                end)
                if not okBanner then
                    okBanner = pcall(function()
                        writer:write(banner .. "\n")
                    end)
                end
                if not okBanner then
                    closeWriterSafe(writer)
                    runner.streamWriter = nil
                    runner.streamWriterOpen = false
                    runner.streamWriterFailed = true
                    runner.streamWriterErr = "stream_banner_write_failed"
                    return false, nil, runner.streamWriterErr
                end
                return true, attempt.path, nil
            end
        end
    end

    runner.streamWriterErr = "stream_writer_unavailable"
    return false, nil, runner.streamWriterErr
end

function BenchRunnerSnapshot.streamLine(runner, line)
    if type(runner) ~= "table" or type(line) ~= "string" then
        return false
    end
    local writer = runner.streamWriter
    if not writer or runner.streamWriterFailed == true then
        return false
    end

    local okWrite = pcall(function()
        writer:writeln(line)
    end)
    if not okWrite then
        okWrite = pcall(function()
            writer:write(tostring(line) .. "\n")
        end)
    end
    if okWrite then
        return true
    end

    runner.streamWriterFailed = true
    runner.streamWriterErr = "stream_writer_write_failed"
    closeWriterSafe(writer)
    runner.streamWriter = nil
    runner.streamWriterOpen = false
    return false
end

function BenchRunnerSnapshot.streamAppend(runner, line, markerType)
    if type(runner) ~= "table" or type(line) ~= "string" then
        return false
    end
    BenchRunnerSnapshot.benchSnapshotAppend(runner.snapshot, line, markerType)
    return BenchRunnerSnapshot.streamLine(runner, line)
end

function BenchRunnerSnapshot.closeStreamWriter(runner)
    if type(runner) ~= "table" then
        return false
    end
    closeWriterSafe(runner.streamWriter)
    runner.streamWriter = nil
    runner.streamWriterOpen = false
    return true
end

function BenchRunnerSnapshot.writeBenchSnapshotFile(runner, reason, nowMinutesFn, normFloor)
    if type(runner) ~= "table" then
        return false, nil, "snapshot_missing_runner"
    end

    local _, relPrimary, relFallback = resolveBenchLogPaths(runner)

    local worldTime = tonumber(type(nowMinutesFn) == "function" and nowMinutesFn() or 0) or 0
    local wallClock = "na"
    if type(os) == "table" and type(os.date) == "function" then
        local okDate, valueDate = pcall(os.date, "%Y-%m-%d %H:%M:%S")
        if okDate and valueDate then
            wallClock = tostring(valueDate)
        end
    end

    local snapshot = type(runner.snapshot) == "table" and runner.snapshot or {}
    local stepResults = type(runner.stepResults) == "table" and runner.stepResults or {}
    local setsApplied = tonumber(runner.setsApplied)
    if setsApplied == nil then
        setsApplied = #((type(runner.setOrder) == "table" and runner.setOrder) or {})
    end
    local scenariosApplied = tonumber(runner.scenariosApplied)
    if scenariosApplied == nil then
        scenariosApplied = #((type(runner.scenarioOrder) == "table" and runner.scenarioOrder) or {})
    end

    local lastError = tostring(runner.lastError or "none")
    local lastGateFailed = tostring(runner.lastGateFailed or "none")
    local lastStepValidity = tostring(runner.lastStepValidity or "none")
    local lastExitReason = tostring(runner.lastExitReason or "none")

    for i = #stepResults, 1, -1 do
        local result = stepResults[i] or {}
        if lastGateFailed == "none" then
            local gate = tostring(result.gateFailed or result.gate_failed or "none")
            if gate ~= "" and gate ~= "none" then
                lastGateFailed = gate
            end
        end
        if lastStepValidity == "none" then
            local validity = tostring(result.stepValidity or result.step_validity or "none")
            if validity ~= "" and validity ~= "none" then
                lastStepValidity = validity
            end
        end
        if lastExitReason == "none" then
            local exitReason = tostring(result.exitReason or result.exit_reason or "none")
            if exitReason ~= "" and exitReason ~= "none" then
                lastExitReason = exitReason
            end
        end
        if lastGateFailed ~= "none" and lastStepValidity ~= "none" and lastExitReason ~= "none" then
            break
        end
    end

    local outLines = {
        "# AMS Bench Snapshot",
        "snapshot_version=2",
        string.format("run_id=%s", tostring(runner.id or "na")),
        string.format("label=%s", tostring(runner.label or "")),
        string.format("preset=%s", tostring(runner.preset or "na")),
        string.format("reason=%s", tostring(reason or "completed")),
        string.format("mode=%s", tostring(runner.mode or "lab")),
        string.format("speed=%.2f", tonumber(runner.speedReq) or 0),
        string.format("repeats=%d", math.max(1, math.floor(tonumber(runner.repeats) or 1))),
        string.format("sets_applied=%d", math.max(0, math.floor(tonumber(setsApplied) or 0))),
        string.format("scenarios_applied=%d", math.max(0, math.floor(tonumber(scenariosApplied) or 0))),
        string.format("norm_floor=%.2f", tonumber(runner.normFloor) or tonumber(normFloor) or DEFAULT_NORM_FLOOR),
        string.format("total_steps=%d", math.max(0, math.floor(tonumber(runner.total) or 0))),
        string.format("completed_steps=%d", math.max(0, math.floor(tonumber(runner.index) or 0))),
        string.format("script_version=%s", tostring(runner.scriptVersion or "na")),
        string.format("script_build=%s", tostring(runner.scriptBuild or "na")),
        string.format("started_at_world_min=%.3f", tonumber(runner.startedAt) or 0),
        string.format("ended_at_world_min=%.3f", worldTime),
        string.format("wall_clock=%s", tostring(wallClock)),
        string.format("error=%s", lastError),
        string.format("last_gate_failed=%s", lastGateFailed),
        string.format("last_step_validity=%s", lastStepValidity),
        string.format("last_exit_reason=%s", lastExitReason),
        string.format("start_lines=%d", tonumber(snapshot.startCount) or 0),
        string.format("step_start_lines=%d", tonumber(snapshot.stepStartCount) or 0),
        string.format("sample_lines=%d", tonumber(snapshot.sampleCount) or 0),
        string.format("step_lines=%d", tonumber(snapshot.stepCount) or 0),
        string.format("report_lines=%d", tonumber(snapshot.reportCount) or 0),
        string.format("done_lines=%d", tonumber(snapshot.doneCount) or 0),
        "",
        "# Captured bench markers",
    }

    for _, line in ipairs(snapshot.lines or {}) do
        outLines[#outLines + 1] = tostring(line)
    end

    local function tryWrite(path, factory)
        if type(factory) ~= "function" then
            return false, "writer_factory_missing"
        end
        local writer = factory(path, true, false)
        if not writer then
            return false, "writer_open_failed"
        end
        for _, line in ipairs(outLines) do
            local writeOk = pcall(function()
                writer:writeln(tostring(line))
            end)
            if not writeOk then
                local fallbackOk = pcall(function()
                    writer:write(tostring(line) .. "\n")
                end)
                if not fallbackOk then
                    pcall(function()
                        writer:close()
                    end)
                    return false, "writer_write_failed"
                end
            end
        end
        local closeOk = pcall(function()
            writer:close()
        end)
        if not closeOk then
            return false, "writer_close_failed"
        end
        return true, nil
    end

    local attempts = {
        { path = relPrimary, factory = (type(getFileWriter) == "function") and getFileWriter or nil },
        { path = relPrimary, factory = (type(getSandboxFileWriter) == "function") and getSandboxFileWriter or nil },
        { path = relFallback, factory = (type(getFileWriter) == "function") and getFileWriter or nil },
        { path = relFallback, factory = (type(getSandboxFileWriter) == "function") and getSandboxFileWriter or nil },
    }

    for _, attempt in ipairs(attempts) do
        local ok, err = tryWrite(attempt.path, attempt.factory)
        if ok then
            return true, attempt.path, nil
        end
        runner.snapshotWriteErr = tostring(err)
    end

    return false, nil, tostring(runner.snapshotWriteErr or "snapshot_writer_unavailable")
end

return BenchRunnerSnapshot
